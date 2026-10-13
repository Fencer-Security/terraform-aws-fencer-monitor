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
  name_prefix         = "fencer-siem"
}

run "no_subscription_resources_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.fencer) == 0
    error_message = "No subscription filters without log groups."
  }

  assert {
    condition     = length(aws_iam_role.cloudwatch_to_firehose) == 0
    error_message = "No subscription role without log groups."
  }
}

run "one_filter_per_log_group" {
  command = plan

  variables {
    cloudwatch_log_groups = {
      cloudtrail = "aws-cloudtrail-logs-example"
      second     = "second-log-group-example"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.fencer) == 2
    error_message = "The module must create one subscription filter per log group."
  }

  assert {
    condition     = length(aws_iam_role.cloudwatch_to_firehose) == 1
    error_message = "The module must create exactly one subscription role."
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.fencer["cloudtrail"].filter_pattern == ""
    error_message = "The default filter pattern must be empty (all events)."
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.fencer["cloudtrail"].log_group_name == "aws-cloudtrail-logs-example"
    error_message = "The map value must be the log group name."
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.fencer["cloudtrail"].name == "fencer-siem"
    error_message = "The filter name must use name_prefix."
  }
}
