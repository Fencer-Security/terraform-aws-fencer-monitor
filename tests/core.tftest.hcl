mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}

variables {
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
  fencer_access_key   = "test-token"
}

run "core_pipeline" {
  command = plan

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.destination == "http_endpoint"
    error_message = "Delivery stream destination must be http_endpoint."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.name == "fencer-siem"
    error_message = "Delivery stream name must use name_prefix."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].url == var.fencer_endpoint_url
    error_message = "HTTP endpoint URL must equal fencer_endpoint_url."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].buffering_size == 1
    error_message = "Buffering size must stay at 1 MiB (validated design)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].buffering_interval == 60
    error_message = "Buffering interval must stay at 60 seconds (validated design)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].s3_backup_mode == "FailedDataOnly"
    error_message = "Backup mode must be FailedDataOnly (validated design)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].request_configuration[0].content_encoding == "GZIP"
    error_message = "Request content encoding must be GZIP (validated design)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].s3_configuration[0].compression_format == "GZIP"
    error_message = "S3 backup compression must be GZIP (validated design)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.firehose.name == "/aws/kinesisfirehose/fencer-siem"
    error_message = "Error log group name must be /aws/kinesisfirehose/<name_prefix>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.firehose.retention_in_days == 7
    error_message = "Error log group retention must default to 7 days."
  }

  assert {
    condition     = aws_s3_bucket.backup.bucket_prefix == "fencer-siem-backup-"
    error_message = "Backup bucket prefix must be <name_prefix>-backup-."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.backup.block_public_acls && aws_s3_bucket_public_access_block.backup.block_public_policy && aws_s3_bucket_public_access_block.backup.ignore_public_acls && aws_s3_bucket_public_access_block.backup.restrict_public_buckets
    error_message = "Backup bucket must block all public access."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.backup.rule[0].expiration[0].days == 30
    error_message = "Backup objects must expire after backup_expiration_days (default 30)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].name == "Fencer SIEM Log Ingestion"
    error_message = "HTTP endpoint name must be \"Fencer SIEM Log Ingestion\" (validated design)."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].cloudwatch_logging_options[0].enabled
    error_message = "Firehose error logging must be enabled."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].cloudwatch_logging_options[0].log_group_name == "/aws/kinesisfirehose/fencer-siem"
    error_message = "Firehose error logging must target the module's error log group."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.http_endpoint_configuration[0].cloudwatch_logging_options[0].log_stream_name == "DestinationDelivery"
    error_message = "Firehose error log stream must be DestinationDelivery (validated design)."
  }
}
