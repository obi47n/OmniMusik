# OmniMusik Infrastructure

Terraform for the API and its identity layer. Validated with Terraform 1.9.8 and the
AWS provider 5.x; **never applied** — see the caveat at the bottom.

```bash
cd infra
terraform init
terraform plan
terraform apply
```

Then wire the outputs into the clients:

```bash
terraform output cognito_domain          # -> CognitoConfiguration.swift, VITE_COGNITO_DOMAIN
terraform output cognito_app_client_id   # -> both clients
terraform output api_url                 # -> VITE_API_BASE_URL
```

## What it builds

| Resource | Why |
|---|---|
| VPC, 2 private subnets, 2 public subnets, internet gateway | Database in private; load balancer and API tasks in public, no NAT |
| Cognito user pool, hosted UI domain, public app client | One client for both iOS and web; PKCE, no secret |
| Sign in with Apple identity provider | Optional, off by default — see below |
| RDS Postgres in private subnets | Reachable only from the app's security group |
| Secrets Manager entry | Generated password, injected at container start |
| ECR repository with a lifecycle policy | Ten most recent images |
| ECS cluster, three IAM roles, task security group, log group | Everything the Express service depends on; the service itself is `scripts/deploy-api.sh` |
| S3 bucket + CloudFront with OAC | The web client; private bucket, only CloudFront can read it |
| GitHub OIDC provider + deploy role | CI publishes artifacts with no stored AWS key |

## Decisions worth knowing

**ECS Express Mode, after App Runner closed.** App Runner was the original choice and
the reasoning still holds: a managed runtime that takes an image and a port, chosen
over hand-wiring an ALB, target groups and task definitions. AWS stopped accepting
new App Runner services in April 2026 and this account cannot create one, so the API
runs on ECS Express Mode -- the same bargain, on ECS. Terraform has no resource for
an Express service, so the service is one idempotent script that looks its inputs
up by name; everything it depends on is here.

**There is still no NAT gateway, deliberately.** The API tasks run in public subnets
with public addresses and a security group that admits only the load balancer. That
is what lets them pull an image, write logs and fetch Cognito's signing keys without
a $32/month NAT gateway in front of private subnets. Addressable, not reachable. The
database stays private. The interface endpoint the earlier design used for Cognito is
gone: a task with a route to the internet reaches Cognito directly.

**Sign in with Apple is optional and off by default.** It needs a Services ID, team ID,
key ID and .p8 key, and the stack has to be applyable without them. Cognito's own email
and password sign-in works from the first apply, and enabling SIWA later changes
nothing in either client. Pass the key as `TF_VAR_apple_private_key`, never in a
committed tfvars file.

**Two IAM roles, not one.** The access role is assumed by the build side to pull from
ECR; the instance role is what the running container uses to read its database secret.
Conflating them is a common mistake and grants the build more than it needs.

**`multi_az`, `deletion_protection` and Performance Insights are all off.** Every one
would be on in production. They are off so this stack stays cheap and tears down
cleanly, which is the right tradeoff for a portfolio and the wrong one for a product.

**The web client needs SPA error responses, and it is authentication that breaks
without them.** Vite emits one `index.html` and the router resolves the path, so S3
has no object at `/callback` -- the OAuth redirect URI. Without the 403/404 rewrites
to `/index.html`, finishing sign-in lands on an XML access-denied page rather than the
app.

**CI has no AWS key.** GitHub Actions federates through OIDC and assumes a role that
only this repository can assume, so there is no long-lived credential to leak. The
role can push images, publish the web client and trigger a rollout -- it deliberately
cannot change infrastructure. Terraform stays a local, deliberate action.

Set `github_repository` once the repo has a remote; leave it empty and none of the CI
resources are created, so the stack applies either way. If the account already has a
GitHub OIDC provider from another project, set `create_github_oidc_provider = false`
-- an account may only have one.

## Cost

Rough monthly, us-east-1, idle:

| Item | Approx |
|---|---|
| RDS db.t4g.micro, 20 GB gp3 | $12-15 |
| Fargate task, 0.5 vCPU / 1 GB, one always on | ~$15 |
| Application Load Balancer (managed by Express Mode) | ~$16 |
| CloudFront + S3 at portfolio traffic | Cents |

Call it **~$45/month** left running. The load balancer is the new line item: App
Runner bundled one in; Express Mode bills it separately.

For a portfolio the cheaper move is not to leave it running at all: `terraform apply`
before a demo and `terraform destroy` after costs roughly $1/day. Budget 10-15 minutes
for the apply, almost all of it RDS.

If the account still qualifies for the 12-month free tier, `db.t4g.micro` may be
covered outright — worth checking, since AWS has reworked the free-tier model.

## Caveat

The Express service is not in Terraform state. `terraform destroy` removes everything
it depends on and will fail on the security group the service still uses; delete the
service first with `aws ecs delete-express-gateway-service`.
