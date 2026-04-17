# ECS auto-scaling based on SQS queue depth.
# High-priority queue drives fraud + risk services; low-priority drives analytics + audit-logging.
# Each service gets scale-out and scale-in step policies with matching CloudWatch alarms.

locals {
  # Queue name is just the last segment of the ARN
  high_priority_queue_name = element(split(":", var.high_priority_queue_arn), 5)
  low_priority_queue_name  = element(split(":", var.low_priority_queue_arn), 5)
  alert_queue_name         = element(split(":", var.alert_queue_arn), 5)
  high_priority_dlq_name   = element(split(":", var.high_priority_dlq_arn), 5)

  # ALBRequestCountPerTarget resource_label = "{alb_suffix}/{tg_suffix}"
  # e.g. app/trading-risk-monitor-alb/abc123/targetgroup/trading-risk-monitor-transaction/def456
  alb_suffix    = regex("loadbalancer/(.*)", var.alb_arn)[0]
  alb_tg_suffix = regex("(targetgroup/.+)$", var.alb_target_group_arn)[0]

  high_priority_services = {
    fraud      = var.fraud_service_name
    risk       = var.risk_service_name
    compliance = var.compliance_service_name
  }

  low_priority_services = {
    analytics     = var.analytics_service_name
    audit_logging = var.audit_logging_service_name
  }
}

# Auto scaling targets

resource "aws_appautoscaling_target" "high_priority" {
  for_each = local.high_priority_services

  max_capacity       = var.high_priority_max_capacity
  min_capacity       = var.high_priority_min_capacity
  resource_id        = "service/${var.cluster_name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "low_priority" {
  for_each = local.low_priority_services

  max_capacity       = var.low_priority_max_capacity
  min_capacity       = var.low_priority_min_capacity
  resource_id        = "service/${var.cluster_name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale-out for high-priority services.
# Step offsets are relative to the alarm threshold (10 msgs):
#   10–49 msgs  → +1 task
#   50+ msgs    → +2 tasks

resource "aws_appautoscaling_policy" "high_priority_scale_out" {
  for_each = local.high_priority_services

  name               = "${each.value}-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.high_priority[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.high_priority[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.high_priority[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 40
      scaling_adjustment          = 1
    }

    step_adjustment {
      metric_interval_lower_bound = 40
      scaling_adjustment          = 2
    }
  }
}

# Scale-in for high-priority services. Fires when depth drops below the scale_in_threshold.
# upper_bound = 0 captures everything below the threshold.

resource "aws_appautoscaling_policy" "high_priority_scale_in" {
  for_each = local.high_priority_services

  name               = "${each.value}-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.high_priority[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.high_priority[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.high_priority[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# Scale-out for low-priority services.
# Low-priority queues tolerate more backlog, so thresholds are higher (50 msgs):
#   50–199 msgs  → +1 task
#   200+ msgs    → +2 tasks

resource "aws_appautoscaling_policy" "low_priority_scale_out" {
  for_each = local.low_priority_services

  name               = "${each.value}-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.low_priority[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.low_priority[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.low_priority[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 150
      scaling_adjustment          = 1
    }

    step_adjustment {
      metric_interval_lower_bound = 150
      scaling_adjustment          = 2
    }
  }
}

# Scale-in for low-priority services. Longer cooldown (5 min) to avoid flapping.

resource "aws_appautoscaling_policy" "low_priority_scale_in" {
  for_each = local.low_priority_services

  name               = "${each.value}-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.low_priority[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.low_priority[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.low_priority[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# CloudWatch alarms for high-priority queue consumers

resource "aws_cloudwatch_metric_alarm" "high_priority_scale_out" {
  for_each = local.high_priority_services

  alarm_name          = "${each.value}-high-queue-depth-scale-out"
  alarm_description   = "Scale out ${each.value}: high-priority queue depth >= ${var.high_priority_scale_out_threshold}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.high_priority_scale_out_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.high_priority_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.high_priority_scale_out[each.key].arn]
}

resource "aws_cloudwatch_metric_alarm" "high_priority_scale_in" {
  for_each = local.high_priority_services

  alarm_name          = "${each.value}-high-queue-depth-scale-in"
  alarm_description   = "Scale in ${each.value}: high-priority queue depth < ${var.high_priority_scale_in_threshold}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.high_priority_scale_in_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.high_priority_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.high_priority_scale_in[each.key].arn]
}

# CloudWatch alarms for low-priority queue consumers

resource "aws_cloudwatch_metric_alarm" "low_priority_scale_out" {
  for_each = local.low_priority_services

  alarm_name          = "${each.value}-low-queue-depth-scale-out"
  alarm_description   = "Scale out ${each.value}: low-priority queue depth >= ${var.low_priority_scale_out_threshold}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.low_priority_scale_out_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.low_priority_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.low_priority_scale_out[each.key].arn]
}

resource "aws_cloudwatch_metric_alarm" "low_priority_scale_in" {
  for_each = local.low_priority_services

  alarm_name          = "${each.value}-low-queue-depth-scale-in"
  alarm_description   = "Scale in ${each.value}: low-priority queue depth < ${var.low_priority_scale_in_threshold}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.low_priority_scale_in_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.low_priority_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.low_priority_scale_in[each.key].arn]
}

# ---------------------------------------------------------------------------
# Alert service — scales on its own dedicated alert queue depth
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "alert" {
  max_capacity       = var.alert_max_capacity
  min_capacity       = var.alert_min_capacity
  resource_id        = "service/${var.cluster_name}/${var.alert_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "alert_scale_out" {
  name               = "${var.alert_service_name}-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.alert.resource_id
  scalable_dimension = aws_appautoscaling_target.alert.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alert.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 15
      scaling_adjustment          = 1
    }

    step_adjustment {
      metric_interval_lower_bound = 15
      scaling_adjustment          = 2
    }
  }
}

