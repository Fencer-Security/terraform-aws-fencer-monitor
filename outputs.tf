output "firehose_delivery_stream_arn" {
  description = "ARN of the Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.fencer.arn
}

output "firehose_delivery_stream_name" {
  description = "Name of the Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.fencer.name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket that stores failed deliveries."
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket that stores failed deliveries."
  value       = aws_s3_bucket.backup.arn
}

output "firehose_role_arn" {
  description = "ARN of the IAM role Firehose assumes."
  value       = aws_iam_role.firehose.arn
}

output "cloudwatch_to_firehose_role_arn" {
  description = "ARN of the IAM role CloudWatch Logs assumes for the subscription filters. Null when cloudwatch_log_group_names is empty."
  value       = one(aws_iam_role.cloudwatch_to_firehose[*].arn)
}
