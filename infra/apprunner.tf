# The service.
#
# App Runner rather than ECS Fargate, chosen against a fixed deadline. Fargate means
# hand-wiring an ALB, target groups, task definitions and autoscaling policies -- days
# that do not buy proportional signal on a project this size. The container pipeline,
# the private networking and the IAM boundaries are all still here; what is gone is
# the orchestration boilerplate.
#
# Where this would change: sustained traffic, a need for sidecars, or anything
# requiring fine-grained deployment control. Then Fargate, with this VPC unchanged.

resource "aws_ecr_repository" "api" {
  name                 = "${var.project}-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # A portfolio stack should destroy cleanly rather than stranding a repository that
  # still holds images.
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the ten most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# App Runner needs two distinct roles, and conflating them is a common mistake:
# the access role is assumed by the build side to pull from ECR, while the instance
# role is what the running container itself uses to reach other AWS services.

data "aws_iam_policy_document" "apprunner_access_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_access" {
  name               = "${var.project}-apprunner-access"
  assume_role_policy = data.aws_iam_policy_document.apprunner_access_assume.json
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

data "aws_iam_policy_document" "apprunner_instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_instance" {
  name               = "${var.project}-apprunner-instance"
  assume_role_policy = data.aws_iam_policy_document.apprunner_instance_assume.json
}

data "aws_iam_policy_document" "read_database_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.database.arn]
  }
}

resource "aws_iam_role_policy" "apprunner_secrets" {
  name   = "${var.project}-read-database-secret"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.read_database_secret.json
}

resource "aws_apprunner_vpc_connector" "main" {
  vpc_connector_name = "${var.project}-connector"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.app_runner.id]
}

resource "aws_apprunner_service" "api" {
  service_name = "${var.project}-api"

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }

    image_repository {
      image_identifier      = "${aws_ecr_repository.api.repository_url}:${var.container_image_tag}"
      image_repository_type = "ECR"

      image_configuration {
        port = "8080"

        runtime_environment_variables = {
          SPRING_PROFILES_ACTIVE = "prod"
          DB_HOST                = aws_db_instance.main.address
          DB_PORT                = tostring(aws_db_instance.main.port)
          DB_NAME                = aws_db_instance.main.db_name
          DB_USER                = aws_db_instance.main.username
          ALLOWED_ORIGINS        = var.web_origin
          COGNITO_ISSUER_URI     = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
        }

        # The password is injected from Secrets Manager at start, so it never
        # appears in the service configuration or in the Terraform state's plan
        # output as an environment variable.
        runtime_environment_secrets = {
          DB_PASSWORD = "${aws_secretsmanager_secret.database.arn}:password::"
        }
      }
    }

    auto_deployments_enabled = true
  }

  instance_configuration {
    cpu               = var.app_runner_cpu
    memory            = var.app_runner_memory
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.main.arn
    }
  }

  health_check_configuration {
    protocol = "HTTP"
    # Spring Boot's liveness probe, which SecurityConfig leaves unauthenticated --
    # a health check that needs a token can never report healthy.
    path                = "/actuator/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  depends_on = [aws_secretsmanager_secret_version.database]
}
