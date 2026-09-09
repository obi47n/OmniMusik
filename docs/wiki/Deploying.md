# Deploying

Two paths reach AWS. CI is the one to use; by hand is the one that explains what CI
does, and the one that works when CI cannot.

## Through CI (GitHub Actions)

1. Push to `master`.
2. GitHub → **Actions → Deploy → Run workflow**, choose `api`, `web` or `both`.

The workflow assumes `omnimusik-github-deploy` through OIDC — there is no AWS key
stored in GitHub, and the role's trust policy admits only this repository. It can push
images, roll the API out, and publish the web client. It cannot change infrastructure;
that stays with `terraform apply` from a machine with real credentials.

**API job:** Jib builds the image from Maven and pushes it to ECR tagged `latest` and
with the commit SHA, then `scripts/deploy-api.sh` updates the Express service with
that SHA. The SHA is what makes it a rollout: ECS resolves the image when a deployment
starts, so a moved `:latest` tag on its own changes nothing.

**Web job:** builds with the `VITE_*` repository variables baked in, syncs `dist/` to
S3 with immutable cache headers on hashed assets and `no-cache` on `index.html`, and
invalidates `/index.html` on CloudFront.

Requires the secret and variables listed in
[Environments and URLs](Environments-and-URLs.md#github).

## By hand

Credentials first: `aws login`, then confirm with `aws sts get-caller-identity`.

### API

```bash
cd backend
./mvnw -q -DskipTests compile jib:build \
  -Dimage.repository=463092208222.dkr.ecr.us-east-1.amazonaws.com/omnimusik-api \
  -Djib.to.tags=latest,$(git rev-parse HEAD) \
  -Djib.to.auth.username=AWS \
  -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"

cd ..
IMAGE_TAG=$(git rev-parse HEAD) ./scripts/deploy-api.sh
```

No Docker is needed: Jib assembles the layers and pushes them itself. The script
creates the Express service if it does not exist and updates it if it does, resolving
every input by name from AWS, so it needs no Terraform state.

Watch the rollout:

```bash
ARN=arn:aws:ecs:us-east-1:463092208222:service/omnimusik/omnimusik-api
aws ecs describe-express-gateway-service --region us-east-1 --service-arn $ARN
aws logs tail /ecs/omnimusik-api --region us-east-1 --follow
```

A fresh service's hostname is not in DNS until its first deployment reports
`SUCCESSFUL`. A resolver that looked it up earlier caches the miss — query
`dig @8.8.8.8` if it seems dead.

### Web client

```bash
cd web
VITE_COGNITO_DOMAIN=omnimusik-463092208222.auth.us-east-1.amazoncognito.com \
VITE_COGNITO_CLIENT_ID=533bcjsr65iq88t7vg2kmetrkp \
VITE_API_BASE_URL=https://om-4dfe457f79a84726a4058ed47871dbbd.ecs.us-east-1.on.aws \
npm run build

aws s3 sync dist s3://omnimusik-web-463092208222 --delete --exclude index.html \
  --cache-control "public,max-age=31536000,immutable"
aws s3 cp dist/index.html s3://omnimusik-web-463092208222/index.html --cache-control no-cache
aws cloudfront create-invalidation --distribution-id E21470R0DRAVCF --paths /index.html
```

### Infrastructure (Terraform)

```bash
cd infra
terraform plan  -var="github_repository=obi47n/OmniMusik"
terraform apply -var="github_repository=obi47n/OmniMusik"
```

Terraform is at `~/.local/bin/terraform`. State is a local file (`infra/terraform.tfstate`,
gitignored) — only this machine can apply.

**Terraform cannot read `aws login` credentials.** They live in a CLI-only cache, so
the provider reports "No valid credential sources found" while the CLI works fine.
Give it a config file whose `credential_process` asks the CLI, and it refreshes on its
own — which matters, because a static export expires mid-apply:

```ini
# ~/.aws/terraform.config
[default]
region = us-east-1
credential_process = env AWS_CONFIG_FILE=/Users/obinnaduruaku/.aws/config /Users/obinnaduruaku/.local/bin/aws configure export-credentials --format process
```

```bash
AWS_CONFIG_FILE=~/.aws/terraform.config terraform apply -var="github_repository=obi47n/OmniMusik"
```

The `AWS_CONFIG_FILE` reset inside the command is what stops the CLI reading this file
and calling itself forever.

### The phone

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd OmniMusik
xcodebuild -project OmniMusik.xcodeproj -scheme OmniMusik -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/dd build
xcrun devicectl device install app --device 34635B4F-CC7B-476A-9556-8BDD271328B8 \
  /tmp/dd/Build/Products/Debug-iphoneos/OmniMusik.app
```

`xcode-select` on this machine points at CommandLineTools; `DEVELOPER_DIR` is required.

## Database migrations

Production runs `ddl-auto=validate`: Hibernate checks the schema and refuses to invent
it. Flyway creates it. A new entity or column is a new file in
`backend/src/main/resources/db/migration/` named `V<n>__<description>.sql`; the next
deployment applies it before the app starts, and validate confirms the two agree.

Tests run with Flyway disabled on H2 `create-drop`, so a migration that disagrees with
the entities is caught by the deployment, loudly, not by the suite. Verify locally
before pushing:

```bash
cd backend && ./mvnw -q -DskipTests package
java -jar target/*.jar \
  --spring.datasource.url="jdbc:h2:mem:verify;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE" \
  --spring.jpa.hibernate.ddl-auto=validate --spring.flyway.enabled=true \
  --spring.security.oauth2.resourceserver.jwt.issuer-uri= \
  --spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://localhost:1/jwks.json \
  --omnimusik.cors.allowed-origins=http://localhost:5173 --server.port=8099
```

"Started OmnimusikApiApplication" means the migration and the entities agree.
