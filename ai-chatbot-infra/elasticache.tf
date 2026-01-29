# ElastiCache Redis for Caching
# Used for session management, conversation context, and bot configurations

# Subnet group for ElastiCache
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Project = var.project_name
    Purpose = "redis-caching"
  }
}

# Security group for ElastiCache
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  # Allow inbound from EKS nodes
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.aws_security_group.eks_nodes.id]
    description     = "Allow Redis access from EKS nodes"
  }

  # Allow outbound to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Project = var.project_name
    Purpose = "redis-sg"
  }
}

# ElastiCache Redis cluster (single node)
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type           = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  # Maintenance window
  maintenance_window = "sun:05:00-sun:06:00"

  # Notification topic
  notification_topic_arn = aws_sns_topic.elasticache_notifications.arn

  tags = {
    Project = var.project_name
    Purpose = "session-and-cache"
  }

  depends_on = [aws_elasticache_subnet_group.redis]
}

# CloudWatch Logs group for slow log
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${var.project_name}/slow-log"
  retention_in_days = 7

  tags = {
    Project = var.project_name
    Purpose = "redis-slow-log"
  }
}

# CloudWatch Logs group for engine log
resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${var.project_name}/engine-log"
  retention_in_days = 3

  tags = {
    Project = var.project_name
    Purpose = "redis-engine-log"
  }
}

# SNS topic for ElastiCache notifications
resource "aws_sns_topic" "elasticache_notifications" {
  name = "${var.project_name}-elasticache-notifications"

  tags = {
    Project = var.project_name
  }
}

# CloudWatch alarm for evictions
resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "${var.project_name}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Alert when Redis evictions exceed threshold"
  alarm_actions       = [aws_sns_topic.elasticache_notifications.arn]

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }
}

# CloudWatch alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.project_name}-redis-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alert when Redis CPU exceeds 75%"
  alarm_actions       = [aws_sns_topic.elasticache_notifications.arn]

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }
}

# Data source to get private subnets - just get subnets in the VPC
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  # Get at least 2 subnets for ElastiCache
  filter {
    name   = "availability-zone"
    values = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  }
}

# Outputs
output "redis_endpoint" {
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  description = "Redis cluster endpoint address"
}

output "redis_port" {
  value       = aws_elasticache_cluster.redis.port
  description = "Redis cluster port"
}

output "redis_security_group_id" {
  value       = aws_security_group.redis.id
  description = "Security group ID for Redis"
}
