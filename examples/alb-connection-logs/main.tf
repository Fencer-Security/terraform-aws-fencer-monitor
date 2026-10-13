# Deliver Application Load Balancer connection logs straight to the Fencer Firehose stream as JSON.
# The module creates one CloudWatch log delivery per load balancer. It does not change the load
# balancers.
#
# One module instance delivers one log type to one Fencer data source. For access logs,
# create a second Fencer data source and use examples/alb-access-logs with its own token.
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
  description = "Firehose HTTP endpoint URL. Copy it from the AWS Monitor page in the Fencer app."
  type        = string
}

variable "fencer_access_key" {
  description = "Fencer access token. Generate it on the AWS Monitor page in the Fencer app. The Fencer data source must have the type AWS ALB Connection Logs."
  type        = string
  sensitive   = true
}

variable "load_balancers" {
  description = "Application Load Balancers to deliver logs from: a key of your choice to the load balancer ARN. The key names the delivery source (<name_prefix>-<key>)."
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
#   elasticloadbalancing:AllowVendedLogDeliveryForResource   on the load balancers
module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  # One prefix per log type, so the instances for both log types do not collide in one account.
  name_prefix = "fencer-alb-connection-logs"

  alb_log_type       = "ALB_CONNECTION_LOGS"
  alb_load_balancers = var.load_balancers
}

output "firehose_delivery_stream_arn" {
  description = "The Firehose stream that delivers the logs to Fencer."
  value       = module.fencer_monitor.firehose_delivery_stream_arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "alb_log_delivery_ids" {
  description = "Map of load_balancers key to CloudWatch log delivery ID."
  value       = module.fencer_monitor.alb_log_delivery_ids
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
