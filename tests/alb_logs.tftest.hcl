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
  alb_a               = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/web-prod/50dc6c495c0c9188"
  alb_b               = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/api-prod/0123456789abcdef"
}

run "no_alb_log_delivery_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.alb) == 0 && length(aws_cloudwatch_log_delivery_source.alb) == 0 && length(aws_cloudwatch_log_delivery.alb) == 0
    error_message = "No log delivery resources without load balancer ARNs."
  }

  assert {
    condition     = !contains(keys(aws_kinesis_firehose_delivery_stream.fencer.tags), "LogDeliveryEnabled")
    error_message = "The stream must not carry the LogDeliveryEnabled tag when no ALB logs are delivered."
  }
}

run "one_delivery_per_load_balancer" {
  # The stream ARN is unknown at plan time, so this run applies against the mock provider.
  command = apply

  variables {
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = [var.alb_a, var.alb_b]
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.alb) == 1
    error_message = "The module must create one delivery destination."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.alb[0].output_format == "json"
    error_message = "The delivery destination must use the json output format: Fencer parses JSON records only."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.alb[0].delivery_destination_configuration[0].destination_resource_arn == aws_kinesis_firehose_delivery_stream.fencer.arn
    error_message = "The delivery destination must point at the module's stream."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.alb) == 2 && length(aws_cloudwatch_log_delivery.alb) == 2
    error_message = "The module must create one delivery source and one delivery per load balancer."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.alb[var.alb_a].name == "fencer-siem-web-prod"
    error_message = "The delivery source name must be <name_prefix>-<load balancer name>."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.alb[var.alb_a].log_type == "ALB_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.alb[var.alb_a].resource_arn == var.alb_a
    error_message = "Each delivery source must carry the log type and its load balancer ARN."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.alb[var.alb_a].delivery_source_name == "fencer-siem-web-prod" && aws_cloudwatch_log_delivery.alb[var.alb_a].delivery_destination_arn == aws_cloudwatch_log_delivery_destination.alb[0].arn
    error_message = "Each delivery must link its source to the module's destination."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry LogDeliveryEnabled = true, or the log delivery cannot write to it."
  }

  assert {
    condition     = length(output.alb_log_delivery_ids) == 2 && contains(keys(output.alb_log_delivery_ids), var.alb_a)
    error_message = "alb_log_delivery_ids must map each load balancer ARN to its delivery."
  }

  assert {
    condition     = output.alb_log_delivery_destination_arn == aws_cloudwatch_log_delivery_destination.alb[0].arn
    error_message = "alb_log_delivery_destination_arn must be the destination ARN."
  }
}

run "connection_logs_use_their_log_type" {
  command = plan

  variables {
    alb_log_type           = "ALB_CONNECTION_LOGS"
    alb_load_balancer_arns = [var.alb_a]
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.alb[var.alb_a].log_type == "ALB_CONNECTION_LOGS"
    error_message = "The delivery source must carry ALB_CONNECTION_LOGS."
  }
}

run "stream_keeps_module_tags_with_the_delivery_tag" {
  command = plan

  variables {
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = [var.alb_a]
    tags                   = { team = "security" }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["team"] == "security" && aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must carry the module tags and the LogDeliveryEnabled tag."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.alb[var.alb_a].tags["team"] == "security"
    error_message = "Delivery sources must carry the module tags."
  }
}

run "rejects_load_balancers_without_a_log_type" {
  command = plan

  variables {
    alb_load_balancer_arns = [var.alb_a]
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_unknown_log_type" {
  command = plan

  variables {
    alb_log_type           = "ALB_HEALTH_CHECK_LOGS"
    alb_load_balancer_arns = [var.alb_a]
  }

  expect_failures = [var.alb_log_type]
}

run "rejects_duplicate_load_balancer_arns" {
  command = plan

  variables {
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = [var.alb_a, var.alb_a]
  }

  expect_failures = [var.alb_load_balancer_arns]
}

run "rejects_a_load_balancer_name_instead_of_an_arn" {
  command = plan

  variables {
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = ["app/web-prod/50dc6c495c0c9188"]
  }

  expect_failures = [var.alb_load_balancer_arns]
}

run "rejects_a_network_load_balancer_arn" {
  command = plan

  variables {
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = ["arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/web-prod/50dc6c495c0c9188"]
  }

  expect_failures = [var.alb_load_balancer_arns]
}

run "rejects_a_delivery_source_name_over_60_characters" {
  command = plan

  variables {
    name_prefix            = "fencer-siem-alb-access-logs-x"
    alb_log_type           = "ALB_ACCESS_LOGS"
    alb_load_balancer_arns = ["arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/a-very-long-load-balancer-name-12/50dc6c495c0c9188"]
  }

  expect_failures = [aws_cloudwatch_log_delivery_source.alb]
}
