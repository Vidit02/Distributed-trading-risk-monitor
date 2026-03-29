locals {
  name_prefix = var.project
}

# transaction-events — primary fan-out topic
# Producers set a `priority` message attribute (String):
#   "high" | "critical" → high-priority SQS
#   "medium" | "low"    → low-priority SQS
resource "aws_sns_topic" "transaction_events" {
  name = "${local.name_prefix}-transaction-events"

  tags = {
    Name = "${local.name_prefix}-transaction-events"
  }
}

# fraud-alert-events — published by the Fraud Detection Service
# Consumed by the Alert Service
resource "aws_sns_topic" "fraud_alert_events" {
  name = "${local.name_prefix}-fraud-alert-events"

  tags = {
    Name = "${local.name_prefix}-fraud-alert-events"
  }
}

# risk-breach-events — published by the Risk Monitor Service
# Consumed by the Alert Service
resource "aws_sns_topic" "risk_breach_events" {
  name = "${local.name_prefix}-risk-breach-events"

  tags = {
    Name = "${local.name_prefix}-risk-breach-events"
  }
}
