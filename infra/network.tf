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
# The database accepts traffic only from the API tasks' group, by group reference
# rather than by CIDR, so the rule stays correct if subnets are renumbered.

resource "aws_security_group" "database" {
  name        = "${var.project}-database"
  description = "Postgres, reachable only from the application"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from the API tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_tasks.id]
  }

  tags = { Name = "${var.project}-database" }
}
