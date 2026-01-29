# GitHub Actions OIDC Role - CORRECTED VERSION 2
# This version uses proper variable references instead of hardcoding

terraform {

}




# Create OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# Local variables for easier reference
locals {
  github_org  = "BhuvaneshSSB"
  github_repo = "ai-chatbot-code-infra"
}

# IAM Role for GitHub Actions - Using proper variable reference
resource "aws_iam_role" "github_actions" {
  name = "GitHubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Use the actual OIDC provider ARN, not a string
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_org}/${local.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "github-actions-role"
  }
}

# Policy for ECR Access - Split into 2 statements for clarity
resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "arn:aws:ecr:ap-south-1:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

# Output the role ARN for reference
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "ARN of GitHub Actions OIDC role"
}

output "github_actions_role_name" {
  value       = aws_iam_role.github_actions.name
  description = "Name of GitHub Actions OIDC role"
}

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS Account ID"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "ARN of GitHub OIDC provider"
}

output "trust_policy" {
  value       = aws_iam_role.github_actions.assume_role_policy
  description = "Trust policy for reference"
  sensitive   = false
}
