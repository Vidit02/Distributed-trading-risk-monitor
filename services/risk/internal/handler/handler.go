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
	"github.com/redis/go-redis/v9"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

const dailyKeyTTL = 24 * time.Hour

// SyncMode controls how the risk service writes to Redis across regions.
//   single     — write only to the primary Redis.
//   local      — write only to the primary Redis (but assumes it's region-local).
//   dual-write — write to primary, then synchronously to a secondary Redis.
//                This is the CP leg of the CAP tradeoff: consistency across
//                regions at the cost of added cross-region latency per write.
type SyncMode string

const (
	SyncModeSingle    SyncMode = "single"
	SyncModeLocal     SyncMode = "local"
	SyncModeDualWrite SyncMode = "dual-write"
)

// CheckMode controls how the daily-limit check is performed against Redis.
//   atomic     — uses INCRBYFLOAT: increment and read the new total in one
//                atomic Redis operation; no race window.
//   non-atomic — GET current value → sleep 10 ms → compare+SET; deliberately
//                racy so two concurrent requests can both read the old value,
//                both pass the limit check, and both be allowed through.
type CheckMode string

const (
	CheckModeAtomic    CheckMode = "atomic"
	CheckModeNonAtomic CheckMode = "non-atomic"
)

// Handler tracks cumulative user risk exposure in Redis.
// When a user's daily spend crosses the configured threshold, it publishes
// a RiskBreach event to SNS and marks the transaction blocked in DynamoDB.
type Handler struct {
	redis          *redis.Client
	redisSecondary *redis.Client // nil unless syncMode == dual-write
	sns            *sns.Client
	topicARN       string
	dynamo         *dynamodb.Client
	tableName      string
	dailyLimit     float64
	syncMode       SyncMode
	checkMode      CheckMode
	regionLabel    string
}

// New creates a Handler in single-region, atomic-check mode.
// Kept for backwards compatibility with existing callers.
func New(redisClient *redis.Client, snsClient *sns.Client, topicARN string, dynamoClient *dynamodb.Client, tableName string, dailyLimit float64) *Handler {
	return &Handler{
		redis:       redisClient,
		sns:         snsClient,
		topicARN:    topicARN,
		dynamo:      dynamoClient,
		tableName:   tableName,
		dailyLimit:  dailyLimit,
		syncMode:    SyncModeSingle,
		checkMode:   CheckModeAtomic,
		regionLabel: "default",
	}
}

// NewWithSync creates a Handler that can run in any sync/check mode combination.
// redisSecondary is only consulted when syncMode == SyncModeDualWrite; pass nil otherwise.
func NewWithSync(
	redisClient *redis.Client,
	redisSecondary *redis.Client,
	snsClient *sns.Client,
	topicARN string,
	dynamoClient *dynamodb.Client,
	tableName string,
	dailyLimit float64,
	syncMode SyncMode,
	checkMode CheckMode,
	regionLabel string,
) *Handler {
	return &Handler{
		redis:          redisClient,
		redisSecondary: redisSecondary,
		sns:            snsClient,
		topicARN:       topicARN,
		dynamo:         dynamoClient,
		tableName:      tableName,
		dailyLimit:     dailyLimit,
		syncMode:       syncMode,
		checkMode:      checkMode,
		regionLabel:    regionLabel,
	}
}

// Handle is the sqsconsumer.HandlerFunc implementation.
// Return nil → message deleted. Return error → message stays in queue for retry.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		log.Printf("[%s] risk: unparseable message, discarding: %v", h.regionLabel, err)
		return nil
	}

	prevTotal, newTotal, err := h.updateRisk(ctx, tx)
	if err != nil {
		return fmt.Errorf("update risk state: %w", err)
	}

	allowed := newTotal <= h.dailyLimit
	log.Printf("[%s] risk: check_mode=%s sync_mode=%s user=%s tx=%s amount=%.2f prev_total=%.2f new_total=%.2f limit=%.2f allowed=%v",
		h.regionLabel, h.checkMode, h.syncMode,
		tx.UserID, tx.TransactionID, tx.Amount, prevTotal, newTotal, h.dailyLimit, allowed)

	if !allowed {
		breach := events.RiskBreach{
			BreachID:       uuid.New().String(),
			TransactionID:  tx.TransactionID,
			UserID:         tx.UserID,
			ThresholdType:  events.ThresholdTypeDailyLimit,
			CurrentValue:   newTotal,
			ThresholdValue: h.dailyLimit,
			BreachedAt:     time.Now().UTC(),
		}
		if err := h.blockTransaction(ctx, tx, breach.BreachID); err != nil {
			log.Printf("[%s] risk: DynamoDB update failed for %s: %v", h.regionLabel, tx.TransactionID, err)
		}
		if err := h.publishBreach(ctx, breach); err != nil {
			return fmt.Errorf("publish risk breach: %w", err)
		}
		log.Printf("[%s] risk: breach published for user=%s (total=%.2f > limit=%.2f)",
			h.regionLabel, tx.UserID, newTotal, h.dailyLimit)
	}

	return nil
}

// updateRisk updates the user's daily spend in Redis and returns (prevTotal, newTotal, error).
// The update strategy depends on checkMode:
//
//   atomic     — INCRBYFLOAT in a single Redis round-trip; no race window.
//   non-atomic — GET → sleep 10 ms → check → SET; deliberately racy so two
//                concurrent requests can both read the same stale value, both
//                pass the limit check, and both be written as allowed.
//
// In dual-write syncMode the chosen operation is also mirrored to the secondary.
func (h *Handler) updateRisk(ctx context.Context, tx events.TransactionEvent) (prevTotal, newTotal float64, err error) {
	key := fmt.Sprintf("risk:user:%s:daily", tx.UserID)

	if h.checkMode == CheckModeNonAtomic {
		return h.updateRiskNonAtomic(ctx, tx, key)
	}
	return h.updateRiskAtomic(ctx, tx, key)
}

