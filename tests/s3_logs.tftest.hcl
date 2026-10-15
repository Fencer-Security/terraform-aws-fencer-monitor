mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  # The Firehose resource validates ARN syntax on apply, so the mock apply run
  # needs well-formed ARNs instead of random strings.
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::fencer-siem-backup-test"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/fencer-siem-firehose"
    }
  }

  mock_resource "aws_kinesis_firehose_delivery_stream" {
    defaults = {
      arn = "arn:aws:firehose:us-east-1:111111111111:deliverystream/fencer-siem"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:111111111111:delivery-destination:fencer-siem"
    }
  }
}

variables {
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
  fencer_access_key   = "test-token"
  name_prefix         = "fencer-siem"
  bucket_a            = "arn:aws:s3:::web-prod-assets"
  bucket_b            = "arn:aws:s3:::api-prod-uploads"
}

run "no_s3_log_delivery_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.s3) == 0 && length(aws_cloudwatch_log_delivery_source.s3) == 0 && length(aws_cloudwatch_log_delivery.s3) == 0
    error_message = "No log delivery resources without bucket ARNs."
  }

  assert {
    condition     = !contains(keys(aws_kinesis_firehose_delivery_stream.fencer.tags), "LogDeliveryEnabled")
    error_message = "The stream must not carry the LogDeliveryEnabled tag when no S3 logs are delivered."
  }
}

run "one_delivery_per_bucket" {
  # The stream ARN is unknown at plan time, so this run applies against the mock provider.
  command = apply

  variables {
    s3_buckets = { web-prod = var.bucket_a, api-prod = var.bucket_b }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.s3) == 1
    error_message = "The module must create one delivery destination."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.s3[0].output_format == "json"
    error_message = "The delivery destination must use the json output format: Fencer parses JSON records only, and AWS allows only json for this log type."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.s3[0].delivery_destination_configuration[0].destination_resource_arn == aws_kinesis_firehose_delivery_stream.fencer.arn
    error_message = "The delivery destination must point at the module's stream."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.s3) == 2 && length(aws_cloudwatch_log_delivery.s3) == 2
    error_message = "The module must create one delivery source and one delivery per bucket."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.s3["web-prod"].name == "fencer-siem-web-prod" && aws_cloudwatch_log_delivery_source.s3["api-prod"].name == "fencer-siem-api-prod"
    error_message = "The delivery source name must be <name_prefix>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.s3["web-prod"].log_type == "S3_SERVER_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.s3["web-prod"].resource_arn == var.bucket_a
    error_message = "Each delivery source must carry the log type and its bucket ARN."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.s3["api-prod"].log_type == "S3_SERVER_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.s3["api-prod"].resource_arn == var.bucket_b
    error_message = "Each delivery source must carry the log type and its bucket ARN."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.s3["web-prod"].delivery_source_name == "fencer-siem-web-prod" && aws_cloudwatch_log_delivery.s3["web-prod"].delivery_destination_arn == aws_cloudwatch_log_delivery_destination.s3[0].arn
    error_message = "Each delivery must link its source to the module's destination."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry LogDeliveryEnabled = true, or the log delivery cannot write to it."
  }

  assert {
    condition     = length(output.s3_log_delivery_ids) == 2 && contains(keys(output.s3_log_delivery_ids), "web-prod")
    error_message = "s3_log_delivery_ids must map each s3_buckets key to its delivery."
  }

  assert {
    condition     = output.s3_log_delivery_destination_arn == aws_cloudwatch_log_delivery_destination.s3[0].arn
    error_message = "s3_log_delivery_destination_arn must be the destination ARN."
  }
}

run "stream_keeps_module_tags_with_the_delivery_tag" {
  command = plan

  variables {
    s3_buckets = { web-prod = var.bucket_a }
    tags       = { Team = "x" }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["Team"] == "x" && aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry the module tags and the LogDeliveryEnabled tag."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.s3["web-prod"].tags["Team"] == "x"
    error_message = "Delivery sources must carry the module tags."
  }
}

run "rejects_s3_and_nlb_together" {
  command = plan

  variables {
    s3_buckets         = { web-prod = var.bucket_a }
    nlb_load_balancers = { web = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/web-prod/50dc6c495c0c9188" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_s3_and_alb_together" {
  command = plan

  variables {
    s3_buckets         = { web-prod = var.bucket_a }
    alb_log_type       = "ALB_ACCESS_LOGS"
    alb_load_balancers = { web = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/web-prod/50dc6c495c0c9188" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_s3_and_vpcs_together" {
  command = plan

  variables {
    s3_buckets    = { web-prod = var.bucket_a }
    vpc_flow_logs = { main = "vpc-0aaa1111" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_s3_and_log_groups_together" {
  command = plan

  variables {
    s3_buckets            = { web-prod = var.bucket_a }
    cloudwatch_log_groups = { cloudtrail = "/aws/cloudtrail/test" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_duplicate_bucket_arns" {
  command = plan

  variables {
    s3_buckets = { web-prod = var.bucket_a, web2 = var.bucket_a }
  }

  expect_failures = [var.s3_buckets]
}

run "rejects_a_bucket_name_instead_of_an_arn" {
  command = plan

  variables {
    s3_buckets = { web-prod = "web-prod-assets" }
  }

  expect_failures = [var.s3_buckets]
}

run "rejects_an_object_arn" {
  command = plan

  variables {
    s3_buckets = { web-prod = "arn:aws:s3:::web-prod-assets/key" }
  }

  expect_failures = [var.s3_buckets]
}

run "rejects_a_key_that_cannot_name_a_delivery_source" {
  command = plan

  variables {
    s3_buckets = { "Web Prod" = var.bucket_a }
  }

  expect_failures = [var.s3_buckets]
}

run "rejects_a_delivery_source_name_over_60_characters" {
  command = plan

  variables {
    name_prefix = "fencer-siem-s3-access-logs-xx"
    s3_buckets  = { a-very-long-bucket-key-for-the-test-1234 = var.bucket_a }
  }

  expect_failures = [aws_cloudwatch_log_delivery_source.s3]
}

run "deliveries_exist" {
  command = apply

  variables {
    s3_buckets = { web = var.bucket_a }
    tags       = { team = "a" }
  }
}

run "tag_change_keeps_the_delivery" {
  command = apply

  variables {
    s3_buckets = { web = var.bucket_a }
    tags       = { team = "b" }
  }

  assert {
    condition     = output.s3_log_delivery_ids["web"] == run.deliveries_exist.s3_log_delivery_ids["web"]
    error_message = "A tag change must not replace the delivery."
  }
}

run "bucket_arn_change_replaces_the_delivery" {
  command = apply

  variables {
    s3_buckets = { web = var.bucket_b }
    tags       = { team = "b" }
  }

  assert {
    condition     = output.s3_log_delivery_ids["web"] != run.tag_change_keeps_the_delivery.s3_log_delivery_ids["web"]
    error_message = "A bucket ARN change must replace the delivery, or AWS refuses to delete the delivery source."
  }
}
