terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  project            = var.project
  container_insights = var.container_insights
}


# SNS
module "sns" {
  source = "./modules/sns"

  project = var.project
}


# SQS
module "sqs" {
  source = "./modules/sqs"

  project             = var.project
  sns_topic_arn       = module.sns.transaction_events_arn
  sns_fraud_alert_arn = module.sns.fraud_alert_events_arn
  sns_risk_breach_arn = module.sns.risk_breach_events_arn
  project       = var.project
  sns_topic_arn = module.sns.transaction_events_arn

  fraud_alert_topic_arn = module.sns.fraud_alert_events_arn
  risk_breach_topic_arn = module.sns.risk_breach_events_arn
}


# DynamoDB
module "dynamodb" {
  source = "./modules/dynamodb"

  project = var.project
}


# S3
module "s3" {
  source = "./modules/s3"

  project       = var.project
  force_destroy = true
}


# Redis
module "redis" {
  source = "./modules/redis"

  project                 = var.project
  private_subnet_ids      = module.vpc.private_subnet_ids
  redis_security_group_id = module.vpc.redis_security_group_id
}

# ALB
module "alb" {
  source = "./modules/alb"

  project               = var.project
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.vpc.alb_security_group_id
}

# ECR
module "ecr" {
  source = "./modules/ecr"

  project = var.project
}

# Auto-Scaling — ECS services scaled by SQS queue depth
module "autoscaling" {
  source = "./modules/autoscaling"

  project      = var.project
  cluster_name = module.ecs_cluster.cluster_name

  fraud_service_name         = module.ecs_services.fraud_service_name
  risk_service_name          = module.ecs_services.risk_service_name
  analytics_service_name     = module.ecs_services.analytics_service_name
  audit_logging_service_name = module.ecs_services.audit_logging_service_name
  compliance_service_name    = "${var.project}-compliance"
  alert_service_name         = "${var.project}-alert"
  manual_review_service_name = "${var.project}-manual-review"

  high_priority_queue_arn = module.sqs.high_priority_queue_arn
  low_priority_queue_arn  = module.sqs.low_priority_queue_arn
  alert_queue_arn         = module.sqs.alert_queue_arn
  high_priority_dlq_arn   = module.sqs.high_priority_dlq_arn
}

# CloudWatch Dashboard — queue depth, latency, errors, task count
module "cloudwatch_dashboard" {
  source = "./modules/cloudwatch-dashboard"

  project    = var.project
  aws_region = var.aws_region

  cluster_name               = module.ecs_cluster.cluster_name
  transaction_service_name   = module.ecs_services.transaction_service_name
  fraud_service_name         = module.ecs_services.fraud_service_name
  risk_service_name          = module.ecs_services.risk_service_name
  analytics_service_name     = module.ecs_services.analytics_service_name
  audit_logging_service_name = module.ecs_services.audit_logging_service_name

  alb_arn = module.alb.alb_arn
}

# ECS Services
module "ecs_services" {
  source = "./modules/ecs-services"

  project    = var.project
  aws_region = var.aws_region

  # Cluster
  cluster_id              = module.ecs_cluster.cluster_id
  cluster_name            = module.ecs_cluster.cluster_name
  task_execution_role_arn = module.ecs_cluster.task_execution_role_arn
  task_role_arn           = module.ecs_cluster.task_role_arn
  log_group_name          = module.ecs_cluster.log_group_name

  # Networking
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.vpc.ecs_security_group_id

  # ALB
  transaction_target_group_arn = module.alb.transaction_target_group_arn

  # ECR images (tagged as "latest" — update after docker push)
  ecr_transaction_image   = "${module.ecr.repository_urls["transaction"]}:latest"
  ecr_fraud_image         = "${module.ecr.repository_urls["fraud"]}:latest"
  ecr_risk_image          = "${module.ecr.repository_urls["risk"]}:latest"
  ecr_analytics_image     = "${module.ecr.repository_urls["analytics"]}:latest"
  ecr_audit_logging_image = "${module.ecr.repository_urls["audit-logging"]}:latest"
  ecr_compliance_image    = "${module.ecr.repository_urls["compliance"]}:latest"
  ecr_alert_image         = "${module.ecr.repository_urls["alert"]}:latest"
  ecr_manual_review_image = "${module.ecr.repository_urls["manual-review"]}:latest"

  # SNS
  sns_transaction_events_arn = module.sns.transaction_events_arn
  sns_fraud_alert_events_arn = module.sns.fraud_alert_events_arn
  sns_risk_breach_events_arn = module.sns.risk_breach_events_arn
  sns_compliance_events_arn  = module.sns.compliance_events_arn

  # SQS
  high_priority_queue_url = module.sqs.high_priority_queue_url
  low_priority_queue_url  = module.sqs.low_priority_queue_url
  alert_queue_url         = module.sqs.alert_queue_url
  high_priority_dlq_url   = module.sqs.high_priority_dlq_url

  # DynamoDB
  dynamodb_table_name = module.dynamodb.transactions_table_name

  # S3
  s3_audit_logs_bucket_name = module.s3.audit_logs_bucket_name

  # Redis
  redis_primary_endpoint = module.redis.redis_primary_endpoint
  redis_port             = module.redis.redis_port
}