// updateRiskAtomic uses INCRBYFLOAT — the increment and read are one atomic operation.
func (h *Handler) updateRiskAtomic(ctx context.Context, tx events.TransactionEvent, key string) (prevTotal, newTotal float64, err error) {
	primaryStart := time.Now()
	newTotal, err = h.redis.IncrByFloat(ctx, key, tx.Amount).Result()
	if err != nil {
		return 0, 0, fmt.Errorf("redis INCRBYFLOAT (primary): %w", err)
	}
	log.Printf("[%s] risk: primary_redis_latency=%v", h.regionLabel, time.Since(primaryStart))

	prevTotal = newTotal - tx.Amount

	if newTotal == tx.Amount {
		if err := h.redis.Expire(ctx, key, dailyKeyTTL).Err(); err != nil {
			log.Printf("[%s] risk: failed to set TTL on primary key %s: %v", h.regionLabel, key, err)
		}
	}

	if h.syncMode == SyncModeDualWrite && h.redisSecondary != nil {
		secondaryStart := time.Now()
		secondaryTotal, err := h.redisSecondary.IncrByFloat(ctx, key, tx.Amount).Result()
		if err != nil {
			return 0, 0, fmt.Errorf("redis INCRBYFLOAT (secondary): %w", err)
		}
		log.Printf("[%s] risk: secondary_redis_latency=%v", h.regionLabel, time.Since(secondaryStart))
		if secondaryTotal == tx.Amount {
			if err := h.redisSecondary.Expire(ctx, key, dailyKeyTTL).Err(); err != nil {
				log.Printf("[%s] risk: failed to set TTL on secondary key %s: %v", h.regionLabel, key, err)
			}
		}
	}

	return prevTotal, newTotal, nil
}

// updateRiskNonAtomic deliberately introduces a race window: GET the current
// value, sleep 10 ms (widening the window for concurrent requests), then SET
// the new total. Two goroutines can both read the same stale prevTotal, both
// compute newTotal < dailyLimit, and both write — allowing spend past the limit.
func (h *Handler) updateRiskNonAtomic(ctx context.Context, tx events.TransactionEvent, key string) (prevTotal, newTotal float64, err error) {
	// Step 1: GET current value (may be stale if a concurrent request is in flight)
	val, err := h.redis.Get(ctx, key).Result()
	if err != nil && err != redis.Nil {
		return 0, 0, fmt.Errorf("redis GET (non-atomic primary): %w", err)
	}
	if err == redis.Nil {
		prevTotal = 0
	} else {
		if _, scanErr := fmt.Sscanf(val, "%f", &prevTotal); scanErr != nil {
			return 0, 0, fmt.Errorf("redis GET parse error: %w", scanErr)
		}
	}

	// Step 2: sleep to widen the race window
	time.Sleep(10 * time.Millisecond)

	// Step 3: compute new total and SET (no atomicity guarantee)
	newTotal = prevTotal + tx.Amount
	if err := h.redis.Set(ctx, key, fmt.Sprintf("%f", newTotal), dailyKeyTTL).Err(); err != nil {
		return 0, 0, fmt.Errorf("redis SET (non-atomic primary): %w", err)
	}

	if h.syncMode == SyncModeDualWrite && h.redisSecondary != nil {
		if err := h.redisSecondary.Set(ctx, key, fmt.Sprintf("%f", newTotal), dailyKeyTTL).Err(); err != nil {
			return 0, 0, fmt.Errorf("redis SET (non-atomic secondary): %w", err)
		}
	}

	return prevTotal, newTotal, nil
}

// blockTransaction marks the transaction as blocked in DynamoDB due to a risk limit breach.
func (h *Handler) blockTransaction(ctx context.Context, tx events.TransactionEvent, breachID string) error {
	_, err := h.dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(h.tableName),
		Key: map[string]dynamodbTypes.AttributeValue{
			"transaction_id": &dynamodbTypes.AttributeValueMemberS{Value: tx.TransactionID},
			"timestamp":      &dynamodbTypes.AttributeValueMemberS{Value: tx.Timestamp.Format(time.RFC3339Nano)},
		},
		UpdateExpression: aws.String("SET #st = :status, flagged_reason = :reason, breach_id = :breach_id"),
		ExpressionAttributeNames: map[string]string{
			"#st": "status",
		},
		ExpressionAttributeValues: map[string]dynamodbTypes.AttributeValue{
			":status":   &dynamodbTypes.AttributeValueMemberS{Value: "blocked"},
			":reason":   &dynamodbTypes.AttributeValueMemberS{Value: "risk_limit_exceeded"},
			":breach_id": &dynamodbTypes.AttributeValueMemberS{Value: breachID},
		},
	})
	return err
}

// publishBreach serialises the RiskBreach and sends it to SNS.
func (h *Handler) publishBreach(ctx context.Context, breach events.RiskBreach) error {
	payload, err := json.Marshal(breach)
	if err != nil {
		return fmt.Errorf("marshal breach: %w", err)
	}

	_, err = h.sns.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(h.topicARN),
		Message:  aws.String(string(payload)),
		MessageAttributes: map[string]snsTypes.MessageAttributeValue{
			"event_type": {
				DataType:    aws.String("String"),
				StringValue: aws.String("risk-breach"),
			},
			"threshold_type": {
				DataType:    aws.String("String"),
				StringValue: aws.String(string(breach.ThresholdType)),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("sns publish: %w", err)
	}
	return nil
}
