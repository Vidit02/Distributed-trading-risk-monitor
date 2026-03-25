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
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  project            = var.project
  environment        = var.environment
  container_insights = var.container_insights
}


# SNS
module "sns" {
  source = "./modules/sns"

  project     = var.project
  environment = var.environment
}


# SQS
module "sqs" {
  source = "./modules/sqs"

  project       = var.project
  environment   = var.environment
  sns_topic_arn = module.sns.transaction_events_arn
}


# DynamoDB
module "dynamodb" {
  source = "./modules/dynamodb"

  project     = var.project
  environment = var.environment
}


# S3
module "s3" {
  source = "./modules/s3"

  project     = var.project
  environment = var.environment
}


# Redis
module "redis" {
  source = "./modules/redis"

  project                 = var.project
  environment             = var.environment
  private_subnet_ids      = module.vpc.private_subnet_ids
  redis_security_group_id = module.vpc.redis_security_group_id
}
