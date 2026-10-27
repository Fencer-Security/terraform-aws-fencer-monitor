# Route 53 Resolver query logs → Fencer

Publishes Route 53 Resolver query logs straight to a Fencer Firehose stream.
The module creates one query logging configuration and one association per
VPC. It does not change the VPCs.

Run this in the same AWS account and region as the VPCs. A query logging
configuration cannot deliver to a Firehose stream in another region, and it
logs only the VPCs of its own region.

Resolver logs only queries that it cannot answer from its cache. A VPC can have
one query logging configuration per destination type, so a VPC that already
logs to a Firehose stream cannot log to this stream as well.

## Before you apply

Create the Fencer data source with the type AWS Route53 DNS Query Logs and
generate its access token.

Check that the principal that runs Terraform has these IAM permissions:

- `route53resolver:CreateResolverQueryLogConfig`, `route53resolver:DeleteResolverQueryLogConfig`
- `route53resolver:AssociateResolverQueryLogConfig`, `route53resolver:DisassociateResolverQueryLogConfig`
- `route53resolver:GetResolverQueryLogConfig`, `route53resolver:GetResolverQueryLogConfigAssociation`
- `route53resolver:ListResolverQueryLogConfigs`, `route53resolver:ListResolverQueryLogConfigAssociations`
- `route53resolver:TagResource`, `route53resolver:UntagResource`, `route53resolver:ListTagsForResource`
- `logs:CreateLogDelivery`, `logs:DeleteLogDelivery`
- `firehose:TagDeliveryStream`
- `iam:CreateServiceLinkedRole`

Find the VPC IDs:

```sh
aws ec2 describe-vpcs --query 'Vpcs[].VpcId'
```

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_vpcs='{"main":"vpc-0123456789abcdef0"}'
# The first association in an account makes AWS create the service-linked role
# AWSServiceRoleForRoute53Resolver. That first apply can fail. Apply again.

terraform init
terraform plan    # only new fencer-route53-resolver* resources plus one association per VPC
terraform apply
```

## Verify

Query logs need DNS queries from the VPC. AWS delivers the first records within
a few minutes. Firehose buffers for up to 60 s.

```sh
aws route53resolver get-resolver-query-log-config \
  --resolver-query-log-config-id "$(terraform output -raw query_log_config_id)" \
  --query 'ResolverQueryLogConfig.[Status,DestinationArn,AssociationCount]'

aws route53resolver list-resolver-query-log-config-associations \
  --filters Name=ResourceId,Values=<your-vpc-id> \
  --query 'ResolverQueryLogConfigAssociations[].[ResolverQueryLogConfigId,Status,Error]'

aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_delivery_stream_name)" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Failed deliveries — must stay empty
aws s3 ls "s3://$(terraform output -raw backup_bucket)" --recursive
```

The configuration `Status` must be `CREATED` and the association `Status` must
be `ACTIVE`. Events appear in the Fencer app (Hunts) within a few minutes.

## Clean up

```sh
terraform destroy
```

This removes the query logging configuration, the associations and the Fencer
resources only. If the backup bucket holds objects, empty it first. The bucket
is versioned, so delete every object version and delete marker, or
`terraform destroy` fails with `BucketNotEmpty`:

```sh
for B in "$(terraform output -raw backup_bucket)"; do
  aws s3api delete-objects --bucket "$B" --delete "$(aws s3api list-object-versions --bucket "$B" --output json \
    --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][]}')"
done
```
