# Subscribe an existing CloudTrail trail that already delivers to a
# CloudWatch Logs log group. The module only adds a subscription filter —
# it does not change the trail or the log group.
#
# Run this in the same AWS account and region as the log group. For an
# organization trail that is the management account.
# No trail yet? See ../cloudtrail-new-trail.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
  description = "Fencer access token. Generate it on the AWS Monitor page in the Fencer app."
  type        = string
  sensitive   = true
}

variable "cloudtrail_log_group_name" {
  description = "The CloudWatch Logs log group your CloudTrail trail delivers into."
  type        = string
}

# Fails at plan time if the log group does not exist, and guarantees the
# example never creates or alters it.
data "aws_cloudwatch_log_group" "cloudtrail" {
  name = var.cloudtrail_log_group_name
}

module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  cloudwatch_log_group_names = [data.aws_cloudwatch_log_group.cloudtrail.name]
}

output "firehose_delivery_stream_arn" {
  description = "The Firehose stream that delivers events to Fencer."
  value       = module.fencer_monitor.firehose_delivery_stream_arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
