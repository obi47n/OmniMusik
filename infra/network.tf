# Networking.
#
# App Runner is public and AWS-managed, but reaching a private database means
# attaching a VPC connector -- and a VPC connector routes *all* of the service's
# outbound traffic through the VPC. That is the detail worth knowing: once attached,
# the service can no longer reach Cognito's JWKS endpoint by default, and token
# validation starts failing as a timeout that looks nothing like a networking problem.
#
# The reference answer is a NAT gateway. This stack does not use one, because the API
# has exactly one destination outside the VPC: `cognito-idp`, to fetch the signing
# keys. A NAT gateway is a general-purpose route to the whole internet at ~$32/month;
# a single interface endpoint serves the one thing actually needed for ~$7. Paying
# four times as much for reachability nothing uses is the kind of default worth
# questioning.
#
# There are consequently no public subnets and no internet gateway: nothing lives in
# them once the NAT is gone. Adding either back is a few lines if a bastion or general
# egress is ever needed.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # Both required for the interface endpoint's private DNS to resolve
  # cognito-idp.<region>.amazonaws.com to the in-VPC ENI.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# Two AZs because RDS requires a subnet group spanning at least two, even for a
# single-AZ instance.
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.project}-private-${local.azs[count.index]}" }
}

# No default route. Nothing in these subnets reaches the internet, by design.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# MARK: Security groups
#
# The database accepts traffic only from the App Runner connector's group, by group
# reference rather than by CIDR, so the rule stays correct if subnets are renumbered.

resource "aws_security_group" "app_runner" {
  name        = "${var.project}-apprunner"
  description = "Egress for the App Runner VPC connector"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Postgres to the database"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "HTTPS to the Cognito interface endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "${var.project}-apprunner" }
}

resource "aws_security_group" "database" {
  name        = "${var.project}-database"
  description = "Postgres, reachable only from the application"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from App Runner only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_runner.id]
  }

  tags = { Name = "${var.project}-database" }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-endpoints"
  description = "HTTPS to interface endpoints from the application"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from App Runner"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app_runner.id]
  }

  tags = { Name = "${var.project}-endpoints" }
}

# The one route out of the VPC: Cognito's JWKS, so the resource server can verify
# token signatures.

# Interface endpoints are not offered in every availability zone, and the set differs
# per service and per region -- cognito-idp in us-east-1 covers b, c and d but not a.
# Hardcoding a subnet index fails with "does not support the availability zone of the
# subnet", which names the subnet rather than the reason. Asking the service which
# AZs it supports and intersecting with our own subnets is both self-correcting and a
# clearer statement of the actual constraint.
data "aws_vpc_endpoint_service" "cognito_idp" {
  service_name = "com.amazonaws.${var.region}.cognito-idp"
}

locals {
  endpoint_capable_subnets = [
    for subnet in aws_subnet.private : subnet.id
    if contains(data.aws_vpc_endpoint_service.cognito_idp.availability_zones, subnet.availability_zone)
  ]
}

# One subnet rather than all of them: an interface endpoint bills per ENI per hour, so
# additional AZs double the cost for redundancy this deployment does not need. Private
# DNS still resolves from the other subnet, at a fraction of a cent in cross-AZ
# transfer. Production would use every capable subnet.
resource "aws_vpc_endpoint" "cognito_idp" {
  vpc_id              = aws_vpc.main.id
  service_name        = data.aws_vpc_endpoint_service.cognito_idp.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(local.endpoint_capable_subnets, 0, 1)
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  lifecycle {
    precondition {
      condition     = length(local.endpoint_capable_subnets) > 0
      error_message = "No private subnet sits in an AZ that offers the cognito-idp endpoint. Move the subnets into ${join(", ", data.aws_vpc_endpoint_service.cognito_idp.availability_zones)}."
    }
  }

  tags = { Name = "${var.project}-cognito-idp" }
}
