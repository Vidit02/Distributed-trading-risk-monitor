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

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/fraud/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL := os.Getenv("HIGH_PRIORITY_QUEUE_URL")
	if queueURL == "" {
		log.Fatal("HIGH_PRIORITY_QUEUE_URL is required")
	}
	fraudAlertTopicARN := os.Getenv("FRAUD_ALERT_TOPIC_ARN")
	if fraudAlertTopicARN == "" {
		log.Fatal("FRAUD_ALERT_TOPIC_ARN is required")
	}
	tableName := os.Getenv("DYNAMODB_TABLE_NAME")
	if tableName == "" {
		log.Fatal("DYNAMODB_TABLE_NAME is required")
	}

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	snsClient := sns.NewFromConfig(awsCfg)
	dynamoClient := dynamodb.NewFromConfig(awsCfg)

	h := handler.New(snsClient, fraudAlertTopicARN, dynamoClient, tableName)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: queueURL,
	}, h.Handle)

	log.Println("Starting fraud detection service...")
	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("consumer error: %v", err)
	}
	log.Println("Fraud detection service stopped.")
}
