resource "aws_security_group" "rds_cross_account_access" {
  name_prefix = "${var.project_name}-rds-cross-account-"
  description = "Security group for RDS allowing cross-account Lambda access"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow PostgreSQL from Account A Lambda"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.account_a_vpc_cidr]
  }

  # Explicitly deny all other inbound traffic
  # (AWS does this by default, but being explicit for clarity)

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-rds-cross-account-sg"
    Environment = var.environment
    Purpose     = "Cross-account RDS access"
    ManagedBy   = "Terraform"
    Project     = var.project_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Log Group for security group flow logs (optional but recommended)
resource "aws_cloudwatch_log_group" "sg_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}-rds-sg"
  retention_in_days = 30
  
  tags = merge(var.tags, {
    Name        = "${var.project_name}-rds-sg-flow-logs"
    Environment = var.environment
    Purpose     = "Security group flow logs"
    ManagedBy   = "Terraform"
  })
}

# VPC Flow Logs for the security group (optional but recommended for monitoring)
resource "aws_flow_log" "rds_sg_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.sg_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = var.vpc_id
  
  tags = merge(var.tags, {
    Name        = "${var.project_name}-rds-sg-flow-log"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_log_role" {
  name_prefix = "${var.project_name}-flow-log-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-flow-log-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# IAM policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log_policy" {
  name_prefix = "${var.project_name}-flow-log-"
  role        = aws_iam_role.flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
