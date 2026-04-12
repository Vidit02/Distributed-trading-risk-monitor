package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamodbTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snsTypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

// Handler consumes messages from the high-priority DLQ.
// These are transactions that the fraud detection service failed to process
// (service down, crashes, repeated errors). The handler:
//  1. Writes the transaction to DynamoDB with status "pending_manual_review"
//  2. Publishes a notification so the Alert Service can page someone
type Handler struct {
	dynamo    *dynamodb.Client
	tableName string
	sns       *sns.Client
	topicARN  string
}

func New(dynamoClient *dynamodb.Client, tableName string, snsClient *sns.Client, topicARN string) *Handler {
	return &Handler{
		dynamo:    dynamoClient,
		tableName: tableName,
		sns:       snsClient,
		topicARN:  topicARN,
	}
}

// Handle processes a single DLQ message.
// Always returns nil so the message is deleted from the DLQ after processing —
// we don't want infinite DLQ retries; the record is persisted in DynamoDB instead.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		log.Printf("manual-review: unparseable message, logging raw body and discarding")
		if err := h.storeUnparseable(ctx, body); err != nil {
			log.Printf("manual-review: failed to store unparseable message: %v", err)
		}
		return nil
	}

	if err := h.flagForReview(ctx, tx); err != nil {
		log.Printf("manual-review: DynamoDB write failed for tx=%s: %v", tx.TransactionID, err)
		// Return error so the message stays in DLQ and is retried.
		return fmt.Errorf("flag for review: %w", err)
	}

	if err := h.notifyReviewNeeded(ctx, tx); err != nil {
		// Non-fatal — the record is already in DynamoDB.
		log.Printf("manual-review: notification failed for tx=%s: %v", tx.TransactionID, err)
	}

	log.Printf("manual-review: tx=%s user=%s amount=%.2f flagged for manual review",
		tx.TransactionID, tx.UserID, tx.Amount)
	return nil
}

// flagForReview writes or updates the transaction record in DynamoDB with
// status "pending_manual_review" and a review_reason explaining why.
func (h *Handler) flagForReview(ctx context.Context, tx events.TransactionEvent) error {
	if h.dynamo == nil {
		return fmt.Errorf("dynamodb client not configured")
	}
	_, err := h.dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(h.tableName),
		Key: map[string]dynamodbTypes.AttributeValue{
			"transaction_id": &dynamodbTypes.AttributeValueMemberS{Value: tx.TransactionID},
			"timestamp":      &dynamodbTypes.AttributeValueMemberS{Value: tx.Timestamp.Format(time.RFC3339Nano)},
		},
		UpdateExpression: aws.String("SET #st = :status, review_reason = :reason, review_flagged_at = :flagged_at"),
		ExpressionAttributeNames: map[string]string{
			"#st": "status",
		},
		ExpressionAttributeValues: map[string]dynamodbTypes.AttributeValue{
			":status":    &dynamodbTypes.AttributeValueMemberS{Value: "pending_manual_review"},
			":reason":    &dynamodbTypes.AttributeValueMemberS{Value: "fraud detection service was unavailable — automatic checks were not completed"},
			":flagged_at": &dynamodbTypes.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339)},
		},
	})
	return err
}

// storeUnparseable writes a raw unparseable message to DynamoDB so it isn't lost.
func (h *Handler) storeUnparseable(ctx context.Context, body string) error {
	if h.dynamo == nil {
		return fmt.Errorf("dynamodb client not configured")
	}
	id := uuid.New().String()
	_, err := h.dynamo.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(h.tableName),
		Item: map[string]dynamodbTypes.AttributeValue{
			"transaction_id":  &dynamodbTypes.AttributeValueMemberS{Value: "unparseable-" + id},
			"timestamp":       &dynamodbTypes.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339Nano)},
			"status":          &dynamodbTypes.AttributeValueMemberS{Value: "pending_manual_review"},
			"review_reason":   &dynamodbTypes.AttributeValueMemberS{Value: "unparseable message landed in DLQ"},
			"raw_body":        &dynamodbTypes.AttributeValueMemberS{Value: body},
			"review_flagged_at": &dynamodbTypes.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339)},
		},
	})
	return err
}

// notifyReviewNeeded publishes a notification to SNS so the Alert Service
// can page someone to perform the manual review.
func (h *Handler) notifyReviewNeeded(ctx context.Context, tx events.TransactionEvent) error {
	msg := fmt.Sprintf(
		"Manual review required — tx=%s user=%s amount=%.2f %s. "+
			"Fraud detection was unavailable; automatic checks were skipped.",
		tx.TransactionID, tx.UserID, tx.Amount, tx.Currency,
	)

	_, err := h.sns.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(h.topicARN),
		Message:  aws.String(msg),
		MessageAttributes: map[string]snsTypes.MessageAttributeValue{
			"event_type": {
				DataType:    aws.String("String"),
				StringValue: aws.String("manual-review-needed"),
			},
			"severity": {
				DataType:    aws.String("String"),
				StringValue: aws.String("high"),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("sns publish: %w", err)
	}
	return nil
}
