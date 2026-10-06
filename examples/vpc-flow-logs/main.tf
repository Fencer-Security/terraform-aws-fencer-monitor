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

# Permissions. The principal that runs terraform apply needs the usual rights on Firehose, IAM, S3
# and CloudWatch Logs, plus these for the flow logs:
#   logs:CreateLogDelivery, logs:DeleteLogDelivery   flow log delivery to Firehose
#   iam:CreateServiceLinkedRole                      first flow log in the account
#   firehose:TagDeliveryStream
# Versions 7 and later include ECS fields. For them AWS also requires:
#   ecs:ListClusters, ecs:ListContainerInstances, ecs:ListServices, ecs:ListTaskDefinitions,
#   ecs:ListTasks
module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  vpc_flow_log_vpc_ids = var.vpc_ids

  # Log format. Fencer reads the fields by position and accepts the full field set of one flow log
  # version, in the AWS order. The default is the version 10 set (42 fields). A subset, another
  # order or an unlisted version lands in Fencer as an error row. There is no version 6.
  #
  #   Version | Fields | Fields the version adds, in order
  #   2       | 14     | version account-id interface-id srcaddr dstaddr srcport dstport protocol
  #           |        | packets bytes start end action log-status
  #   3       | 21     | vpc-id subnet-id instance-id tcp-flags type pkt-srcaddr pkt-dstaddr
  #   4       | 25     | region az-id sublocation-type sublocation-id
  #   5       | 29     | pkt-src-aws-service pkt-dst-aws-service flow-direction traffic-path
  #   7       | 39     | ecs-cluster-arn ecs-cluster-name ecs-container-instance-arn
  #           |        | ecs-container-instance-id ecs-container-id ecs-second-container-id
  #           |        | ecs-service-name ecs-task-definition-arn ecs-task-arn ecs-task-id
  #   8       | 40     | reject-reason
  #   9       | 41     | resource-id
  #   10      | 42     | encryption-status                                  (default)
  #   11      | 54     | instance-tag instance-tag-2 interface-tag interface-tag-2 asg-tag asg-tag-2
  #           |        | interface-type next-hop-interface-id next-hop-subnet-id next-hop-az-id
  #           |        | next-hop-vpc-id next-hop-interface-type
  #
  # Version 11 needs TagFieldSpecifications on the flow log before AWS fills the tag fields.
  # To use another version, set vpc_flow_log_format to every field of that version as a
  # "$${field-name}" token (the double $ is the Terraform escape). The AWS default format,
  # version 2:
  #
  # vpc_flow_log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"
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
