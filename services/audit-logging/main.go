package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/Vidit02/Distributed-trading-risk-monitor/services/audit-logging/internal/handler"
	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/sqsconsumer"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	queueURL  := mustEnv("QUEUE_URL")
	bucket    := mustEnv("S3_BUCKET")
	batchSize := envInt("BATCH_SIZE", 100)
	flushSecs := envInt("FLUSH_INTERVAL_SECONDS", 30)

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("audit-logging: load AWS config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(cfg)
	s3Client  := s3.NewFromConfig(cfg)

	h := handler.New(s3Client, handler.Config{
		Bucket:        bucket,
		BatchSize:     batchSize,
		FlushInterval: time.Duration(flushSecs) * time.Second,
	})

	// Background flusher — runs until ctx is cancelled, then does a final flush
	go h.Start(ctx)

	consumer := sqsconsumer.New(sqsClient, sqsconsumer.Config{
		QueueURL:        queueURL,
		MaxMessages:     10,
		WaitTimeSeconds: 20,
	}, h.Handle)

	log.Printf("audit-logging: service started (bucket=%s batchSize=%d flushEvery=%ds)",
		bucket, batchSize, flushSecs)

	if err := consumer.Start(ctx); err != nil {
		log.Fatalf("audit-logging: consumer error: %v", err)
	}

	log.Println("audit-logging: service stopped")
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("audit-logging: required env var %q is not set", key)
	}
	return v
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		log.Fatalf("audit-logging: env var %q must be an integer, got %q", key, v)
	}
	return n
}
