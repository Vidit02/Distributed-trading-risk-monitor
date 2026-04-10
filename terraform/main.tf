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

  project       = var.project
  sns_topic_arn = module.sns.transaction_events_arn
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

  # SNS
  sns_transaction_events_arn = module.sns.transaction_events_arn
  sns_fraud_alert_events_arn = module.sns.fraud_alert_events_arn
  sns_risk_breach_events_arn = module.sns.risk_breach_events_arn

  # SQS
  high_priority_queue_url = module.sqs.high_priority_queue_url
  low_priority_queue_url  = module.sqs.low_priority_queue_url

  # S3
  s3_audit_logs_bucket_name = module.s3.audit_logs_bucket_name

  # Redis
  redis_primary_endpoint = module.redis.redis_primary_endpoint
  redis_port             = module.redis.redis_port
}
