data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.name_prefix}"
  retention_in_days = var.error_log_retention_days
  tags              = var.tags
}

resource "aws_s3_bucket" "backup" {
  bucket_prefix = "${var.name_prefix}-backup-"
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureConnections"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "expire-failed-deliveries"
    status = "Enabled"
    filter {}
    expiration {
      days = var.backup_expiration_days
    }
    noncurrent_version_expiration {
      noncurrent_days = var.backup_expiration_days
    }
  }
}

resource "aws_iam_role" "firehose" {
  name = "${var.name_prefix}-firehose"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.name_prefix}-firehose"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.firehose.arn}:*"]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "fencer" {
  name        = var.name_prefix
  destination = "http_endpoint"
  # The AWSServiceRoleForLogDelivery role can write only to a stream with the tag
  # LogDeliveryEnabled=true. AWS adds the tag when it creates a flow log, and Terraform removes a
  # tag that is not in the configuration on the next apply. Keep it while the module creates flow
  # logs, so a stream that only CloudTrail uses does not get it.
  tags = merge(var.tags, length(var.vpc_flow_log_vpc_ids) > 0 ? { LogDeliveryEnabled = "true" } : {})

  http_endpoint_configuration {
    url                = var.fencer_endpoint_url
    name               = "Fencer SIEM Log Ingestion"
    access_key         = var.fencer_access_key
    buffering_size     = 1
    buffering_interval = 60
    role_arn           = aws_iam_role.firehose.arn
    s3_backup_mode     = "FailedDataOnly"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "DestinationDelivery"
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose.arn
      bucket_arn         = aws_s3_bucket.backup.arn
      buffering_size     = 1
      buffering_interval = 60
      compression_format = "GZIP"
    }

    request_configuration {
      content_encoding = "GZIP"
    }
  }

  # Firehose validates S3 and CloudWatch access lazily, but stream creation must
  # not race the policy attachment on a customer's first apply.
  depends_on = [aws_iam_role_policy.firehose]
}

resource "aws_iam_role" "cloudwatch_to_firehose" {
  count = length(var.cloudwatch_log_group_names) > 0 ? 1 : 0
  name  = "${var.name_prefix}-cw-subscription"
  tags  = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "cloudwatch_to_firehose" {
  count = length(var.cloudwatch_log_group_names) > 0 ? 1 : 0
  name  = "${var.name_prefix}-cw-subscription"
  role  = aws_iam_role.cloudwatch_to_firehose[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = [aws_kinesis_firehose_delivery_stream.fencer.arn]
    }]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "fencer" {
  for_each        = toset(var.cloudwatch_log_group_names)
  name            = var.name_prefix
  role_arn        = aws_iam_role.cloudwatch_to_firehose[0].arn
  log_group_name  = each.value
  filter_pattern  = var.subscription_filter_pattern
  destination_arn = aws_kinesis_firehose_delivery_stream.fencer.arn

  depends_on = [aws_iam_role_policy.cloudwatch_to_firehose]
}

resource "aws_flow_log" "fencer" {
  for_each                 = toset(var.vpc_flow_log_vpc_ids)
  vpc_id                   = each.value
  traffic_type             = var.vpc_flow_log_traffic_type
  log_destination_type     = "kinesis-data-firehose"
  log_destination          = aws_kinesis_firehose_delivery_stream.fencer.arn
  log_format               = var.vpc_flow_log_format
  max_aggregation_interval = var.vpc_flow_log_max_aggregation_interval
  tags                     = var.tags

  dynamic "tag_field_specification" {
    for_each = var.vpc_flow_log_tag_field_specifications
    content {
      resource_type = tag_field_specification.value.resource_type
      tag_keys      = tag_field_specification.value.tag_keys
    }
  }

  # One instance sends data to one Fencer data source of one type. Flow logs and CloudTrail events
  # in the same stream fail the transformation of the other type.
  lifecycle {
    precondition {
      condition     = length(var.cloudwatch_log_group_names) == 0
      error_message = "Use a different module instance for VPC flow logs. One instance sends data to one Fencer data source."
    }
    # AWS fills a tag field only from TagFieldSpecifications, which exist at creation only.
    precondition {
      condition     = !can(regex("-tag(-2)?}", var.vpc_flow_log_format)) || length(var.vpc_flow_log_tag_field_specifications) > 0
      error_message = "vpc_flow_log_format has tag fields. Set vpc_flow_log_tag_field_specifications, or AWS cannot fill them."
    }
  }
}
