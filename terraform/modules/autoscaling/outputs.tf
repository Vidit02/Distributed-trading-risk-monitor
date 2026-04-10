output "high_priority_scale_out_policy_arns" {
  description = "ARNs of scale-out policies for high-priority queue consumers"
  value = {
    for k, v in aws_appautoscaling_policy.high_priority_scale_out : k => v.arn
  }
}

output "high_priority_scale_in_policy_arns" {
  description = "ARNs of scale-in policies for high-priority queue consumers"
  value = {
    for k, v in aws_appautoscaling_policy.high_priority_scale_in : k => v.arn
  }
}

output "low_priority_scale_out_policy_arns" {
  description = "ARNs of scale-out policies for low-priority queue consumers"
  value = {
    for k, v in aws_appautoscaling_policy.low_priority_scale_out : k => v.arn
  }
}

output "low_priority_scale_in_policy_arns" {
  description = "ARNs of scale-in policies for low-priority queue consumers"
  value = {
    for k, v in aws_appautoscaling_policy.low_priority_scale_in : k => v.arn
  }
}
