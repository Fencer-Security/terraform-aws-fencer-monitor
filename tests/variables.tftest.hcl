mock_provider "aws" {}

run "rejects_non_https_url" {
  command = plan

  variables {
    fencer_endpoint_url = "http://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key   = "test-token"
  }

  expect_failures = [var.fencer_endpoint_url]
}

run "rejects_empty_access_key" {
  command = plan

  variables {
    fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key   = ""
  }

  expect_failures = [var.fencer_access_key]
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key   = "test-token"
    name_prefix         = "Fencer_SIEM"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_too_long_name_prefix" {
  command = plan

  variables {
    fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key   = "test-token"
    name_prefix         = "fencer-siem-cloudtrail-production-eu"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_zero_backup_expiration_days" {
  command = plan

  variables {
    fencer_endpoint_url    = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key      = "test-token"
    backup_expiration_days = 0
  }

  expect_failures = [var.backup_expiration_days]
}

run "rejects_zero_error_log_retention_days" {
  command = plan

  variables {
    fencer_endpoint_url      = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key        = "test-token"
    error_log_retention_days = 0
  }

  expect_failures = [var.error_log_retention_days]
}

run "rejects_leading_hyphen_name_prefix" {
  command = plan

  variables {
    fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key   = "test-token"
    name_prefix         = "-fencer-siem"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_duplicate_log_group_names" {
  command = plan

  variables {
    fencer_endpoint_url        = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key          = "test-token"
    cloudwatch_log_group_names = ["dup", "dup"]
  }

  expect_failures = [var.cloudwatch_log_group_names]
}

run "rejects_empty_log_group_name" {
  command = plan

  variables {
    fencer_endpoint_url        = "https://ingest.fencer.dev/v1/firehose/test"
    fencer_access_key          = "test-token"
    cloudwatch_log_group_names = [""]
  }

  expect_failures = [var.cloudwatch_log_group_names]
}
