package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/compliance/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL := requireEnv("HIGH_PRIORITY_QUEUE_URL")
	complianceTopicARN := requireEnv("COMPLIANCE_TOPIC_ARN")

	// Comma-separated lists of blocked user/merchant IDs loaded at startup.
	// Example: BLOCKED_USERS=user-123,user-456
	blockedUsers := splitCSV(os.Getenv("BLOCKED_USERS"))
	blockedMerchants := splitCSV(os.Getenv("BLOCKED_MERCHANTS"))

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(awsCfg)
	snsClient := sns.NewFromConfig(awsCfg)

	h := handler.New(snsClient, complianceTopicARN, blockedUsers, blockedMerchants)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL: queueURL,
	}, h.Handle)

	log.Printf("Starting compliance service (blocked_users=%d blocked_merchants=%d)...",
		len(blockedUsers), len(blockedMerchants))

	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("consumer error: %v", err)
	}
	log.Println("Compliance service stopped.")
}

func requireEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("%s is required", key)
	}
	return v
}

func splitCSV(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, ",")
}
