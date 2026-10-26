# Route 53 Resolver query logs of a Profile → Fencer

Publishes the Route 53 Resolver query logs of a Route 53 Profile straight to a
Fencer Firehose stream. The module creates one query logging configuration and
attaches it to the Profile. Every VPC that is associated with the Profile is
logged. The module does not change the Profile or its VPCs.

Use a Profile when you log many VPCs, or when the Profile is shared with other
accounts. To log single VPCs, use [`examples/route53-resolver-logs`](../route53-resolver-logs).

Run this in the same AWS account and region as the Profile. A query logging
configuration cannot deliver to a Firehose stream in another region.

Records of a Profile carry the Profile ID (`resource_id`) instead of the VPC ID
(`vpc_id`). A Profile holds at most two query logging configurations. If the
Profile already has two, remove one before you apply.

Resolver logs only queries that it cannot answer from its cache.

## Before you apply

Create the Fencer data source with the type AWS Route53 DNS Query Logs and
generate its access token.

Check that the principal that runs Terraform has these IAM permissions:

- `route53resolver:CreateResolverQueryLogConfig`, `route53resolver:DeleteResolverQueryLogConfig`
- `route53resolver:GetResolverQueryLogConfig`, `route53resolver:ListResolverQueryLogConfigs`
- `route53resolver:TagResource`, `route53resolver:UntagResource`, `route53resolver:ListTagsForResource`
- `route53profiles:AssociateResourceToProfile`, `route53profiles:DisassociateResourceFromProfile`
- `route53profiles:GetProfileResourceAssociation`
- `logs:CreateLogDelivery`, `logs:DeleteLogDelivery`
- `firehose:TagDeliveryStream`
- `iam:CreateServiceLinkedRole`

Find the Profile ID:

```sh
aws route53profiles list-profiles --query 'ProfileSummaries[].[Id,Name]'
```

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_profile_id="rp-0123456789abcdef"
# The first association in an account makes AWS create the service-linked role
# AWSServiceRoleForRoute53Resolver. That first apply can fail. Apply again.

terraform init
terraform plan    # only new fencer-route53-resolver* resources plus one Profile association
terraform apply
```

## Verify

Query logs need DNS queries from a VPC that is associated with the Profile. AWS
delivers the first records within a few minutes. Firehose buffers for up to 60 s.

```sh
aws route53resolver get-resolver-query-log-config \
  --resolver-query-log-config-id "$(terraform output -raw query_log_config_id)" \
  --query 'ResolverQueryLogConfig.[Status,DestinationArn]'

aws route53profiles list-profile-resource-associations \
  --profile-id "$TF_VAR_profile_id" \
  --query 'ProfileResourceAssociations[].[Name,ResourceType,Status]'

aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_delivery_stream_name)" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Failed deliveries — must stay empty
aws s3 ls "s3://$(terraform output -raw backup_bucket)" --recursive
```

The configuration `Status` must be `CREATED`. Events appear in the Fencer app
(Hunts) within a few minutes.

## Clean up

```sh
terraform destroy
```

This removes the query logging configuration, the Profile association and the
Fencer resources only. If the backup bucket holds objects, empty it first. The
bucket is versioned, so delete every object version and delete marker, or
`terraform destroy` fails with `BucketNotEmpty`:

```sh
for B in "$(terraform output -raw backup_bucket)"; do
  aws s3api delete-objects --bucket "$B" --delete "$(aws s3api list-object-versions --bucket "$B" --output json \
    --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][]}')"
done
```
