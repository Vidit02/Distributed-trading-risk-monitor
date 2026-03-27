package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// AuditRecord is one line written to S3. It wraps the original TransactionEvent
// and adds the time the service received it.
	ReceivedAt      time.Time              `json:"received_at"`
	TransactionID   string                 `json:"transaction_id"`
	UserID          string                 `json:"user_id"`
	Amount          float64                `json:"amount"`
	Currency        string                 `json:"currency"`
	TransactionType events.TransactionType `json:"transaction_type"`
	Priority        events.Priority        `json:"priority"`
	RawPayload      string                 `json:"raw_payload"`
}

// Handler buffers incoming TransactionEvents and batch-writes them to S3
// as JSONL files. A flush happens when the buffer is full OR the flush
// interval elapses — whichever comes first.
type Handler struct {
	s3Client      *s3.Client
	bucket        string
	batchSize     int
	flushInterval time.Duration

	mu     sync.Mutex
	buffer []AuditRecord
}

// Config holds tuning parameters for the Handler.
type Config struct {
	Bucket        string
	BatchSize     int
	FlushInterval time.Duration
}

func New(s3Client *s3.Client, cfg Config) *Handler {
	if cfg.BatchSize == 0 {
		cfg.BatchSize = 100
	}
	if cfg.FlushInterval == 0 {
		cfg.FlushInterval = 30 * time.Second
	}
	return &Handler{
		s3Client:      s3Client,
		bucket:        cfg.Bucket,
		batchSize:     cfg.BatchSize,
		flushInterval: cfg.FlushInterval,
		buffer:        make([]AuditRecord, 0, cfg.BatchSize),
	}
}

// Start runs the background ticker that flushes the buffer on an interval.
// It blocks until ctx is cancelled, then does a final flush of any remaining records.
func (h *Handler) Start(ctx context.Context) {
	ticker := time.NewTicker(h.flushInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			h.flush(ctx, "interval")
		case <-ctx.Done():
			log.Println("audit-logging: context cancelled, flushing final batch")
			h.flush(context.Background(), "shutdown")
			return
		}
	}
}

// Handle parses one TransactionEvent, appends it to the buffer,
// and triggers an immediate flush if the buffer is full.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		return fmt.Errorf("unmarshal TransactionEvent: %w", err)
	}

	record := AuditRecord{
		ReceivedAt:      time.Now().UTC(),
		TransactionID:   tx.TransactionID,
		UserID:          tx.UserID,
		Amount:          tx.Amount,
		Currency:        tx.Currency,
		TransactionType: tx.TransactionType,
		Priority:        tx.Priority,
		RawPayload:      body,
	}

	h.mu.Lock()
	h.buffer = append(h.buffer, record)
	full := len(h.buffer) >= h.batchSize
	h.mu.Unlock()

	if full {
		h.flush(ctx, "batch_full")
	}

	return nil
}

// flush drains the buffer and writes it to S3 as a single JSONL object.
// reason is logged for observability ("interval", "batch_full", "shutdown").
func (h *Handler) flush(ctx context.Context, reason string) {
	h.mu.Lock()
	if len(h.buffer) == 0 {
		h.mu.Unlock()
		return
	}
	batch := h.buffer
	h.buffer = make([]AuditRecord, 0, h.batchSize)
	h.mu.Unlock()

	key := s3Key(time.Now().UTC())

	var buf bytes.Buffer
	for _, r := range batch {
		line, err := json.Marshal(r)
		if err != nil {
			log.Printf("audit-logging: marshal record %s: %v", r.TransactionID, err)
			continue
		}
		buf.Write(line)
		buf.WriteByte('\n')
	}

	_, err := h.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(h.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(buf.Bytes()),
		ContentType: aws.String("application/x-ndjson"),
	})
	if err != nil {
		// Put the batch back so it is not lost — next flush will retry
		h.mu.Lock()
		h.buffer = append(batch, h.buffer...)
		h.mu.Unlock()
		log.Printf("audit-logging: S3 PutObject failed (%s), batch returned to buffer: %v", key, err)
		return
	}

	log.Printf("audit-logging: flushed %d records → s3://%s/%s (reason=%s)",
		len(batch), h.bucket, key, reason)
}

// s3Key returns a time-partitioned path for the batch object.
// Example: audit-logs/2026/03/27/15-04-05-000000000.jsonl
func s3Key(t time.Time) string {
	return fmt.Sprintf("audit-logs/%d/%02d/%02d/%02d-%02d-%02d-%09d.jsonl",
		t.Year(), t.Month(), t.Day(),
		t.Hour(), t.Minute(), t.Second(), t.Nanosecond())
}
