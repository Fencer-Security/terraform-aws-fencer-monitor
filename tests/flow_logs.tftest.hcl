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
}

variables {
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
  fencer_access_key   = "test-token"
  name_prefix         = "fencer-siem"
}

run "no_flow_logs_by_default" {
  command = plan

  assert {
    condition     = length(aws_flow_log.fencer) == 0
    error_message = "No flow logs without VPC ids."
  }
}

run "one_flow_log_per_vpc" {
  # The stream ARN is unknown at plan time, so this run applies against the mock provider.
  command = apply

  variables {
    vpc_flow_logs = { main = "vpc-0aaa1111", second = "vpc-0bbb2222" }
  }

  assert {
    condition     = length(aws_flow_log.fencer) == 2
    error_message = "The module must create one flow log per VPC id."
  }

  assert {
    condition     = length(output.flow_log_ids) == 2 && contains(keys(output.flow_log_ids), "main") && contains(keys(output.flow_log_ids), "second")
    error_message = "flow_log_ids must map each vpc_flow_logs key to its flow log."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].vpc_id == "vpc-0aaa1111"
    error_message = "Each flow log must attach to its VPC."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].log_destination_type == "kinesis-data-firehose"
    error_message = "Flow logs must deliver straight to Firehose."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].log_destination == aws_kinesis_firehose_delivery_stream.fencer.arn
    error_message = "The flow log destination must be the module's stream ARN."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].traffic_type == "ALL"
    error_message = "The default traffic type must be ALL."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].max_aggregation_interval == 60
    error_message = "The default aggregation interval must be 60 seconds."
  }
}

run "flow_logs_use_module_tags" {
  command = plan

  variables {
    vpc_flow_logs = { main = "vpc-0aaa1111" }
    tags          = { team = "security" }
  }

  assert {
    condition     = aws_flow_log.fencer["main"].tags["team"] == "security"
    error_message = "Flow logs must carry the module tags."
  }
}

run "default_format_is_the_version_10_format" {
  command = plan

  variables {
    vpc_flow_logs = { main = "vpc-0aaa1111" }
  }

  assert {
    condition     = var.vpc_flow_log_format == "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path} $${ecs-cluster-arn} $${ecs-cluster-name} $${ecs-container-instance-arn} $${ecs-container-instance-id} $${ecs-container-id} $${ecs-second-container-id} $${ecs-service-name} $${ecs-task-definition-arn} $${ecs-task-arn} $${ecs-task-id} $${reject-reason} $${resource-id} $${encryption-status}"
    error_message = "The default log format must be the version 10 format: the 42 fields of AWS flow log version 10 in this order."
  }

  assert {
    condition     = aws_flow_log.fencer["main"].log_format == var.vpc_flow_log_format
    error_message = "The flow log must use vpc_flow_log_format."
  }
}

run "custom_format_is_passed_through" {
  command = plan

  variables {
    vpc_flow_logs       = { main = "vpc-0aaa1111" }
    vpc_flow_log_format = "$${version} $${account-id} $${interface-id}"
  }

  assert {
    condition     = aws_flow_log.fencer["main"].log_format == "$${version} $${account-id} $${interface-id}"
    error_message = "A custom vpc_flow_log_format must reach the flow log unchanged."
  }
}

run "rejects_unknown_traffic_type" {
  command = plan

  variables {
    vpc_flow_logs             = { main = "vpc-0aaa1111" }
    vpc_flow_log_traffic_type = "SOME"
  }

  expect_failures = [var.vpc_flow_log_traffic_type]
}

run "rejects_unsupported_aggregation_interval" {
  command = plan

  variables {
    vpc_flow_logs                         = { main = "vpc-0aaa1111" }
    vpc_flow_log_max_aggregation_interval = 120
  }

  expect_failures = [var.vpc_flow_log_max_aggregation_interval]
}

run "rejects_duplicate_vpc_ids" {
  command = plan

  variables {
    vpc_flow_logs = { a = "vpc-0aaa1111", b = "vpc-0aaa1111" }
  }

  expect_failures = [var.vpc_flow_logs]
}

run "rejects_empty_vpc_id" {
  command = plan

  variables {
    vpc_flow_logs = { main = "" }
  }

  expect_failures = [var.vpc_flow_logs]
}

run "rejects_empty_format" {
  command = plan

  variables {
    vpc_flow_log_format = ""
  }

  expect_failures = [var.vpc_flow_log_format]
}

run "stream_keeps_log_delivery_tag" {
  command = plan

  variables {
    vpc_flow_logs = { main = "vpc-0aaa1111" }
    tags          = { team = "security" }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.fencer.tags["LogDeliveryEnabled"] == "true" && aws_kinesis_firehose_delivery_stream.fencer.tags["team"] == "security"
    error_message = "The stream must have LogDeliveryEnabled=true when the module creates flow logs."
  }
}

run "no_log_delivery_tag_without_flow_logs" {
  command = plan

  assert {
    condition     = !contains(keys(aws_kinesis_firehose_delivery_stream.fencer.tags), "LogDeliveryEnabled")
    error_message = "The stream must not have LogDeliveryEnabled when the module creates no flow logs."
  }
}

run "rejects_flow_logs_and_log_groups_together" {
  command = plan

  variables {
    vpc_flow_logs         = { main = "vpc-0aaa1111" }
    cloudwatch_log_groups = { cloudtrail = "/aws/cloudtrail/test" }
  }

  expect_failures = [aws_kinesis_firehose_delivery_stream.fencer]
}

run "tag_field_specifications_reach_the_flow_log" {
  command = apply

  variables {
    vpc_flow_logs       = { main = "vpc-0aaa1111" }
    vpc_flow_log_format = "$${version} $${instance-tag} $${asg-tag}"
    vpc_flow_log_tag_field_specifications = [
      { resource_type = "instance", tag_keys = ["Name"] },
      { resource_type = "auto-scaling-group", tag_keys = ["team"] },
    ]
  }

  assert {
    condition     = length(aws_flow_log.fencer["main"].tag_field_specification) == 2
    error_message = "Each tag field specification must reach the flow log."
  }
}

run "rejects_tag_fields_without_specifications" {
  command = plan

  variables {
    vpc_flow_logs       = { main = "vpc-0aaa1111" }
    vpc_flow_log_format = "$${version} $${interface-tag-2}"
  }

  expect_failures = [aws_flow_log.fencer]
}

run "rejects_unknown_tag_resource_type" {
  command = plan

  variables {
    vpc_flow_logs                         = { main = "vpc-0aaa1111" }
    vpc_flow_log_tag_field_specifications = [{ resource_type = "subnet", tag_keys = ["Name"] }]
  }

  expect_failures = [var.vpc_flow_log_tag_field_specifications]
}
