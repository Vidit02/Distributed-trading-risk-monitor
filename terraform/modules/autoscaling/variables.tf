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

variable "compliance_service_name" {
  description = "ECS service name for the compliance service"
  type        = string
}

variable "alert_service_name" {
  description = "ECS service name for the alert service"
  type        = string
}

variable "manual_review_service_name" {
  description = "ECS service name for the manual review service"
  type        = string
}

# Queue ARNs — each service now has its own dedicated queue (SNS fan-out).

variable "fraud_queue_arn" {
  description = "ARN of the fraud service SQS queue"
  type        = string
}

variable "risk_queue_arn" {
  description = "ARN of the risk service SQS queue"
  type        = string
}

variable "compliance_queue_arn" {
  description = "ARN of the compliance service SQS queue"
  type        = string
}

variable "analytics_queue_arn" {
  description = "ARN of the analytics service SQS queue"
  type        = string
}

variable "audit_logging_queue_arn" {
  description = "ARN of the audit-logging service SQS queue"
  type        = string
}

variable "alert_queue_arn" {
  description = "ARN of the alert SQS queue (consumed by the alert service)"
  type        = string
}

variable "fraud_dlq_arn" {
  description = "ARN of the fraud DLQ (watched by the manual-review service)"
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

variable "alert_min_capacity" {
  description = "Minimum number of tasks for the alert service"
  type        = number
  default     = 1
}

variable "alert_max_capacity" {
  description = "Maximum number of tasks for the alert service"
  type        = number
  default     = 5
}

variable "alert_scale_out_threshold" {
  description = "Alert queue depth at which the alert service scales out"
  type        = number
  default     = 5
}

variable "alert_scale_in_threshold" {
  description = "Alert queue depth below which the alert service scales in"
  type        = number
  default     = 2
}

variable "manual_review_min_capacity" {
  description = "Minimum number of tasks for the manual-review service (0 = scale to zero when DLQ is empty)"
  type        = number
  default     = 0
}

variable "manual_review_max_capacity" {
  description = "Maximum number of tasks for the manual-review service"
  type        = number
  default     = 3
}

variable "manual_review_scale_out_threshold" {
  description = "DLQ depth at which the manual-review service scales out (any DLQ message triggers processing)"
  type        = number
  default     = 1
}

variable "manual_review_scale_in_threshold" {
  description = "DLQ depth below which the manual-review service scales in (empty queue)"
  type        = number
  default     = 1
}
