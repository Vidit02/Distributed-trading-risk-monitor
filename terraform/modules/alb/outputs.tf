output "alb_dns_name" {
  description = "DNS name of the ALB — use this as the transaction service endpoint"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "transaction_target_group_arn" {
  description = "ARN of the transaction service target group (used in ECS service definition)"
  value       = aws_lb_target_group.transaction.arn
}
