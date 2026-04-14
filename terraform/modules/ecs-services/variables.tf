variable "project" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Cluster
variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of IAMLabRole for task execution"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of IAMLabRole for task permissions"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

# Networking
variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

# ALB
variable "transaction_target_group_arn" {
  description = "ALB target group ARN for the transaction service"
  type        = string
}

# ECR image URIs
variable "ecr_transaction_image" {
  description = "ECR image URI for the transaction service"
  type        = string
}

variable "ecr_fraud_image" {
  description = "ECR image URI for the fraud service"
  type        = string
}

variable "ecr_risk_image" {
  description = "ECR image URI for the risk service"
  type        = string
}

variable "ecr_analytics_image" {
  description = "ECR image URI for the analytics service"
  type        = string
}

variable "ecr_audit_logging_image" {
  description = "ECR image URI for the audit-logging service"
  type        = string
}

variable "ecr_compliance_image" {
  description = "ECR image URI for the compliance service"
  type        = string
}

variable "ecr_alert_image" {
  description = "ECR image URI for the alert service"
  type        = string
}

variable "ecr_manual_review_image" {
  description = "ECR image URI for the manual-review service"
  type        = string
}

# SNS
variable "sns_transaction_events_arn" {
  description = "ARN of transaction-events SNS topic"
  type        = string
}

variable "sns_fraud_alert_events_arn" {
  description = "ARN of fraud-alert-events SNS topic"
  type        = string
}

variable "sns_risk_breach_events_arn" {
  description = "ARN of risk-breach-events SNS topic"
  type        = string
}

variable "sns_compliance_events_arn" {
  description = "ARN of compliance-events SNS topic"
  type        = string
}

# SQS
variable "high_priority_queue_url" {
  description = "URL of high-priority SQS queue"
  type        = string
}

variable "low_priority_queue_url" {
  description = "URL of low-priority SQS queue"
  type        = string
}

variable "alert_queue_url" {
  description = "URL of the alert SQS queue (receives fraud-alert + risk-breach events)"
  type        = string
}

variable "high_priority_dlq_url" {
  description = "URL of the high-priority dead-letter queue (consumed by manual-review)"
  type        = string
}

# DynamoDB
variable "dynamodb_table_name" {
  description = "Name of the transactions DynamoDB table"
  type        = string
}

# S3
variable "s3_audit_logs_bucket_name" {
  description = "Name of the audit logs S3 bucket"
  type        = string
}

# Redis
variable "redis_primary_endpoint" {
  description = "Redis primary endpoint address"
  type        = string
}

variable "redis_port" {
  description = "Redis port"
  type        = number
}

variable "daily_limit" {
  description = "Per-user daily spend limit in USD (for risk service)"
  type        = number
  default     = 50000
}
