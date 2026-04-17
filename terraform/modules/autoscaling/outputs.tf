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

output "alert_scale_out_policy_arn" {
  description = "ARN of the scale-out policy for the alert service"
  value       = aws_appautoscaling_policy.alert_scale_out.arn
}

output "alert_scale_in_policy_arn" {
  description = "ARN of the scale-in policy for the alert service"
  value       = aws_appautoscaling_policy.alert_scale_in.arn
}

output "manual_review_scale_out_policy_arn" {
  description = "ARN of the scale-out policy for the manual-review service"
  value       = aws_appautoscaling_policy.manual_review_scale_out.arn
}

output "manual_review_scale_in_policy_arn" {
  description = "ARN of the scale-in policy for the manual-review service"
  value       = aws_appautoscaling_policy.manual_review_scale_in.arn
}

output "transaction_scaling_policy_arn" {
  description = "ARN of the target-tracking scaling policy for the transaction service"
  value       = aws_appautoscaling_policy.transaction.arn
}
