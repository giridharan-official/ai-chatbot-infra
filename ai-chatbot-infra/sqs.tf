# AWS SQS for Asynchronous Message Processing
# Used for background jobs, analytics processing, and model training tasks

# Main SQS Queue for chat processing
resource "aws_sqs_queue" "chat_processing" {
  name                       = "${var.project_name}-chat-processing.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 86400  # 24 hours

  # Visibility timeout (how long a message is invisible after being received)
  visibility_timeout_seconds = 300  # 5 minutes

  # Long polling
  receive_wait_time_seconds = 10

  tags = {
    Project = var.project_name
    Purpose = "chat-processing-queue"
  }
}

# Dead Letter Queue for failed messages
resource "aws_sqs_queue" "chat_processing_dlq" {
  name                       = "${var.project_name}-chat-processing-dlq.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 604800  # 7 days

  tags = {
    Project = var.project_name
    Purpose = "chat-processing-dlq"
  }
}

# Associate DLQ with main queue
resource "aws_sqs_queue_redrive_policy" "chat_processing" {
  queue_url = aws_sqs_queue.chat_processing.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.chat_processing_dlq.arn
    maxReceiveCount     = 3  # Move to DLQ after 3 failed attempts
  })
}

# Analytics SQS Queue
resource "aws_sqs_queue" "analytics" {
  name                       = "${var.project_name}-analytics.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 604800  # 7 days

  visibility_timeout_seconds = 600  # 10 minutes
  receive_wait_time_seconds  = 10

  tags = {
    Project = var.project_name
    Purpose = "analytics-queue"
  }
}

# Analytics DLQ
resource "aws_sqs_queue" "analytics_dlq" {
  name                       = "${var.project_name}-analytics-dlq.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 604800

  tags = {
    Project = var.project_name
    Purpose = "analytics-dlq"
  }
}

resource "aws_sqs_queue_redrive_policy" "analytics" {
  queue_url = aws_sqs_queue.analytics.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.analytics_dlq.arn
    maxReceiveCount     = 3
  })
}

# Model Training Queue
resource "aws_sqs_queue" "model_training" {
  name                       = "${var.project_name}-model-training.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 86400

  visibility_timeout_seconds = 3600  # 1 hour (model training takes time)
  receive_wait_time_seconds  = 10

  tags = {
    Project = var.project_name
    Purpose = "model-training-queue"
  }
}

# Model Training DLQ
resource "aws_sqs_queue" "model_training_dlq" {
  name                       = "${var.project_name}-model-training-dlq.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds   = 604800

  tags = {
    Project = var.project_name
    Purpose = "model-training-dlq"
  }
}

resource "aws_sqs_queue_redrive_policy" "model_training" {
  queue_url = aws_sqs_queue.model_training.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.model_training_dlq.arn
    maxReceiveCount     = 2  # More strict for training jobs
  })
}

# IAM Policy for Workers to access SQS
resource "aws_iam_policy" "sqs_worker_policy" {
  name        = "${var.project_name}-sqs-worker-policy"
  description = "Policy for worker pods to access SQS queues"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          aws_sqs_queue.chat_processing.arn,
          aws_sqs_queue.analytics.arn,
          aws_sqs_queue.model_training.arn,
          aws_sqs_queue.chat_processing_dlq.arn,
          aws_sqs_queue.analytics_dlq.arn,
          aws_sqs_queue.model_training_dlq.arn
        ]
      }
    ]
  })
}

# CloudWatch Alarms for Chat Processing Queue
resource "aws_cloudwatch_metric_alarm" "chat_queue_messages" {
  alarm_name          = "${var.project_name}-chat-queue-high-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Alert when chat processing queue has too many messages"
  alarm_actions       = [aws_sns_topic.sqs_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.chat_processing.name
  }
}

# CloudWatch Alarm for DLQ messages
resource "aws_cloudwatch_metric_alarm" "chat_dlq_messages" {
  alarm_name          = "${var.project_name}-chat-dlq-has-messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when messages are in DLQ (failures detected)"
  alarm_actions       = [aws_sns_topic.sqs_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.chat_processing_dlq.name
  }
}

# SNS topic for SQS alerts
resource "aws_sns_topic" "sqs_alerts" {
  name = "${var.project_name}-sqs-alerts"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_policy" "sqs_alerts" {
  arn = aws_sns_topic.sqs_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.sqs_alerts.arn
      }
    ]
  })
}

# Outputs
output "chat_processing_queue_url" {
  value       = aws_sqs_queue.chat_processing.id
  description = "URL of chat processing queue"
}

output "chat_processing_queue_arn" {
  value       = aws_sqs_queue.chat_processing.arn
  description = "ARN of chat processing queue"
}

output "analytics_queue_url" {
  value       = aws_sqs_queue.analytics.id
  description = "URL of analytics queue"
}

output "model_training_queue_url" {
  value       = aws_sqs_queue.model_training.id
  description = "URL of model training queue"
}

output "sqs_worker_policy_arn" {
  value       = aws_iam_policy.sqs_worker_policy.arn
  description = "ARN of SQS worker policy"
}

output "sqs_alerts_topic_arn" {
  value       = aws_sns_topic.sqs_alerts.arn
  description = "SNS topic for SQS alerts"
}
