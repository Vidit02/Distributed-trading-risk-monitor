package events

import "time"

// ThresholdType identifies which risk rule was violated.
type ThresholdType string

const (
	ThresholdTypeDailyLimit        ThresholdType = "daily_limit"
	ThresholdTypeMonthlyLimit      ThresholdType = "monthly_limit"
	ThresholdTypeSingleTransaction ThresholdType = "single_transaction"
	ThresholdTypeVelocity          ThresholdType = "velocity"
)

// RiskBreach is published by the Risk Monitor Service when a transaction
// causes a user to exceed a defined risk threshold.
type RiskBreach struct {
	BreachID       string        `json:"breach_id"`
	TransactionID  string        `json:"transaction_id"`
	UserID         string        `json:"user_id"`
	ThresholdType  ThresholdType `json:"threshold_type"`
	CurrentValue   float64       `json:"current_value"`
	ThresholdValue float64       `json:"threshold_value"`
	BreachedAt     time.Time     `json:"breached_at"`
}
