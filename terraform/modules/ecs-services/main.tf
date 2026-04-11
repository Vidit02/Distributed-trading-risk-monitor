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
        { name = "HIGH_PRIORITY_QUEUE_URL", value = var.high_priority_queue_url },
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
        { name = "HIGH_PRIORITY_QUEUE_URL", value = var.high_priority_queue_url },
        { name = "RISK_BREACH_TOPIC_ARN", value = var.sns_risk_breach_events_arn },
        { name = "REDIS_ADDR", value = "${var.redis_primary_endpoint}:${var.redis_port}" },
        { name = "DAILY_LIMIT", value = tostring(var.daily_limit) },
        { name = "AWS_REGION", value = var.aws_region }
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
        { name = "QUEUE_URL", value = var.low_priority_queue_url },
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
        { name = "QUEUE_URL", value = var.low_priority_queue_url },
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

  tags = { Name = "${local.name_prefix}-audit-logging" }
}
