terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.5.0"
    }
  }

  required_version = ">= 1.1.0"
}

terraform {
  backend "local" {
    path = "state/devops.state"
  }
}

locals {
  src_location = "devops/main.tf"
}



provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "platform" {
  name                 = "platform"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    owner        = "devops"
    src_location = local.src_location
  }
  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_kms_key" "s3-state-key" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}
locals {
  bucket_name    = "hamilton-pay-infra-state"
  backups_bucket = "hamilton-pay-infra-backup"
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                  = local.bucket_name
  acl                     = "log-delivery-write"
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
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
    "owner"      = "devops"
    src_location = local.src_location

  }

  logging = {
    target_bucket = local.bucket_name
    target_prefix = "logs/"
  }

}

module "backups_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                  = local.backups_bucket
  acl                     = "log-delivery-write"
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
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
    owner        = "devops"
    src_location = local.src_location

  }

  logging = {
    target_bucket = local.bucket_name
    target_prefix = "logs/"
  }

}

resource "aws_dynamodb_table" "state_lock" {
  name         = "infra-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    owner = "devops"
  }
}

resource "aws_iam_user" "platform-ci-user" {
  name = "platform_ci@v3.cash"
  tags = {
    owner        = "devops"
    src_location = local.src_location

  }
}

resource "aws_iam_policy" "platform-ci-policy" {
  name        = "platform-ci-policy"
  description = "iam policy to create platform container images"
  tags = {
    owner        = "devops"
    src_location = local.src_location

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
          "ecr:BatchDeleteImage",
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
    owner        = "devops"
    src_location = local.src_location

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

resource "aws_iam_policy" "ecs-base-policy" {
  name        = "ecs-base-ci-policy"
  description = "iam policy to get authorization for ecr"
  tags = {
    owner        = "devops"
    src_location = local.src_location

  }
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecs:ListTaskDefinitionFamilies",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

}

# resource "aws_iam_policy" "ecs-platform-policy" {
#   name        = "ecs-platform-ci-policy"
#   description = "iam policy to get authorization for ecr"
#   tags = {
#     owner        = "devops"
#     src_location = local.src_location

#   }
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = [
#           "ecs:RegisterTaskDefinition"
#         ]
#         Effect   = "Allow"
#         Resource = "*"
#       }
#     ]
#   })

# }

resource "aws_iam_user_policy_attachment" "ecs-platform-policy-attach-ci-user" {
  user       = aws_iam_user.platform-ci-user.name
  policy_arn = aws_iam_policy.ecs-base-policy.arn
}

resource "aws_iam_user_policy_attachment" "ecr-base-policy-attach-ci-user" {
  user       = aws_iam_user.platform-ci-user.name
  policy_arn = aws_iam_policy.ecr-base-policy.arn
}
resource "aws_iam_user_policy_attachment" "ecr-platform-ci-policy-attach-ci-user" {
  user       = aws_iam_user.platform-ci-user.name
  policy_arn = aws_iam_policy.platform-ci-policy.arn
}

resource "aws_iam_policy" "opslyft-readonly-policy" {
  name        = "opslyftReadOnlyPolicy"
  description = "Read only access policy for EC2, RDS, ECS, R53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Get*",
          "ec2:Describe*",
          "ec2:List*",
          "rds:Describe*",
          "rds:List*",
          "route53:Get*",
          "route53:List*",
          "ecs:List*",
          "ecs:Describe*",
          "elasticloadbalancing:Describe*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "opslyft-readonly-role" {
  name="opslyftReadOnlyRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid="AssumeRole"
        Action = "sts:AssumeRole"
        Effect   = "Allow"
        Principal = {"AWS": "arn:aws:iam::${var.opslyft_account_id}:root"}
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "opslyft-attach" {
  role       = aws_iam_role.opslyft-readonly-role.name
  policy_arn = aws_iam_policy.opslyft-readonly-policy.arn
}


data "aws_vpc" "default_vpc" {
  default = true
}


resource "aws_secretsmanager_secret" "stripe" {
  name = "stripe"
  tags = {
    owner        = "devops"
    src_location = local.src_location
  }
}

resource "aws_secretsmanager_secret" "plaid" {
  name = "plaid"
  tags = {
    owner        = "devops"
    src_location = local.src_location
  }
}

resource "aws_secretsmanager_secret" "cloudfare" {
  name = "cloudfare"
  tags = {
    owner        = "devops"
    src_location = local.src_location
  }
}



resource "aws_secretsmanager_secret" "mailgun" {
  name = "mailgun"
  tags = {
    owner        = "devops"
    src_location = local.src_location
  }
}

resource "aws_secretsmanager_secret_version" "cloudfare" {
  secret_id     = aws_secretsmanager_secret.cloudfare.id
  secret_string = jsonencode(var.cloudfare_secrets)
}

resource "aws_secretsmanager_secret_version" "mailgun" {
  secret_id     = aws_secretsmanager_secret.mailgun.id
  secret_string = jsonencode(var.mailgun_secrets)
}

resource "aws_secretsmanager_secret_version" "stripe" {
  secret_id     = aws_secretsmanager_secret.stripe.id
  secret_string = jsonencode(var.stripe_secrets)
}
resource "aws_secretsmanager_secret_version" "plaid" {
  secret_id     = aws_secretsmanager_secret.plaid.id
  secret_string = jsonencode(var.plaid_secrets)
}