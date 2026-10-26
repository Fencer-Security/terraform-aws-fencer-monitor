# Publish Route 53 Resolver query logs straight to the Fencer Firehose stream.
# The module creates one query logging configuration and one association per VPC. It does not
# change the VPCs.
#
# Run this in the same AWS account and region as the VPCs.

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
  description = "Fencer access token. Generate it on the AWS Monitor page in the Fencer app. The Fencer data source must have the type AWS Route53 DNS Query Logs."
  type        = string
  sensitive   = true
}

variable "vpcs" {
  description = "VPCs whose Resolver queries to log: a key of your choice to the VPC ID. The key is the association's Terraform instance key."
  type        = map(string)
}

# Permissions. The principal that runs terraform apply needs the usual rights on Firehose, IAM, S3
# and CloudWatch Logs, plus these for the query logging:
#   route53resolver:CreateResolverQueryLogConfig, route53resolver:DeleteResolverQueryLogConfig
#   route53resolver:AssociateResolverQueryLogConfig, route53resolver:DisassociateResolverQueryLogConfig
#   route53resolver:GetResolverQueryLogConfig, route53resolver:GetResolverQueryLogConfigAssociation
#   route53resolver:ListResolverQueryLogConfigs, route53resolver:ListResolverQueryLogConfigAssociations
#   route53resolver:TagResource, route53resolver:UntagResource
#   route53resolver:ListTagsForResource
#   logs:CreateLogDelivery, logs:DeleteLogDelivery   delivery to Firehose
#   firehose:TagDeliveryStream
#   iam:CreateServiceLinkedRole                      first association in the account
module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  # Each module instance in an AWS account must have a different name_prefix. The IAM role, the
  # stream, the log group and the query logging configuration take their names from it.
  name_prefix = "fencer-route53-resolver"

  route53_resolver_vpcs = var.vpcs
}

output "firehose_delivery_stream_arn" {
  description = "The Firehose stream that delivers Resolver query logs to Fencer."
  value       = module.fencer_monitor.firehose_delivery_stream_arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "query_log_config_id" {
  description = "ID of the Resolver query logging configuration."
  value       = module.fencer_monitor.route53_resolver_query_log_config_id
}

output "query_log_config_association_ids" {
  description = "Map of vpcs key to query logging association ID."
  value       = module.fencer_monitor.route53_resolver_query_log_config_association_ids
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
