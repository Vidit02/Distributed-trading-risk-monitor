package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/analytics/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL := mustEnv("QUEUE_URL")

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("analytics: load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(cfg)
	cwClient := cloudwatch.NewFromConfig(cfg)

	h := handler.New(cwClient)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL:        queueURL,
		MaxMessages:     10,
		WaitTimeSeconds: 20,
	}, h.Handle)

	log.Println("analytics: service started, consuming low-priority queue")

	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("analytics: consumer error: %v", err)
	}

	log.Println("analytics: service stopped")
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("analytics: required env var %q is not set", key)
	}
	return v
}
