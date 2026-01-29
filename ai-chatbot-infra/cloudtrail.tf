# CloudTrail for audit logging
# Logs all AWS API calls for compliance and security monitoring

# CloudTrail KMS key
resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for CloudTrail encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:DecryptDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = var.project_name
    Purpose = "cloudtrail-encryption"
  }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/${var.project_name}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# IAM role for CloudTrail to write logs to CloudWatch
resource "aws_iam_role" "cloudtrail_role" {
  name = "${var.project_name}-cloudtrail-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM policy for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloudtrail/${var.project_name}:*"
      }
    ]
  })
}

# CloudWatch Logs group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 30

  tags = {
    Project = var.project_name
    Purpose = "cloudtrail-logs"
  }
}

# CloudTrail trail
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = false
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_role.arn
  

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_cloudwatch_log_group.cloudtrail
  ]

  tags = {
    Project = var.project_name
    Purpose = "audit-trail"
  }
}

# SNS topic for CloudTrail alarms
resource "aws_sns_topic" "cloudtrail_alarms" {
  name = "${var.project_name}-cloudtrail-alarms"

  tags = {
    Project = var.project_name
  }
}

# SNS topic policy to allow CloudWatch to publish
resource "aws_sns_topic_policy" "cloudtrail_alarms" {
  arn = aws_sns_topic.cloudtrail_alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cloudtrail_alarms.arn
      }
    ]
  })
}

# Get current AWS account ID (shared data source for all modules)
data "aws_caller_identity" "current" {}

# Outputs
output "cloudtrail_name" {
  value       = aws_cloudtrail.main.name
  description = "Name of the CloudTrail trail"
}

output "cloudtrail_log_group" {
  value       = aws_cloudwatch_log_group.cloudtrail.name
  description = "CloudWatch Logs group for CloudTrail"
}

output "cloudtrail_alarms_topic" {
  value       = aws_sns_topic.cloudtrail_alarms.arn
  description = "SNS topic for CloudTrail alarms"
}
