variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days before audit log objects are expired"
  type        = number
  default     = 365
}

variable "glacier_transition_days" {
  description = "Number of days before audit log objects are transitioned to Glacier"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow bucket destruction even when it contains objects (set true for dev)"
  type        = bool
  default     = false
}
