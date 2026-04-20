# ---------------------------------------------------------------------------
# Per-service queue URLs
# ---------------------------------------------------------------------------
output "fraud_queue_url" {
  description = "URL of the fraud service SQS queue"
  value       = aws_sqs_queue.service["fraud"].id
}

output "risk_queue_url" {
  description = "URL of the risk service SQS queue"
  value       = aws_sqs_queue.service["risk"].id
}

output "compliance_queue_url" {
  description = "URL of the compliance service SQS queue"
  value       = aws_sqs_queue.service["compliance"].id
}

output "analytics_queue_url" {
  description = "URL of the analytics service SQS queue"
  value       = aws_sqs_queue.service["analytics"].id
}

output "audit_logging_queue_url" {
  description = "URL of the audit-logging service SQS queue"
  value       = aws_sqs_queue.service["audit-logging"].id
}

# ---------------------------------------------------------------------------
# Per-service queue ARNs (used by auto-scaling alarms)
# ---------------------------------------------------------------------------
output "fraud_queue_arn" {
  description = "ARN of the fraud service SQS queue"
  value       = aws_sqs_queue.service["fraud"].arn
}

output "risk_queue_arn" {
  description = "ARN of the risk service SQS queue"
  value       = aws_sqs_queue.service["risk"].arn
}

output "compliance_queue_arn" {
  description = "ARN of the compliance service SQS queue"
  value       = aws_sqs_queue.service["compliance"].arn
}

output "analytics_queue_arn" {
  description = "ARN of the analytics service SQS queue"
  value       = aws_sqs_queue.service["analytics"].arn
}

output "audit_logging_queue_arn" {
  description = "ARN of the audit-logging service SQS queue"
  value       = aws_sqs_queue.service["audit-logging"].arn
}

# ---------------------------------------------------------------------------
# Per-service DLQ URLs and ARNs
# ---------------------------------------------------------------------------
output "fraud_dlq_url" {
  description = "URL of the fraud service DLQ (consumed by manual-review)"
  value       = aws_sqs_queue.service_dlq["fraud"].id
}

output "fraud_dlq_arn" {
  description = "ARN of the fraud service DLQ"
  value       = aws_sqs_queue.service_dlq["fraud"].arn
}

output "risk_dlq_url" {
  description = "URL of the risk service DLQ"
  value       = aws_sqs_queue.service_dlq["risk"].id
}

output "risk_dlq_arn" {
  description = "ARN of the risk service DLQ"
  value       = aws_sqs_queue.service_dlq["risk"].arn
}

output "compliance_dlq_url" {
  description = "URL of the compliance service DLQ"
  value       = aws_sqs_queue.service_dlq["compliance"].id
}

output "compliance_dlq_arn" {
  description = "ARN of the compliance service DLQ"
  value       = aws_sqs_queue.service_dlq["compliance"].arn
}

output "analytics_dlq_url" {
  description = "URL of the analytics service DLQ"
  value       = aws_sqs_queue.service_dlq["analytics"].id
}

output "analytics_dlq_arn" {
  description = "ARN of the analytics service DLQ"
  value       = aws_sqs_queue.service_dlq["analytics"].arn
}

output "audit_logging_dlq_url" {
  description = "URL of the audit-logging service DLQ"
  value       = aws_sqs_queue.service_dlq["audit-logging"].id
}

output "audit_logging_dlq_arn" {
  description = "ARN of the audit-logging service DLQ"
  value       = aws_sqs_queue.service_dlq["audit-logging"].arn
}

# ---------------------------------------------------------------------------
# Alert queue (unchanged)
# ---------------------------------------------------------------------------
output "alert_queue_url" {
  description = "URL of the alert SQS queue"
  value       = aws_sqs_queue.alert.id
}

output "alert_queue_arn" {
  description = "ARN of the alert SQS queue"
  value       = aws_sqs_queue.alert.arn
}
