## terraform-aws-fencer-monitor

Terraform module that sets up AWS log streaming to [Fencer](https://www.fencer.dev).
It creates an Amazon Data Firehose delivery stream that sends log events to
Fencer's HTTP endpoint, plus the IAM roles, error logging, and failed-delivery
backup around it. Optionally it subscribes CloudWatch Logs log groups to the
stream, or publishes VPC flow logs to it.

This is the Infrastructure-as-Code equivalent of the manual console steps on
the AWS Monitor page in the Fencer app — apply it instead of clicking through
them. You configure the data source itself (type, parsing) in the Fencer app.

### Usage

One module instance per Fencer data source. CloudTrail example:

```hcl
module "fencer_monitor" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.3"

  # Copy both values from the AWS Monitor page in the Fencer app.
  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/replace-me"
  fencer_access_key   = var.fencer_access_key

  # The CloudWatch Logs log group your CloudTrail trail delivers into. The key
  # is yours to choose; it is the Terraform instance key of the subscription filter.
  name_prefix           = "fencer-cloudtrail"
  cloudwatch_log_groups = { cloudtrail = "aws-cloudtrail-logs-example" }
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
cloudwatch_log_groups = { cloudtrail = "aws-cloudtrail-logs-example" }
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
  name_prefix           = "fencer-cloudtrail"
  cloudwatch_log_groups = { cloudtrail = aws_cloudwatch_log_group.cloudtrail.name }
}
```

**No trail at all?**
[`examples/cloudtrail-new-trail`](./examples/cloudtrail-new-trail) creates the
trail, its S3 bucket, the log group, the delivery role, and the module in one
configuration.

Note: a log group supports at most 5 subscription filters (AWS quota, not
adjustable). If the log group already feeds other destinations, check
`aws logs describe-subscription-filters` before you apply.

### Connect VPC flow logs

Deploy the module in the same AWS account and region as the VPCs. A flow log
delivers straight to the Firehose stream, so it needs no IAM role and no log
group. Pass the VPCs as a map of a key of your choice to the VPC ID:

```hcl
module "fencer_monitor" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.3"

  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/replace-me"
  fencer_access_key   = var.fencer_access_key

  # Each module instance in an AWS account must have a different name_prefix.
  name_prefix   = "fencer-flowlogs"
  vpc_flow_logs = { main = "vpc-0123456789abcdef0" }
}
```

The module creates one flow log per VPC. Use one module instance per Fencer
data source. Do not send CloudTrail and flow logs through the same instance;
the module refuses VPCs and log groups together. Each module instance
in an AWS account must have a different `name_prefix` (the input is required): the IAM role, the
stream and the log group take their names from it.

The default `vpc_flow_log_format` is the AWS version 10 field set (42 fields).
Fencer accepts the full field set of one flow log version in AWS table order.
To publish another version, set `vpc_flow_log_format` to the full field set of
that version; [`examples/vpc-flow-logs/formats.tf`](./examples/vpc-flow-logs/formats.tf)
holds the string for every version. A subset or another order lands in Fencer
as error rows.

Version 11 adds tag fields (`instance-tag`, `interface-tag`, `asg-tag` and
their `-2` variants). AWS fills them only from tag field specifications set at
flow log creation, so set `vpc_flow_log_tag_field_specifications` together
with the version 11 format:

```hcl
  vpc_flow_log_tag_field_specifications = [
    { resource_type = "instance", tag_keys = ["Name", "team"] },
    { resource_type = "auto-scaling-group", tag_keys = ["Name"] },
  ]
```

The module refuses a format with tag fields and no specifications. For the tag
fields the principal also needs `ec2:DescribeTags` (instance and network
interface tags) and `autoscaling:DescribeTags` (Auto Scaling group tags). Auto
Scaling group tag values update only when the account has an enabled CloudTrail
trail.

The first flow log with tag fields in an AWS account makes AWS create the
service-linked role `AWSServiceRoleForVPCFlowLogs`. That first `terraform apply`
can fail with `IncorrectState: FlowLogs Service Linked Role is not yet
available`. Run `terraform apply` again; the role exists from then on. The
module does not manage the role: it belongs to the account, not to one
instance, and AWS refuses to delete it while any flow log with tag fields
exists.

The principal that runs Terraform needs these IAM permissions:
`logs:CreateLogDelivery`, `logs:DeleteLogDelivery`,
`iam:CreateServiceLinkedRole`, and `firehose:TagDeliveryStream`. For the ECS
fields it also needs `ecs:ListClusters`, `ecs:ListContainerInstances`,
`ecs:ListServices`, `ecs:ListTaskDefinitions`, and `ecs:ListTasks`.

See [`examples/vpc-flow-logs`](./examples/vpc-flow-logs).

### Connect ALB access logs or connection logs

Deploy the module in the same AWS account and region as the load balancers.
An Application Load Balancer delivers its access logs and connection logs
through a CloudWatch log delivery (vended logs), straight to the Firehose
stream, as JSON. Pass the log type and the load balancers as a map of a key of
your choice to the load balancer ARN. The key names the delivery source
(`<name_prefix>-<key>`) and is its Terraform instance key, so a load balancer
created in the same apply works. The plan refuses a load balancer from another
account or region:

```hcl
module "fencer_alb_access_logs" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.3"

  fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/replace-me"
  fencer_access_key   = var.fencer_alb_access_logs_access_key
  name_prefix         = "fencer-alb-access-logs"

  alb_log_type       = "ALB_ACCESS_LOGS"
  alb_load_balancers = { my-lb = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/50dc6c495c0c9188" }
}
```

The module creates one delivery destination that points at the stream, and
one delivery source plus one delivery per load balancer. One module instance
delivers one log type to one Fencer data source. For connection logs, create a
second Fencer data source of type AWS ALB Connection Logs and a second
instance with `alb_log_type = "ALB_CONNECTION_LOGS"` and another
`name_prefix`. Do not send both log types through one instance: Fencer
rejects a record of the other type and records an ingestion error.

The delivery writes only to a stream with the tag `LogDeliveryEnabled = true`.
The module adds that tag to the stream when `alb_load_balancers` is set,
so Terraform never removes it.

The principal that runs Terraform needs the CloudWatch Logs delivery
permissions (`logs:PutDeliverySource`, `logs:PutDeliveryDestination`,
`logs:CreateDelivery`, their `Get`, `Describe`, `Delete` and
`logs:UpdateDeliveryConfiguration` counterparts), `firehose:TagDeliveryStream`,
`iam:CreateServiceLinkedRole` for the first log delivery to Firehose in the
account, and `elasticloadbalancing:AllowVendedLogDeliveryForResource` on the
load balancers. `PutDeliverySource` checks that last action on the load
balancer ARN and fails with an access error without it. The module needs
provider `hashicorp/aws` 6.56.0 or newer.

AWS allows one vended log delivery source per load balancer and log type. A
load balancer that already sends the same log type somewhere through a log
delivery cannot send it to Fencer as well.

If you created the delivery with the AWS CLI commands from the Fencer app
before this module version, delete that delivery first
(`aws logs delete-delivery --id <id>`). The module adopts a delivery source
and a delivery destination with the same names, but `CreateDelivery` for a
source and destination that already have a delivery fails.

See [`examples/alb-access-logs`](./examples/alb-access-logs) and
[`examples/alb-connection-logs`](./examples/alb-connection-logs), or
[`examples/alb-logs`](./examples/alb-logs) for both log types in one
configuration.

### Breaking changes in 1.3

`cloudwatch_log_group_names` and `vpc_flow_log_vpc_ids` are gone. Pass
`cloudwatch_log_groups` and `vpc_flow_logs`, maps of a key of your choice to
the log group name or the VPC ID. The key is the Terraform instance key. In
1.2 the instance key was the value itself, so keep the value as the key to
upgrade without a replacement, for example
`cloudwatch_log_groups = { "aws-cloudtrail-logs-example" = "aws-cloudtrail-logs-example" }`.
A new key such as `cloudtrail` destroys and recreates the subscription filter
or the flow log, and events in that gap never reach Fencer. `flow_log_ids` is
keyed by the map key.

### What gets created

- An Amazon Data Firehose delivery stream with an HTTP endpoint destination:
  Fencer's URL, your Fencer access token, GZIP content encoding, 1 MiB / 60 s
  buffering.
- An S3 bucket that stores failed deliveries only. Public access blocked, versioning on, HTTP denied.
  Objects expire after 30 days.
- A CloudWatch Logs log group `/aws/kinesisfirehose/<name_prefix>` for
  Firehose error logs (7-day retention).
- An IAM role Firehose assumes to write to the bucket and the log group.
- When `cloudwatch_log_groups` is set: an IAM role CloudWatch Logs
  assumes, and one subscription filter per log group (empty filter pattern =
  all events).
- When `vpc_flow_logs` is set: one VPC flow log per VPC. Each flow log
  delivers to the Firehose stream.
- When `alb_load_balancers` is set: one CloudWatch log delivery
  destination (the stream, JSON output), one delivery source and one delivery
  per load balancer, and the `LogDeliveryEnabled = true` tag on the stream.

### Other data source types

The AWS delivery mechanism decides the setup:

| Data source | Setup |
|---|---|
| CloudTrail | This module. Pass the trail's log group. |
| VPC flow logs | This module. Pass the VPCs. |
| RDS PostgreSQL logs, Route 53 resolver query logs | Not supported yet. |
| ALB access logs, ALB connection logs | This module. Pass the log type and the load balancers. One instance per log type. |
| ALB health check logs | Not supported. Fencer has no data source type for them. |
| NLB access logs, S3 access logs | Not supported by this module yet. Use the batch setup in the Fencer app. |

### Examples

Each example is a complete configuration with its own README (pre-checks,
apply, verify, clean up):

| Example | Scenario |
|---|---|
| [`examples/cloudtrail`](./examples/cloudtrail) | Existing trail that already delivers to CloudWatch Logs. |
| [`examples/cloudtrail-new-trail`](./examples/cloudtrail-new-trail) | No trail yet — creates the trail, its S3 bucket, the log group, and the stream. |
| [`examples/vpc-flow-logs`](./examples/vpc-flow-logs) | VPC flow logs that deliver straight to the stream. |
| [`examples/alb-access-logs`](./examples/alb-access-logs) | ALB access logs through a CloudWatch log delivery to the stream. |
| [`examples/alb-connection-logs`](./examples/alb-connection-logs) | ALB connection logs through a CloudWatch log delivery to the stream. |
| [`examples/alb-logs`](./examples/alb-logs) | Both ALB log types from one configuration: two instances, two Fencer data sources. |

### Verify

After `terraform apply`, the Firehose monitoring tab shows successful HTTP
endpoint deliveries (2xx) within ~5 minutes, and the backup bucket stays
empty. Events appear in Fencer (Hunts).

### Use from Pulumi

Pulumi consumes this module directly — no rewrite:

```bash
pulumi package add terraform-module Fencer-Security/fencer-monitor/aws 1.3.0 fencermonitor
```

```ts
import * as fencermonitor from "@pulumi/fencermonitor";

const monitor = new fencermonitor.Module("fencer-monitor", {
  fencer_endpoint_url: "https://ingest.fencer.dev/v1/firehose/replace-me",
  fencer_access_key: config.requireSecret("fencerAccessKey"),
  cloudwatch_log_groups: { cloudtrail: "aws-cloudtrail-logs-example" },
});
```

### Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `fencer_endpoint_url` | `string` | — | Fencer Firehose HTTP endpoint URL (from the Fencer app). |
| `fencer_access_key` | `string` | — | Fencer access token (from the Fencer app). Sensitive. |
| `cloudwatch_log_groups` | `map(string)` | `{}` | Log groups to subscribe to the stream: a key of your choice to the log group name. Unique, non-empty names. |
| `name_prefix` | `string` | required | Prefix for all resource names. `^[a-z0-9][a-z0-9-]*$`, max 29 chars. Each module instance in an AWS account needs a different one. |
| `vpc_flow_logs` | `map(string)` | `{}` | VPCs to publish flow logs from: a key of your choice to the VPC ID. One flow log per VPC. Unique, non-empty IDs. |
| `vpc_flow_log_format` | `string` | AWS version 10 field set (42 fields) | Flow log format. Fencer accepts the full field set of any version (2 to 11). Any other field set needs a custom Fencer transformation. |
| `vpc_flow_log_traffic_type` | `string` | `"ALL"` | Traffic to log: `ACCEPT`, `REJECT`, or `ALL`. |
| `vpc_flow_log_max_aggregation_interval` | `number` | `60` | Seconds AWS aggregates records before it publishes them: `60` or `600`. |
| `alb_log_type` | `string` | `null` | `ALB_ACCESS_LOGS` or `ALB_CONNECTION_LOGS`. Required when `alb_load_balancers` is set. One instance delivers one log type. A change replaces every delivery source and delivery. |
| `alb_load_balancers` | `map(string)` | `{}` | Application Load Balancers to deliver logs from: a key of your choice (`^[a-z0-9][a-z0-9-]*$`, it names the delivery source `<name_prefix>-<key>`) to the load balancer ARN. One log delivery per load balancer. Unique ARNs. |
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
| `flow_log_ids` | Map of `vpc_flow_logs` key to flow log ID. Empty when no VPCs. |
| `alb_log_delivery_destination_arn` | Log delivery destination ARN, `null` when no load balancers. |
| `alb_log_delivery_ids` | Map of `alb_load_balancers` key to log delivery ID. Empty when no load balancers. |

### License

MIT — see [LICENSE](./LICENSE).
