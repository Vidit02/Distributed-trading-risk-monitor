package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/redis/go-redis/v9"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/risk/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL := requireEnv("HIGH_PRIORITY_QUEUE_URL")
	riskBreachTopicARN := requireEnv("RISK_BREACH_TOPIC_ARN")
	redisAddr := requireEnv("REDIS_ADDR")

	// Sync mode controls how writes propagate across regions.
	//   "single"     → only the primary Redis is written.
	//   "local"      → only the primary Redis is written (assumed region-local).
	//   "dual-write" → primary THEN secondary (synchronous).
	syncMode := handler.SyncMode(envOr("REDIS_SYNC_MODE", string(handler.SyncModeSingle)))
	regionLabel := envOr("REDIS_REGION_LABEL", "default")

	dailyLimit := 50_000.0
	if v := os.Getenv("DAILY_LIMIT"); v != "" {
		parsed, err := strconv.ParseFloat(v, 64)
		if err != nil {
			log.Fatalf("invalid DAILY_LIMIT value: %v", err)
		}
		dailyLimit = parsed
	}

	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("primary redis connection failed: %v", err)
	}
	defer redisClient.Close()

	// Secondary Redis is only created and tested when we're actually going to use it.
	var redisSecondary *redis.Client
	if syncMode == handler.SyncModeDualWrite {
		secondaryAddr := requireEnv("REDIS_SECONDARY_ADDR")
		redisSecondary = redis.NewClient(&redis.Options{Addr: secondaryAddr})
		if err := redisSecondary.Ping(ctx).Err(); err != nil {
			log.Fatalf("secondary redis connection failed: %v", err)
		}
		defer redisSecondary.Close()
		log.Printf("Secondary redis connected at %s", secondaryAddr)
	}

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	snsClient := sns.NewFromConfig(awsCfg)

	h := handler.NewWithSync(
		redisClient,
		redisSecondary,
		snsClient,
		riskBreachTopicARN,
		dailyLimit,
		syncMode,
		regionLabel,
	)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: queueURL,
	}, h.Handle)

	log.Printf("Starting risk monitor service (daily_limit=%.2f sync_mode=%s region_label=%s)...",
		dailyLimit, syncMode, regionLabel)
	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("consumer error: %v", err)
	}
	log.Println("Risk monitor service stopped.")
}

func requireEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("%s is required", key)
	}
	return v
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
