# Service Control Policies (SCPs) - Security Guardrails
# Preventive policies that restrict what can be done across all accounts

# SCP: Prevent root account access (except MFA)
resource "aws_organizations_policy" "deny_root_account" {
  name    = "DenyRootAccount"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootAccountActions"
        Effect = "Deny"
        NotPrincipal = {
          AWS = "arn:aws:iam::*:root"
        }
        Action = "*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:PrincipalIsAWSService" = "false"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "security-guardrail"
  }
}

# SCP: Require MFA for console access
resource "aws_organizations_policy" "require_mfa" {
  name    = "RequireMFA"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyConsoleAccessWithoutMFA"
        Effect = "Deny"
        Action = [
          "iam:*",
          "ec2:*",
          "rds:*"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "mfa-requirement"
  }
}

# SCP: Prevent deletion of CloudTrail
resource "aws_organizations_policy" "protect_cloudtrail" {
  name    = "ProtectCloudTrail"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailDeletion"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopLogging"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "cloudtrail-protection"
  }
}

# SCP: Prevent disabling SecurityHub
resource "aws_organizations_policy" "protect_security_hub" {
  name    = "ProtectSecurityHub"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenySecurityHubDisable"
        Effect = "Deny"
        Action = [
          "securityhub:DisableSecurityHub",
          "securityhub:DeleteInvitations"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "securityhub-protection"
  }
}

# SCP: Prevent public S3 bucket access
resource "aws_organizations_policy" "prevent_public_s3" {
  name    = "PreventPublicS3Access"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicS3Access"
        Effect = "Deny"
        Action = [
          "s3:PutAccountPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "s3:BlockPublicAcls" = "false"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "s3-security"
  }
}

# SCP: Restrict regions (allow only ap-south-1)
resource "aws_organizations_policy" "restrict_regions" {
  name    = "RestrictRegionsApSouth1"
  type    = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOutsideApSouth1"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = [
              "ap-south-1",
              "us-east-1"  # Allow for global services
            ]
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "region-restriction"
  }
}

# Attach SCPs to OUs
resource "aws_organizations_policy_attachment" "dev_protect_cloudtrail" {
  policy_id = aws_organizations_policy.protect_cloudtrail.id
  target_id = aws_organizations_organizational_unit.dev.id
}

resource "aws_organizations_policy_attachment" "staging_protect_cloudtrail" {
  policy_id = aws_organizations_policy.protect_cloudtrail.id
  target_id = aws_organizations_organizational_unit.staging.id
}

resource "aws_organizations_policy_attachment" "prod_protect_cloudtrail" {
  policy_id = aws_organizations_policy.protect_cloudtrail.id
  target_id = aws_organizations_organizational_unit.production.id
}

resource "aws_organizations_policy_attachment" "security_protect_cloudtrail" {
  policy_id = aws_organizations_policy.protect_cloudtrail.id
  target_id = aws_organizations_organizational_unit.security.id
}

# Outputs
output "scp_deny_root" {
  value       = aws_organizations_policy.deny_root_account.id
  description = "SCP: Deny Root Account ID"
}

output "scp_require_mfa" {
  value       = aws_organizations_policy.require_mfa.id
  description = "SCP: Require MFA ID"
}

output "scp_protect_cloudtrail" {
  value       = aws_organizations_policy.protect_cloudtrail.id
  description = "SCP: Protect CloudTrail ID"
}

output "scp_protect_securityhub" {
  value       = aws_organizations_policy.protect_security_hub.id
  description = "SCP: Protect Security Hub ID"
}

output "scp_prevent_public_s3" {
  value       = aws_organizations_policy.prevent_public_s3.id
  description = "SCP: Prevent Public S3 ID"
}

output "scp_restrict_regions" {
  value       = aws_organizations_policy.restrict_regions.id
  description = "SCP: Restrict Regions ID"
}
