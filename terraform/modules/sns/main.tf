locals {
  name_prefix = "${var.project}-${var.environment}"
}

# SNS Topic — transaction-events
#
# Message attribute expected on every publish:
#   priority (String) = "high" | "critical" | "medium" | "low"
resource "aws_sns_topic" "transaction_events" {
  name = "${local.name_prefix}-transaction-events"

  tags = {
    Name = "${local.name_prefix}-transaction-events"
  }
}
