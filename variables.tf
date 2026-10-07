variable "fencer_endpoint_url" {
  type        = string
  description = "The Fencer Firehose HTTP endpoint URL. Copy it from the AWS Monitor page in the Fencer app."

  validation {
    condition     = startswith(var.fencer_endpoint_url, "https://")
    error_message = "fencer_endpoint_url must start with https://."
  }
}

variable "fencer_access_key" {
  type        = string
  description = "The Fencer access token. Generate it on the AWS Monitor page in the Fencer app. Pass it from a secrets manager or TF_VAR_fencer_access_key. Do not commit it."
  sensitive   = true

  validation {
    condition     = length(var.fencer_access_key) > 0
    error_message = "fencer_access_key must not be empty."
  }
}

variable "cloudwatch_log_group_names" {
  type        = list(string)
  description = "CloudWatch Logs log groups to stream to Fencer. The module creates one subscription filter per log group. Leave empty when the AWS service writes to the Firehose stream directly."
  default     = []

  validation {
    condition     = alltrue([for name in var.cloudwatch_log_group_names : length(name) > 0]) && length(var.cloudwatch_log_group_names) == length(distinct(var.cloudwatch_log_group_names))
    error_message = "cloudwatch_log_group_names entries must be non-empty and unique."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names. Required: each module instance in an AWS account needs a different prefix (for example fencer-cloudtrail, fencer-flowlogs), or the IAM role, the stream and the log group collide."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name_prefix)) && length(var.name_prefix) <= 29
    error_message = "name_prefix must start with a lowercase letter or digit, match ^[a-z0-9][a-z0-9-]*$, and contain at most 29 characters."
  }
}

variable "subscription_filter_pattern" {
  type        = string
  description = "Filter pattern for the subscription filters. Empty sends all events."
  default     = ""
}

variable "backup_expiration_days" {
  type        = number
  description = "Days before failed-delivery objects expire from the backup bucket."
  default     = 30

  validation {
    condition     = var.backup_expiration_days >= 1
    error_message = "backup_expiration_days must be at least 1."
  }
}

variable "error_log_retention_days" {
  type        = number
  description = "Retention in days for the Firehose error log group."
  default     = 7

  validation {
    condition     = var.error_log_retention_days >= 1
    error_message = "error_log_retention_days must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all taggable resources."
  default     = {}
}

variable "vpc_flow_log_vpc_ids" {
  type        = list(string)
  description = "IDs of the VPCs to publish flow logs from. The module creates one flow log per VPC and delivers it straight to the Firehose stream. The VPCs must be in the same account and region as the stream. Leave empty to create no flow logs."
  default     = []

  validation {
    condition     = alltrue([for id in var.vpc_flow_log_vpc_ids : length(id) > 0]) && length(var.vpc_flow_log_vpc_ids) == length(distinct(var.vpc_flow_log_vpc_ids))
    error_message = "vpc_flow_log_vpc_ids entries must be non-empty and unique."
  }
}

variable "vpc_flow_log_format" {
  type        = string
  description = "Log format of the flow logs. The default is the AWS version 10 field set (42 fields). Fencer accepts the full field set of any flow log version (2 to 11) in AWS table order. Any other field set needs a custom Fencer transformation."
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path} $${ecs-cluster-arn} $${ecs-cluster-name} $${ecs-container-instance-arn} $${ecs-container-instance-id} $${ecs-container-id} $${ecs-second-container-id} $${ecs-service-name} $${ecs-task-definition-arn} $${ecs-task-arn} $${ecs-task-id} $${reject-reason} $${resource-id} $${encryption-status}"

  validation {
    condition     = length(var.vpc_flow_log_format) > 0
    error_message = "vpc_flow_log_format must not be empty."
  }
}

variable "vpc_flow_log_traffic_type" {
  type        = string
  description = "Traffic to log: ACCEPT, REJECT, or ALL."
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.vpc_flow_log_traffic_type)
    error_message = "vpc_flow_log_traffic_type must be ACCEPT, REJECT, or ALL."
  }
}

variable "vpc_flow_log_max_aggregation_interval" {
  type        = number
  description = "Maximum interval in seconds that AWS aggregates flow log records before it publishes them: 60 or 600."
  default     = 60

  validation {
    condition     = contains([60, 600], var.vpc_flow_log_max_aggregation_interval)
    error_message = "vpc_flow_log_max_aggregation_interval must be 60 or 600."
  }
}

variable "vpc_flow_log_tag_field_specifications" {
  type = list(object({
    resource_type = string
    tag_keys      = list(string)
  }))
  description = "Tag keys to publish in the version 11 tag fields (instance-tag, interface-tag, asg-tag and their -2 variants), by resource type: instance, network-interface or auto-scaling-group. Required when vpc_flow_log_format has a tag field. The principal needs ec2:DescribeTags for instance and network-interface tags and autoscaling:DescribeTags for Auto Scaling group tags."
  default     = []

  validation {
    condition = alltrue([
      for spec in var.vpc_flow_log_tag_field_specifications :
      contains(["instance", "network-interface", "auto-scaling-group"], spec.resource_type)
    ])
    error_message = "resource_type must be instance, network-interface or auto-scaling-group."
  }
}
