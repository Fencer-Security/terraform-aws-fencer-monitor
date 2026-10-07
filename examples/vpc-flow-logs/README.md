# VPC flow logs → Fencer

Publishes VPC flow logs straight to a Fencer Firehose stream. The module
creates one flow log per VPC. It does not change the VPCs.

Run this in the same AWS account and region as the VPCs. A flow log cannot
deliver to a Firehose stream in another region.

## Before you apply

Check that the principal that runs Terraform has these IAM permissions:

- `logs:CreateLogDelivery`
- `logs:DeleteLogDelivery`
- `iam:CreateServiceLinkedRole`
- `firehose:TagDeliveryStream`

The default version 10 format (42 fields) includes ECS fields. For those fields, the principal also
needs these permissions:

- `ecs:ListClusters`
- `ecs:ListContainerInstances`
- `ecs:ListServices`
- `ecs:ListTaskDefinitions`
- `ecs:ListTasks`

Find the VPC IDs:

```sh
aws ec2 describe-vpcs --query 'Vpcs[].VpcId'
```

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_vpc_ids='["vpc-0123456789abcdef0"]'
export TF_VAR_flow_log_version=10                    # optional: 2, 3, 4, 5, 7, 8, 9, 10 or 11, see formats.tf
# Version 11 only: the tag keys to publish, by resource type.
# export TF_VAR_tag_field_specifications='[{"resource_type":"instance","tag_keys":["Name"]}]'
# The first apply with tag fields in an account can fail with "FlowLogs Service Linked Role is
# not yet available" while AWS creates AWSServiceRoleForVPCFlowLogs. Apply again.

terraform init
terraform plan    # only new fencer-siem* resources plus one flow log per VPC
terraform apply
```

## Verify

Flow log records need traffic in the VPC. AWS aggregates records for up to
60 s. Firehose buffers for up to 60 s more.

```sh
aws ec2 describe-flow-logs \
  --filter Name=resource-id,Values=<your-vpc-id> \
  --query 'FlowLogs[].[FlowLogId,FlowLogStatus,DeliverLogsStatus,LogDestinationType]'

aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_delivery_stream_name)" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Failed deliveries — must stay empty
aws s3 ls "s3://$(terraform output -raw backup_bucket)" --recursive
```

`FlowLogStatus` must be `ACTIVE` and `LogDestinationType` must be
`kinesis-data-firehose`. Events appear in the Fencer app (Hunts) within a few
minutes.

## Clean up

```sh
terraform destroy
```

This removes the flow logs and the Fencer resources only. If the backup
bucket holds objects, empty it first:

```sh
aws s3 rm "s3://$(terraform output -raw backup_bucket)" --recursive
```
