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

  mock_resource "aws_route53_resolver_query_log_config" {
    defaults = {
      id  = "rqlc-0000000000000000"
      arn = "arn:aws:route53resolver:us-east-1:111111111111:resolver-query-log-config/rqlc-0000000000000000"
    }
  }
}

variables {
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
  fencer_access_key   = "test-token"
  name_prefix         = "fencer-siem"
}

run "no_resolver_logging_by_default" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_query_log_config.fencer) == 0 && length(aws_route53_resolver_query_log_config_association.fencer) == 0 && length(aws_route53profiles_resource_association.fencer) == 0
    error_message = "No query logging resources without VPC or Profile ids."
  }

  assert {
    condition     = output.route53_resolver_query_log_config_id == null && length(output.route53_resolver_query_log_config_association_ids) == 0 && length(output.route53_resolver_profile_association_ids) == 0
    error_message = "The Resolver outputs must be null or empty when the module logs no Resolver queries."
  }
}

run "one_config_and_one_association_per_vpc" {
  # The stream ARN is unknown at plan time, so this run applies against the mock provider.
  command = apply

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111", second = "vpc-0bbb2222" }
  }

  assert {
    condition     = length(aws_route53_resolver_query_log_config.fencer) == 1
    error_message = "The module must create one query logging configuration for all VPCs."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config.fencer[0].name == var.name_prefix
    error_message = "The configuration must be named after name_prefix."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config.fencer[0].destination_arn == aws_kinesis_firehose_delivery_stream.fencer.arn
    error_message = "The configuration destination must be the module's stream ARN."
  }

  assert {
    condition     = length(aws_route53_resolver_query_log_config_association.fencer) == 2
    error_message = "The module must create one association per VPC id."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config_association.fencer["vpc-0aaa1111"].resource_id == "vpc-0aaa1111" && aws_route53_resolver_query_log_config_association.fencer["vpc-0bbb2222"].resource_id == "vpc-0bbb2222"
    error_message = "Each association must attach to its VPC."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config_association.fencer["vpc-0aaa1111"].resolver_query_log_config_id == aws_route53_resolver_query_log_config.fencer[0].id
    error_message = "Each association must use the module's configuration."
  }

  assert {
    condition     = output.route53_resolver_query_log_config_id == "rqlc-0000000000000000"
    error_message = "route53_resolver_query_log_config_id must return the configuration ID."
  }

  assert {
    condition     = length(output.route53_resolver_query_log_config_association_ids) == 2 && contains(keys(output.route53_resolver_query_log_config_association_ids), "main") && contains(keys(output.route53_resolver_query_log_config_association_ids), "second")
    error_message = "route53_resolver_query_log_config_association_ids must map each route53_resolver_vpcs key to its association."
  }

  assert {
    condition     = length(aws_route53profiles_resource_association.fencer) == 0
    error_message = "VPCs alone must create no Profile association."
  }
}

run "config_uses_module_tags" {
  command = apply

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    tags                  = { team = "sec" }
  }

  assert {
    condition     = aws_route53_resolver_query_log_config.fencer[0].tags["team"] == "sec"
    error_message = "The configuration must carry the module tags."
  }
}

run "stream_keeps_log_delivery_tag" {
  command = apply

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    tags                  = { team = "sec" }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true" && aws_kinesis_firehose_delivery_stream.fencer.tags["team"] == "sec"
    error_message = "The stream must have LogDeliveryEnabled=true and the module tags when the module logs Resolver queries."
  }
}

run "no_log_delivery_tag_without_resolver_vpcs" {
  command = plan

  assert {
    condition     = !contains(keys(aws_kinesis_firehose_delivery_stream.fencer.tags), "LogDeliveryEnabled")
    error_message = "The stream must not have LogDeliveryEnabled when the module logs no Resolver queries."
  }
}

