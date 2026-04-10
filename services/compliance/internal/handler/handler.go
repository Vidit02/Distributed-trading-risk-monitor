package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	snsTypes "github.com/aws/aws-sdk-go-v2/service/sns/types"
	"github.com/google/uuid"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

var allowedCurrencies = map[string]struct{}{
	"USD": {}, "EUR": {}, "GBP": {}, "JPY": {}, "CAD": {}, "AUD": {}, "CHF": {},
}

var allowedTransactionTypes = map[events.TransactionType]struct{}{
	events.TransactionTypePurchase:   {},
	events.TransactionTypeWithdrawal: {},
	events.TransactionTypeTransfer:   {},
	events.TransactionTypeDeposit:    {},
}

const ctrThreshold = 10_000.0

type Handler struct {
	sns              *sns.Client
	topicARN         string
	blockedUsers     map[string]struct{}
	blockedMerchants map[string]struct{}
}

func New(snsClient *sns.Client, topicARN string, blockedUsers, blockedMerchants []string) *Handler {
	h := &Handler{
		sns:              snsClient,
		topicARN:         topicARN,
		blockedUsers:     toSet(blockedUsers),
		blockedMerchants: toSet(blockedMerchants),
	}
	return h
}

func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		log.Printf("compliance: unparseable message, discarding: %v", err)
		return nil
	}

	violations := h.checkRules(tx)
	if len(violations) == 0 {
		log.Printf("compliance: transaction %s passed all rules", tx.TransactionID)
		return nil
	}

	v := events.ComplianceViolation{
		ViolationID:   uuid.New().String(),
		TransactionID: tx.TransactionID,
		UserID:        tx.UserID,
		Rules:         violations,
		Reason:        fmt.Sprintf("%d compliance rule(s) violated", len(violations)),
		Severity:      resolveSeverity(violations),
		DetectedAt:    time.Now().UTC(),
	}

	if err := h.publishViolation(ctx, v); err != nil {
		return fmt.Errorf("publish compliance violation: %w", err)
	}

	log.Printf("compliance: violation published for transaction %s (severity=%s rules=%v)",
		tx.TransactionID, v.Severity, v.Rules)
	return nil
}

func (h *Handler) checkRules(tx events.TransactionEvent) []string {
	var violations []string

	if tx.Amount <= 0 {
		violations = append(violations, "zero_or_negative_amount")
	}

	if _, blocked := h.blockedUsers[tx.UserID]; blocked {
		violations = append(violations, "blocked_user")
	}

	if _, blocked := h.blockedMerchants[tx.MerchantID]; blocked {
		violations = append(violations, "blocked_merchant")
	}

	if _, ok := allowedCurrencies[tx.Currency]; !ok {
		violations = append(violations, "unsupported_currency")
	}

	if _, ok := allowedTransactionTypes[tx.TransactionType]; !ok {
		violations = append(violations, "unsupported_transaction_type")
	}

	if tx.Amount >= ctrThreshold {
		violations = append(violations, "ctr_reporting_required")
	}

	return violations
}

func resolveSeverity(rules []string) events.Severity {
	hasCritical, hasHigh, hasMedium := false, false, false
	for _, rule := range rules {
		switch rule {
		case "blocked_user", "blocked_merchant":
			hasCritical = true
		case "zero_or_negative_amount":
			hasHigh = true
		case "unsupported_currency", "ctr_reporting_required":
			hasMedium = true
		}
	}
	switch {
	case hasCritical:
		return events.SeverityCritical
	case hasHigh:
		return events.SeverityHigh
	case hasMedium:
		return events.SeverityMedium
	default:
		return events.SeverityLow
	}
}

func (h *Handler) publishViolation(ctx context.Context, v events.ComplianceViolation) error {
	payload, err := json.Marshal(v)
	if err != nil {
		return fmt.Errorf("marshal violation: %w", err)
	}

	_, err = h.sns.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(h.topicARN),
		Message:  aws.String(string(payload)),
		MessageAttributes: map[string]snsTypes.MessageAttributeValue{
			"event_type": {
				DataType:    aws.String("String"),
				StringValue: aws.String("compliance-violation"),
			},
			"severity": {
				DataType:    aws.String("String"),
				StringValue: aws.String(string(v.Severity)),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("sns publish: %w", err)
	}
	return nil
}

func toSet(items []string) map[string]struct{} {
	s := make(map[string]struct{}, len(items))
	for _, item := range items {
		if item != "" {
			s[item] = struct{}{}
		}
	}
	return s
}
