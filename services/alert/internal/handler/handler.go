package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

// eventType identifies which upstream service published the event.
type eventType string

const (
	eventFraudAlert          eventType = "fraud-alert"
	eventRiskBreach          eventType = "risk-breach"
	eventComplianceViolation eventType = "compliance-violation"
	eventUnknown             eventType = "unknown"
)

// Handler listens for events published by Fraud, Risk, and Compliance services,
// detects the event type, and simulates dispatching notifications through the
// appropriate channel based on severity.
type Handler struct{}

func New() *Handler {
	return &Handler{}
}

// Handle is the sqsconsumer.HandlerFunc implementation.
// It never returns an error because notifications are best-effort —
// a failed notification should not block the queue.
func (h *Handler) Handle(ctx context.Context, body string) error {
	eType := detectEventType(body)

	switch eType {
	case eventFraudAlert:
		var alert events.FraudAlert
		if err := json.Unmarshal([]byte(body), &alert); err != nil {
			log.Printf("alert: failed to parse fraud alert: %v", err)
			return nil
		}
		notify(alert.Severity, formatFraudAlert(alert))

	case eventRiskBreach:
		var breach events.RiskBreach
		if err := json.Unmarshal([]byte(body), &breach); err != nil {
			log.Printf("alert: failed to parse risk breach: %v", err)
			return nil
		}
		notify(severityFromBreach(breach), formatRiskBreach(breach))

	case eventComplianceViolation:
		var violation events.ComplianceViolation
		if err := json.Unmarshal([]byte(body), &violation); err != nil {
			log.Printf("alert: failed to parse compliance violation: %v", err)
			return nil
		}
		notify(violation.Severity, formatComplianceViolation(violation))

	default:
		log.Printf("alert: ignoring unrecognised event type")
	}

	return nil
}

// detectEventType probes for distinguishing JSON fields to figure out which
// upstream service produced the event.
func detectEventType(body string) eventType {
	var probe struct {
		AlertID     string `json:"alert_id"`
		BreachID    string `json:"breach_id"`
		ViolationID string `json:"violation_id"`
	}
	if err := json.Unmarshal([]byte(body), &probe); err != nil {
		return eventUnknown
	}
	switch {
	case probe.AlertID != "":
		return eventFraudAlert
	case probe.BreachID != "":
		return eventRiskBreach
	case probe.ViolationID != "":
		return eventComplianceViolation
	default:
		return eventUnknown
	}
}

// notify simulates dispatching through the appropriate channel based on severity.
// In production these would be real integrations (PagerDuty, Slack, SES, etc.).
func notify(severity events.Severity, message string) {
	switch severity {
	case events.SeverityCritical:
		log.Printf("[PAGER/SMS] CRITICAL: %s", message)
	case events.SeverityHigh:
		log.Printf("[SLACK]     HIGH:     %s", message)
	case events.SeverityMedium:
		log.Printf("[EMAIL]     MEDIUM:   %s", message)
	default:
		log.Printf("[LOG]       LOW:      %s", message)
	}
}

// --- formatters ---------------------------------------------------------------

func formatFraudAlert(a events.FraudAlert) string {
	return fmt.Sprintf("Fraud alert %s — user=%s tx=%s severity=%s patterns=[%s] reason=%q",
		a.AlertID, a.UserID, a.TransactionID, a.Severity,
		strings.Join(a.Patterns, ", "), a.Reason)
}

func formatRiskBreach(b events.RiskBreach) string {
	return fmt.Sprintf("Risk breach %s — user=%s tx=%s threshold=%s current=%.2f limit=%.2f",
		b.BreachID, b.UserID, b.TransactionID, b.ThresholdType,
		b.CurrentValue, b.ThresholdValue)
}

func formatComplianceViolation(v events.ComplianceViolation) string {
	return fmt.Sprintf("Compliance violation %s — user=%s tx=%s rules=[%s] reason=%q",
		v.ViolationID, v.UserID, v.TransactionID,
		strings.Join(v.Rules, ", "), v.Reason)
}

// severityFromBreach derives a severity level from a RiskBreach event.
// RiskBreach doesn't carry its own Severity field, so we infer it
// from how far over the threshold the current value is.
func severityFromBreach(b events.RiskBreach) events.Severity {
	if b.ThresholdValue == 0 {
		return events.SeverityHigh
	}
	ratio := b.CurrentValue / b.ThresholdValue
	switch {
	case ratio >= 2.0:
		return events.SeverityCritical
	case ratio >= 1.5:
		return events.SeverityHigh
	default:
		return events.SeverityMedium
	}
}
