# Security Groups for AI Chatbot Services
# Manages network access between EKS, ElastiCache, and other services

# Get EKS node security group (using specific pattern)
data "aws_security_group" "eks_nodes" {
  filter {
    name   = "group-name"
    values = ["ai-chatbot-eks-node*"]
  }
}

# Additional security group for inter-pod communication
resource "aws_security_group" "eks_internal" {
  name        = "${var.project_name}-eks-internal"
  description = "Security group for internal EKS pod communication"
  vpc_id      = var.vpc_id

  # Allow pod-to-pod communication
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "Allow TCP from pods"
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
    description = "Allow UDP from pods"
  }

  # Allow HTTPS from pods
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound"
  }

  # Allow DNS (port 53)
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow DNS"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name    = "${var.project_name}-eks-internal"
    Project = var.project_name
    Purpose = "internal-communication"
  }
}

# Security group for ALB (Application Load Balancer)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # Allow HTTP from internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  # Allow HTTPS from internet
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from internet"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
    Purpose = "load-balancer"
  }
}

# Allow ALB to communicate with EKS nodes
resource "aws_security_group_rule" "alb_to_eks" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = data.aws_security_group.eks_nodes.id
  description              = "Allow ALB to communicate with EKS nodes"
}

# Allow EKS nodes to communicate with MongoDB Atlas (via internet)
resource "aws_security_group_rule" "eks_to_mongodb" {
  type              = "egress"
  from_port         = 27017
  to_port           = 27017
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.eks_nodes.id
  description       = "Allow EKS nodes to connect to MongoDB Atlas"
}

# Allow EKS nodes to access Redis
# NOTE: This rule may already exist if created by ElastiCache
# If you get a duplicate rule error, comment this out
# resource "aws_security_group_rule" "eks_to_redis" {
#   type                     = "ingress"
#   from_port                = 6379
#   to_port                  = 6379
#   protocol                 = "tcp"
#   source_security_group_id = data.aws_security_group.eks_nodes.id
#   security_group_id        = aws_security_group.redis.id
#   description              = "Allow EKS nodes to access Redis"
# }

# Outputs
output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "Security group ID for ALB"
}

output "eks_internal_security_group_id" {
  value       = aws_security_group.eks_internal.id
  description = "Security group ID for EKS internal communication"
}

output "eks_nodes_security_group_id" {
  value       = data.aws_security_group.eks_nodes.id
  description = "EKS nodes security group ID"
}
