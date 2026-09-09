terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State is local by default so this can be read and reasoned about without an
  # existing bucket. A shared deployment should move it to S3 with DynamoDB
  # locking before a second person ever runs apply.
  # backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "OmniMusik"
      ManagedBy = "Terraform"
    }
  }
}
