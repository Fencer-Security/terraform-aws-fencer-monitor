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
  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
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

  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
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
stream and the log group take their names from it. On one log group the collision is silent:
`PutSubscriptionFilter` creates or updates a filter by name, so a second instance with the same
`name_prefix` takes over the filter of the first, and the first stream stops receiving events.

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

  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
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

### Connect NLB access logs

Deploy the module in the same AWS account and region as the load balancers.
A Network Load Balancer delivers its access logs through a CloudWatch log
delivery (vended logs), straight to the Firehose stream, as JSON. Pass the
load balancers as a map of a key of your choice to the load balancer ARN. The
key names the delivery source (`<name_prefix>-<key>`) and is its Terraform
instance key, so a load balancer created in the same apply works:

```hcl
module "fencer_nlb_access_logs" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.4"

  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
  fencer_access_key   = var.fencer_nlb_access_logs_access_key
  name_prefix         = "fencer-nlb-access-logs"

  nlb_load_balancers = { my-nlb = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/50dc6c495c0c9188" }
}
```

The module creates one delivery destination that points at the stream, and
one delivery source plus one delivery per load balancer. One module instance
sends data to one Fencer data source, of type AWS NLB Access Logs. A Network
Load Balancer writes access log entries only for TLS listeners.

The delivery writes only to a stream with the tag `LogDeliveryEnabled = true`.
The module adds that tag to the stream when `nlb_load_balancers` is set,
so Terraform never removes it.

The principal that runs Terraform needs the same permissions as for ALB logs,
including `elasticloadbalancing:AllowVendedLogDeliveryForResource` on the
load balancers. The module needs provider `hashicorp/aws` 6.56.0 or newer.

AWS allows one vended log delivery source per load balancer and log type. A
load balancer that already sends access logs somewhere through a log delivery
cannot send them to Fencer as well.

If you created the delivery with the AWS CLI commands from the Fencer app,
delete that delivery first (`aws logs delete-delivery --id <id>`). The module
adopts a delivery source and a delivery destination with the same names, but
`CreateDelivery` for a source and destination that already have a delivery
fails.

See [`examples/nlb-access-logs`](./examples/nlb-access-logs).

### Connect S3 server access logs

Deploy the module in the same AWS account and region as the buckets. An S3
bucket delivers its server access logs through a CloudWatch log delivery
(vended logs), straight to the Firehose stream, as JSON. Pass the buckets as a
map of a key of your choice to the bucket ARN. The key names the delivery
source (`<name_prefix>-<key>`) and is its Terraform instance key, so a bucket
created in the same apply works:

```hcl
module "fencer_s3_access_logs" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.5"

  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
  fencer_access_key   = var.fencer_s3_access_logs_access_key
  name_prefix         = "fencer-s3-access-logs"

  s3_buckets = { my-bucket = "arn:aws:s3:::my-bucket" }
}
```

The module creates one delivery destination that points at the stream, and
one delivery source plus one delivery per bucket. One module instance sends
data to one Fencer data source, of type AWS S3 Bucket Access Logs. AWS
supports general purpose buckets only. The only output format is JSON.

AWS takes 15 to 20 minutes to apply the delivery. Delivery then begins within a few hours and includes new requests only.

The delivery writes only to a stream with the tag `LogDeliveryEnabled = true`.
The module adds that tag to the stream when `s3_buckets` is set, so Terraform
never removes it.

The principal that runs Terraform needs the same permissions as for ALB logs,
except that the resource-side permission is `s3:AllowVendedLogDeliveryForResource`
on the buckets. The module needs provider `hashicorp/aws` 6.56.0 or newer.

AWS allows one vended log delivery source per bucket and log type. A bucket
that already sends server access logs somewhere through a log delivery cannot
send them to Fencer as well.

If you created the delivery with the AWS CLI commands from the Fencer app,
delete that delivery first (`aws logs delete-delivery --id <id>`). The module
adopts a delivery source and a delivery destination with the same names, but
`CreateDelivery` for a source and destination that already have a delivery
fails.

See [`examples/s3-access-logs`](./examples/s3-access-logs).

### Connect RDS PostgreSQL logs

Deploy the module in the same AWS account and region as the database. An RDS
for PostgreSQL instance publishes its PostgreSQL log to a CloudWatch Logs log
group. The module subscribes that log group to the stream, as for CloudTrail.
Subscription filters cannot cross accounts.

