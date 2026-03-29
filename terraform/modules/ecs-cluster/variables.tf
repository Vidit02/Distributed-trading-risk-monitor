variable "project" {
  description = "Project name"
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}
