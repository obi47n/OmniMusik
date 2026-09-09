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
| VPC, 2 private subnets, 1 interface endpoint | App Runner's VPC connector routes all egress through the VPC |
| Cognito user pool, hosted UI domain, public app client | One client for both iOS and web; PKCE, no secret |
| Sign in with Apple identity provider | Optional, off by default — see below |
| RDS Postgres in private subnets | Reachable only from the app's security group |
| Secrets Manager entry | Generated password, injected at container start |
| ECR repository with a lifecycle policy | Ten most recent images |
| App Runner service, VPC connector, two IAM roles | The service itself |
| S3 bucket + CloudFront with OAC | The web client; private bucket, only CloudFront can read it |
| GitHub OIDC provider + deploy role | CI publishes artifacts with no stored AWS key |

## Decisions worth knowing

**App Runner rather than ECS Fargate.** Chosen against a fixed deadline. Fargate means
hand-wiring an ALB, target groups, task definitions and autoscaling — days that do not
buy proportional signal here. The container pipeline, private networking and IAM
boundaries are all still present; the orchestration boilerplate is not. It would
change with sustained traffic, sidecars, or a need for fine-grained deployment
control, and this VPC would carry over unchanged.

**There is no NAT gateway, deliberately.** A VPC connector routes *all* of the
service's outbound traffic through the VPC, so once attached the service cannot reach
Cognito's JWKS endpoint by default — token validation starts timing out in a way that
looks nothing like a networking problem. The reference answer is a NAT gateway at
~$32/month. But the API has exactly one destination outside the VPC, `cognito-idp`, so
a single interface endpoint serves it for ~$7. Paying four times as much for
general-purpose internet reachability that nothing uses is a default worth
questioning.

Consequently there are no public subnets and no internet gateway — nothing lives in
them once the NAT is gone. The endpoint sits in one subnet rather than two, since an
interface endpoint bills per ENI per hour and private DNS still resolves from the
other AZ for a fraction of a cent in cross-AZ transfer.

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
| Interface endpoint (`cognito-idp`, 1 AZ) | ~$7 |
| RDS db.t4g.micro, 20 GB gp3 | $12-15 |
| App Runner 0.25 vCPU / 0.5 GB | $5-25 depending on active time |
| CloudFront + S3 at portfolio traffic | Cents |

Call it **~$25/month** left running, down from ~$60 before the NAT gateway was
replaced.

For a portfolio the cheaper move is not to leave it running at all: `terraform apply`
before a demo and `terraform destroy` after costs roughly $1/day. Budget 10-15 minutes
for the apply, almost all of it RDS.

If the account still qualifies for the 12-month free tier, `db.t4g.micro` may be
covered outright — worth checking, since AWS has reworked the free-tier model.

## Caveat

`terraform validate` passes and the configuration is formatted, but this has **never
been applied** — that needs AWS credentials and spends real money. Expect the first
apply to surface things validation cannot catch: RDS engine version availability in
the chosen region, the Cognito domain prefix already being taken globally, and
App Runner's own service quotas.