1. Enable the PostgreSQL log export on the instance. In the RDS console, choose
   Modify → Log exports → PostgreSQL. With the AWS CLI:

   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier my-db \
     --cloudwatch-logs-export-configuration '{"EnableLogTypes":["postgresql"]}'
   ```

   With Terraform, add `enabled_cloudwatch_logs_exports = ["postgresql"]` to
   the `aws_db_instance` resource.

   For an Aurora PostgreSQL cluster, the export is a cluster setting. Run
   `aws rds modify-db-cluster --db-cluster-identifier <cluster>
   --cloudwatch-logs-export-configuration '{"EnableLogTypes":["postgresql"]}'`,
   or set `enabled_cloudwatch_logs_exports = ["postgresql"]` on the
   `aws_rds_cluster` resource.

2. Pass the log group name. For an instance it is
   `/aws/rds/instance/<identifier>/postgresql`. For an Aurora PostgreSQL
   cluster it is `/aws/rds/cluster/<cluster>/postgresql`:

   ```hcl
   module "fencer_rds_postgres_logs" {
     source  = "Fencer-Security/fencer-monitor/aws"
     version = "~> 1.4"

     fencer_endpoint_url = "https://ingest.fencer.dev/v1/firehose/replace-me"
     fencer_access_key   = var.fencer_rds_postgres_logs_access_key
     name_prefix         = "fencer-rds-postgres"

     cloudwatch_log_groups = { main = "/aws/rds/instance/my-db/postgresql" }
   }
   ```

   Pass one entry per instance to send several instances to the same Fencer
   data source. The data source has the type AWS RDS PostgreSQL Std Logs.

3. Set the parameters that produce useful lines in the instance's parameter
   group. `log_connections` and `log_disconnections` write the connection
   events. `log_statement = ddl` writes schema changes. The `pgaudit` extension
   writes statements in a structured form. It needs
   `shared_preload_libraries = pgaudit`, a static parameter that takes effect
   after a reboot. Set `pgaudit.log`, for example `pgaudit.log = 'ddl, role'`,
   and run `CREATE EXTENSION pgaudit` in the database. Without both, pgAudit
   logs nothing. `log_statement` writes statement text verbatim, passwords
   included (`CREATE ROLE ... PASSWORD`). Current pgAudit versions redact the
   password in `CREATE ROLE` and `ALTER ROLE`, so prefer pgAudit, and check
   what your statements hold before you enable `log_statement`.

Only new log lines reach Fencer. RDS does not upload log lines it wrote before
you enabled the export, and a subscription filter does not send older events.

The log group exists only after the export is active and the instance has
written its first line. If `terraform apply` fails with
`ResourceNotFoundException` on the subscription filter, wait a few minutes and
run it again.

A log group supports at most 5 subscription filters (AWS quota, not
adjustable). If the log group already feeds other destinations, check
`aws logs describe-subscription-filters` before you apply.

See [`examples/rds-postgresql-logs`](./examples/rds-postgresql-logs).

### Connect Route 53 Resolver query logs

Deploy the module in the same AWS account and region as the VPCs. A Resolver
query logging configuration delivers straight to the Firehose stream, so it
needs no IAM role and no log group. Pass the VPCs as a map of a key of your
choice to the VPC ID:

```hcl
module "fencer_route53_resolver_logs" {
  source  = "Fencer-Security/fencer-monitor/aws"
  version = "~> 1.6"

  fencer_endpoint_url = var.fencer_endpoint_url # from the Fencer app, ends in /firehose
  fencer_access_key   = var.fencer_route53_resolver_logs_access_key
  name_prefix         = "fencer-route53-resolver"

