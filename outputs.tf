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
  description = "ARN of the IAM role CloudWatch Logs assumes for the subscription filters. Null when cloudwatch_log_groups is empty."
  value       = one(aws_iam_role.cloudwatch_to_firehose[*].arn)
}

output "flow_log_ids" {
  description = "Map of vpc_flow_logs key to flow log ID. Empty when vpc_flow_logs is empty."
  value       = { for k, v in aws_flow_log.fencer : k => v.id }
}

output "alb_log_delivery_destination_arn" {
  description = "ARN of the CloudWatch log delivery destination that points at the stream. Null when alb_load_balancers is empty."
  value       = one(aws_cloudwatch_log_delivery_destination.alb[*].arn)
}

output "alb_log_delivery_ids" {
  description = "Map of alb_load_balancers key to CloudWatch log delivery ID. Empty when alb_load_balancers is empty."
  value       = { for k, v in aws_cloudwatch_log_delivery.alb : k => v.id }
}

output "nlb_log_delivery_destination_arn" {
  description = "ARN of the CloudWatch log delivery destination that points at the stream. Null when nlb_load_balancers is empty."
  value       = one(aws_cloudwatch_log_delivery_destination.nlb[*].arn)
}

output "nlb_log_delivery_ids" {
  description = "Map of nlb_load_balancers key to CloudWatch log delivery ID. Empty when nlb_load_balancers is empty."
  value       = { for k, v in aws_cloudwatch_log_delivery.nlb : k => v.id }
}

output "s3_log_delivery_destination_arn" {
  description = "ARN of the CloudWatch log delivery destination that points at the stream. Null when s3_buckets is empty."
  value       = one(aws_cloudwatch_log_delivery_destination.s3[*].arn)
}

output "s3_log_delivery_ids" {
  description = "Map of s3_buckets key to CloudWatch log delivery ID. Empty when s3_buckets is empty."
  value       = { for k, v in aws_cloudwatch_log_delivery.s3 : k => v.id }
}

output "route53_resolver_query_log_config_id" {
  description = "ID of the Route 53 Resolver query logging configuration. Null when route53_resolver_vpcs and route53_resolver_profiles are empty."
  value       = one(aws_route53_resolver_query_log_config.fencer[*].id)
}

output "route53_resolver_query_log_config_association_ids" {
  description = "Map of route53_resolver_vpcs key to query logging association ID. Empty when route53_resolver_vpcs is empty."
  value       = { for key, id in var.route53_resolver_vpcs : key => aws_route53_resolver_query_log_config_association.fencer[id].id }
}

output "route53_resolver_profile_association_ids" {
  description = "Map of route53_resolver_profiles key to Profile association ID. Empty when route53_resolver_profiles is empty."
  value       = { for key, id in var.route53_resolver_profiles : key => aws_route53profiles_resource_association.fencer[id].id }
}
