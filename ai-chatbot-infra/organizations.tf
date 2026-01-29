# AWS Organizations - Multi-Account Management
# Creates organizational structure with dev, staging, prod, and security accounts

# Enable AWS Organizations
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "securityhub.amazonaws.com",
    "guardduty.amazonaws.com"
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY"
  ]

  feature_set = "ALL"
}

# Organization Root
locals {
  organization_root_id = aws_organizations_organization.main.roots[0].id
}

# Development OU
resource "aws_organizations_organizational_unit" "dev" {
  name      = "Development"
  parent_id = local.organization_root_id

  tags = {
    Environment = "dev"
    Project     = var.project_name
  }
}

# Staging OU
resource "aws_organizations_organizational_unit" "staging" {
  name      = "Staging"
  parent_id = local.organization_root_id

  tags = {
    Environment = "staging"
    Project     = var.project_name
  }
}

# Production OU
resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = local.organization_root_id

  tags = {
    Environment = "prod"
    Project     = var.project_name
  }
}

# Security OU
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.organization_root_id

  tags = {
    Environment = "security"
    Project     = var.project_name
  }
}

# Development AWS Account
resource "aws_organizations_account" "dev" {
  name              = "${var.project_name}-dev"
  email             = var.aws_account_email_dev
  parent_id         = aws_organizations_organizational_unit.dev.id
  close_on_deletion = false
  
  tags = {
    Environment = "dev"
    Project     = var.project_name
    AccountType = "Workload"
  }
}

# Staging AWS Account
resource "aws_organizations_account" "staging" {
  name              = "${var.project_name}-staging"
  email             = var.aws_account_email_staging
  parent_id         = aws_organizations_organizational_unit.staging.id
  close_on_deletion = false
  
  tags = {
    Environment = "staging"
    Project     = var.project_name
    AccountType = "Workload"
  }
}

# Production AWS Account
resource "aws_organizations_account" "prod" {
  name              = "${var.project_name}-prod"
  email             = var.aws_account_email_prod
  parent_id         = aws_organizations_organizational_unit.production.id
  close_on_deletion = false
  
  tags = {
    Environment = "prod"
    Project     = var.project_name
    AccountType = "Workload"
  }
}

# Security/Audit AWS Account
resource "aws_organizations_account" "security" {
  name              = "${var.project_name}-security"
  email             = var.aws_account_email_security
  parent_id         = aws_organizations_organizational_unit.security.id
  close_on_deletion = false
  
  tags = {
    Environment = "security"
    Project     = var.project_name
    AccountType = "Security"
  }
}

# Organization CloudTrail for centralized logging
resource "aws_cloudtrail" "organization" {
  name                          = "${var.project_name}-org-trail"
  s3_bucket_name                = aws_s3_bucket.org_trail_logs.id
  is_multi_region_trail         = true
  include_global_service_events = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  
  depends_on                    = [aws_s3_bucket_policy.org_trail_logs]

  tags = {
    Project = var.project_name
    Purpose = "organization-trail"
  }
}

# S3 bucket for organization CloudTrail logs
resource "aws_s3_bucket" "org_trail_logs" {
  bucket = "${var.project_name}-org-trail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = var.project_name
    Purpose = "org-trail-logs"
  }
}

# Block public access to trail bucket
resource "aws_s3_bucket_public_access_block" "org_trail_logs" {
  bucket = aws_s3_bucket.org_trail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "org_trail_logs" {
  bucket = aws_s3_bucket.org_trail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "org_trail_logs" {
  bucket = aws_s3_bucket.org_trail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.org_trail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.org_trail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# NOTE: data.aws_caller_identity.current is defined in cloudtrail.tf

# Outputs
output "organization_id" {
  value       = aws_organizations_organization.main.id
  description = "AWS Organization ID"
}

output "organization_arn" {
  value       = aws_organizations_organization.main.arn
  description = "AWS Organization ARN"
}

output "root_id" {
  value       = local.organization_root_id
  description = "Organization Root ID"
}

output "dev_account_id" {
  value       = aws_organizations_account.dev.id
  description = "Development AWS Account ID"
}

output "staging_account_id" {
  value       = aws_organizations_account.staging.id
  description = "Staging AWS Account ID"
}

output "prod_account_id" {
  value       = aws_organizations_account.prod.id
  description = "Production AWS Account ID"
}

output "security_account_id" {
  value       = aws_organizations_account.security.id
  description = "Security/Audit AWS Account ID"
}

output "dev_ou_id" {
  value       = aws_organizations_organizational_unit.dev.id
  description = "Development OU ID"
}

output "staging_ou_id" {
  value       = aws_organizations_organizational_unit.staging.id
  description = "Staging OU ID"
}

output "prod_ou_id" {
  value       = aws_organizations_organizational_unit.production.id
  description = "Production OU ID"
}

output "security_ou_id" {
  value       = aws_organizations_organizational_unit.security.id
  description = "Security OU ID"
}
