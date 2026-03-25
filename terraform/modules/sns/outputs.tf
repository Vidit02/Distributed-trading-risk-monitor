output "transaction_events_arn" {
  description = "ARN of the transaction-events SNS topic"
  value       = aws_sns_topic.transaction_events.arn
}

output "transaction_events_name" {
  description = "Name of the transaction-events SNS topic"
  value       = aws_sns_topic.transaction_events.name
}
