output "state_bucket_name" {
  description = "S3 bucket to reference from infra/live/<env>/backend.tf"
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tf_state.arn
}

output "lock_table_name" {
  description = "DynamoDB table to reference from infra/live/<env>/backend.tf"
  value       = aws_dynamodb_table.tf_lock.name
}

output "lock_table_arn" {
  value = aws_dynamodb_table.tf_lock.arn
}
