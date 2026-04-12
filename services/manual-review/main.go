package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/manual-review/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	dlqURL := requireEnv("DLQ_QUEUE_URL")
	tableName := requireEnv("DYNAMODB_TABLE_NAME")
	alertTopicARN := requireEnv("ALERT_TOPIC_ARN")

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	dynamoClient := dynamodb.NewFromConfig(awsCfg)
	snsClient := sns.NewFromConfig(awsCfg)

	h := handler.New(dynamoClient, tableName, snsClient, alertTopicARN)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: dlqURL,
	}, h.Handle)

	log.Println("Starting manual review service (consuming from DLQ)...")
	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("consumer error: %v", err)
	}
	log.Println("Manual review service stopped.")
}

func requireEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("%s is required", key)
	}
	return v
}
