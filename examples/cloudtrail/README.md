# CloudTrail → Fencer (existing trail)

Subscribes an existing CloudTrail log group to a Fencer Firehose stream.
Use this when your trail already delivers to CloudWatch Logs. The module
does not change the trail or the log group. No trail yet? See
[`../cloudtrail-new-trail`](../cloudtrail-new-trail).

## Before you apply

Find your trail's log group name (CloudTrail console → your trail → detail
page), or:

```sh
aws cloudtrail get-trail --name my-trail \
  --query 'Trail.CloudWatchLogsLogGroupArn'
```

Check the subscription filter slots (AWS quota: 5 per log group, not
adjustable):

```sh
aws logs describe-subscription-filters \
  --log-group-name <your-log-group> \
  --query 'subscriptionFilters[].filterName'
```

If 5 filters exist, the apply fails.

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_cloudtrail_log_group_name="<your-log-group>"

terraform init
terraform plan    # only new fencer-siem* resources plus one subscription filter
terraform apply
```

## Verify

CloudTrail is live, so events flow without manual triggers. Firehose buffers
up to 60 s.

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

This removes the subscription filter and the Fencer resources only. If the
backup bucket holds objects, empty it first:

```sh
aws s3 rm "s3://$(terraform output -raw backup_bucket)" --recursive
```
