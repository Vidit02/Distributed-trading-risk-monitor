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
	redisAddr := requireEnv("REDIS_ADDR") // e.g. "localhost:6379"

	dailyLimit := 50_000.0 // default $50,000 daily per user
	if v := os.Getenv("DAILY_LIMIT"); v != "" {
		parsed, err := strconv.ParseFloat(v, 64)
		if err != nil {
			log.Fatalf("invalid DAILY_LIMIT value: %v", err)
		}
		dailyLimit = parsed
	}

	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("redis connection failed: %v", err)
	}
	defer redisClient.Close()

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	snsClient := sns.NewFromConfig(awsCfg)

	h := handler.New(redisClient, snsClient, riskBreachTopicARN, dailyLimit)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: queueURL,
	}, h.Handle)

	log.Printf("Starting risk monitor service (daily_limit=%.2f)...", dailyLimit)
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
