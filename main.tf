terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 1.1.0"
}

terraform {
  backend "s3" {
  }
}


provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

resource "aws_ecr_repository" "v3_cash_platform" {
  name                 = "v3.cash/platform"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Owner = var.aws_profile
  }
}

resource "aws_iam_user" "v3_cash_platform_ci_user" {
  name = "platform_ci@v3.cash"
  tags = {
    Owner = var.aws_profile
  }
}

resource "aws_iam_policy" "v3_cash_platform_ci_policy" {
  name        = "v3-cash-platform-ci-policy"
  description = "iam policy to create platform container images"
  tags = {
    Owner = var.aws_profile
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Effect   = "Allow"
        Resource = [aws_ecr_repository.v3_cash_platform.arn]
      }
    ]
  })
}

resource "aws_iam_policy" "ecr_base_policy" {
  name        = "ecr-base-policy"
  description = "iam policy to get authorization for ecr"
  tags = {
    Owner = var.aws_profile
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}


