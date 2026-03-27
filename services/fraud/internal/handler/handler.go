package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snsTypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

// Handler processes incoming TransactionEvents from the high-priority SQS queue,
// checks them against known fraud patterns, and publishes a FraudAlert to SNS
// if any pattern is matched.
type Handler struct {
	sns      *sns.Client
	topicARN string
}

func New(snsClient *sns.Client, topicARN string) *Handler {
	return &Handler{
		sns:      snsClient,
		topicARN: topicARN,
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

	if err := h.publishAlert(ctx, alert); err != nil {
		// Return the error so the message stays in queue and is retried.
		return fmt.Errorf("publish fraud alert: %w", err)
	}

	log.Printf("fraud: alert published for transaction %s (severity=%s patterns=%v)",
		tx.TransactionID, alert.Severity, alert.Patterns)
	return nil
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

// resolveSeverity maps transaction properties and number of matched patterns to a FraudAlert severity level.
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

// publishAlert serialises the FraudAlert
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
