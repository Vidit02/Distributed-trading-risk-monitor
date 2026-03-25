output "transactions_table_name" {
  description = "Name of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.name
}

output "transactions_table_arn" {
  description = "ARN of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.arn
}

output "transactions_table_id" {
  description = "ID of the transactions DynamoDB table"
  value       = aws_dynamodb_table.transactions.id
}
