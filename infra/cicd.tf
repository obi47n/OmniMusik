# Deployment identity for CI.
#
# GitHub Actions authenticates through OIDC and assumes this role, so no long-lived
# AWS access key is ever stored as a repository secret. A leaked static key is the
# single most common way a personal AWS account gets drained; a federated role that
# only this repository can assume removes the thing there is to leak.
#
# Guarded by `github_repository` because the stack has to apply before the repo has a
# remote. Leave it empty and none of this is created; set it later and re-apply.

variable "github_repository" {
  description = "owner/repo that may assume the deploy role, e.g. \"obi47n/OmniMusik\". Empty disables CI deployment entirely."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Whether to create the GitHub OIDC provider. An AWS account can only have one, so
    set this false if the account already has it from another project -- Terraform
    would otherwise fail on a duplicate it did not create.
  EOT
  type        = bool
  default     = true
}

locals {
  ci_enabled = var.github_repository != ""
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.ci_enabled && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.ci_enabled && !var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = local.ci_enabled ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  ) : ""
}

data "aws_iam_policy_document" "github_assume" {
  count = local.ci_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to this repository. Without this condition any GitHub repository in the
    # world could assume the role -- the most consequential line in the file.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count = local.ci_enabled ? 1 : 0

  name               = "${var.project}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

data "aws_iam_policy_document" "github_deploy" {
  count = local.ci_enabled ? 1 : 0

  statement {
    sid       = "PushContainerImages"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # This action does not support resource scoping
  }

  statement {
    sid = "WriteToThisRepositoryOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  statement {
    sid       = "PublishWebClient"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.web.arn, "${aws_s3_bucket.web.arn}/*"]
  }

  statement {
    sid       = "InvalidateCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.web.arn]
  }

  # Deliberately absent: any ability to change infrastructure. CI publishes
  # artifacts; Terraform changes the stack, and that stays a deliberate local action.
  # Rolling out the API is one update call, but the script that makes it looks every
  # input up by name first, so the role needs to *read* the things it names. All
  # read-only except the update itself and PassRole -- and PassRole is scoped to the
  # three ECS roles, because a role that can pass any role can become any role.
  statement {
    sid = "RollOutApi"
    actions = [
      "ecs:UpdateExpressGatewayService",
      "ecs:DescribeExpressGatewayService",
      "ecs:ListServices",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # Express services and task definitions do not scope cleanly yet
  }

  statement {
    sid     = "PassEcsRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.ecs_task.arn,
      aws_iam_role.ecs_infrastructure.arn,
    ]
  }

  statement {
    sid = "ResolveDeployInputsByName"
    actions = [
      "iam:GetRole",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ecr:DescribeRepositories",
      "rds:DescribeDBInstances",
      "secretsmanager:ListSecrets",
      "cognito-idp:ListUserPools",
      "cloudfront:ListDistributions",
    ]
    resources = ["*"] # Describe/List actions are not resource-scoped
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count = local.ci_enabled ? 1 : 0

  name   = "${var.project}-github-deploy"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
