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

run "outputs" {
  command = plan

  assert {
    condition     = output.firehose_delivery_stream_name == "fencer-siem"
    error_message = "firehose_delivery_stream_name must equal name_prefix."
  }

  assert {
    condition     = output.cloudwatch_to_firehose_role_arn == null
    error_message = "cloudwatch_to_firehose_role_arn must be null without log groups."
  }
}
