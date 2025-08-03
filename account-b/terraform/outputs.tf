output "security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds_cross_account_access.id
}

output "security_group_name" {
  description = "Name of the RDS security group"
  value       = aws_security_group.rds_cross_account_access.name
}

output "security_group_arn" {
  description = "ARN of the RDS security group"
  value       = aws_security_group.rds_cross_account_access.arn
}

output "vpc_id" {
  description = "VPC ID where the security group is deployed"
  value       = var.vpc_id
}

output "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access RDS"
  value       = [var.account_a_vpc_cidr]
}
