# Publish Route 53 Resolver query logs of a Route 53 Profile straight to the Fencer Firehose stream.
# The module creates one query logging configuration and attaches it to the Profile. Every VPC
# that is associated with the Profile is logged. The module does not change the Profile's VPCs.
#
# Run this in the same AWS account and region as the Profile.

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

variable "profile_id" {
  description = "ID of the Route 53 Profile whose Resolver queries to log."
  type        = string
}

# Permissions. The principal that runs terraform apply needs the usual rights on Firehose, IAM, S3
# and CloudWatch Logs, plus these for the query logging:
#   route53resolver:CreateResolverQueryLogConfig, route53resolver:DeleteResolverQueryLogConfig
#   route53resolver:GetResolverQueryLogConfig, route53resolver:ListResolverQueryLogConfigs
#   route53resolver:TagResource, route53resolver:UntagResource
#   route53resolver:ListTagsForResource
#   logs:CreateLogDelivery, logs:DeleteLogDelivery   delivery to Firehose
#   firehose:TagDeliveryStream
#   iam:CreateServiceLinkedRole                      first association in the account
# and these for the Profile association:
#   route53profiles:AssociateResourceToProfile, route53profiles:DisassociateResourceFromProfile
#   route53profiles:GetProfileResourceAssociation
module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  # Each module instance in an AWS account must have a different name_prefix. The IAM role, the
  # stream, the log group and the query logging configuration take their names from it.
  name_prefix = "fencer-route53-resolver"

  # The key names the association (<name_prefix>-<key>).
  route53_resolver_profiles = { main = var.profile_id }
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

output "profile_association_ids" {
  description = "Map of route53_resolver_profiles key to Profile association ID."
  value       = module.fencer_monitor.route53_resolver_profile_association_ids
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
