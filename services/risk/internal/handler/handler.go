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
	"github.com/redis/go-redis/v9"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
)

const dailyKeyTTL = 24 * time.Hour

// Handler tracks cumulative user risk exposure in Redis.
// When a user's daily spend crosses the configured threshold, it publishes
// a RiskBreach event to SNS.
type Handler struct {
	redis      *redis.Client
	sns        *sns.Client
	topicARN   string
	dailyLimit float64
}

func New(redisClient *redis.Client, snsClient *sns.Client, topicARN string, dailyLimit float64) *Handler {
	return &Handler{
		redis:      redisClient,
		sns:        snsClient,
		topicARN:   topicARN,
		dailyLimit: dailyLimit,
	}
}

// Handle is the sqsconsumer.HandlerFunc implementation.
// Return nil → message deleted. Return error → message stays in queue for retry.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		log.Printf("risk: unparseable message, discarding: %v", err)
		return nil
	}

	newTotal, err := h.updateRisk(ctx, tx)
	if err != nil {
		return fmt.Errorf("update risk state: %w", err)
	}

	log.Printf("risk: user=%s tx=%s amount=%.2f daily_total=%.2f limit=%.2f",
		tx.UserID, tx.TransactionID, tx.Amount, newTotal, h.dailyLimit)

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
		if err := h.publishBreach(ctx, breach); err != nil {
			return fmt.Errorf("publish risk breach: %w", err)
		}
		log.Printf("risk: breach published for user=%s (total=%.2f > limit=%.2f)",
			tx.UserID, newTotal, h.dailyLimit)
	}

	return nil
}

// updateRisk atomically adds the transaction amount to the user's daily
// cumulative spend in Redis and returns the new total.
func (h *Handler) updateRisk(ctx context.Context, tx events.TransactionEvent) (float64, error) {
	key := fmt.Sprintf("risk:user:%s:daily", tx.UserID)

	newTotal, err := h.redis.IncrByFloat(ctx, key, tx.Amount).Result()
	if err != nil {
		return 0, fmt.Errorf("redis INCRBYFLOAT: %w", err)
	}

	if newTotal == tx.Amount {
		if err := h.redis.Expire(ctx, key, dailyKeyTTL).Err(); err != nil {
			log.Printf("risk: failed to set TTL for key %s: %v", key, err)
		}
	}

	return newTotal, nil
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
