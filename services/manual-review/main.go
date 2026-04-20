package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strings"
	"sync"
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

	tableName     := requireEnv("DYNAMODB_TABLE_NAME")
	alertTopicARN := requireEnv("ALERT_TOPIC_ARN")

	// Collect all DLQ URLs — primary + any additional ones
	dlqURLs := collectDLQURLs()
	if len(dlqURLs) == 0 {
		log.Fatalf("no DLQ URLs configured — set DLQ_QUEUE_URL and/or EXTRA_DLQ_URLS")
	}

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("load AWS config: %v", err)
	}

	sqsClient    := sqs.NewFromConfig(awsCfg)
	dynamoClient := dynamodb.NewFromConfig(awsCfg)
	snsClient    := sns.NewFromConfig(awsCfg)

	h := handler.New(dynamoClient, tableName, snsClient, alertTopicARN)

	log.Printf("Starting manual review service — consuming from %d DLQ(s)...", len(dlqURLs))
	for _, url := range dlqURLs {
		log.Printf("  → %s", url)
	}

	var wg sync.WaitGroup
	for _, url := range dlqURLs {
		wg.Add(1)
		go func(queueURL string) {
			defer wg.Done()
			consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
				QueueURL: queueURL,
			}, h.Handle)
			if err := consumer.Start(ctx); err != nil {
				log.Printf("consumer error (%s): %v", queueURL, err)
			}
		}(url)
	}

	wg.Wait()
	log.Println("Manual review service stopped.")
}

// collectDLQURLs gathers DLQ URLs from:
//   DLQ_QUEUE_URL  — primary (required, backwards-compat)
//   EXTRA_DLQ_URLS — comma-separated list of additional DLQs
func collectDLQURLs() []string {
	seen := map[string]bool{}
	var urls []string

	add := func(u string) {
		u = strings.TrimSpace(u)
		if u != "" && !seen[u] {
			seen[u] = true
			urls = append(urls, u)
		}
	}

	add(os.Getenv("DLQ_QUEUE_URL"))

	for _, u := range strings.Split(os.Getenv("EXTRA_DLQ_URLS"), ",") {
		add(u)
	}

	return urls
}

func requireEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("%s is required", key)
	}
	return v
}
