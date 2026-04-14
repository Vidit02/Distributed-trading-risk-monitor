output "transaction_service_name" {
  description = "ECS service name for transaction"
  value       = aws_ecs_service.transaction.name
}

output "fraud_service_name" {
  description = "ECS service name for fraud"
  value       = aws_ecs_service.fraud.name
}

output "risk_service_name" {
  description = "ECS service name for risk"
  value       = aws_ecs_service.risk.name
}

output "analytics_service_name" {
  description = "ECS service name for analytics"
  value       = aws_ecs_service.analytics.name
}

output "audit_logging_service_name" {
  description = "ECS service name for audit-logging"
  value       = aws_ecs_service.audit_logging.name
}

output "compliance_service_name" {
  description = "ECS service name for compliance"
  value       = aws_ecs_service.compliance.name
}

output "alert_service_name" {
  description = "ECS service name for alert"
  value       = aws_ecs_service.alert.name
}

output "manual_review_service_name" {
  description = "ECS service name for manual-review"
  value       = aws_ecs_service.manual_review.name
}
