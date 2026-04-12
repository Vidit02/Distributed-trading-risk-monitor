package handler

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

// validTxJSON returns a valid TransactionEvent JSON string.
func validTxJSON() string {
	tx := events.TransactionEvent{
		TransactionID:   "tx-100",
		UserID:          "user-42",
		Amount:          7500.00,
		Currency:        "USD",
		MerchantID:      "merchant-abc",
		TransactionType: events.TransactionTypePurchase,
		Priority:        events.PriorityHigh,
		Timestamp:       time.Date(2026, 4, 11, 12, 0, 0, 0, time.UTC),
	}
	b, _ := json.Marshal(tx)
	return string(b)
}

// --- TransactionEvent parsing ---

func TestParseValidTransaction(t *testing.T) {
	var tx events.TransactionEvent
	err := json.Unmarshal([]byte(validTxJSON()), &tx)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if tx.TransactionID != "tx-100" {
		t.Errorf("expected tx-100, got %s", tx.TransactionID)
	}
	if tx.UserID != "user-42" {
		t.Errorf("expected user-42, got %s", tx.UserID)
	}
	if tx.Amount != 7500.00 {
		t.Errorf("expected 7500, got %.2f", tx.Amount)
	}
}

func TestParseInvalidJSON(t *testing.T) {
	var tx events.TransactionEvent
	err := json.Unmarshal([]byte("not json at all"), &tx)
	if err == nil {
		t.Fatal("expected error for invalid JSON, got nil")
	}
}

func TestParseEmptyBody(t *testing.T) {
	var tx events.TransactionEvent
	err := json.Unmarshal([]byte(""), &tx)
	if err == nil {
		t.Fatal("expected error for empty body, got nil")
	}
}

func TestParsePartialJSON(t *testing.T) {
	body := `{"transaction_id":"tx-partial","user_id":"user-1"}`
	var tx events.TransactionEvent
	err := json.Unmarshal([]byte(body), &tx)
	if err != nil {
		t.Fatalf("expected no error for partial JSON, got %v", err)
	}
	if tx.TransactionID != "tx-partial" {
		t.Errorf("expected tx-partial, got %s", tx.TransactionID)
	}
	if tx.Amount != 0 {
		t.Errorf("expected zero amount for missing field, got %.2f", tx.Amount)
	}
}

// --- Handle behaviour (without AWS clients) ---
// Handler has nil DynamoDB/SNS clients. This verifies branching logic:
//   - Invalid JSON → returns nil (discards gracefully, logs error, never panics)
//   - Valid JSON   → returns error (because DynamoDB write fails on nil client)

func TestHandle_InvalidJSON_ReturnsNil(t *testing.T) {
	h := &Handler{}
	err := h.Handle(context.Background(), "garbage data {{{")
	if err != nil {
		t.Errorf("expected nil error for unparseable message, got %v", err)
	}
}

func TestHandle_EmptyBody_ReturnsNil(t *testing.T) {
	h := &Handler{}
	err := h.Handle(context.Background(), "")
	if err != nil {
		t.Errorf("expected nil error for empty body, got %v", err)
	}
}

func TestHandle_ValidJSON_FailsOnDynamo(t *testing.T) {
	// With nil DynamoDB client, Handle should return an error (not panic)
	// because it tries to call flagForReview which needs DynamoDB.
	h := &Handler{}
	err := h.Handle(context.Background(), validTxJSON())
	if err == nil {
		t.Error("expected error when DynamoDB client is nil, got nil")
	}
}
