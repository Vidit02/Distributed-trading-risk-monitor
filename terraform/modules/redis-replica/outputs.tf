output "redis_east_primary_endpoint" {
  description = "Primary endpoint address of the us-east-1 Redis replica"
  value       = aws_elasticache_replication_group.east_redis.primary_endpoint_address
}

output "redis_east_port" {
  description = "Port the us-east-1 Redis replica is listening on"
  value       = aws_elasticache_replication_group.east_redis.port
}

output "east_vpc_id" {
  description = "ID of the isolated us-east-1 VPC hosting the Redis replica"
  value       = aws_vpc.east.id
}
