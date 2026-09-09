# Environments and URLs

Everything on this page is safe to share. Where a value has a secret behind it, the
secret's *location* is given, never the secret.

## Production

### User-facing

| What | Value |
|---|---|
| Web app | https://d31gmchu33wc40.cloudfront.net |
| API | https://om-4dfe457f79a84726a4058ed47871dbbd.ecs.us-east-1.on.aws |
| API health | https://om-4dfe457f79a84726a4058ed47871dbbd.ecs.us-east-1.on.aws/actuator/health |
| Sign-in (Cognito hosted UI) | https://omnimusik-463092208222.auth.us-east-1.amazoncognito.com |

The API hostname is assigned by ECS when the Express service is created. TLS is
issued by Amazon for that name; there is no custom domain. Deleting and recreating
the service produces a new hostname — see [Home](Home.md#keeping-this-current) for
the three places that then need updating.

### Authentication (Cognito)

| What | Value |
|---|---|
| User pool id | `us-east-1_c9yH4UiHc` |
| Issuer URI | `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_c9yH4UiHc` |
| App client id | `533bcjsr65iq88t7vg2kmetrkp` (public client, PKCE, no secret) |
| Hosted UI domain | `omnimusik-463092208222.auth.us-east-1.amazoncognito.com` |
| iOS redirect | `omnimusik://auth` scheme, configured in `Auth/CognitoConfiguration.swift` |
| Web redirect | `<web origin>/callback` |

Both clients run the same OAuth2 authorization-code flow with PKCE against the hosted
UI. The client id is not a secret: PKCE is what makes an intercepted code useless.

Cognito's default email sender is development-only (50/day, distrusted by Gmail).
Verification emails may not arrive; confirm a user with
`aws cognito-idp admin-confirm-sign-up --user-pool-id us-east-1_c9yH4UiHc --username <email>`.

### Compute (ECS Express Mode)

| What | Value |
|---|---|
| Cluster | `omnimusik` |
| Service | `omnimusik-api` — `arn:aws:ecs:us-east-1:463092208222:service/omnimusik/omnimusik-api` |
| Task size | 0.5 vCPU, 1 GB, minimum 1 task, scales on CPU |
| Container port | 8080 |
| Health check | `/actuator/health` |
| Load balancer | `ecs-express-gateway-alb-e2ec05ba` (created and owned by ECS) |
| Application logs | CloudWatch group `/ecs/omnimusik-api`, 14-day retention |
| Image | `463092208222.dkr.ecr.us-east-1.amazonaws.com/omnimusik-api` (`:latest` and `:<git sha>`) |

The service is created by `scripts/deploy-api.sh`, not Terraform — the provider has
no resource for Express services. Inspect it with
`aws ecs describe-express-gateway-service --service-arn <arn>`.

### Database (RDS Postgres)

| What | Value |
|---|---|
| Instance | `omnimusik-postgres` |
| Endpoint | `omnimusik-postgres.csdig04wyrw6.us-east-1.rds.amazonaws.com:5432` |
| Database / user | `omnimusik` / `omnimusik` |
| Password | Secrets Manager `omnimusik/database`, key `password` — injected into the task by the execution role, never stored in config |
| Class | `db.t4g.micro`, 20 GB gp3, single AZ, private subnets only |
| Schema | Owned by Flyway; migrations in `backend/src/main/resources/db/migration/` |

The endpoint is unreachable from outside the VPC by design. The only path in is the
API's task security group.

### Network (VPC `vpc-02f0d81d0949b56df`, 10.0.0.0/16)

| What | Value |
|---|---|
| Public subnets (load balancer + API tasks) | `subnet-09701051a2eaf146d` (1a, 10.0.10.0/24), `subnet-04b09a66f5409452e` (1b, 10.0.11.0/24) |
| Private subnets (database) | `subnet-05423b13b9da2213c` (1a, 10.0.0.0/24), `subnet-0caed6acb07906678` (1b, 10.0.1.0/24) |
| Internet gateway | `igw-0d14a95e1578df726` |
| API task security group | `sg-06feb768b13b017e6` `omnimusik-api-tasks` — ingress 8080 from the load balancer's group only |
| Load balancer security group | `sg-0218b6af5c51cfd80` (created by ECS) |
| NAT gateway | None, deliberately. Tasks have public addresses and a group that admits only the load balancer. |

### Web hosting

| What | Value |
|---|---|
| S3 bucket | `omnimusik-web-463092208222` (private; only CloudFront reads it) |
| CloudFront distribution | `E21470R0DRAVCF` |
| SPA routing | 403 and 404 rewrite to `/index.html` — required for the `/callback` OAuth redirect |

### IAM roles

| Role | Used by |
|---|---|
| `omnimusik-github-deploy` — `arn:aws:iam::463092208222:role/omnimusik-github-deploy` | GitHub Actions, via OIDC; only `repo:obi47n/OmniMusik:*` can assume it |
| `omnimusik-ecs-execution` | The ECS agent: pull image, write logs, read the database secret |
| `omnimusik-ecs-task` | The application itself (currently no permissions — it makes no AWS calls) |
| `omnimusik-ecs-infrastructure` | ECS, to build the load balancer and target groups for the Express service |

### GitHub

| What | Value |
|---|---|
| Repository | https://github.com/obi47n/OmniMusik |
| Deploy workflow | Actions → Deploy → Run workflow (`workflow_dispatch`, choose api / web / both) |
| Secret `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::463092208222:role/omnimusik-github-deploy` |
| Variable `VITE_COGNITO_DOMAIN` | `omnimusik-463092208222.auth.us-east-1.amazoncognito.com` |
| Variable `VITE_COGNITO_CLIENT_ID` | `533bcjsr65iq88t7vg2kmetrkp` |
| Variable `VITE_API_BASE_URL` | `https://om-4dfe457f79a84726a4058ed47871dbbd.ecs.us-east-1.on.aws` |
| Variable `WEB_BUCKET` | `omnimusik-web-463092208222` |
| Variable `CLOUDFRONT_DISTRIBUTION_ID` | `E21470R0DRAVCF` |

Secrets and variables live at https://github.com/obi47n/OmniMusik/settings/secrets/actions.

### Third-party services

| What | Value |
|---|---|
| Spotify app client id | `38ab0fbae2b74060b3bccf507d59f7d9` (public; PKCE) |
| Spotify redirect URI | `omnimusik://spotify-auth` |
| Spotify client secret | Not used and not stored anywhere. The app uses PKCE. Never paste it into a chat or commit it. |
| Apple Music (MusicKit) | Blocked — App Service not yet enabled on the developer account. `AppleMusicSource` is a stub. |

## Local development

| What | Value |
|---|---|
| Backend | `http://localhost:8080` — `cd backend && ./mvnw spring-boot:run` (or `java -jar target/*.jar`) |
| Backend database | H2 on disk at `backend/data/omnimusik.mv.db` (gitignored); survives restarts |
| Web client | `http://localhost:5173` — `cd web && npm run dev`; reads `web/.env.local` at startup |
| Phone → Mac backend | `http://Obis-MacBook-Air.local:8080` (Bonjour name, allowed by the local-networking ATS exception) |

Which API the phone uses is decided in `OmniMusik/Library/APIConfiguration.swift`:
`baseURLString` set → that URL; `REPLACE_ME` → the Mac's backend in DEBUG builds,
nothing in Release. It is currently set to the production API.

## Published documents

| Document | URL |
|---|---|
| Field guide | https://claude.ai/code/artifact/c0676296-9d95-4f78-92c4-9017d1a53920 |
| Interview notes | https://claude.ai/code/artifact/f4b69ae6-fc9c-477a-b3d9-92eb0f566fa4 |
| System design | https://claude.ai/code/artifact/140c4904-8d3b-42ac-ab08-b67a45d5d6c4 |
