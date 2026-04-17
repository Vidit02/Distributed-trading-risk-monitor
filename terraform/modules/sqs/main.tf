locals {
  name_prefix = var.project

  # fraud/risk/compliance receive only high-priority transactions.
  # analytics/audit-logging receive ALL transactions (no filter) so every
  # transaction is logged and analysed regardless of priority.
  filtered_services = {
    "fraud" = {
      priority_values    = ["high", "critical"]
      visibility_timeout = var.high_priority_visibility_timeout
      max_receive_count  = var.high_priority_max_receive_count
    }
    "risk" = {
      priority_values    = ["high", "critical"]
      visibility_timeout = var.high_priority_visibility_timeout
      max_receive_count  = var.high_priority_max_receive_count
    }
    "compliance" = {
      priority_values    = ["high", "critical"]
      visibility_timeout = var.high_priority_visibility_timeout
      max_receive_count  = var.high_priority_max_receive_count
    }
  }

  unfiltered_services = {
    "analytics" = {
      visibility_timeout = var.low_priority_visibility_timeout
      max_receive_count  = var.low_priority_max_receive_count
    }
    "audit-logging" = {
      visibility_timeout = var.low_priority_visibility_timeout
      max_receive_count  = var.low_priority_max_receive_count
    }
  }

  # Combined map used for queue/DLQ/policy resources.
  services = merge(
    { for k, v in local.filtered_services : k => v },
    { for k, v in local.unfiltered_services : k => v }
  )
}

# ---------------------------------------------------------------------------
# Per-service Dead-Letter Queues
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "service_dlq" {
  for_each = local.services

  name                      = "${local.name_prefix}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${local.name_prefix}-${each.key}-dlq" }
}

# ---------------------------------------------------------------------------
# Per-service Queues — one dedicated queue per consumer
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "service" {
  for_each = local.services

  name                       = "${local.name_prefix}-${each.key}"
  visibility_timeout_seconds = each.value.visibility_timeout
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.service_dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })

  tags = {
    Name    = "${local.name_prefix}-${each.key}"
    Service = each.key
  }
}

# Queue policy — allow SNS to SendMessage
data "aws_iam_policy_document" "service" {
  for_each = local.services

  statement {
    sid    = "AllowSNSPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.service[each.key].arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.sns_topic_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "service" {
  for_each = local.services

  queue_url = aws_sqs_queue.service[each.key].id
  policy    = data.aws_iam_policy_document.service[each.key].json
}

# Filtered subscriptions — fraud/risk/compliance receive only high/critical
resource "aws_sns_topic_subscription" "filtered_service" {
  for_each = local.filtered_services

  topic_arn = var.sns_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.service[each.key].arn

  filter_policy = jsonencode({
    priority = each.value.priority_values
  })

  depends_on = [aws_sqs_queue_policy.service]
}

# Unfiltered subscriptions — analytics/audit-logging receive ALL transactions
resource "aws_sns_topic_subscription" "unfiltered_service" {
  for_each = local.unfiltered_services

  topic_arn = var.sns_topic_arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.service[each.key].arn

  depends_on = [aws_sqs_queue_policy.service]
}

# ---------------------------------------------------------------------------
# Alert Queue — receives fraud-alert-events and risk-breach-events
# Consumed ONLY by the Alert Service (separate concern from the fan-out above).
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "alert_dlq" {
  name                      = "${local.name_prefix}-alert-dlq"
  message_retention_seconds = 1209600

  tags = { Name = "${local.name_prefix}-alert-dlq" }
}

resource "aws_sqs_queue" "alert" {
  name                       = "${local.name_prefix}-alert"
  visibility_timeout_seconds = 60
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
      values   = [var.sns_fraud_alert_arn, var.sns_risk_breach_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "alert" {
  queue_url = aws_sqs_queue.alert.id
  policy    = data.aws_iam_policy_document.alert_policy.json
}

resource "aws_sns_topic_subscription" "fraud_alert_to_alert_queue" {
  topic_arn  = var.sns_fraud_alert_arn
  protocol   = "sqs"
  endpoint   = aws_sqs_queue.alert.arn
  depends_on = [aws_sqs_queue_policy.alert]
}

resource "aws_sns_topic_subscription" "risk_breach_to_alert_queue" {
  topic_arn  = var.sns_risk_breach_arn
  protocol   = "sqs"
  endpoint   = aws_sqs_queue.alert.arn
  depends_on = [aws_sqs_queue_policy.alert]
}
