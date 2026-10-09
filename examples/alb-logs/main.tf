# Deliver Application Load Balancer access logs and connection logs straight to Fencer as JSON,
# through two CloudWatch log deliveries per load balancer. The module does not change the load
# balancers.
#
# One module instance delivers one log type to one Fencer data source, so this configuration has
# two instances: one for access logs and one for connection logs. Each has its own Fencer data
# source, its own token, its own stream and its own name_prefix. Both read the same load balancers.
#
# Run this in the same AWS account and region as the load balancers.

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
  description = "Firehose HTTP endpoint URL. Copy it from the AWS Monitor page in the Fencer app. Both Fencer data sources of one organization share it."
  type        = string
}

variable "fencer_access_logs_access_key" {
  description = "Fencer access token of the data source with the type AWS ALB Access Logs."
  type        = string
  sensitive   = true
}

variable "fencer_connection_logs_access_key" {
  description = "Fencer access token of the data source with the type AWS ALB Connection Logs."
  type        = string
  sensitive   = true
}

variable "load_balancers" {
  description = "Application Load Balancers to deliver both log types from: a key of your choice to the load balancer ARN. The key names the delivery sources (<name_prefix>-<key>)."
  type        = map(string)
}

# Permissions. The principal that runs terraform apply needs the usual rights on Firehose, IAM, S3
# and CloudWatch Logs, plus these for the log deliveries:
#   logs:PutDeliverySource, logs:GetDeliverySource, logs:DeleteDeliverySource,
#   logs:PutDeliveryDestination, logs:GetDeliveryDestination, logs:DeleteDeliveryDestination,
#   logs:CreateDelivery, logs:GetDelivery, logs:DeleteDelivery, logs:UpdateDeliveryConfiguration,
#   logs:DescribeDeliverySources, logs:DescribeDeliveryDestinations, logs:DescribeDeliveries
#   firehose:TagDeliveryStream
#   iam:CreateServiceLinkedRole                      first log delivery to Firehose in the account
#   elasticloadbalancing:AllowVendedLogDeliveryForResource   on the load balancers

# ---------------------------------------------------------------------------
# Access logs: one entry per request
# ---------------------------------------------------------------------------
module "fencer_alb_access_logs" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_logs_access_key

  # One prefix per instance, so the two instances do not collide in one account.
  name_prefix = "fencer-alb-access-logs"

  alb_log_type       = "ALB_ACCESS_LOGS"
  alb_load_balancers = var.load_balancers
}

# ---------------------------------------------------------------------------
# Connection logs: one entry per TLS connection
# ---------------------------------------------------------------------------
module "fencer_alb_connection_logs" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_connection_logs_access_key

  name_prefix = "fencer-alb-connection-logs"

  alb_log_type       = "ALB_CONNECTION_LOGS"
  alb_load_balancers = var.load_balancers
}

output "access_logs_stream_name" {
  description = "Stream of the access logs, for aws firehose describe-delivery-stream."
  value       = module.fencer_alb_access_logs.firehose_delivery_stream_name
}

output "connection_logs_stream_name" {
  description = "Stream of the connection logs, for aws firehose describe-delivery-stream."
  value       = module.fencer_alb_connection_logs.firehose_delivery_stream_name
}

output "access_log_delivery_ids" {
  description = "Map of load_balancers key to the CloudWatch log delivery of its access logs."
  value       = module.fencer_alb_access_logs.alb_log_delivery_ids
}

output "connection_log_delivery_ids" {
  description = "Map of load_balancers key to the CloudWatch log delivery of its connection logs."
  value       = module.fencer_alb_connection_logs.alb_log_delivery_ids
}

output "access_logs_backup_bucket" {
  description = "Bucket that stores failed access log deliveries. It must stay empty."
  value       = module.fencer_alb_access_logs.backup_bucket_name
}

output "connection_logs_backup_bucket" {
  description = "Bucket that stores failed connection log deliveries. It must stay empty."
  value       = module.fencer_alb_connection_logs.backup_bucket_name
}
