output "transaction_events_arn" {
  description = "ARN of the transaction-events SNS topic"
  value       = aws_sns_topic.transaction_events.arn
}

output "transaction_events_name" {
  description = "Name of the transaction-events SNS topic"
  value       = aws_sns_topic.transaction_events.name
}

output "fraud_alert_events_arn" {
  description = "ARN of the fraud-alert-events SNS topic"
  value       = aws_sns_topic.fraud_alert_events.arn
}

output "risk_breach_events_arn" {
  description = "ARN of the risk-breach-events SNS topic"
  value       = aws_sns_topic.risk_breach_events.arn
}

output "compliance_events_arn" {
  description = "ARN of the compliance-events SNS topic"
  value       = aws_sns_topic.compliance_events.arn
}
