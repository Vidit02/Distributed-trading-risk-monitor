package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/Vidit02/Distributed-trading-risk-monitor/shared/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
)

const metricsNamespace = "TradingRiskMonitor/Analytics"

// Handler processes analytics messages from the low-priority SQS queue
// and publishes aggregated metrics to CloudWatch.
type Handler struct {
	cw *cloudwatch.Client
}

func New(cw *cloudwatch.Client) *Handler {
	return &Handler{cw: cw}
}

// Handle parses a TransactionEvent and emits CloudWatch metrics.
func (h *Handler) Handle(ctx context.Context, body string) error {
	var tx events.TransactionEvent
	if err := json.Unmarshal([]byte(body), &tx); err != nil {
		return fmt.Errorf("unmarshal TransactionEvent: %w", err)
	}

	log.Printf("analytics: processing txn=%s user=%s type=%s amount=%.2f %s priority=%s",
		tx.TransactionID, tx.UserID, tx.TransactionType, tx.Amount, tx.Currency, tx.Priority)

	metrics := h.buildMetrics(tx)

	_, err := h.cw.PutMetricData(ctx, &cloudwatch.PutMetricDataInput{
		Namespace:  aws.String(metricsNamespace),
		MetricData: metrics,
	})
	if err != nil {
		return fmt.Errorf("PutMetricData: %w", err)
	}

	log.Printf("analytics: pushed %d metrics for txn=%s", len(metrics), tx.TransactionID)
	return nil
}

// buildMetrics constructs the CloudWatch metric data points for one transaction.
func (h *Handler) buildMetrics(tx events.TransactionEvent) []types.MetricDatum {
	now := aws.Time(time.Now())

	return []types.MetricDatum{
		// Transaction volume — sliced by type, currency, and priority
		{
			MetricName: aws.String("TransactionCount"),
			Timestamp:  now,
			Value:      aws.Float64(1),
			Unit:       types.StandardUnitCount,
			Dimensions: []types.Dimension{
				{Name: aws.String("TransactionType"), Value: aws.String(string(tx.TransactionType))},
				{Name: aws.String("Currency"), Value: aws.String(tx.Currency)},
				{Name: aws.String("Priority"), Value: aws.String(string(tx.Priority))},
			},
		},
		// Transaction amount — sliced by type and currency for revenue / exposure tracking
		{
			MetricName: aws.String("TransactionAmount"),
			Timestamp:  now,
			Value:      aws.Float64(tx.Amount),
			Unit:       types.StandardUnitNone,
			Dimensions: []types.Dimension{
				{Name: aws.String("TransactionType"), Value: aws.String(string(tx.TransactionType))},
				{Name: aws.String("Currency"), Value: aws.String(tx.Currency)},
			},
		},
		// Per-user activity — helps detect velocity anomalies in dashboards
		{
			MetricName: aws.String("UserTransactionCount"),
			Timestamp:  now,
			Value:      aws.Float64(1),
			Unit:       types.StandardUnitCount,
			Dimensions: []types.Dimension{
				{Name: aws.String("UserID"), Value: aws.String(tx.UserID)},
				{Name: aws.String("Priority"), Value: aws.String(string(tx.Priority))},
			},
		},
	}
}
