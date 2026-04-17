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
	regionLabel    string
}

// New creates a Handler in single-region mode (no secondary Redis).
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
		regionLabel: "default",
	}
}

// NewWithSync creates a Handler that can run in any of the three sync modes.
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

	newTotal, err := h.updateRisk(ctx, tx)
	if err != nil {
		return fmt.Errorf("update risk state: %w", err)
	}

	log.Printf("[%s] risk: user=%s tx=%s amount=%.2f daily_total=%.2f limit=%.2f sync_mode=%s",
		h.regionLabel, tx.UserID, tx.TransactionID, tx.Amount, newTotal, h.dailyLimit, h.syncMode)

	if newTotal > h.dailyLimit {
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

// updateRisk atomically adds the transaction amount to the user's daily
// cumulative spend in Redis and returns the new total. In dual-write mode
// it also writes synchronously to the secondary Redis, failing the whole
// operation if the secondary write fails (CP tradeoff).
func (h *Handler) updateRisk(ctx context.Context, tx events.TransactionEvent) (float64, error) {
	key := fmt.Sprintf("risk:user:%s:daily", tx.UserID)

	// --- Primary Redis write (always happens, in every mode) ---
	primaryStart := time.Now()
	newTotal, err := h.redis.IncrByFloat(ctx, key, tx.Amount).Result()
	primaryLatency := time.Since(primaryStart)
	if err != nil {
		return 0, fmt.Errorf("redis INCRBYFLOAT (primary): %w", err)
	}
	log.Printf("[%s] risk: primary_redis_latency=%v", h.regionLabel, primaryLatency)

	// Anchor TTL to the first write of the day (primary).
	if newTotal == tx.Amount {
		if err := h.redis.Expire(ctx, key, dailyKeyTTL).Err(); err != nil {
			log.Printf("[%s] risk: failed to set TTL on primary key %s: %v", h.regionLabel, key, err)
		}
	}

	// --- Secondary Redis write (dual-write mode only, SYNCHRONOUS) ---
	// This is the CP leg: the handler does not return until the secondary
	// acknowledges, so the user waits for cross-region replication. A failure
	// here is fatal to the whole operation — the message stays on the queue
	// and will be retried.
	if h.syncMode == SyncModeDualWrite && h.redisSecondary != nil {
		secondaryStart := time.Now()
		secondaryTotal, err := h.redisSecondary.IncrByFloat(ctx, key, tx.Amount).Result()
		secondaryLatency := time.Since(secondaryStart)
		if err != nil {
			return 0, fmt.Errorf("redis INCRBYFLOAT (secondary): %w", err)
		}
		log.Printf("[%s] risk: secondary_redis_latency=%v", h.regionLabel, secondaryLatency)

		if secondaryTotal == tx.Amount {
			if err := h.redisSecondary.Expire(ctx, key, dailyKeyTTL).Err(); err != nil {
				log.Printf("[%s] risk: failed to set TTL on secondary key %s: %v",
					h.regionLabel, key, err)
			}
		}
	}

	return newTotal, nil
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
