# S3 server access logs → Fencer

Delivers S3 server access logs straight to a Fencer Firehose stream as JSON,
through a CloudWatch log delivery. The module creates one log delivery per
bucket. It does not change the buckets.

AWS takes 15 to 20 minutes to apply the delivery. Delivery then begins within a few hours and includes new requests only.
AWS supports general purpose buckets only.

Run this in the same AWS account and region as the buckets.

## Before you apply

Create the Fencer data source with the type AWS S3 Bucket Access Logs and generate
its access token.

Check that the principal that runs Terraform has these IAM permissions:

- `logs:PutDeliverySource`, `logs:GetDeliverySource`, `logs:DeleteDeliverySource`
- `logs:PutDeliveryDestination`, `logs:GetDeliveryDestination`, `logs:DeleteDeliveryDestination`
- `logs:CreateDelivery`, `logs:GetDelivery`, `logs:DeleteDelivery`, `logs:UpdateDeliveryConfiguration`
- `logs:DescribeDeliverySources`, `logs:DescribeDeliveryDestinations`, `logs:DescribeDeliveries`
- `firehose:TagDeliveryStream`
- `iam:CreateServiceLinkedRole` (the first log delivery to Firehose in the account creates `AWSServiceRoleForLogDelivery`)
- `s3:AllowVendedLogDeliveryForResource` on the buckets (AWS defines it for vended log delivery from a bucket)

The ARN of a bucket is `arn:aws:s3:::<bucket-name>`. Pass bucket ARNs, not
bucket names and not object ARNs.

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_buckets='{"my-bucket":"arn:aws:s3:::my-bucket"}'

terraform init
terraform plan    # only new fencer-s3-access-logs* resources plus one delivery per bucket
terraform apply
```

## Verify

Log records need new requests to the bucket. AWS takes 15 to 20 minutes to apply the delivery, and delivery then begins within a few hours. Firehose buffers for up to 60 s.

```sh
aws logs describe-deliveries \
  --query 'deliveries[].[id,deliverySourceName,deliveryDestinationType]'

aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_delivery_stream_name)" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Failed deliveries — must stay empty
aws s3 ls "s3://$(terraform output -raw backup_bucket)" --recursive
```

Events appear in the Fencer app (Hunts) within a few minutes.

## Clean up

```sh
terraform destroy
```

This removes the log deliveries and the Fencer resources only. If the backup
bucket holds objects, empty it first. The bucket is versioned, so
delete every object version and delete marker, or `terraform destroy` fails
with `BucketNotEmpty`:

```sh
for B in "$(terraform output -raw backup_bucket)"; do
  aws s3api delete-objects --bucket "$B" --delete "$(aws s3api list-object-versions --bucket "$B" --output json \
    --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][]}')"
done
```
