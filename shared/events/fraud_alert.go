package events

import "time"

// Severity indicates how serious a detected fraud pattern is.
type Severity string

const (
	SeverityLow      Severity = "low"
	SeverityMedium   Severity = "medium"
	SeverityHigh     Severity = "high"
	SeverityCritical Severity = "critical"
)

// FraudAlert is published by the Fraud Detection Service when suspicious
// patterns are detected on a transaction.
type FraudAlert struct {
	AlertID       string    `json:"alert_id"`
	TransactionID string    `json:"transaction_id"`
	UserID        string    `json:"user_id"`
	Severity      Severity  `json:"severity"`
	Reason        string    `json:"reason"`
	Patterns      []string  `json:"patterns"`
	DetectedAt    time.Time `json:"detected_at"`
}