  route53_resolver_vpcs = { main = "vpc-0123456789abcdef0" }
}
```

The module creates one query logging configuration, named `name_prefix`, with
the stream as its destination, and one association per VPC. One module instance
sends data to one Fencer data source, of type AWS Route53 DNS Query Logs. The
module refuses VPCs and any other source input together.

A query logging configuration logs only the VPCs of its own region and
delivers only to a stream in that region. Resolver logs only queries that it
cannot answer from its cache. A VPC can have one query logging configuration per
destination type, so a VPC that already logs to a Firehose stream cannot log to
this stream as well. AWS allows 20 configurations and 100 VPC associations per
region.

The delivery writes only to a stream with the tag `LogDeliveryEnabled = true`.
The module adds that tag to the stream when `route53_resolver_vpcs` or
`route53_resolver_profiles` is set, so Terraform never removes it.

The principal that runs Terraform needs these IAM permissions:
`route53resolver:CreateResolverQueryLogConfig`,
`route53resolver:DeleteResolverQueryLogConfig`,
`route53resolver:AssociateResolverQueryLogConfig`,
`route53resolver:DisassociateResolverQueryLogConfig`,
`route53resolver:GetResolverQueryLogConfig`,
`route53resolver:GetResolverQueryLogConfigAssociation`,
`route53resolver:ListResolverQueryLogConfigs`,
`route53resolver:ListResolverQueryLogConfigAssociations`,
`route53resolver:TagResource`, `route53resolver:UntagResource`,
`route53resolver:ListTagsForResource`,
`logs:CreateLogDelivery`, `logs:DeleteLogDelivery`,
`firehose:TagDeliveryStream`, and `iam:CreateServiceLinkedRole`.

Two service-linked roles take part. The first association in an AWS account
makes AWS create `AWSServiceRoleForRoute53Resolver`, which sets up the log
delivery. That first `terraform apply` can fail. Run `terraform apply` again; the
role exists from then on. The delivery itself runs through
`AWSServiceRoleForLogDelivery`, which writes only to a stream with the tag
`LogDeliveryEnabled = true`. The module manages neither role: they belong to the
account, not to one instance.

The configuration takes its name from `name_prefix`. AWS rejects a name of
digits only, so `name_prefix` must contain a letter or a hyphen.

AWS delivers the first records within a few minutes after the association is
active.

A `name_prefix` change replaces the query logging configuration and every
association. Resolver logging stops for the gap, the same way a flow log is
replaced.

#### Use a Route 53 Profile

To log many VPCs, or VPCs that a Profile shares with other accounts, attach the
configuration to a Route 53 Profile. Pass the Profiles as a map of a key of your
choice to the Profile ID. The key names the association (`<name_prefix>-<key>`):

```hcl
  route53_resolver_profiles = { main = "rp-0123456789abcdef" }
```

Every VPC that is associated with the Profile is logged. Its records carry the
Profile ID (`resource_id`) instead of the VPC ID (`vpc_id`). A Profile holds at
most two query logging configurations. `route53_resolver_vpcs` and
`route53_resolver_profiles` can be set together: both use the same
configuration. For a Profile the principal also needs
`route53profiles:AssociateResourceToProfile`,
`route53profiles:DisassociateResourceFromProfile`, and
`route53profiles:GetProfileResourceAssociation`.

See [`examples/route53-resolver-logs`](./examples/route53-resolver-logs) and
[`examples/route53-resolver-logs-profile`](./examples/route53-resolver-logs-profile).

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
- When `nlb_load_balancers` is set: the same set of resources as for
  `alb_load_balancers`, with the log type `NLB_ACCESS_LOGS`.
- When `s3_buckets` is set: the same set of resources as for
  `alb_load_balancers`, with the log type `S3_SERVER_ACCESS_LOGS`.
- When `route53_resolver_vpcs` or `route53_resolver_profiles` is set: one Route 53
  Resolver query logging configuration that delivers to the Firehose stream, one
  association per VPC, one association per Profile, and the
  `LogDeliveryEnabled = true` tag on the stream.

### Other data source types

The AWS delivery mechanism decides the setup:

| Data source | Setup |
|---|---|
| CloudTrail | This module. Pass the trail's log group. |
| VPC flow logs | This module. Pass the VPCs. |
| RDS PostgreSQL logs | This module. Pass the instance's log group. |
| ALB access logs, ALB connection logs | This module. Pass the log type and the load balancers. One instance per log type. |
| ALB health check logs | Not supported. Fencer has no data source type for them. |
| NLB access logs | This module. Pass the load balancer ARNs. |
| S3 access logs | This module. Pass the bucket ARNs. |
| Route 53 Resolver query logs | This module. Pass the VPCs or the Profiles. |

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
| [`examples/nlb-access-logs`](./examples/nlb-access-logs) | NLB access logs through a CloudWatch log delivery to the stream. |
| [`examples/s3-access-logs`](./examples/s3-access-logs) | S3 server access logs through a CloudWatch log delivery to the stream. |
| [`examples/rds-postgresql-logs`](./examples/rds-postgresql-logs) | RDS PostgreSQL logs that an instance publishes to CloudWatch Logs. |
| [`examples/route53-resolver-logs`](./examples/route53-resolver-logs) | Route 53 Resolver query logs of VPCs that deliver straight to the stream. |
| [`examples/route53-resolver-logs-profile`](./examples/route53-resolver-logs-profile) | Route 53 Resolver query logs of a Route 53 Profile that deliver straight to the stream. |

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
  fencer_endpoint_url: config.require("fencerEndpointUrl"), // from the Fencer app, ends in /firehose
  fencer_access_key: config.requireSecret("fencerAccessKey"),
  cloudwatch_log_groups: { cloudtrail: "aws-cloudtrail-logs-example" },
});
```

### Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `fencer_endpoint_url` | `string` | — | Fencer Firehose HTTP endpoint URL, copied from the Fencer app. It ends in `/firehose` and is the same for every data source: the access token identifies the data source. |
| `fencer_access_key` | `string` | — | Fencer access token (from the Fencer app). Sensitive. |
| `cloudwatch_log_groups` | `map(string)` | `{}` | Log groups to subscribe to the stream: a key of your choice to the log group name. Unique, non-empty names. |
| `name_prefix` | `string` | required | Prefix for all resource names. `^[a-z0-9][a-z0-9-]*$`, max 29 chars. Each module instance in an AWS account needs a different one. |
| `vpc_flow_logs` | `map(string)` | `{}` | VPCs to publish flow logs from: a key of your choice to the VPC ID. One flow log per VPC. Unique, non-empty IDs. |
| `vpc_flow_log_format` | `string` | AWS version 10 field set (42 fields) | Flow log format. Fencer accepts the full field set of any version (2 to 11). Any other field set needs a custom Fencer transformation. |
| `vpc_flow_log_traffic_type` | `string` | `"ALL"` | Traffic to log: `ACCEPT`, `REJECT`, or `ALL`. |
| `vpc_flow_log_max_aggregation_interval` | `number` | `60` | Seconds AWS aggregates records before it publishes them: `60` or `600`. |
| `alb_log_type` | `string` | `null` | `ALB_ACCESS_LOGS` or `ALB_CONNECTION_LOGS`. Required when `alb_load_balancers` is set. One instance delivers one log type. A change replaces every delivery source and delivery. |
| `alb_load_balancers` | `map(string)` | `{}` | Application Load Balancers to deliver logs from: a key of your choice (`^[a-z0-9][a-z0-9-]*$`, it names the delivery source `<name_prefix>-<key>`) to the load balancer ARN. One log delivery per load balancer. Unique ARNs. An ARN change under the same key replaces that delivery source and delivery. |
| `nlb_load_balancers` | `map(string)` | `{}` | Network Load Balancers to deliver access logs from: a key of your choice (`^[a-z0-9][a-z0-9-]*$`, it names the delivery source `<name_prefix>-<key>`) to the load balancer ARN. One log delivery per load balancer. Unique ARNs. An ARN change under the same key replaces that delivery source and delivery. Entries only for TLS listeners. |
| `s3_buckets` | `map(string)` | `{}` | General purpose S3 buckets to deliver server access logs from: a key of your choice (`^[a-z0-9][a-z0-9-]*$`, it names the delivery source `<name_prefix>-<key>`) to the bucket ARN. One log delivery per bucket. Unique bucket ARNs, not names and not object ARNs. An ARN change under the same key replaces that delivery source and delivery. AWS takes 15 to 20 minutes to apply the delivery. Delivery then begins within a few hours and includes new requests only. |
| `route53_resolver_vpcs` | `map(string)` | `{}` | VPCs whose Route 53 Resolver queries to log: a key of your choice to the VPC ID. One association per VPC. Unique, non-empty IDs. Same account and region as the stream. A VPC can have one query logging configuration per destination type. A VPC ID change under the same key replaces that association. A key change changes nothing in AWS. |
| `route53_resolver_profiles` | `map(string)` | `{}` | Route 53 Profiles to attach the query logging configuration to: a key of your choice (it names the association `<name_prefix>-<key>`) to the Profile ID. One association per Profile. Unique, non-empty IDs. The key matches `^[a-z0-9][a-z0-9-]*$`, and `<name_prefix>-<key>` has at most 64 characters. A Profile holds at most two query logging configurations. Records carry the Profile ID instead of the VPC ID. A Profile ID change under the same key replaces that association. A key change renames the association: AWS removes the old one before it creates the new one. |
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
| `nlb_log_delivery_destination_arn` | Log delivery destination ARN, `null` when no load balancers. |
| `nlb_log_delivery_ids` | Map of `nlb_load_balancers` key to log delivery ID. Empty when no load balancers. |
| `s3_log_delivery_destination_arn` | Log delivery destination ARN, `null` when no buckets. |
| `s3_log_delivery_ids` | Map of `s3_buckets` key to log delivery ID. Empty when no buckets. |
| `route53_resolver_query_log_config_id` | Query logging configuration ID, `null` when no VPCs and no Profiles. |
| `route53_resolver_query_log_config_association_ids` | Map of `route53_resolver_vpcs` key to association ID. Empty when no VPCs. |
| `route53_resolver_profile_association_ids` | Map of `route53_resolver_profiles` key to Profile association ID. Empty when no Profiles. |

### License

MIT — see [LICENSE](./LICENSE).
