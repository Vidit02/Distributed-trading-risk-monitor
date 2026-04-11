variable "project" {
  description = "Project name prefix used across all resources"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

# Service names

variable "fraud_service_name" {
  description = "ECS service name for the fraud detection service"
  type        = string
}

variable "risk_service_name" {
  description = "ECS service name for the risk monitor service"
  type        = string
}

variable "analytics_service_name" {
  description = "ECS service name for the analytics service"
  type        = string
}

variable "audit_logging_service_name" {
  description = "ECS service name for the audit logging service"
  type        = string
}

# Queue ARNs

variable "high_priority_queue_arn" {
  description = "ARN of the high-priority SQS queue (consumed by fraud and risk services)"
  type        = string
}

variable "low_priority_queue_arn" {
  description = "ARN of the low-priority SQS queue (consumed by analytics and audit-logging services)"
  type        = string
}

# Capacity bounds

variable "high_priority_min_capacity" {
  description = "Minimum number of tasks for high-priority queue consumers"
  type        = number
  default     = 1
}

variable "high_priority_max_capacity" {
  description = "Maximum number of tasks for high-priority queue consumers"
  type        = number
  default     = 5
}

variable "low_priority_min_capacity" {
  description = "Minimum number of tasks for low-priority queue consumers"
  type        = number
  default     = 1
}

variable "low_priority_max_capacity" {
  description = "Maximum number of tasks for low-priority queue consumers"
  type        = number
  default     = 3
}

# Scale-out thresholds

variable "high_priority_scale_out_threshold" {
  description = "Queue depth at which high-priority consumers scale out (ApproximateNumberOfMessagesVisible)"
  type        = number
  default     = 10
}

variable "low_priority_scale_out_threshold" {
  description = "Queue depth at which low-priority consumers scale out (ApproximateNumberOfMessagesVisible)"
  type        = number
  default     = 50
}

# Scale-in thresholds

variable "high_priority_scale_in_threshold" {
  description = "Queue depth below which high-priority consumers scale in"
  type        = number
  default     = 5
}

variable "low_priority_scale_in_threshold" {
  description = "Queue depth below which low-priority consumers scale in"
  type        = number
  default     = 10
}
