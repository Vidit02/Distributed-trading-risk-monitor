output "high_priority_queue_url" {
  description = "URL of the high-priority SQS queue"
  value       = aws_sqs_queue.high_priority.id
}

output "high_priority_queue_arn" {
  description = "ARN of the high-priority SQS queue"
  value       = aws_sqs_queue.high_priority.arn
}

output "high_priority_dlq_arn" {
  description = "ARN of the high-priority dead-letter queue"
  value       = aws_sqs_queue.high_priority_dlq.arn
}

output "low_priority_queue_url" {
  description = "URL of the low-priority SQS queue"
  value       = aws_sqs_queue.low_priority.id
}

output "low_priority_queue_arn" {
  description = "ARN of the low-priority SQS queue"
  value       = aws_sqs_queue.low_priority.arn
}

output "low_priority_dlq_arn" {
  description = "ARN of the low-priority dead-letter queue"
  value       = aws_sqs_queue.low_priority_dlq.arn
}

output "high_priority_dlq_url" {
  description = "URL of the high-priority dead-letter queue"
  value       = aws_sqs_queue.high_priority_dlq.id
}

output "alert_queue_url" {
  description = "URL of the alert SQS queue"
  value       = aws_sqs_queue.alert.id
}

output "alert_queue_arn" {
  description = "ARN of the alert SQS queue"
  value       = aws_sqs_queue.alert.arn
}
