output "audit_logs_bucket_name" {
  description = "Name of the audit logs S3 bucket"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "audit_logs_bucket_arn" {
  description = "ARN of the audit logs S3 bucket"
  value       = aws_s3_bucket.audit_logs.arn
}

output "audit_logs_bucket_id" {
  description = "ID of the audit logs S3 bucket"
  value       = aws_s3_bucket.audit_logs.id
}
