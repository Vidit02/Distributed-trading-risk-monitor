variable "project" {
  description = "Project name"
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
  default     = 300 # 5 minutes — low priority workers can take longer
}

variable "message_retention_seconds" {
  description = "How long SQS retains unprocessed messages (seconds)"
  type        = number
  default     = 86400 # 1 day
}

variable "sns_fraud_alert_arn" {
  description = "ARN of the fraud-alert-events SNS topic (subscribed by the alert queue)"
  type        = string
}

variable "sns_risk_breach_arn" {
  description = "ARN of the risk-breach-events SNS topic (subscribed by the alert queue)"
  type        = string
}

variable "high_priority_max_receive_count" {
  description = "Failed receives before a high-priority message moves to the DLQ"
  type        = number
  default     = 3
}

variable "low_priority_max_receive_count" {
  description = "Failed receives before a low-priority message moves to the DLQ"
  type        = number
  default     = 5
}

variable "fraud_alert_topic_arn" {
  description = "ARN of the fraud-alert-events SNS topic (subscribed by alert queue)"
  type        = string
  default     = ""
}

variable "risk_breach_topic_arn" {
  description = "ARN of the risk-breach-events SNS topic (subscribed by alert queue)"
  type        = string
  default     = ""
}
