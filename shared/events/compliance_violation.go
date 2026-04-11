package events

import "time"

type ComplianceViolation struct {
	ViolationID   string    `json:"violation_id"`
	TransactionID string    `json:"transaction_id"`
	UserID        string    `json:"user_id"`
	Rules         []string  `json:"rules"`  // all rules that fired
	Reason        string    `json:"reason"` // human-readable summary
	Severity      Severity  `json:"severity"`
	DetectedAt    time.Time `json:"detected_at"`
}
