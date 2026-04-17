locals {
  alb_suffix = regex("loadbalancer/(.*)", var.alb_arn)[0]

  # Per-service queue + DLQ names (SNS fan-out — one queue per consumer)
  fraud_queue_name         = "${var.project}-fraud"
  risk_queue_name          = "${var.project}-risk"
  compliance_queue_name    = "${var.project}-compliance"
  analytics_queue_name     = "${var.project}-analytics"
  audit_logging_queue_name = "${var.project}-audit-logging"

  fraud_dlq_name         = "${var.project}-fraud-dlq"
  risk_dlq_name          = "${var.project}-risk-dlq"
  compliance_dlq_name    = "${var.project}-compliance-dlq"
  analytics_dlq_name     = "${var.project}-analytics-dlq"
  audit_logging_dlq_name = "${var.project}-audit-logging-dlq"
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-trading-risk-monitor"

  dashboard_body = jsonencode({
    widgets = [

      # Row 1: Queue Depth

      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## Queue Depth"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title   = "Per-Service Queue Depth"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.fraud_queue_name, { label = "fraud" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.risk_queue_name, { label = "risk" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.compliance_queue_name, { label = "compliance" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.analytics_queue_name, { label = "analytics" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.audit_logging_queue_name, { label = "audit-logging" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title   = "Per-Service DLQ Depth"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.fraud_dlq_name, { label = "fraud DLQ" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.risk_dlq_name, { label = "risk DLQ" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.compliance_dlq_name, { label = "compliance DLQ" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.analytics_dlq_name, { label = "analytics DLQ" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.audit_logging_dlq_name, { label = "audit-logging DLQ" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      },

      # Row 2: Latency

      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = {
          markdown = "## Latency"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Oldest Message Age (per service)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.fraud_queue_name, { label = "fraud" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.risk_queue_name, { label = "risk" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.compliance_queue_name, { label = "compliance" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.analytics_queue_name, { label = "analytics" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.audit_logging_queue_name, { label = "audit-logging" }]
          ]
          yAxis = { left = { min = 0, label = "Seconds" } }
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Transaction Service Response Time (ALB)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", local.alb_suffix,
            { stat = "p50", label = "p50", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", local.alb_suffix,
            { stat = "p95", label = "p95", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", local.alb_suffix,
            { stat = "p99", label = "p99", color = "#d13212" }]
          ]
          yAxis = { left = { min = 0, label = "Seconds" } }
        }
      },

      # Row 3: Errors

      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = {
          markdown = "## Errors"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 12
        height = 6
        properties = {
          title   = "ALB HTTP Error Rates"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count",
              "LoadBalancer", local.alb_suffix,
            { label = "4xx (Client Errors)", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
              "LoadBalancer", local.alb_suffix,
            { label = "5xx (Server Errors)", color = "#d13212" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count",
              "LoadBalancer", local.alb_suffix,
            { label = "5xx (ALB Errors)", color = "#9467bd" }]
          ]
          yAxis = { left = { min = 0, label = "Count" } }
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 15
        width  = 12
        height = 6
        properties = {
          title   = "Messages Sent to DLQs (processing failures)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.fraud_dlq_name, { label = "fraud DLQ" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.risk_dlq_name, { label = "risk DLQ" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.compliance_dlq_name, { label = "compliance DLQ" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.analytics_dlq_name, { label = "analytics DLQ" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.audit_logging_dlq_name, { label = "audit-logging DLQ" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      },

      # Row 4: Task Count

      {
        type   = "text"
        x      = 0
        y      = 21
        width  = 24
        height = 1
        properties = {
          markdown = "## ECS Task Count"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 22
        width  = 24
        height = 6
        properties = {
          title   = "Running Tasks per Service"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", var.transaction_service_name,
            { label = "transaction" }],
            ["ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", var.fraud_service_name,
            { label = "fraud" }],
            ["ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", var.risk_service_name,
            { label = "risk" }],
            ["ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", var.analytics_service_name,
            { label = "analytics" }],
            ["ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", var.audit_logging_service_name,
            { label = "audit-logging" }]
          ]
          yAxis = { left = { min = 0, label = "Tasks" } }
        }
      },

      # Row 5: Throughput

      {
        type   = "text"
        x      = 0
        y      = 28
        width  = 24
        height = 1
        properties = {
          markdown = "## Throughput"
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 29
        width  = 12
        height = 6
        properties = {
          title   = "Messages Sent to Queues (per service)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.fraud_queue_name, { label = "fraud" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.risk_queue_name, { label = "risk" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.compliance_queue_name, { label = "compliance" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.analytics_queue_name, { label = "analytics" }],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.audit_logging_queue_name, { label = "audit-logging" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 29
        width  = 12
        height = 6
        properties = {
          title   = "Messages Deleted / Successfully Processed (per service)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.fraud_queue_name, { label = "fraud" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.risk_queue_name, { label = "risk" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.compliance_queue_name, { label = "compliance" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.analytics_queue_name, { label = "analytics" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.audit_logging_queue_name, { label = "audit-logging" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      }

    ]
  })
}
