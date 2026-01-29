# Cross-Account IAM Roles
# Allows management account to access and manage workload accounts

# Role in management account to assume roles in workload accounts
resource "aws_iam_role" "management_cross_account" {
  name = "${var.project_name}-management-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "cross-account-access"
  }
}

# Policy for management role to assume workload account roles
resource "aws_iam_role_policy" "management_cross_account_assume" {
  name = "${var.project_name}-assume-workload-roles"
  role = aws_iam_role.management_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${aws_organizations_account.dev.id}:role/OrganizationAccountAccessRole",
          "arn:aws:iam::${aws_organizations_account.staging.id}:role/OrganizationAccountAccessRole",
          "arn:aws:iam::${aws_organizations_account.prod.id}:role/OrganizationAccountAccessRole",
          "arn:aws:iam::${aws_organizations_account.security.id}:role/OrganizationAccountAccessRole"
        ]
      }
    ]
  })
}

# CloudFormation stack set for cross-account access
# This ensures all accounts have proper roles for federation

# CloudFormation role in management account
resource "aws_iam_role" "cloudformation_stackset" {
  name = "${var.project_name}-cloudformation-stackset-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "cloudformation-stackset"
  }
}

# Policy for CloudFormation to create stacks in other accounts
resource "aws_iam_role_policy" "cloudformation_stackset_policy" {
  name = "${var.project_name}-cloudformation-stackset-policy"
  role = aws_iam_role.cloudformation_stackset.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole"
      }
    ]
  })
}

# Lambda execution role for cross-account operations
resource "aws_iam_role" "lambda_cross_account" {
  name = "${var.project_name}-lambda-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "lambda-cross-account"
  }
}

# Policy for Lambda to assume roles in other accounts
resource "aws_iam_role_policy" "lambda_cross_account_assume" {
  name = "${var.project_name}-lambda-assume-workload"
  role = aws_iam_role.lambda_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${aws_organizations_account.dev.id}:role/LambdaCrossAccountRole",
          "arn:aws:iam::${aws_organizations_account.staging.id}:role/LambdaCrossAccountRole",
          "arn:aws:iam::${aws_organizations_account.prod.id}:role/LambdaCrossAccountRole"
        ]
      }
    ]
  })
}

# Policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_cross_account.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Outputs
output "management_cross_account_role_arn" {
  value       = aws_iam_role.management_cross_account.arn
  description = "Management account cross-account role ARN"
}

output "cloudformation_stackset_role_arn" {
  value       = aws_iam_role.cloudformation_stackset.arn
  description = "CloudFormation StackSet role ARN"
}

output "lambda_cross_account_role_arn" {
  value       = aws_iam_role.lambda_cross_account.arn
  description = "Lambda cross-account role ARN"
}
