# Subscribe the PostgreSQL log of an existing RDS for PostgreSQL instance to
# Fencer. The instance publishes the log to a CloudWatch Logs log group. The
# module only adds a subscription filter on that log group. It does not change
# the instance or the log group.
#
# Run this in the same AWS account and region as the instance.
# For an Aurora PostgreSQL cluster, pass /aws/rds/cluster/<cluster>/postgresql
# to the module instead.

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
  description = "Fencer access token. Generate it on the AWS Monitor page in the Fencer app."
  type        = string
  sensitive   = true
}

variable "db_instance_identifier" {
  description = "The identifier of the RDS for PostgreSQL instance."
  type        = string
}

# Fails at plan time if the instance does not exist or does not export its
# PostgreSQL log to CloudWatch Logs. It also guarantees the example never
# creates or alters the instance.
data "aws_db_instance" "this" {
  db_instance_identifier = var.db_instance_identifier

  lifecycle {
    postcondition {
      condition     = contains(self.enabled_cloudwatch_logs_exports, "postgresql")
      error_message = "Enable the PostgreSQL log export on the instance first (Modify → Log exports → PostgreSQL)."
    }
  }
}

module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  # Each module instance in an AWS account must have a different name_prefix.
  name_prefix           = "fencer-rds-postgres"
  cloudwatch_log_groups = { postgresql = "/aws/rds/instance/${data.aws_db_instance.this.db_instance_identifier}/postgresql" }
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
