package handler

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamodbTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snsTypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"
)

// TransactionRequest is the JSON body accepted by POST /transaction.
type TransactionRequest struct {
	UserID          string                 `json:"user_id"`
	Amount          float64                `json:"amount"`
	Currency        string                 `json:"currency"`
	MerchantID      string                 `json:"merchant_id"`
	TransactionType events.TransactionType `json:"transaction_type"`
	// Priority is optional; derived from Amount if omitted.
	Priority events.Priority   `json:"priority,omitempty"`
	Metadata map[string]string `json:"metadata,omitempty"`
}

// TransactionResponse is returned on successful acceptance.
type TransactionResponse struct {
	TransactionID string    `json:"transaction_id"`
	Status        string    `json:"status"`
	Timestamp     time.Time `json:"timestamp"`
}

// Handler handles POST /transaction requests.
type Handler struct {
	sns       *sns.Client
	topicARN  string
	dynamo    *dynamodb.Client
	tableName string
}

func New(snsClient *sns.Client, topicARN string, dynamoClient *dynamodb.Client, tableName string) *Handler {
	return &Handler{
		sns:       snsClient,
		topicARN:  topicARN,
		dynamo:    dynamoClient,
		tableName: tableName,
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.UserID == "" || req.Amount <= 0 || req.Currency == "" || req.TransactionType == "" {
		http.Error(w, "missing required fields: user_id, amount, currency, transaction_type", http.StatusBadRequest)
		return
	}

	switch req.TransactionType {
	case events.TransactionTypePurchase, events.TransactionTypeWithdrawal,
		events.TransactionTypeTransfer, events.TransactionTypeDeposit:
	default:
		http.Error(w, "invalid transaction_type: must be purchase, withdrawal, transfer, or deposit", http.StatusBadRequest)
		return
	}

	if req.Priority == "" {
		req.Priority = derivePriority(req.Amount)
	} else {
		switch req.Priority {
		case events.PriorityLow, events.PriorityMedium, events.PriorityHigh, events.PriorityCritical:
		default:
			http.Error(w, "invalid priority: must be low, medium, high, or critical", http.StatusBadRequest)
			return
		}
	}

	now := time.Now().UTC()
	event := events.TransactionEvent{
		TransactionID:   uuid.New().String(),
		UserID:          req.UserID,
		Amount:          req.Amount,
		Currency:        req.Currency,
		MerchantID:      req.MerchantID,
		TransactionType: req.TransactionType,
		Priority:        req.Priority,
		Timestamp:       now,
		Metadata:        req.Metadata,
	}

	// Persist to DynamoDB before publishing to SNS.
	ttl := now.Add(90 * 24 * time.Hour).Unix()
	item := map[string]dynamodbTypes.AttributeValue{
		"transaction_id":   &dynamodbTypes.AttributeValueMemberS{Value: event.TransactionID},
		"timestamp":        &dynamodbTypes.AttributeValueMemberS{Value: event.Timestamp.Format(time.RFC3339Nano)},
		"user_id":          &dynamodbTypes.AttributeValueMemberS{Value: event.UserID},
		"amount":           &dynamodbTypes.AttributeValueMemberN{Value: fmt.Sprintf("%.2f", event.Amount)},
		"currency":         &dynamodbTypes.AttributeValueMemberS{Value: event.Currency},
		"transaction_type": &dynamodbTypes.AttributeValueMemberS{Value: string(event.TransactionType)},
		"priority":         &dynamodbTypes.AttributeValueMemberS{Value: string(event.Priority)},
		"status":           &dynamodbTypes.AttributeValueMemberS{Value: "pending"},
		"ttl":              &dynamodbTypes.AttributeValueMemberN{Value: fmt.Sprintf("%d", ttl)},
	}
	if event.MerchantID != "" {
		item["merchant_id"] = &dynamodbTypes.AttributeValueMemberS{Value: event.MerchantID}
	}

	if _, err := h.dynamo.PutItem(r.Context(), &dynamodb.PutItemInput{
		TableName: aws.String(h.tableName),
		Item:      item,
	}); err != nil {
		log.Printf("transaction: DynamoDB PutItem failed: %v", err)
		http.Error(w, "failed to save transaction", http.StatusInternalServerError)
		return
	}

	payload, err := json.Marshal(event)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	_, err = h.sns.Publish(r.Context(), &sns.PublishInput{
		TopicArn: aws.String(h.topicARN),
		Message:  aws.String(string(payload)),
		MessageAttributes: map[string]snsTypes.MessageAttributeValue{
			"priority": {
				DataType:    aws.String("String"),
				StringValue: aws.String(string(event.Priority)),
			},
		},
	})
	if err != nil {
		http.Error(w, "failed to publish event", http.StatusInternalServerError)
		return
	}

	log.Printf("transaction: saved %s (user=%s amount=%.2f %s priority=%s status=pending)",
		event.TransactionID, event.UserID, event.Amount, event.Currency, event.Priority)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(TransactionResponse{
		TransactionID: event.TransactionID,
		Status:        "accepted",
		Timestamp:     now,
	})
}

// derivePriority maps amount thresholds to priority levels.
func derivePriority(amount float64) events.Priority {
	switch {
	case amount >= 50000:
		return events.PriorityCritical
	case amount >= 10000:
		return events.PriorityHigh
	case amount >= 1000:
		return events.PriorityMedium
	default:
		return events.PriorityLow
	}
}
