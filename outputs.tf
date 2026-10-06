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

output "flow_log_ids" {
  description = "Map of VPC ID to flow log ID. Empty when vpc_flow_log_vpc_ids is empty."
  value       = { for k, v in aws_flow_log.fencer : k => v.id }
}

output "alb_log_delivery_destination_arn" {
  description = "ARN of the CloudWatch log delivery destination that points at the stream. Null when alb_load_balancer_arns is empty."
  value       = one(aws_cloudwatch_log_delivery_destination.alb[*].arn)
}

output "alb_log_delivery_ids" {
  description = "Map of load balancer ARN to CloudWatch log delivery ID. Empty when alb_load_balancer_arns is empty."
  value       = { for k, v in aws_cloudwatch_log_delivery.alb : k => v.id }
}
