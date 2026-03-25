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
