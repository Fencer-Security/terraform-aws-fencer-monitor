# Deliver S3 server access logs straight to the Fencer Firehose stream as JSON.
# The module creates one CloudWatch log delivery per bucket. It does not change the buckets.
#
# AWS takes 15 to 20 minutes to apply the delivery. Delivery then begins within a few hours and
# includes new requests only. AWS supports general purpose buckets only.
#
# Run this in the same AWS account and region as the buckets.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.56.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "fencer_endpoint_url" {
  description = "Firehose HTTP endpoint URL. Copy it from the AWS Monitor page in the Fencer app."
  type        = string
}

variable "fencer_access_key" {
  description = "Fencer access token. Generate it on the AWS Monitor page in the Fencer app. The Fencer data source must have the type AWS S3 Bucket Access Logs."
  type        = string
  sensitive   = true
}

variable "buckets" {
  description = "General purpose S3 buckets to deliver server access logs from: a key of your choice to the bucket ARN. The key names the delivery source (<name_prefix>-<key>)."
  type        = map(string)
}

# Permissions. The principal that runs terraform apply needs the usual rights on Firehose, IAM, S3
# and CloudWatch Logs, plus these for the log delivery:
#   logs:PutDeliverySource, logs:GetDeliverySource, logs:DeleteDeliverySource,
#   logs:PutDeliveryDestination, logs:GetDeliveryDestination, logs:DeleteDeliveryDestination,
#   logs:CreateDelivery, logs:GetDelivery, logs:DeleteDelivery, logs:UpdateDeliveryConfiguration,
#   logs:DescribeDeliverySources, logs:DescribeDeliveryDestinations, logs:DescribeDeliveries
#   firehose:TagDeliveryStream
#   iam:CreateServiceLinkedRole                      first log delivery to Firehose in the account
#   s3:AllowVendedLogDeliveryForResource             on the buckets
module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  # One prefix per log type, so instances for different log types do not collide in one account.
  name_prefix = "fencer-s3-access-logs"

  s3_buckets = var.buckets
}

output "firehose_delivery_stream_arn" {
  description = "The Firehose stream that delivers the logs to Fencer."
  value       = module.fencer_monitor.firehose_delivery_stream_arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "s3_log_delivery_ids" {
  description = "Map of buckets key to CloudWatch log delivery ID."
  value       = module.fencer_monitor.s3_log_delivery_ids
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
