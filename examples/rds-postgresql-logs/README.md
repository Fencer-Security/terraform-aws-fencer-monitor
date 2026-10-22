# RDS PostgreSQL logs → Fencer

Subscribes the PostgreSQL log of an RDS for PostgreSQL instance to a Fencer
Firehose stream. The instance publishes the log to a CloudWatch Logs log group.
The module adds one subscription filter on that log group. It does not change
the instance or the log group.

Run this in the same AWS account and region as the instance. An Aurora
PostgreSQL cluster uses the log group `/aws/rds/cluster/<cluster>/postgresql`.
For a cluster, replace the `cloudwatch_log_groups` value in `main.tf` with the
cluster log group name, and remove the `aws_db_instance` data source and the
`db_instance_identifier` variable. Also remove `TF_VAR_db_instance_identifier`
from the apply step.

## Before you apply

Create the Fencer data source with the type AWS RDS PostgreSQL Std Logs and
generate its access token.

Enable the PostgreSQL log export on the instance: RDS console → your instance →
Modify → Log exports → PostgreSQL. Or:

```sh
aws rds modify-db-instance \
  --db-instance-identifier <your-instance> \
  --cloudwatch-logs-export-configuration '{"EnableLogTypes":["postgresql"]}'
```

For an Aurora cluster, the export is a cluster setting. Run
`aws rds modify-db-cluster --db-cluster-identifier <cluster>
--cloudwatch-logs-export-configuration '{"EnableLogTypes":["postgresql"]}'`,
or set `enabled_cloudwatch_logs_exports = ["postgresql"]` on the
`aws_rds_cluster` resource.

Only new log lines reach Fencer. RDS does not upload log lines it wrote before
you enabled the export, and a subscription filter does not send older events.

Set these parameters in the instance's parameter group, so that the log holds
useful lines:

- `log_connections` and `log_disconnections` write the connection events.
- `log_statement = ddl` writes schema changes verbatim, passwords included
  (`CREATE ROLE ... PASSWORD`). Check what the statements can hold before you
  enable it. The `pgaudit` extension is the alternative for statement logging,
  and current versions redact the password in `CREATE ROLE` and `ALTER ROLE`.
  It needs `shared_preload_libraries = pgaudit`, a static parameter that takes
  effect after a reboot. Also set `pgaudit.log`, for example
  `pgaudit.log = 'ddl, role'`, and run `CREATE EXTENSION pgaudit` in the
  database. Without both, pgAudit logs nothing.

Check the subscription filter slots (AWS quota: 5 per log group, not
adjustable):

```sh
aws logs describe-subscription-filters \
  --log-group-name /aws/rds/instance/<your-instance>/postgresql \
  --query 'subscriptionFilters[].filterName'
```

If 5 filters exist, the apply fails.

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_db_instance_identifier="<your-instance>"

terraform init
terraform plan    # only new fencer-rds-postgres* resources plus one subscription filter
terraform apply
```

The plan fails with the message "Enable the PostgreSQL log export on the
instance first" when the export is off.

The log group exists only after the export is active and the instance has
written its first line. If `terraform apply` fails with
`ResourceNotFoundException` on the subscription filter, wait a few minutes and
run it again.

## Verify

Connect to the database once. With `log_connections` on, the connection
produces log lines. Firehose buffers up to 60 s.

```sh
psql "host=<instance-endpoint> user=<user> dbname=<database>" -c 'select 1'

aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_delivery_stream_name)" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Failed deliveries — must stay empty
aws s3 ls "s3://$(terraform output -raw backup_bucket)" --recursive
```

Connection events appear in the Fencer app (Hunts) within a few minutes.

## Clean up

```sh
terraform destroy
```

This removes the subscription filter and the Fencer resources only. If the
backup bucket holds objects, empty it first. The bucket is versioned, so
delete every object version and delete marker, or `terraform destroy` fails
with `BucketNotEmpty`:

```sh
for B in "$(terraform output -raw backup_bucket)"; do
  aws s3api delete-objects --bucket "$B" --delete "$(aws s3api list-object-versions --bucket "$B" --output json \
    --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][]}')"
done
```
