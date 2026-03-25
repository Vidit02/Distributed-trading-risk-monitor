resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project}-${var.environment}-transactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"
  range_key    = "timestamp"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "priority"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # GSI: query all transactions for a given priority, sorted by time
  global_secondary_index {
    name            = "priority-timestamp-index"
    hash_key        = "priority"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # GSI: query all transactions for a given status, sorted by time
  global_secondary_index {
    name            = "status-timestamp-index"
    hash_key        = "status"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-transactions"
  }
}
