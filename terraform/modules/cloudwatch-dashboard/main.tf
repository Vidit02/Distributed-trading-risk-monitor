locals {
  # CloudWatch needs just the part after "loadbalancer/" in the ARN as the LoadBalancer dimension
  # e.g. arn:aws:...:loadbalancer/app/project-alb/abc123 becomes app/project-alb/abc123
  alb_suffix = regex("loadbalancer/(.*)", var.alb_arn)[0]

  # These match the queue names created in the sqs module
  high_priority_queue_name     = "${var.project}-high-priority"
  low_priority_queue_name      = "${var.project}-low-priority"
  high_priority_dlq_name       = "${var.project}-high-priority-dlq"
  low_priority_dlq_name        = "${var.project}-low-priority-dlq"
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
          title   = "Main Queue Depth"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", local.high_priority_queue_name,
              { label = "High Priority", color = "#d13212" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", local.low_priority_queue_name,
              { label = "Low Priority", color = "#1f77b4" }]
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
          title   = "Dead-Letter Queue Depth"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", local.high_priority_dlq_name,
              { label = "High Priority DLQ", color = "#d13212" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", local.low_priority_dlq_name,
              { label = "Low Priority DLQ", color = "#ff7f0e" }]
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
          title   = "Queue Processing Latency (Oldest Message Age)"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage",
              "QueueName", local.high_priority_queue_name,
              { label = "High Priority", color = "#d13212" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage",
              "QueueName", local.low_priority_queue_name,
              { label = "Low Priority", color = "#1f77b4" }]
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
          title   = "SQS Message Processing Failures (DLQ rate)"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent",
              "QueueName", local.high_priority_dlq_name,
              { label = "Sent to High DLQ", color = "#d13212" }],
            ["AWS/SQS", "NumberOfMessagesSent",
              "QueueName", local.low_priority_dlq_name,
              { label = "Sent to Low DLQ", color = "#ff7f0e" }]
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
          title   = "Messages Sent to Queues"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent",
              "QueueName", local.high_priority_queue_name,
              { label = "High Priority", color = "#d13212" }],
            ["AWS/SQS", "NumberOfMessagesSent",
              "QueueName", local.low_priority_queue_name,
              { label = "Low Priority", color = "#1f77b4" }]
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
          title   = "Messages Deleted (Successfully Processed)"
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesDeleted",
              "QueueName", local.high_priority_queue_name,
              { label = "High Priority", color = "#2ca02c" }],
            ["AWS/SQS", "NumberOfMessagesDeleted",
              "QueueName", local.low_priority_queue_name,
              { label = "Low Priority", color = "#17becf" }]
          ]
          yAxis = { left = { min = 0, label = "Messages" } }
        }
      }

    ]
  })
}
