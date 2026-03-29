variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for the ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "target_port" {
  description = "Port the transaction service listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check endpoint on the transaction service"
  type        = string
  default     = "/health"
}
