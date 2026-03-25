package events

import "time"

// Priority maps directly to the SNS message attribute used for SQS filter routing.
type Priority string

const (
	PriorityLow      Priority = "low"
	PriorityMedium   Priority = "medium"
	PriorityHigh     Priority = "high"
	PriorityCritical Priority = "critical"
)

// TransactionType describes the nature of the transaction.
type TransactionType string

const (
	TransactionTypePurchase   TransactionType = "purchase"
	TransactionTypeWithdrawal TransactionType = "withdrawal"
	TransactionTypeTransfer   TransactionType = "transfer"
	TransactionTypeDeposit    TransactionType = "deposit"
)

// TransactionEvent is published to SNS and consumed by all high/low priority services.
// This is the primary event that drives the entire pipeline.
type TransactionEvent struct {
	TransactionID   string            `json:"transaction_id"`
	UserID          string            `json:"user_id"`
	Amount          float64           `json:"amount"`
	Currency        string            `json:"currency"`
	MerchantID      string            `json:"merchant_id"`
	TransactionType TransactionType   `json:"transaction_type"`
	Priority        Priority          `json:"priority"`
	Timestamp       time.Time         `json:"timestamp"`
	Metadata        map[string]string `json:"metadata,omitempty"`
}
