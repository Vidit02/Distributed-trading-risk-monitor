# VPC outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = module.vpc.alb_security_group_id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = module.vpc.ecs_security_group_id
}

output "redis_security_group_id" {
  description = "Security group ID for Redis"
  value       = module.vpc.redis_security_group_id
}

# ECS outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = module.ecs_cluster.task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = module.ecs_cluster.task_role_arn
}

# SNS outputs
output "sns_transaction_events_arn" {
  description = "ARN of the transaction-events SNS topic"
  value       = module.sns.transaction_events_arn
}

output "sns_fraud_alert_events_arn" {
  description = "ARN of the fraud-alert-events SNS topic (env var FRAUD_ALERT_TOPIC_ARN)"
  value       = module.sns.fraud_alert_events_arn
}

output "sns_risk_breach_events_arn" {
  description = "ARN of the risk-breach-events SNS topic (env var RISK_BREACH_TOPIC_ARN)"
  value       = module.sns.risk_breach_events_arn
}

# SQS outputs
output "sqs_high_priority_url" {
  description = "URL of the high-priority SQS queue"
  value       = module.sqs.high_priority_queue_url
}

output "sqs_high_priority_arn" {
  description = "ARN of the high-priority SQS queue"
  value       = module.sqs.high_priority_queue_arn
}

output "sqs_low_priority_url" {
  description = "URL of the low-priority SQS queue"
  value       = module.sqs.low_priority_queue_url
}

output "sqs_low_priority_arn" {
  description = "ARN of the low-priority SQS queue"
  value       = module.sqs.low_priority_queue_arn
}

# DynamoDB outputs
output "dynamodb_transactions_table_name" {
  description = "Name of the transactions DynamoDB table"
  value       = module.dynamodb.transactions_table_name
}

output "dynamodb_transactions_table_arn" {
  description = "ARN of the transactions DynamoDB table"
  value       = module.dynamodb.transactions_table_arn
}

# S3 outputs
output "s3_audit_logs_bucket_name" {
  description = "Name of the audit logs S3 bucket"
  value       = module.s3.audit_logs_bucket_name
}

output "s3_audit_logs_bucket_arn" {
  description = "ARN of the audit logs S3 bucket"
  value       = module.s3.audit_logs_bucket_arn
}

# Redis outputs
output "redis_primary_endpoint" {
  description = "Primary endpoint for Redis writes"
  value       = module.redis.redis_primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Reader endpoint for Redis reads (load-balanced across replicas)"
  value       = module.redis.redis_reader_endpoint
}

output "redis_port" {
  description = "Port Redis is listening on"
  value       = module.redis.redis_port
}

# ALB outputs
output "alb_dns_name" {
  description = "DNS name of the ALB — transaction service endpoint"
  value       = module.alb.alb_dns_name
}

output "transaction_target_group_arn" {
  description = "ARN of the transaction service target group"
  value       = module.alb.transaction_target_group_arn
}

# Auto-scaling outputs
output "autoscaling_high_priority_scale_out_policy_arns" {
  description = "Scale-out policy ARNs for high-priority queue consumers (fraud, risk)"
  value       = module.autoscaling.high_priority_scale_out_policy_arns
}

output "autoscaling_high_priority_scale_in_policy_arns" {
  description = "Scale-in policy ARNs for high-priority queue consumers (fraud, risk)"
  value       = module.autoscaling.high_priority_scale_in_policy_arns
}

output "autoscaling_low_priority_scale_out_policy_arns" {
  description = "Scale-out policy ARNs for low-priority queue consumers (analytics, audit-logging)"
  value       = module.autoscaling.low_priority_scale_out_policy_arns
}

output "autoscaling_low_priority_scale_in_policy_arns" {
  description = "Scale-in policy ARNs for low-priority queue consumers (analytics, audit-logging)"
  value       = module.autoscaling.low_priority_scale_in_policy_arns
}

# CloudWatch Dashboard outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.cloudwatch_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "Direct URL to the CloudWatch dashboard in the AWS console"
  value       = module.cloudwatch_dashboard.dashboard_url
}

# ECR outputs
output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = module.ecr.registry_id
}
