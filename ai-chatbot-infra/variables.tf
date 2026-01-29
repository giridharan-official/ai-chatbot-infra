variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}



variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}















variable "aws_account_email_dev" {
  description = "Email address for development AWS account"
  type        = string
  sensitive   = true
}

variable "aws_account_email_staging" {
  description = "Email address for staging AWS account"
  type        = string
  sensitive   = true
}

variable "aws_account_email_prod" {
  description = "Email address for production AWS account"
  type        = string
  sensitive   = true
}

variable "aws_account_email_security" {
  description = "Email address for security/audit AWS account"
  type        = string
  sensitive   = true
}

# Organization settings
variable "organization_root_name" {
  description = "Name for the organization root"
  type        = string
  default     = "Organization Root"
}

variable "enable_cloudtrail_organization_trail" {
  description = "Enable CloudTrail organization trail"
  type        = bool
  default     = true
}

variable "enable_config_organization" {
  description = "Enable AWS Config for organization"
  type        = bool
  default     = true
}

