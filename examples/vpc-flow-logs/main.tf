# Publish VPC flow logs straight to the Fencer Firehose stream.
# The module creates one flow log per VPC. It does not change the VPCs.
#
# Run this in the same AWS account and region as the VPCs.

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

variable "vpc_ids" {
  description = "IDs of the VPCs to publish flow logs from."
  type        = list(string)
}

module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  vpc_flow_log_vpc_ids = var.vpc_ids
}

output "firehose_delivery_stream_arn" {
  description = "The Firehose stream that delivers flow logs to Fencer."
  value       = module.fencer_monitor.firehose_delivery_stream_arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "flow_log_ids" {
  description = "Map of VPC ID to flow log ID."
  value       = module.fencer_monitor.flow_log_ids
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