resource "aws_appautoscaling_policy" "alert_scale_in" {
  name               = "${var.alert_service_name}-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.alert.resource_id
  scalable_dimension = aws_appautoscaling_target.alert.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alert.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "alert_scale_out" {
  alarm_name          = "${var.alert_service_name}-queue-depth-scale-out"
  alarm_description   = "Scale out ${var.alert_service_name}: alert queue depth >= ${var.alert_scale_out_threshold}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.alert_scale_out_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.alert_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.alert_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "alert_scale_in" {
  alarm_name          = "${var.alert_service_name}-queue-depth-scale-in"
  alarm_description   = "Scale in ${var.alert_service_name}: alert queue depth < ${var.alert_scale_in_threshold}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.alert_scale_in_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.alert_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.alert_scale_in.arn]
}

# ---------------------------------------------------------------------------
# Manual-review service — scales on the high-priority DLQ depth.
# Any message landing in the DLQ means a transaction failed processing and
# needs human attention, so we scale out immediately at threshold = 1.
# min_capacity = 0 so the service stays at zero cost when the DLQ is empty.
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "manual_review" {
  max_capacity       = var.manual_review_max_capacity
  min_capacity       = var.manual_review_min_capacity
  resource_id        = "service/${var.cluster_name}/${var.manual_review_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "manual_review_scale_out" {
  name               = "${var.manual_review_service_name}-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.manual_review.resource_id
  scalable_dimension = aws_appautoscaling_target.manual_review.scalable_dimension
  service_namespace  = aws_appautoscaling_target.manual_review.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 9
      scaling_adjustment          = 1
    }

    step_adjustment {
      metric_interval_lower_bound = 9
      scaling_adjustment          = 2
    }
  }
}

resource "aws_appautoscaling_policy" "manual_review_scale_in" {
  name               = "${var.manual_review_service_name}-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.manual_review.resource_id
  scalable_dimension = aws_appautoscaling_target.manual_review.scalable_dimension
  service_namespace  = aws_appautoscaling_target.manual_review.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "manual_review_scale_out" {
  alarm_name          = "${var.manual_review_service_name}-dlq-depth-scale-out"
  alarm_description   = "Scale out ${var.manual_review_service_name}: high-priority DLQ depth >= ${var.manual_review_scale_out_threshold}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.manual_review_scale_out_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.high_priority_dlq_name
  }

  alarm_actions = [aws_appautoscaling_policy.manual_review_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "manual_review_scale_in" {
  alarm_name          = "${var.manual_review_service_name}-dlq-depth-scale-in"
  alarm_description   = "Scale in ${var.manual_review_service_name}: high-priority DLQ depth < ${var.manual_review_scale_in_threshold}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.manual_review_scale_in_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = local.high_priority_dlq_name
  }

  alarm_actions = [aws_appautoscaling_policy.manual_review_scale_in.arn]
}

# ---------------------------------------------------------------------------
# Transaction service — TargetTrackingScaling on ALBRequestCountPerTarget
#
# When each running task is handling more than 100 req/s, ECS adds tasks.
# AWS automatically creates the corresponding scale-in policy.
# scale_out_cooldown = 60s  — react quickly to traffic spikes
# scale_in_cooldown  = 120s — avoid thrashing after a burst drains
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "transaction" {
  max_capacity       = var.transaction_max_capacity
  min_capacity       = var.transaction_min_capacity
  resource_id        = "service/${var.cluster_name}/${var.transaction_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "transaction" {
  name               = "${var.transaction_service_name}-alb-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.transaction.resource_id
  scalable_dimension = aws_appautoscaling_target.transaction.scalable_dimension
  service_namespace  = aws_appautoscaling_target.transaction.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.transaction_requests_per_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${local.alb_suffix}/${local.alb_tg_suffix}"
    }
  }
}
