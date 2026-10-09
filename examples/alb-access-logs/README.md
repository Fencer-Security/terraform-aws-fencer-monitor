# ALB access logs → Fencer

Delivers Application Load Balancer access logs straight to a Fencer Firehose
stream as JSON, through a CloudWatch log delivery. The module creates one log
delivery per load balancer. It does not change the load balancers.

One module instance delivers one log type to one Fencer data source. For
connection logs, create a second Fencer data source (with its own token) and
use [`examples/alb-connection-logs`](../alb-connection-logs). The two examples use
different `name_prefix` values, so they do not collide in one account.

Run this in the same AWS account and region as the load balancers.

## Before you apply

Create the Fencer data source with the type AWS ALB Access Logs and generate
its access token.

Check that the principal that runs Terraform has these IAM permissions:

- `logs:PutDeliverySource`, `logs:GetDeliverySource`, `logs:DeleteDeliverySource`
- `logs:PutDeliveryDestination`, `logs:GetDeliveryDestination`, `logs:DeleteDeliveryDestination`
- `logs:CreateDelivery`, `logs:GetDelivery`, `logs:DeleteDelivery`, `logs:UpdateDeliveryConfiguration`
- `logs:DescribeDeliverySources`, `logs:DescribeDeliveryDestinations`, `logs:DescribeDeliveries`
- `firehose:TagDeliveryStream`
- `iam:CreateServiceLinkedRole` (the first log delivery to Firehose in the account creates `AWSServiceRoleForLogDelivery`)
- `elasticloadbalancing:AllowVendedLogDeliveryForResource` on the load balancers (AWS defines it for vended log delivery from a load balancer)

Find the load balancer ARNs:

```sh
aws elbv2 describe-load-balancers --query 'LoadBalancers[?Type==`application`].[LoadBalancerName,LoadBalancerArn]'
```

## Apply

```sh
export TF_VAR_fencer_endpoint_url="https://..."       # from the Fencer app
export TF_VAR_fencer_access_key="..."                 # from the Fencer app
export TF_VAR_load_balancers='{"my-lb":"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/50dc6c495c0c9188"}'

terraform init
terraform plan    # only new fencer-alb-access-logs* resources plus one delivery per load balancer
terraform apply
```

## Verify

Log records need requests to the load balancer. Firehose buffers for up to 60 s.

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
bucket holds objects, empty it first:

```sh
aws s3 rm "s3://$(terraform output -raw backup_bucket)" --recursive
```
