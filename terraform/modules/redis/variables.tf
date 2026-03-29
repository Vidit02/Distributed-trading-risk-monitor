variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets in which to place the Redis cluster"
  type        = list(string)
}

variable "redis_security_group_id" {
  description = "Security group ID that controls access to Redis (port 6379)"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node instance type"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (primary + replicas). Minimum 2 for Multi-AZ failover"
  type        = number
  default     = 2
}

variable "redis_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "snapshot_retention_limit" {
  description = "Days to retain automatic snapshots (0 = disabled)"
  type        = number
  default     = 1
}
