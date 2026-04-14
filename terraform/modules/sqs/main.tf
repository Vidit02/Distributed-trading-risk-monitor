locals {
  name_prefix = var.project
}

# Dead-Letter Queues
resource "aws_sqs_queue" "high_priority_dlq" {
  name                      = "${local.name_prefix}-high-priority-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "${local.name_prefix}-high-priority-dlq"
  }
}

resource "aws_sqs_queue" "low_priority_dlq" {
  name                      = "${local.name_prefix}-low-priority-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "${local.name_prefix}-low-priority-dlq"
  }
}

# High-Priority Queue
# Receives transactions with priority = "high" or "critical"
resource "aws_sqs_queue" "high_priority" {
  name                       = "${local.name_prefix}-high-priority"
  visibility_timeout_seconds = var.high_priority_visibility_timeout
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.high_priority_dlq.arn
    maxReceiveCount     = var.high_priority_max_receive_count
  })

  tags = {
    Name     = "${local.name_prefix}-high-priority"
    Priority = "high"
  }
}

# Low-Priority Queue
# Receives transactions with priority = "low" or "medium"
resource "aws_sqs_queue" "low_priority" {
  name                       = "${local.name_prefix}-low-priority"
  visibility_timeout_seconds = var.low_priority_visibility_timeout
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.low_priority_dlq.arn
    maxReceiveCount     = var.low_priority_max_receive_count
  })

  tags = {
    Name     = "${local.name_prefix}-low-priority"
    Priority = "low"
  }
}

# Queue Policies — allow SNS to send messages to both queues
data "aws_iam_policy_document" "high_priority_policy" {
  statement {
    sid    = "AllowSNSPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.high_priority.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.sns_topic_arn]
    }
  }
}

data "aws_iam_policy_document" "low_priority_policy" {
  statement {
    sid    = "AllowSNSPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.low_priority.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.sns_topic_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "high_priority" {
  queue_url = aws_sqs_queue.high_priority.id
  policy    = data.aws_iam_policy_document.high_priority_policy.json
}

resource "aws_sqs_queue_policy" "low_priority" {
  queue_url = aws_sqs_queue.low_priority.id
  policy    = data.aws_iam_policy_document.low_priority_policy.json
}


# SNS → SQS Subscriptions with Filter Policies
#
# Filter key: `priority` (SNS message attribute, type String)
#   high-priority queue  → ["high", "critical"]
#   low-priority queue   → ["low", "medium"]
resource "aws_sns_topic_subscription" "high_priority" {
  topic_arn = var.sns_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.high_priority.arn

  filter_policy = jsonencode({
    priority = ["high", "critical"]
  })

  # filter_policy_scope = "MessageAttributes" is the default; no need to set it
  depends_on = [aws_sqs_queue_policy.high_priority]
}

resource "aws_sns_topic_subscription" "low_priority" {
  topic_arn = var.sns_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.low_priority.arn

  filter_policy = jsonencode({
    priority = ["low", "medium"]
  })

  depends_on = [aws_sqs_queue_policy.low_priority]
}


# ---------------------------------------------------------------------------
# Alert Queue — receives fraud-alert-events and risk-breach-events
# Consumed by the Alert Service
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "alert_dlq" {
  name                      = "${local.name_prefix}-alert-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${local.name_prefix}-alert-dlq" }
}

resource "aws_sqs_queue" "alert" {
  name                       = "${local.name_prefix}-alert"
  visibility_timeout_seconds = 30
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.alert_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${local.name_prefix}-alert" }
}

data "aws_iam_policy_document" "alert_policy" {
  statement {
    sid    = "AllowSNSPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.alert.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.fraud_alert_topic_arn, var.risk_breach_topic_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "alert" {
  queue_url = aws_sqs_queue.alert.id
  policy    = data.aws_iam_policy_document.alert_policy.json
}

resource "aws_sns_topic_subscription" "alert_fraud" {
  topic_arn = var.fraud_alert_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.alert.arn

  depends_on = [aws_sqs_queue_policy.alert]
}

resource "aws_sns_topic_subscription" "alert_risk_breach" {
  topic_arn = var.risk_breach_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.alert.arn

  depends_on = [aws_sqs_queue_policy.alert]
}
