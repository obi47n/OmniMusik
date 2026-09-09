# ECS Express Mode, replacing App Runner.
#
# App Runner stopped accepting new services on 2026-04-30. The existing one could
# not be recreated -- the console's create button is disabled on this account -- so
# the choice was made by the platform rather than by us. AWS points at ECS Express
# Mode, which is the same bargain App Runner offered: hand over a container and a
# port, and the platform runs the load balancer, target groups, scaling and TLS.
#
# What that costs us is the network. App Runner supplied its own public endpoint and
# reached into the VPC through a connector, so the VPC needed no public subnets and
# no internet gateway at all. Express Mode puts an Application Load Balancer in our
# VPC, and a load balancer the internet can reach has to live in a subnet the
# internet can reach. So public subnets arrive here, and with them the routing that
# the original design was proud not to need.
#
# Terraform has no resource for an Express service -- the AWS provider is at v5.100
# and there is not one at any version yet -- so everything the service *depends* on
# is here, and the service itself is created by scripts/deploy-api.sh against the
# API. Split deliberately: the roles, network and cluster are the part worth having
# in state, and the service is one idempotent command that names its own inputs.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# The load balancer's subnets, and the tasks'.
#
# The tasks run here with public addresses rather than in the private subnets behind
# a NAT gateway. That is a deliberate repeat of the reasoning in DECISIONS.md: a NAT
# gateway is $32/month to give tasks outbound access for pulling an image and writing
# logs, and an address plus a security group that admits only the load balancer costs
# nothing. The tasks are addressable but not reachable.
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The tasks' own group.
#
# No ingress rules at all. Express Mode creates the load balancer's security group
# itself and authorises it to reach the tasks, so writing an ingress rule here would
# either duplicate that or fight it. Egress is open because the task pulls its image
# from ECR, writes logs, and fetches Cognito's signing keys.
resource "aws_security_group" "api_tasks" {
  name        = "${var.project}-api-tasks"
  description = "OmniMusik API tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Image pull, logs, and the Cognito JWKS endpoint"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-api-tasks" }
}

resource "aws_ecs_cluster" "main" {
  name = var.project

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project}-api"
  retention_in_days = 14
}

# MARK: Roles
#
# Three roles, because Express Mode separates three jobs that App Runner ran together.

# Pulls the image and writes logs. Used by the ECS agent, not by our code.
resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The execution role also resolves the database secret, because the password is
# injected as an environment variable before the container starts.
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${var.project}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.read_database_secret.json
}

# What the application itself may do. Nothing, so far -- it talks to Postgres with a
# password and to Cognito over HTTPS, and neither is an AWS API call. It exists
# because a task with no role of its own inherits nothing to audit later.
resource "aws_iam_role" "ecs_task" {
  name               = "${var.project}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Lets ECS build the load balancer, target groups, scaling policies and security
# groups that Express Mode manages on our behalf. Used only while the service is
# being created, updated or deleted -- never at runtime.
#
# The policy is the Express-specific one. AmazonECSInfrastructureRolePolicyForLoadBalancers
# is the obvious-looking neighbour and is not attachable; Express Gateway has its own.
resource "aws_iam_role" "ecs_infrastructure" {
  name               = "${var.project}-ecs-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_assume.json
}

data "aws_iam_policy_document" "ecs_infrastructure_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

output "ecs_cluster" { value = aws_ecs_cluster.main.name }
output "ecs_execution_role_arn" { value = aws_iam_role.ecs_execution.arn }
output "ecs_task_role_arn" { value = aws_iam_role.ecs_task.arn }
output "ecs_infrastructure_role_arn" { value = aws_iam_role.ecs_infrastructure.arn }
output "api_task_security_group" { value = aws_security_group.api_tasks.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "api_log_group" { value = aws_cloudwatch_log_group.api.name }

# The load balancer's group is created by ECS, not by us, so it is looked up rather
# than declared. Express Mode builds the balancer and its group but does not touch
# the tasks' group -- the first deployment sat at "unhealthy: failed health checks"
# with the app answering on 8080 the whole time, because nothing admitted the
# balancer. The health check is the balancer connecting to the task; the task's group
# has to say yes.
data "aws_security_group" "express_gateway_alb" {
  vpc_id = aws_vpc.main.id

  filter {
    name   = "group-name"
    values = ["ecs-express-gateway-alb-sg-*"]
  }

  depends_on = [aws_ecs_cluster.main]
}

resource "aws_security_group_rule" "api_tasks_from_alb" {
  type                     = "ingress"
  description              = "ECS Express gateway load balancer"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.api_tasks.id
  source_security_group_id = data.aws_security_group.express_gateway_alb.id
}
