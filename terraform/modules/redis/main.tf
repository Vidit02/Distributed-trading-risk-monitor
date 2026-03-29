locals {
  name_prefix = var.project
}

# Subnet group — places Redis nodes in private subnets across AZs
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-redis-subnet-group"
  }
}

# Parameter group — Redis defaults tuned for low-latency risk state reads
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${local.name_prefix}-redis-params"
  family = "redis7"

  # Keep frequently-accessed risk state keys in memory longer
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = {
    Name = "${local.name_prefix}-redis-params"
  }
}

# Replication group — primary + replica across AZs with automatic failover
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Shared risk state cache for ${var.project}"

  engine               = "redis"
  engine_version       = var.redis_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.redis_security_group_id]

  port = 6379

  # High availability
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Snapshots — retain 1 day of backups
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  apply_immediately = true

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}
