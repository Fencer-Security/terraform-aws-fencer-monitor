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
  nlb_a               = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/web-prod/50dc6c495c0c9188"
  nlb_b               = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/api-prod/0123456789abcdef"
}

run "no_nlb_log_delivery_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.nlb) == 0 && length(aws_cloudwatch_log_delivery_source.nlb) == 0 && length(aws_cloudwatch_log_delivery.nlb) == 0
    error_message = "No log delivery resources without load balancer ARNs."
  }

  assert {
    condition     = !contains(keys(aws_kinesis_firehose_delivery_stream.fencer.tags), "LogDeliveryEnabled")
    error_message = "The stream must not carry the LogDeliveryEnabled tag when no NLB logs are delivered."
  }
}

run "one_delivery_per_load_balancer" {
  # The stream ARN is unknown at plan time, so this run applies against the mock provider.
  command = apply

  variables {
    nlb_load_balancers = { web-prod = var.nlb_a, api-prod = var.nlb_b }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.nlb) == 1
    error_message = "The module must create one delivery destination."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.nlb[0].output_format == "json"
    error_message = "The delivery destination must use the json output format: Fencer parses JSON records only."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.nlb[0].delivery_destination_configuration[0].destination_resource_arn == aws_kinesis_firehose_delivery_stream.fencer.arn
    error_message = "The delivery destination must point at the module's stream."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.nlb) == 2 && length(aws_cloudwatch_log_delivery.nlb) == 2
    error_message = "The module must create one delivery source and one delivery per load balancer."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.nlb["web-prod"].name == "fencer-siem-web-prod" && aws_cloudwatch_log_delivery_source.nlb["api-prod"].name == "fencer-siem-api-prod"
    error_message = "The delivery source name must be <name_prefix>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.nlb["web-prod"].log_type == "NLB_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.nlb["web-prod"].resource_arn == var.nlb_a
    error_message = "Each delivery source must carry the log type and its load balancer ARN."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.nlb["api-prod"].log_type == "NLB_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.nlb["api-prod"].resource_arn == var.nlb_b
    error_message = "Each delivery source must carry the log type and its load balancer ARN."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.nlb["web-prod"].delivery_source_name == "fencer-siem-web-prod" && aws_cloudwatch_log_delivery.nlb["web-prod"].delivery_destination_arn == aws_cloudwatch_log_delivery_destination.nlb[0].arn
    error_message = "Each delivery must link its source to the module's destination."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry LogDeliveryEnabled = true, or the log delivery cannot write to it."
  }

  assert {
    condition     = length(output.nlb_log_delivery_ids) == 2 && contains(keys(output.nlb_log_delivery_ids), "web-prod")
    error_message = "nlb_log_delivery_ids must map each nlb_load_balancers key to its delivery."
  }

  assert {
    condition     = output.nlb_log_delivery_destination_arn == aws_cloudwatch_log_delivery_destination.nlb[0].arn
    error_message = "nlb_log_delivery_destination_arn must be the destination ARN."
  }
}

run "stream_keeps_module_tags_with_the_delivery_tag" {
  command = plan

  variables {
    nlb_load_balancers = { web-prod = var.nlb_a }
    tags               = { Team = "x" }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["Team"] == "x" && aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry the module tags and the LogDeliveryEnabled tag."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.nlb["web-prod"].tags["Team"] == "x"
    error_message = "Delivery sources must carry the module tags."
  }
}

run "rejects_nlb_and_alb_together" {
  command = plan

  variables {
    alb_log_type       = "ALB_ACCESS_LOGS"
    alb_load_balancers = { web = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/web-prod/50dc6c495c0c9188" }
    nlb_load_balancers = { web-prod = var.nlb_a }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_nlb_and_vpcs_together" {
  command = plan

  variables {
    nlb_load_balancers = { web-prod = var.nlb_a }
    vpc_flow_logs      = { main = "vpc-0aaa1111" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_nlb_and_log_groups_together" {
  command = plan

  variables {
    nlb_load_balancers    = { web-prod = var.nlb_a }
    cloudwatch_log_groups = { cloudtrail = "/aws/cloudtrail/test" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_duplicate_nlb_arns" {
  command = plan

  variables {
    nlb_load_balancers = { web-prod = var.nlb_a, web2 = var.nlb_a }
  }

  expect_failures = [var.nlb_load_balancers]
}

run "rejects_an_application_load_balancer_arn" {
  command = plan

  variables {
    nlb_load_balancers = { web-prod = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/web-prod/50dc6c495c0c9188" }
  }

  expect_failures = [var.nlb_load_balancers]
}

run "rejects_a_key_that_cannot_name_a_delivery_source" {
  command = plan

  variables {
    nlb_load_balancers = { "Web Prod" = var.nlb_a }
  }

  expect_failures = [var.nlb_load_balancers]
}

run "rejects_a_delivery_source_name_over_60_characters" {
  command = plan

  variables {
    name_prefix        = "fencer-siem-nlb-access-logs-x"
    nlb_load_balancers = { a-very-long-load-balancer-key-1 = var.nlb_a }
  }

  expect_failures = [aws_cloudwatch_log_delivery_source.nlb]
}
