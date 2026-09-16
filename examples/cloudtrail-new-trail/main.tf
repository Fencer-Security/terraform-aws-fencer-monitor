# Create a CloudTrail trail from scratch and stream it to Fencer:
# S3 bucket for the trail history, CloudWatch Logs log group as transport,
# the trail itself, and the Fencer monitor module.
#
# Already have a trail? See ../cloudtrail — subscribing the existing log
# group is much less setup. Note: the first copy of management events per
# account is free; additional trails are billed by AWS.

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

variable "trail_name" {
  description = "Name for the new CloudTrail trail."
  type        = string
  default     = "fencer-trail"
}

data "aws_caller_identity" "current" {}

# --- Trail storage: S3 keeps the full CloudTrail history ---

resource "aws_s3_bucket" "cloudtrail" {
  bucket_prefix = "${var.trail_name}-logs-"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"
          }
        }
      }
    ]
  })
}

# --- CloudWatch Logs transport: short retention is enough, S3 keeps history ---

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "aws-cloudtrail-logs-${var.trail_name}"
  retention_in_days = 3
}

resource "aws_iam_role" "cloudtrail_to_logs" {
  name = "${var.trail_name}-to-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_logs" {
  name = "deliver-to-log-group"
  role = aws_iam_role.cloudtrail_to_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# --- The trail ---

resource "aws_cloudtrail" "this" {
  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_logs.arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# --- Stream to Fencer ---

module "fencer_monitor" {
  source = "../../"

  fencer_endpoint_url = var.fencer_endpoint_url
  fencer_access_key   = var.fencer_access_key

  cloudwatch_log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
}

output "trail_arn" {
  description = "The new CloudTrail trail."
  value       = aws_cloudtrail.this.arn
}

output "firehose_delivery_stream_name" {
  description = "Stream name, for aws firehose describe-delivery-stream."
  value       = module.fencer_monitor.firehose_delivery_stream_name
}

output "backup_bucket" {
  description = "Bucket that stores failed deliveries. It must stay empty."
  value       = module.fencer_monitor.backup_bucket_name
}
