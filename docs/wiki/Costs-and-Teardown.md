# Costs and teardown

## Left running

Rough monthly, `us-east-1`, idle, one task always on:

| Item | Approx |
|---|---|
| Application Load Balancer (created by ECS Express Mode) | ~$16 |
| Fargate task, 0.5 vCPU / 1 GB, 24×7 | ~$15 |
| RDS `db.t4g.micro`, 20 GB gp3 | $12–15 |
| Public IPv4 addresses (task + load balancer nodes) | ~$4–7 |
| CloudFront, S3, ECR, CloudWatch, Secrets Manager at portfolio traffic | Cents |

Call it **~$45/month**. The load balancer is the line item App Runner used to bundle;
there is no NAT gateway, deliberately, and no interface endpoints any more.

For a project with no users the cheapest deployment is an absent one: bring it up
before a demo, take it down after. Budget 10–15 minutes for `apply` (nearly all RDS)
and about ten for the Express service to report healthy.

## Pausing without destroying

Scale the API to zero and leave everything else in place. The load balancer and the
database keep billing, so this saves roughly a third — useful for a few days, not for
a month:

```bash
ARN=arn:aws:ecs:us-east-1:463092208222:service/omnimusik/omnimusik-api
aws ecs update-express-gateway-service --region us-east-1 --service-arn $ARN \
  --scaling-target minTaskCount=0,maxTaskCount=1
```

## Teardown, in order

The Express service is **not in Terraform state** — the provider has no resource for
it — so `terraform destroy` on its own fails on the security group the service still
holds. Delete the service first, wait for it to go, then destroy:

```bash
# 1. The Express service (also removes its load balancer, target groups and the
#    load balancer's security group). Takes a few minutes.
ARN=arn:aws:ecs:us-east-1:463092208222:service/omnimusik/omnimusik-api
aws ecs delete-express-gateway-service --region us-east-1 --service-arn $ARN
until ! aws ecs describe-express-gateway-service --region us-east-1 --service-arn $ARN >/dev/null 2>&1; do sleep 15; done

# 2. Everything Terraform owns. RDS takes most of the time. The web bucket must be
#    empty first, or the destroy stops on it.
aws s3 rm s3://omnimusik-web-463092208222 --recursive
cd infra
AWS_CONFIG_FILE=~/.aws/terraform.config terraform destroy -var="github_repository=obi47n/OmniMusik"
```

What survives a destroy and why it is fine:

- **ECR images** go with the repository. Rebuild with Jib; nothing about them is
  hand-made.
- **Cognito users** go with the pool. Accounts have to be re-created; playlists are
  on the phone and re-upload on the next sync, because a fresh server has a new epoch.
- **The API hostname changes** on the next bring-up. Update the three places listed
  in [Home](Home.md#keeping-this-current).
- **Terraform state** stays on this machine and now describes nothing; the next
  `apply` builds from scratch.

## Bringing it back

```bash
cd infra
AWS_CONFIG_FILE=~/.aws/terraform.config terraform apply -var="github_repository=obi47n/OmniMusik"
# then, from the repository root:
cd backend && ./mvnw -q -DskipTests compile jib:build \
  -Dimage.repository=463092208222.dkr.ecr.us-east-1.amazonaws.com/omnimusik-api \
  -Djib.to.auth.username=AWS \
  -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)" && cd ..
./scripts/deploy-api.sh      # prints the new endpoint
```

Then the web client, with the new `VITE_API_BASE_URL`, as in [Deploying](Deploying.md#web-client).

## Budget guardrails

The account had a `BudgetsSpendLimitDenyNewWorkloads` service control policy that
denied EC2, RDS and Cognito — including read-only calls — until it was detached from
the management account. If an `apply` fails with "explicit deny in a service control
policy" on a `Describe` call, that policy is back; the spend limit is not the lever.
