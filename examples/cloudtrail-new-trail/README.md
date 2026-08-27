# CloudTrail → Fencer (new trail)

Creates a CloudTrail trail from scratch and streams it to Fencer: the S3
bucket that keeps the trail history, the CloudWatch Logs log group that
transports events, the trail, and the Fencer monitor module.

Already have a trail? Use [`../cloudtrail`](../cloudtrail) instead — it only
attaches a subscription filter.

AWS billing note: the first copy of management events per account is free.
If another trail already records management events, this trail is a second
copy and AWS bills it.

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."   # from the Fencer app
export TF_VAR_fencer_access_key="..."             # from the Fencer app

terraform init
terraform plan
terraform apply
```

## Verify

The trail records management events immediately. Firehose buffers up to
60 s.

```sh
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

The trail's S3 bucket and the backup bucket must be empty before destroy
succeeds:

```sh
aws s3 rm "s3://$(terraform output -raw backup_bucket)" --recursive
```
