# Networking.
#
# App Runner itself is public and AWS-managed, but reaching a private database means
# attaching a VPC connector -- and a VPC connector routes *all* the service's outbound
# traffic through the VPC. That is the detail worth knowing: once it is attached, the
# service can no longer reach Cognito's JWKS endpoint without a route to the internet,
# and token validation starts failing with a timeout that looks nothing like a
# networking problem.
#
# Hence the NAT gateway. There is exactly one, in a single AZ, which is a deliberate
# cost tradeoff for a portfolio deployment: a second NAT would remove a single point
# of failure for outbound traffic and roughly double that line of the bill. In
# production this would be one per AZ. The cheaper alternative is an interface VPC
# endpoint for cognito-idp, which avoids NAT for that one call.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.project}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.project}-private-${local.azs[count.index]}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project}-nat" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = { Name = "${var.project}-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project}-private" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security groups.
#
# The database accepts traffic only from the App Runner connector's group, by group
# reference rather than by CIDR. Referencing the group means the rule keeps being
# correct if the subnets are ever renumbered.

resource "aws_security_group" "app_runner" {
  name        = "${var.project}-apprunner"
  description = "Egress for the App Runner VPC connector"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound, so the service can reach the database and Cognito"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
