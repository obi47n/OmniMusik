#!/usr/bin/env bash
#
# Creates or updates the API's ECS Express Mode service.
#
# Why this is a script and not Terraform: the AWS provider has no resource for an
# Express Gateway service. Everything the service depends on -- cluster, roles,
# subnets, security groups, log group -- is Terraform, in state, reviewable. This
# is the one call that has to be made against the API directly, and it reads its
# own inputs from Terraform's outputs so the two cannot drift.
#
# Idempotent: creates the service if it does not exist, updates it if it does.
#
#   ./scripts/deploy-api.sh                 # deploys :latest
#   IMAGE_TAG=<git sha> ./scripts/deploy-api.sh
#
# ECS resolves the image when a deployment starts, so pushing a new :latest does
# nothing on its own; the update call is the rollout. CI passes the commit SHA so a
# deployment names exactly what it runs, and rolling back is deploying an old tag.
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
SERVICE="omnimusik-api"
# Every input is looked up by name from AWS rather than read from Terraform's
# outputs. Terraform's state is a local file, so `terraform output` works on the
# machine that applied it and nowhere else -- and CI, which has no state, is where
# this most needs to run. The names are the ones Terraform assigned; if it renames
# something, this breaks loudly at lookup rather than quietly deploying against the
# wrong resource.
PROJECT="omnimusik"

CLUSTER="$PROJECT"
LOG_GROUP="/ecs/$PROJECT-api"
EXEC_ROLE=$(aws iam get-role --role-name "$PROJECT-ecs-execution" --query Role.Arn --output text)
TASK_ROLE=$(aws iam get-role --role-name "$PROJECT-ecs-task" --query Role.Arn --output text)
INFRA_ROLE=$(aws iam get-role --role-name "$PROJECT-ecs-infrastructure" --query Role.Arn --output text)
TASK_SG=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=$PROJECT-api-tasks" --query "SecurityGroups[0].GroupId" --output text)
SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=tag:Name,Values=$PROJECT-public-*" --query "Subnets[].SubnetId" --output text | tr '\t' ',')
ECR_URL=$(aws ecr describe-repositories --region "$REGION" \
  --repository-names "$PROJECT-api" --query "repositories[0].repositoryUri" --output text)
IMAGE="$ECR_URL:${IMAGE_TAG:-latest}"

# Runtime configuration. The database password is not here: it is injected from
# Secrets Manager by the execution role, so it never appears in a task definition,
# a shell history, or a CI log.
DB_HOST=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?DBInstanceIdentifier=='$PROJECT-postgres'].Endpoint.Address" --output text)
DB_SECRET=$(aws secretsmanager list-secrets --region "$REGION" \
  --query "SecretList[?starts_with(Name,'$PROJECT/database')].ARN" --output text)
POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "$REGION" \
  --query "UserPools[?Name=='$PROJECT'].Id" --output text)
# The web client's own domain, if one has been put in front of CloudFront: the
# distribution lists it as an alias. Empty until then.
CUSTOM_ORIGINS=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Origins.Items[0].DomainName,'$PROJECT-web')].Aliases.Items[] | [*]" --output text 2>/dev/null \
  | tr '\t' '\n' | sed 's|^|https://|' | paste -sd, -)
CF_DOMAIN="https://$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Origins.Items[0].DomainName,'$PROJECT-web')].DomainName | [0]" --output text)"

for v in EXEC_ROLE TASK_ROLE INFRA_ROLE TASK_SG SUBNETS ECR_URL DB_HOST DB_SECRET POOL_ID; do
  if [ -z "${!v}" ] || [ "${!v}" = "None" ]; then echo "Could not resolve $v" >&2; exit 1; fi
done

CONTAINER=$(python3 - "$IMAGE" "$LOG_GROUP" "$DB_HOST" "$DB_SECRET" "$POOL_ID" "$CF_DOMAIN" "$REGION" "$CUSTOM_ORIGINS" <<'PY'
import json, sys
image, log_group, db_host, db_secret, pool_id, cf_domain, region, custom_origins = sys.argv[1:9]
print(json.dumps({
    "image": image,
    "containerPort": 8080,
    "awsLogsConfiguration": {"logGroup": log_group, "logStreamPrefix": "ecs"},
    "environment": [
        {"name": "SPRING_PROFILES_ACTIVE", "value": "prod"},
        {"name": "DB_HOST", "value": db_host},
        {"name": "DB_PORT", "value": "5432"},
        {"name": "DB_NAME", "value": "omnimusik"},
        {"name": "DB_USER", "value": "omnimusik"},
        {"name": "ALLOWED_ORIGINS",
         "value": ",".join(o for o in [custom_origins, cf_domain, "http://localhost:5173"] if o)},
        {"name": "COGNITO_ISSUER_URI",
         "value": f"https://cognito-idp.{region}.amazonaws.com/{pool_id}"},
    ],
    "secrets": [{"name": "DB_PASSWORD", "valueFrom": f"{db_secret}:password::"}],
}))
PY
)

# Express services are addressed by ARN, not by cluster and name. The ARN is
# deterministic, but asking the cluster is what makes the answer "does it exist"
# rather than "does it look like it should".
EXISTING=$(aws ecs list-services --region "$REGION" --cluster "$CLUSTER" \
  --query "serviceArns[?ends_with(@, '/$SERVICE')] | [0]" --output text 2>/dev/null || true)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "Updating $SERVICE"
  aws ecs update-express-gateway-service --region "$REGION" \
    --service-arn "$EXISTING" \
    --primary-container "$CONTAINER"
else
  echo "Creating $SERVICE"
  aws ecs create-express-gateway-service --region "$REGION" \
    --cluster "$CLUSTER" --service-name "$SERVICE" \
    --infrastructure-role-arn "$INFRA_ROLE" \
    --execution-role-arn "$EXEC_ROLE" \
    --task-role-arn "$TASK_ROLE" \
    --primary-container "$CONTAINER" \
    --network-configuration "securityGroups=$TASK_SG,subnets=$SUBNETS" \
    --cpu 512 --memory 1024 \
    --health-check-path /actuator/health
fi
