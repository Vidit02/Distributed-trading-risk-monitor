variable "project" {
  description = "Project name prefix, used to name the dashboard"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the dashboard lives, also used to build the console URL"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster, needed to pull task count metrics from Container Insights"
  type        = string
}

variable "transaction_service_name" {
  description = "ECS service name for the transaction service"
  type        = string
}

variable "fraud_service_name" {
  description = "ECS service name for the fraud service"
  type        = string
}

variable "risk_service_name" {
  description = "ECS service name for the risk service"
  type        = string
}

variable "analytics_service_name" {
  description = "ECS service name for the analytics service"
  type        = string
}

variable "audit_logging_service_name" {
  description = "ECS service name for the audit-logging service"
  type        = string
}

variable "compliance_service_name" {
  description = "ECS service name for the compliance service"
  type        = string
}

variable "alert_service_name" {
  description = "ECS service name for the alert service"
  type        = string
}

variable "manual_review_service_name" {
  description = "ECS service name for the manual-review service"
  type        = string
}

variable "alb_arn" {
  description = "Full ARN of the ALB, used to extract the LoadBalancer dimension for CloudWatch metrics"
  type        = string
}
