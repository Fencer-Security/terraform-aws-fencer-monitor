# ALB access logs and connection logs → Fencer

Delivers both Application Load Balancer log types straight to Fencer as JSON,
through CloudWatch log deliveries, from one configuration. The module creates
one log delivery per load balancer and log type. It does not change the load
balancers.

One module instance delivers one log type to one Fencer data source, so this
example has two instances. Each has its own Fencer data source, its own token,
its own Firehose stream and its own `name_prefix`. Both read the same
`load_balancers` map. For one log type only, see
[`examples/alb-access-logs`](../alb-access-logs) or
[`examples/alb-connection-logs`](../alb-connection-logs).

Run this in the same AWS account and region as the load balancers.

## Before you apply

Create two Fencer data sources, one with the type AWS ALB Access Logs and one
with the type AWS ALB Connection Logs, and generate an access token for each.

Check that the principal that runs Terraform has these IAM permissions:

- `logs:PutDeliverySource`, `logs:GetDeliverySource`, `logs:DeleteDeliverySource`
- `logs:PutDeliveryDestination`, `logs:GetDeliveryDestination`, `logs:DeleteDeliveryDestination`
- `logs:CreateDelivery`, `logs:GetDelivery`, `logs:DeleteDelivery`, `logs:UpdateDeliveryConfiguration`
- `logs:DescribeDeliverySources`, `logs:DescribeDeliveryDestinations`, `logs:DescribeDeliveries`
- `firehose:TagDeliveryStream`
- `iam:CreateServiceLinkedRole` (the first log delivery to Firehose in the account creates `AWSServiceRoleForLogDelivery`)
- `elasticloadbalancing:AllowVendedLogDeliveryForResource` on the load balancers (`PutDeliverySource` checks it on the load balancer ARN)

AWS allows one vended log delivery source per load balancer and log type. A
load balancer that already sends a log type somewhere through a log delivery
cannot send it to Fencer as well.

Find the load balancer ARNs:

```sh
aws elbv2 describe-load-balancers --query 'LoadBalancers[?Type==`application`].[LoadBalancerName,LoadBalancerArn]'
```

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."                 # from the Fencer app
export TF_VAR_fencer_access_logs_access_key="..."               # token of the access logs source
export TF_VAR_fencer_connection_logs_access_key="..."           # token of the connection logs source
export TF_VAR_load_balancers='{"my-lb":"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/50dc6c495c0c9188"}'

terraform init
terraform plan    # only new fencer-alb-access-logs* and fencer-alb-connection-logs* resources plus two deliveries per load balancer
terraform apply
```

## Verify

Access log records need requests to the load balancer. Connection log records
need TLS connections, so the load balancer needs an HTTPS listener. Firehose
buffers for up to 60 s.

```sh
aws logs describe-deliveries \
  --query 'deliveries[].[id,deliverySourceName,deliveryDestinationType]'

for stream in access_logs_stream_name connection_logs_stream_name; do
  aws firehose describe-delivery-stream \
    --delivery-stream-name "$(terraform output -raw $stream)" \
    --query 'DeliveryStreamDescription.DeliveryStreamStatus'
done

# Failed deliveries — both must stay empty
aws s3 ls "s3://$(terraform output -raw access_logs_backup_bucket)" --recursive
aws s3 ls "s3://$(terraform output -raw connection_logs_backup_bucket)" --recursive
```

Events appear in the Fencer app (Hunts) within a few minutes: access logs as
HTTP Activity, connection logs as Network Activity.

## Clean up

```sh
terraform destroy
```

This removes the log deliveries and the Fencer resources only. If a backup
bucket holds objects, empty it first:

```sh
aws s3 rm "s3://$(terraform output -raw access_logs_backup_bucket)" --recursive
aws s3 rm "s3://$(terraform output -raw connection_logs_backup_bucket)" --recursive
```
