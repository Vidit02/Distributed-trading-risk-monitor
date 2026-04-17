terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.east]
    }
  }
}

locals {
  name_prefix = var.project
  vpc_cidr    = "10.1.0.0/16"
}

# ---------------------------------------------------------------------------
# Minimal VPC in us-east-1 — intentionally isolated from the primary us-west-2
# VPC to simulate true multi-region deployment.
# ---------------------------------------------------------------------------
resource "aws_vpc" "east" {
  provider = aws.east

  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-east-vpc"
  }
}

resource "aws_subnet" "east_private_a" {
  provider = aws.east

  vpc_id            = aws_vpc.east.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${local.name_prefix}-east-private-a"
  }
}

resource "aws_subnet" "east_private_b" {
  provider = aws.east

  vpc_id            = aws_vpc.east.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "${local.name_prefix}-east-private-b"
  }
}

# Security group — allow Redis traffic from anything inside this VPC.
resource "aws_security_group" "east_redis" {
  provider = aws.east

  name        = "${local.name_prefix}-east-redis-sg"
  description = "Allow Redis 6379 from within the east VPC"
  vpc_id      = aws_vpc.east.id

  ingress {
    description = "Redis from within VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-east-redis-sg"
  }
}

# ---------------------------------------------------------------------------
# ElastiCache Redis — single node in us-east-1
# ---------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "east_redis" {
  provider = aws.east

  name       = "${local.name_prefix}-east-redis-subnet-group"
  subnet_ids = [aws_subnet.east_private_a.id, aws_subnet.east_private_b.id]

  tags = {
    Name = "${local.name_prefix}-east-redis-subnet-group"
  }
}

resource "aws_elasticache_parameter_group" "east_redis" {
  provider = aws.east

  name   = "${local.name_prefix}-east-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = {
    Name = "${local.name_prefix}-east-redis-params"
  }
}

resource "aws_elasticache_replication_group" "east_redis" {
  provider = aws.east

  replication_group_id = "${local.name_prefix}-east-redis"
  description          = "Secondary (us-east-1) Redis replica for ${var.project}"

  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.micro"
  num_cache_clusters   = 1
  parameter_group_name = aws_elasticache_parameter_group.east_redis.name
  subnet_group_name    = aws_elasticache_subnet_group.east_redis.name
  security_group_ids   = [aws_security_group.east_redis.id]

  port = 6379

  automatic_failover_enabled = false
  multi_az_enabled           = false

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "preferred"

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-east-redis"
  }
}