run "rejects_resolver_vpcs_and_log_groups_together" {
  command = plan

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    cloudwatch_log_groups = { cloudtrail = "/aws/cloudtrail/test" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_resolver_vpcs_and_flow_logs_together" {
  command = plan

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    vpc_flow_logs         = { main = "vpc-0aaa1111" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_resolver_vpcs_and_alb_together" {
  command = plan

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    alb_log_type          = "ALB_ACCESS_LOGS"
    alb_load_balancers    = { web = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/web-prod/50dc6c495c0c9188" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_resolver_vpcs_and_nlb_together" {
  command = plan

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    nlb_load_balancers    = { web = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/web-prod/50dc6c495c0c9188" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_resolver_vpcs_and_s3_together" {
  command = plan

  variables {
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
    s3_buckets            = { web-prod = "arn:aws:s3:::web-prod-assets" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "rejects_all_digit_name_prefix" {
  command = plan

  variables {
    name_prefix           = "123"
    route53_resolver_vpcs = { main = "vpc-0aaa1111" }
  }

  expect_failures = [aws_route53_resolver_query_log_config.fencer]
}

run "rejects_duplicate_vpc_ids" {
  command = plan

  variables {
    route53_resolver_vpcs = { a = "vpc-1", b = "vpc-1" }
  }

  expect_failures = [var.route53_resolver_vpcs]
}

run "rejects_empty_vpc_id" {
  command = plan

  variables {
    route53_resolver_vpcs = { a = "" }
  }

  expect_failures = [var.route53_resolver_vpcs]
}

run "one_profile_association_per_profile" {
  command = apply

  variables {
    route53_resolver_profiles = { org = "rp-0000000000000000" }
  }

  assert {
    condition     = length(aws_route53_resolver_query_log_config.fencer) == 1
    error_message = "A Profile alone must create the query logging configuration."
  }

  assert {
    condition     = length(aws_route53_resolver_query_log_config_association.fencer) == 0
    error_message = "Profiles alone must create no VPC association."
  }

  assert {
    condition     = length(aws_route53profiles_resource_association.fencer) == 1
    error_message = "The module must create one association per Profile id."
  }

  assert {
    condition     = aws_route53profiles_resource_association.fencer["rp-0000000000000000"].name == "fencer-siem-org"
    error_message = "The Profile association must be named <name_prefix>-<key>."
  }

  assert {
    condition     = aws_route53profiles_resource_association.fencer["rp-0000000000000000"].profile_id == "rp-0000000000000000"
    error_message = "The association must attach to its Profile."
  }

  assert {
    condition     = aws_route53profiles_resource_association.fencer["rp-0000000000000000"].resource_arn == aws_route53_resolver_query_log_config.fencer[0].arn
    error_message = "The Profile association must attach the module's configuration."
  }

  assert {
    condition     = length(output.route53_resolver_profile_association_ids) == 1 && contains(keys(output.route53_resolver_profile_association_ids), "org")
    error_message = "route53_resolver_profile_association_ids must map each route53_resolver_profiles key to its association."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "A Profile alone must set LogDeliveryEnabled=true on the stream."
  }
}

run "vpcs_and_profiles_share_one_config" {
  command = apply

  variables {
    route53_resolver_vpcs     = { main = "vpc-0aaa1111" }
    route53_resolver_profiles = { org = "rp-0000000000000000" }
  }

  assert {
    condition     = length(aws_route53_resolver_query_log_config.fencer) == 1 && length(aws_route53_resolver_query_log_config_association.fencer) == 1 && length(aws_route53profiles_resource_association.fencer) == 1
    error_message = "VPCs and Profiles must share one configuration, with one association each."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream must have LogDeliveryEnabled=true."
  }
}

run "rejects_duplicate_profile_ids" {
  command = plan

  variables {
    route53_resolver_profiles = { a = "rp-1", b = "rp-1" }
  }

  expect_failures = [var.route53_resolver_profiles]
}

run "rejects_empty_profile_id" {
  command = plan

  variables {
    route53_resolver_profiles = { a = "" }
  }

  expect_failures = [var.route53_resolver_profiles]
}

run "rejects_invalid_profile_key" {
  command = plan

  variables {
    route53_resolver_profiles = { "my.profile" = "rp-0000000000000000" }
  }

  expect_failures = [var.route53_resolver_profiles]
}

run "rejects_over_long_profile_association_name" {
  command = plan

  variables {
    route53_resolver_profiles = { "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuv" = "rp-0000000000000000" }
  }

  expect_failures = [aws_route53profiles_resource_association.fencer]
}
