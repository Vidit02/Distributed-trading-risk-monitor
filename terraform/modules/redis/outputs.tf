output "redis_primary_endpoint" {
  description = "Primary endpoint address for Redis writes"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Reader endpoint address for Redis reads (load-balanced across replicas)"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  description = "Port Redis is listening on"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_replication_group_id" {
  description = "ID of the Redis replication group"
  value       = aws_elasticache_replication_group.redis.id
}
