locals {
  name_prefix = var.project
}


# Transaction Service — HTTP, registered to ALB
resource "aws_ecs_task_definition" "transaction" {
  family                   = "${local.name_prefix}-transaction"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "transaction"
      image     = var.ecr_transaction_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = "8080" },
        { name = "SNS_TOPIC_ARN", value = var.sns_transaction_events_arn },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "transaction"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-transaction" }
}

resource "aws_ecs_service" "transaction" {
  name            = "${local.name_prefix}-transaction"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.transaction.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.transaction_target_group_arn
    container_name   = "transaction"
    container_port   = 8080
  }

  tags = { Name = "${local.name_prefix}-transaction" }
}

# Fraud Service — SQS consumer on high-priority queue
resource "aws_ecs_task_definition" "fraud" {
  family                   = "${local.name_prefix}-fraud"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "fraud"
      image     = var.ecr_fraud_image
      essential = true

      environment = [
        { name = "HIGH_PRIORITY_QUEUE_URL", value = var.fraud_queue_url },
        { name = "FRAUD_ALERT_TOPIC_ARN", value = var.sns_fraud_alert_events_arn },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "fraud"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-fraud" }
}

resource "aws_ecs_service" "fraud" {
  name            = "${local.name_prefix}-fraud"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.fraud.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-fraud" }
}

# ---------------------------------------------------------------------------
# Risk Service — SQS consumer on high-priority queue + Redis
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "risk" {
  family                   = "${local.name_prefix}-risk"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "risk"
      image     = var.ecr_risk_image
      essential = true

      environment = [
        { name = "HIGH_PRIORITY_QUEUE_URL", value = var.risk_queue_url },
        { name = "RISK_BREACH_TOPIC_ARN", value = var.sns_risk_breach_events_arn },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "REDIS_ADDR", value = "${var.redis_primary_endpoint}:${var.redis_port}" },
        { name = "DAILY_LIMIT", value = tostring(var.daily_limit) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "REDIS_SYNC_MODE", value = var.redis_sync_mode },
        { name = "REDIS_SECONDARY_ADDR", value = var.redis_secondary_addr },
        { name = "REDIS_REGION_LABEL", value = var.redis_region_label }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "risk"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-risk" }
}

resource "aws_ecs_service" "risk" {
  name            = "${local.name_prefix}-risk"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.risk.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-risk" }
}

# Analytics Service — SQS consumer on low-priority queue
resource "aws_ecs_task_definition" "analytics" {
  family                   = "${local.name_prefix}-analytics"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "analytics"
      image     = var.ecr_analytics_image
      essential = true

      environment = [
        { name = "QUEUE_URL", value = var.analytics_queue_url },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "analytics"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-analytics" }
}

resource "aws_ecs_service" "analytics" {
  name            = "${local.name_prefix}-analytics"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.analytics.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-analytics" }
}

# ---------------------------------------------------------------------------
# Audit Logging Service — SQS consumer on low-priority queue, writes to S3
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "audit_logging" {
  family                   = "${local.name_prefix}-audit-logging"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "audit-logging"
      image     = var.ecr_audit_logging_image
      essential = true

      environment = [
        { name = "QUEUE_URL", value = var.audit_logging_queue_url },
        { name = "S3_BUCKET", value = var.s3_audit_logs_bucket_name },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "audit-logging"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-audit-logging" }
}

resource "aws_ecs_service" "audit_logging" {
  name            = "${local.name_prefix}-audit-logging"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.audit_logging.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-audit-logging" }
}

# ---------------------------------------------------------------------------
# Compliance Service — SQS consumer on high-priority queue
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "compliance" {
  family                   = "${local.name_prefix}-compliance"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "compliance"
      image     = var.ecr_compliance_image
      essential = true

      environment = [
        { name = "HIGH_PRIORITY_QUEUE_URL", value = var.compliance_queue_url },
        { name = "COMPLIANCE_TOPIC_ARN", value = var.sns_compliance_events_arn },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "compliance"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-compliance" }
}

resource "aws_ecs_service" "compliance" {
  name            = "${local.name_prefix}-compliance"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.compliance.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-compliance" }
}

# ---------------------------------------------------------------------------
# Alert Service — SQS consumer on dedicated alert queue
# (subscribed to fraud-alert-events and risk-breach-events SNS topics)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "alert" {
  family                   = "${local.name_prefix}-alert"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "alert"
      image     = var.ecr_alert_image
      essential = true

      environment = [
        { name = "ALERT_QUEUE_URL", value = var.alert_queue_url },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "alert"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-alert" }
}

resource "aws_ecs_service" "alert" {
  name            = "${local.name_prefix}-alert"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.alert.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-alert" }
}

# ---------------------------------------------------------------------------
# Manual Review Service — SQS consumer on the high-priority DLQ
# (fallback when fraud detection is down)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "manual_review" {
  family                   = "${local.name_prefix}-manual-review"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "manual-review"
      image     = var.ecr_manual_review_image
      essential = true

      environment = [
        { name = "DLQ_QUEUE_URL", value = var.fraud_dlq_url },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "ALERT_TOPIC_ARN", value = var.sns_fraud_alert_events_arn },
        { name = "AWS_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "manual-review"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-manual-review" }
}

resource "aws_ecs_service" "manual_review" {
  name            = "${local.name_prefix}-manual-review"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.manual_review.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.name_prefix}-manual-review" }
}
