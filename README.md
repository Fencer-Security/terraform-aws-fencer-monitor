## terraform-aws-fencer-monitor

Terraform module that sets up AWS log streaming to [Fencer](https://www.fencer.dev).
It creates an Amazon Data Firehose delivery stream that sends log events to
Fencer's HTTP endpoint, plus the IAM roles, error logging, and failed-delivery
backup around it. Optionally it subscribes CloudWatch Logs log groups to the
stream.

This is the Infrastructure-as-Code equivalent of the manual console steps on
the AWS Monitor page in the Fencer app — apply it instead of clicking through
them. You configure the data source itself (type, parsing) in the Fencer app.

### Usage

One module instance per Fencer data source. CloudTrail example:

```hcl
module "fencer_monitor" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.1"

  # Copy both values from the AWS Monitor page in the Fencer app.
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/replace-me"
  fencer_access_key   = var.fencer_access_key

  # The CloudWatch Logs log group your CloudTrail trail delivers into.
  cloudwatch_log_group_names = ["aws-cloudtrail-logs-example"]
}
```

Pass `fencer_access_key` from a secrets manager or
`TF_VAR_fencer_access_key`. Do not commit it.
Terraform stores the key in plaintext in the state file — protect your state
(encrypted backend, restricted access).

Your CloudTrail trail must deliver to a CloudWatch Logs log group. See
[Connect an existing CloudTrail trail](#connect-an-existing-cloudtrail-trail)
for the three common starting points.

### Connect an existing CloudTrail trail

Deploy the module in the same AWS account and region as the trail's CloudWatch
Logs log group — subscription filters cannot cross accounts. For an
organization trail, that is the management account; one module instance there
covers all member accounts, because the organization trail collects every
account's events into one log group. Member accounts need no setup.

Then pick the case that matches your trail:

**1. The trail already delivers to a CloudWatch Logs log group.**
Pass the log group name and you are done:

```hcl
cloudwatch_log_group_names = ["aws-cloudtrail-logs-example"]
```

Find the name on the trail's detail page in the CloudTrail console, or:

```bash
aws cloudtrail get-trail --name my-trail \
  --query 'Trail.CloudWatchLogsLogGroupArn'
```

**2. Console-managed trail that delivers to S3 only.**
Enable CloudWatch Logs on the trail: CloudTrail → Trails → your trail → Edit →
CloudWatch Logs → Enabled. The console creates the log group and the delivery
role for you. Then pass the new log group name as in case 1.

**3. Terraform-managed trail that delivers to S3 only.**
Add a log group and a delivery role next to your existing `aws_cloudtrail`
resource, and reference them from it:

```hcl
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name = "aws-cloudtrail-logs-my-trail"
  # CloudTrail keeps the full history in your S3 bucket. This log group only
  # transports events to Firehose, so short retention is enough.
  retention_in_days = 3
}

resource "aws_iam_role" "cloudtrail_to_logs" {
  name = "cloudtrail-to-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_logs" {
  name = "deliver-to-log-group"
  role = aws_iam_role.cloudtrail_to_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# Add these two arguments to your existing trail:
resource "aws_cloudtrail" "my_trail" {
  # ... your existing configuration ...
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_logs.arn
}

module "fencer_monitor" {
  # ...
  cloudwatch_log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
}
```

**No trail at all?**
[`examples/cloudtrail-new-trail`](./examples/cloudtrail-new-trail) creates the
trail, its S3 bucket, the log group, the delivery role, and the module in one
configuration.

Note: a log group supports at most 5 subscription filters (AWS quota, not
adjustable). If the log group already feeds other destinations, check
`aws logs describe-subscription-filters` before you apply.

### What gets created

- An Amazon Data Firehose delivery stream with an HTTP endpoint destination:
  Fencer's URL, your Fencer access token, GZIP content encoding, 1 MiB / 60 s
  buffering.
- An S3 bucket that stores failed deliveries only. Public access blocked, versioning on, HTTP denied.
  Objects expire after 30 days.
- A CloudWatch Logs log group `/aws/kinesisfirehose/<name_prefix>` for
  Firehose error logs (7-day retention).
- An IAM role Firehose assumes to write to the bucket and the log group.
- When `cloudwatch_log_group_names` is set: an IAM role CloudWatch Logs
  assumes, and one subscription filter per log group (empty filter pattern =
  all events).

### Other data source types

The AWS delivery mechanism decides the setup:

| Data source | Setup |
|---|---|
| CloudTrail | This module. Pass the trail's log group. |
| RDS PostgreSQL logs, VPC flow logs, Route 53 resolver query logs | Not supported yet. |
| ALB/NLB access logs, S3 access logs | Not supported by this module yet. These services deliver to S3 only. Use the batch setup in the Fencer app. |

### Examples

Each example is a complete configuration with its own README (pre-checks,
apply, verify, clean up):

| Example | Scenario |
|---|---|
| [`examples/cloudtrail`](./examples/cloudtrail) | Existing trail that already delivers to CloudWatch Logs. |
| [`examples/cloudtrail-new-trail`](./examples/cloudtrail-new-trail) | No trail yet — creates the trail, its S3 bucket, the log group, and the stream. |

### Verify

After `terraform apply`, the Firehose monitoring tab shows successful HTTP
endpoint deliveries (2xx) within ~5 minutes, and the backup bucket stays
empty. Events appear in Fencer (Hunts).

### Use from Pulumi

Pulumi consumes this module directly — no rewrite:

```bash
pulumi package add terraform-module Fencer-Security/fencer-monitor/aws 1.1.0 fencermonitor
```

```ts
import * as fencermonitor from "@pulumi/fencermonitor";

const monitor = new fencermonitor.Module("fencer-monitor", {
  fencer_endpoint_url: "https://ingest.fencer.dev/v1/firehose/replace-me",
  fencer_access_key: config.requireSecret("fencerAccessKey"),
  cloudwatch_log_group_names: ["aws-cloudtrail-logs-example"],
});
```

### Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `fencer_endpoint_url` | `string` | — | Fencer Firehose HTTP endpoint URL (from the Fencer app). |
| `fencer_access_key` | `string` | — | Fencer access token (from the Fencer app). Sensitive. |
| `cloudwatch_log_group_names` | `list(string)` | `[]` | Log groups to subscribe to the stream. |
| `name_prefix` | `string` | `"fencer-siem"` | Prefix for all resource names. `^[a-z0-9][a-z0-9-]*$`, max 29 chars. |
| `subscription_filter_pattern` | `string` | `""` | Filter pattern. Empty sends all events. |
| `backup_expiration_days` | `number` | `30` | Expiry for failed-delivery objects. |
| `error_log_retention_days` | `number` | `7` | Retention of the error log group. |
| `tags` | `map(string)` | `{}` | Tags for all taggable resources. |

### Outputs

| Name | Description |
|---|---|
| `firehose_delivery_stream_arn` | Stream ARN. |
| `firehose_delivery_stream_name` | Stream name. |
| `backup_bucket_name` | Failed-delivery bucket name. |
| `backup_bucket_arn` | Failed-delivery bucket ARN. |
| `firehose_role_arn` | Firehose service role ARN. |
| `cloudwatch_to_firehose_role_arn` | Subscription role ARN, `null` when no log groups. |

### License

MIT — see [LICENSE](./LICENSE).
