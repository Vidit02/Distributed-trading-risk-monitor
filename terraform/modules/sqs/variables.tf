variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to subscribe to"
  type        = string
}

variable "high_priority_visibility_timeout" {
  description = "Visibility timeout (seconds) for the high-priority queue"
  type        = number
  default     = 30
}

variable "low_priority_visibility_timeout" {
  description = "Visibility timeout (seconds) for the low-priority queue"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long SQS retains unprocessed messages (seconds)"
  type        = number
  default     = 86400 # 1 day
}

variable "max_receive_count" {
  description = "Number of receives before a message is moved to the DLQ"
  type        = number
  default     = 3
}
