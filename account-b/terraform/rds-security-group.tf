variable "vpc_id" {
  description = "VPC ID where RDS is deployed"
  type        = string
}

variable "account_a_vpc_cidr" {
  description = "CIDR block of Account A VPC"
  type        = string
  default     = "10.0.0.0/16"
}

resource "aws_security_group" "rds_cross_account_access" {
  name        = "rds-cross-account-access-sg"
  description = "Security group for RDS allowing cross-account Lambda access"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow PostgreSQL from Account A Lambda"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.account_a_vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "rds-cross-account-access-sg"
    Environment = "production"
    Purpose     = "Cross-account RDS access"
  }
}

output "security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds_cross_account_access.id
}

output "security_group_name" {
  description = "Name of the RDS security group"
  value       = aws_security_group.rds_cross_account_access.name
}
