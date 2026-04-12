package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/alert/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL := os.Getenv("ALERT_QUEUE_URL")
	if queueURL == "" {
		log.Fatal("ALERT_QUEUE_URL is required")
	}

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)

	h := handler.New()

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: queueURL,
	}, h.Handle)

	log.Println("Starting alert service...")
	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("consumer error: %v", err)
	}
	log.Println("Alert service stopped.")
}
