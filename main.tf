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

resource "aws_ecr_repository" "platform" {
  name                 = "v3.cash/platform"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Owner = var.aws_profile
  }
}

resource "aws_kms_key" "s3-state-key" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}
locals {
  bucket_name = "v3-cash-${var.aws_profile}-terraform-state"
  backups_bucket = "v3-cash-${var.aws_profile}-backup"
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = local.bucket_name
  acl    = "log-delivery-write"
  block_public_acls = true
  block_public_policy = true
  restrict_public_buckets = true
  ignore_public_acls = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3-state-key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning = {
    enabled = true
  }

  tags = {
    "Owner" = var.aws_profile
  }

  logging = {
    target_bucket = local.bucket_name
    target_prefix = "logs/"
  }

}

module "backups_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = local.backups_bucket
  acl    = "log-delivery-write"
  block_public_acls = true
  block_public_policy = true
  restrict_public_buckets = true
  ignore_public_acls = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3-state-key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning = {
    enabled = true
  }

  tags = {
    "Owner" = var.aws_profile
  }

  logging = {
    target_bucket = local.bucket_name
    target_prefix = "logs/"
  }

}

resource "aws_dynamodb_table" "infra_state_lock" {
  name           = "v3-cash-${var.aws_profile}-infra-state-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
     Owner = var.aws_profile
  }
}

resource "aws_iam_user" "platform-ci-user" {
  name = "platform_ci@v3.cash"
  tags = {
    Owner = var.aws_profile
  }
}

resource "aws_iam_policy" "platform-ci-policy" {
  name        = "platform-ci-policy"
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
        Resource = [aws_ecr_repository.platform.arn]
      }
    ]
  })
}

resource "aws_iam_policy" "ecr-base-policy" {
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

resource "aws_iam_user_policy_attachment" "ecr-base-policy-attach-ci-user" {
  user       = aws_iam_user.platform-ci-user.name
  policy_arn = aws_iam_policy.ecr-base-policy.arn
}

resource "aws_iam_user_policy_attachment" "ecr-platform-ci-policy-attach-ci-user" {
  user       = aws_iam_user.platform-ci-user.name
  policy_arn = aws_iam_policy.platform-ci-policy.arn
}

