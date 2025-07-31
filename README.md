# Cross-Account AWS Lambda to RDS PostgreSQL Connection

This repository provides a complete solution for securely connecting an AWS Lambda function in one AWS account (Account A) to an RDS PostgreSQL database in another AWS account (Account B).

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Why Cross-Account Access?](#why-cross-account-access)
- [Prerequisites](#prerequisites)
- [Security Components](#security-components)
- [Step-by-Step Setup Guide](#step-by-step-setup-guide)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Architecture Overview

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│      Account A (Lambda)     │         │    Account B (RDS)          │
│                             │         │                             │
│  ┌─────────────────────┐   │         │   ┌──────────────────────┐ │
│  │   Lambda Function   │   │         │   │  RDS PostgreSQL DB   │ │
│  │                     │   │         │   │                      │ │
│  │ 1. Read params from │   │         │   │  ┌────────────────┐  │ │
│  │    Parameter Store  │   │         │   │  │ Security Group │  │ │
│  │                     │   │  VPC    │   │  │ Ingress: 5432  │  │ │
│  │ 2. Assume role in  │◄──┼─Peering─┼───┼─►│ from Account A │  │ │
│  │    Account B       │   │         │   │  └────────────────┘  │ │
│  │                     │   │         │   │                      │ │
│  │ 3. Connect to RDS  │   │         │   └──────────────────────┘ │
│  └─────────────────────┘   │         │                             │
│                             │         │   ┌──────────────────────┐ │
│  ┌─────────────────────┐   │         │   │  Cross-Account Role │ │
│  │   Lambda IAM Role   │   │         │   │                      │ │
│  │ - SSM permissions   │   │         │   │  Trust: Account A    │ │
│  │ - STS AssumeRole   │───┼─────────┼──►│  Lambda Role         │ │
│  │ - VPC permissions  │   │         │   │                      │ │
│  └─────────────────────┘   │         │   └──────────────────────┘ │
└─────────────────────────────┘         └─────────────────────────────┘
```

## Why Cross-Account Access?

### Business Reasons
1. **Separation of Concerns**: Different teams or departments manage different AWS accounts
2. **Billing Isolation**: Separate cost tracking for applications and databases
3. **Compliance Requirements**: Data must be isolated in specific accounts for regulatory reasons
4. **Multi-Tenant Architecture**: Each customer/tenant has their own AWS account

### Technical Benefits
1. **Security Isolation**: Blast radius reduction - compromised application account doesn't directly expose database
2. **Access Control**: Granular permissions using IAM roles and temporary credentials
3. **Audit Trail**: All cross-account access is logged in CloudTrail
4. **Scalability**: Easy to add more accounts without changing the core architecture

## Prerequisites

1. **Two AWS Accounts**:
   - Account A (111111111111): Hosts the Lambda function
   - Account B (222222222222): Hosts the RDS PostgreSQL database

2. **Network Connectivity**:
   - VPCs in both accounts
   - VPC Peering or Transit Gateway connection
   - Non-overlapping CIDR blocks

3. **Tools Required**:
   - AWS CLI configured with profiles for both accounts
   - Terraform >= 1.0 (for infrastructure as code)
   - Python 3.9+ (for Lambda function)

## Security Components

### 1. IAM Roles and Trust Relationships

#### Why IAM Roles?
- **No Long-Lived Credentials**: Uses temporary credentials via STS
- **Principle of Least Privilege**: Only necessary permissions granted
- **Auditable**: All actions logged with role session information

#### Account A - Lambda Execution Role
```json
Purpose: Allows Lambda to:
- Write logs to CloudWatch
- Read parameters from Parameter Store
- Assume role in Account B
- Manage VPC network interfaces
```

#### Account B - Cross-Account Access Role
```json
Purpose: Allows Account A Lambda to:
- Describe RDS instances
- Access RDS metadata
- No direct database credentials needed
```

### 2. Security Groups

#### Why Security Groups?
- **Network-Level Security**: Controls traffic at the instance level
- **Stateful**: Return traffic automatically allowed
- **Layered Security**: Works with NACLs for defense in depth

#### Lambda Security Group (Account A)
- **Egress Rules**:
  - Port 5432 to Account B VPC CIDR (PostgreSQL)
  - Port 443 to 0.0.0.0/0 (AWS API calls)

#### RDS Security Group (Account B)
- **Ingress Rules**:
  - Port 5432 from Account A VPC CIDR only

### 3. Parameter Store

#### Why Parameter Store?
- **Encrypted Storage**: Sensitive data encrypted at rest
- **Version Control**: Track parameter changes
- **Access Control**: IAM-based permissions
- **No Hardcoded Secrets**: Credentials not in code

## Step-by-Step Setup Guide

### Step 1: Account B Setup (RDS Account)

1. **Create the Cross-Account IAM Role**:
```bash
# Create the trust policy (allows Account A to assume this role)
aws iam create-role \
  --role-name CrossAccountRDSAccessRole \
  --assume-role-policy-document file://account-b/iam/cross-account-rds-role-trust.json \
  --profile account-b
```

**Why this step?** This creates the role that Account A will assume. The trust policy ensures only the specific Lambda role from Account A can assume it.

2. **Attach the RDS Access Policy**:
```bash
# Attach permissions to describe RDS instances
aws iam put-role-policy \
  --role-name CrossAccountRDSAccessRole \
  --policy-name CrossAccountRDSPolicy \
  --policy-document file://account-b/iam/cross-account-rds-policy.json \
  --profile account-b
```

**Why this step?** The role needs permissions to describe RDS instances so the Lambda can get the database endpoint.

3. **Deploy RDS Security Group** (using Terraform):
```bash
cd account-b/terraform
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply
```

**Why this step?** The security group controls network access to the RDS instance, allowing only traffic from Account A's VPC.

### Step 2: Account A Setup (Lambda Account)

1. **Create Lambda Execution Role**:
```bash
aws iam create-role \
  --role-name LambdaExecutionRole \
  --assume-role-policy-document file://account-a/iam/lambda-execution-role.json \
  --profile account-a
```

**Why this step?** Lambda needs an execution role to run and access AWS services.

2. **Attach Lambda Execution Policy**:
```bash
aws iam put-role-policy \
  --role-name LambdaExecutionRole \
  --policy-name LambdaExecutionPolicy \
  --policy-document file://account-a/iam/lambda-execution-policy.json \
  --profile account-a
```

**Why this step?** The policy grants permissions for CloudWatch Logs, Parameter Store, STS AssumeRole, and VPC operations.

3. **Store Database Credentials in Parameter Store**:
```bash
# Store encrypted parameters
aws ssm put-parameter \
  --name "/myapp/db/username" \
  --value "postgres" \
  --type "SecureString" \
  --profile account-a

aws ssm put-parameter \
  --name "/myapp/db/password" \
  --value "your-secure-password" \
  --type "SecureString" \
  --profile account-a
```

**Why this step?** Keeps sensitive credentials out of code and provides encryption at rest.

### Step 3: Network Configuration

1. **Create VPC Peering Connection**:
```bash
# Initiate from Account A
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-accountA \
  --peer-vpc-id vpc-accountB \
  --peer-owner-id ACCOUNT_B_ID \
  --profile account-a
```

2. **Accept Peering in Account B**:
```bash
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxxxx \
  --profile account-b
```

3. **Update Route Tables** in both accounts to route traffic through the peering connection.

**Why these steps?** VPC Peering provides private network connectivity between accounts without going over the internet.

### Step 4: Deploy Lambda Function

1. **Package Lambda Function**:
```bash
cd account-a/lambda
pip install -r requirements.txt -t .
zip -r lambda-function.zip .
```

2. **Create Lambda Function**:
```bash
aws lambda create-function \
  --function-name RDSCrossAccountConnector \
  --runtime python3.9 \
  --role arn:aws:iam::ACCOUNT_A_ID:role/LambdaExecutionRole \
  --handler rds_connector.lambda_handler \
  --zip-file fileb://lambda-function.zip \
  --vpc-config SubnetIds=subnet-xxx,SecurityGroupIds=sg-xxx \
  --environment Variables="{ACCOUNT_B_ID=222222222222}" \
  --profile account-a
```

**Why this step?** Deploys the Lambda function with VPC configuration for network access to RDS.

## Troubleshooting

### Common Issues and Solutions

1. **Connection Timeout**
   - Check VPC Peering is active and routes are configured
   - Verify security group rules allow traffic on port 5432
   - Ensure Lambda is in a private subnet with NAT for AWS API calls

2. **Access Denied on AssumeRole**
   - Verify trust relationship includes correct Account A role ARN
   - Check external ID matches if configured
   - Ensure Lambda role has sts:AssumeRole permission

3. **Cannot Resolve RDS Endpoint**
   - Verify DNS resolution is enabled on VPC Peering
   - Check Route 53 resolver endpoints if using private hosted zones

4. **Parameter Store Access Denied**
   - Verify Lambda role has ssm:GetParameter permissions
   - Check parameter names match exactly
   - Ensure KMS key permissions if using custom CMK

## Security Best Practices

1. **Use External ID**: Add external ID to trust policy for additional security
2. **Enable MFA**: Require MFA for sensitive operations
3. **Rotate Credentials**: Regularly rotate database passwords
4. **Use VPC Endpoints**: For Parameter Store and STS calls
5. **Enable GuardDuty**: Monitor for unusual cross-account activity
6. **CloudTrail Logging**: Ensure all API calls are logged
7. **Least Privilege**: Only grant minimum required permissions
8. **Network Isolation**: Use private subnets for both Lambda and RDS
9. **Encryption**: Enable encryption for RDS, Parameter Store, and Lambda environment variables
10. **Regular Audits**: Review cross-account roles and permissions quarterly

## Cost Considerations

1. **VPC Peering**: No hourly charges, only data transfer costs
2. **NAT Gateway**: Required for Lambda in private subnet (~$45/month)
3. **Parameter Store**: Free for standard parameters
4. **CloudWatch Logs**: Monitor log retention policies
5. **Lambda Invocations**: First 1M requests/month are free

## Monitoring and Alerting

Set up CloudWatch alarms for:
- Failed Lambda invocations
- High error rates
- Connection timeouts
- Failed AssumeRole calls
- Unusual cross-account activity

## Conclusion

This architecture provides a secure, scalable way to connect Lambda functions to RDS databases across AWS accounts. The use of temporary credentials, network isolation, and defense-in-depth security ensures your database remains protected while still being accessible to authorized applications.
# cross-accounts
