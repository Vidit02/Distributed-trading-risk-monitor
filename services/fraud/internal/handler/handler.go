package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamodbTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snsTypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

// Handler processes incoming TransactionEvents from the high-priority SQS queue,
// checks them against known fraud patterns, and publishes a FraudAlert to SNS
// if any pattern is matched. Flagged transactions are also written back to DynamoDB.
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

// Handle is the sqsconsumer.HandlerFunc implementation.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		log.Printf("fraud: unparseable message, discarding: %v", err)
		return nil
	}

	patterns := detectPatterns(tx)
	if len(patterns) == 0 {
		log.Printf("fraud: transaction %s passed all checks", tx.TransactionID)
		// Mark as clean in DynamoDB so the dashboard shows the correct status.
		if err := h.markClean(ctx, tx); err != nil {
			log.Printf("fraud: DynamoDB clean update failed for %s: %v", tx.TransactionID, err)
		}
		return nil
	}

	alert := events.FraudAlert{
		AlertID:       uuid.New().String(),
		TransactionID: tx.TransactionID,
		UserID:        tx.UserID,
		Severity:      resolveSeverity(tx, patterns),
		Reason:        fmt.Sprintf("%d fraud pattern(s) detected", len(patterns)),
		Patterns:      patterns,
		DetectedAt:    time.Now().UTC(),
	}

	// Update transaction status to "flagged" in DynamoDB.
	if err := h.flagTransaction(ctx, tx, alert); err != nil {
		log.Printf("fraud: DynamoDB update failed for %s: %v", tx.TransactionID, err)
		// Non-fatal: continue to publish the alert even if DB update fails.
	}

	if err := h.publishAlert(ctx, alert); err != nil {
		// Return the error so the message stays in queue and is retried.
		return fmt.Errorf("publish fraud alert: %w", err)
	}

	log.Printf("fraud: alert published for transaction %s (severity=%s patterns=%v)",
		tx.TransactionID, alert.Severity, alert.Patterns)
	return nil
}

// markClean updates the transaction record in DynamoDB to status "clean".
func (h *Handler) markClean(ctx context.Context, tx events.TransactionEvent) error {
	_, err := h.dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(h.tableName),
		Key: map[string]dynamodbTypes.AttributeValue{
			"transaction_id": &dynamodbTypes.AttributeValueMemberS{Value: tx.TransactionID},
			"timestamp":      &dynamodbTypes.AttributeValueMemberS{Value: tx.Timestamp.Format(time.RFC3339Nano)},
		},
		UpdateExpression: aws.String("SET #st = :status"),
		ExpressionAttributeNames: map[string]string{
			"#st": "status",
		},
		ExpressionAttributeValues: map[string]dynamodbTypes.AttributeValue{
			":status": &dynamodbTypes.AttributeValueMemberS{Value: "clean"},
		},
	})
	return err
}

// flagTransaction updates the transaction record in DynamoDB to status "flagged".
func (h *Handler) flagTransaction(ctx context.Context, tx events.TransactionEvent, alert events.FraudAlert) error {
	_, err := h.dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(h.tableName),
		Key: map[string]dynamodbTypes.AttributeValue{
			"transaction_id": &dynamodbTypes.AttributeValueMemberS{Value: tx.TransactionID},
			"timestamp":      &dynamodbTypes.AttributeValueMemberS{Value: tx.Timestamp.Format(time.RFC3339Nano)},
		},
		UpdateExpression: aws.String("SET #st = :status, alert_id = :alert_id, severity = :severity, fraud_reason = :reason"),
		ExpressionAttributeNames: map[string]string{
			"#st": "status",
		},
		ExpressionAttributeValues: map[string]dynamodbTypes.AttributeValue{
			":status":   &dynamodbTypes.AttributeValueMemberS{Value: "flagged"},
			":alert_id": &dynamodbTypes.AttributeValueMemberS{Value: alert.AlertID},
			":severity": &dynamodbTypes.AttributeValueMemberS{Value: string(alert.Severity)},
			":reason":   &dynamodbTypes.AttributeValueMemberS{Value: alert.Reason},
		},
	})
	return err
}

// detectPatterns checks a transaction against all known fraud rules.
func detectPatterns(tx events.TransactionEvent) []string {
	var patterns []string

	if tx.Amount > 10_000 {
		patterns = append(patterns, "high_value_transaction")
	}

	if tx.Amount >= 1_000 && math.Mod(tx.Amount, 1_000) == 0 {
		patterns = append(patterns, "round_number_transaction")
	}

	if tx.TransactionType == events.TransactionTypeWithdrawal && tx.Amount > 5_000 {
		patterns = append(patterns, "large_withdrawal")
	}

	if tx.Priority == events.PriorityCritical && tx.Amount > 5_000 {
		patterns = append(patterns, "critical_priority_high_amount")
	}

	return patterns
}

// resolveSeverity maps transaction properties and matched patterns to a severity level.
func resolveSeverity(tx events.TransactionEvent, patterns []string) events.Severity {
	switch {
	case tx.Priority == events.PriorityCritical || tx.Amount > 50_000:
		return events.SeverityCritical
	case tx.Amount > 20_000 || len(patterns) >= 3:
		return events.SeverityHigh
	case tx.Amount > 10_000 || len(patterns) >= 2:
		return events.SeverityMedium
	default:
		return events.SeverityLow
	}
}

// publishAlert serialises the FraudAlert and sends it to SNS.
func (h *Handler) publishAlert(ctx context.Context, alert events.FraudAlert) error {
	payload, err := json.Marshal(alert)
	if err != nil {
		return fmt.Errorf("marshal alert: %w", err)
	}

	_, err = h.sns.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(h.topicARN),
		Message:  aws.String(string(payload)),
		MessageAttributes: map[string]snsTypes.MessageAttributeValue{
			"event_type": {
				DataType:    aws.String("String"),
				StringValue: aws.String("fraud-alert"),
			},
			"severity": {
				DataType:    aws.String("String"),
				StringValue: aws.String(string(alert.Severity)),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("sns publish: %w", err)
	}
	return nil
}
