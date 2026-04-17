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

# SQS outputs — one queue per service (SNS fan-out)
output "sqs_fraud_url" {
  description = "URL of the fraud service SQS queue"
  value       = module.sqs.fraud_queue_url
}

output "sqs_risk_url" {
  description = "URL of the risk service SQS queue"
  value       = module.sqs.risk_queue_url
}

output "sqs_compliance_url" {
  description = "URL of the compliance service SQS queue"
  value       = module.sqs.compliance_queue_url
}

output "sqs_analytics_url" {
  description = "URL of the analytics service SQS queue"
  value       = module.sqs.analytics_queue_url
}

output "sqs_audit_logging_url" {
  description = "URL of the audit-logging service SQS queue"
  value       = module.sqs.audit_logging_queue_url
}

output "sqs_alert_url" {
  description = "URL of the alert SQS queue"
  value       = module.sqs.alert_queue_url
}

output "sqs_fraud_dlq_url" {
  description = "URL of the fraud DLQ (consumed by manual-review)"
  value       = module.sqs.fraud_dlq_url
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

# Redis Replica (us-east-1) outputs
output "redis_east_primary_endpoint" {
  description = "Primary endpoint for the us-east-1 Redis replica"
  value       = module.redis_replica.redis_east_primary_endpoint
}

output "redis_east_port" {
  description = "Port the us-east-1 Redis replica is listening on"
  value       = module.redis_replica.redis_east_port
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
