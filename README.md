# Cross-Account AWS Lambda to RDS PostgreSQL Connection

This repository provides a complete solution for securely connecting an AWS Lambda function in one AWS account (Account A) to an RDS PostgreSQL database in another AWS account (Account B). The Lambda function extracts data from PostgreSQL and uploads it to S3 as CSV files.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Why Cross-Account Access?](#why-cross-account-access)
- [Lambda Function Implementation](#lambda-function-implementation)
- [Prerequisites](#prerequisites)
- [Security Components](#security-components)
- [Configuration](#configuration)
- [Step-by-Step Setup Guide](#step-by-step-setup-guide)
- [Deployment Scripts](#deployment-scripts)
- [Testing and Validation](#testing-and-validation)
- [Integration Testing](#integration-testing)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Cost Optimization](#cost-optimization)

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

## Lambda Function Implementation

### Java Implementation with Maven

The Lambda function is implemented in Java 11 using Maven for dependency management. It follows a service-oriented architecture for better testability and maintainability.

#### Key Features
- **Data Extraction**: Connects to PostgreSQL database and executes SQL queries
- **CSV Generation**: Converts query results to CSV format using OpenCSV
- **S3 Upload**: Uploads CSV files to S3 with timestamp-based naming
- **Cross-Account Access**: Assumes roles across AWS accounts for secure access
- **Parameter Store Integration**: Retrieves database configuration from SSM Parameter Store
- **Error Handling**: Comprehensive error handling with detailed logging

#### Architecture Components

```java
RDSDataExtractorHandler
├── ParameterStoreService  // SSM Parameter Store operations
├── CrossAccountService    // Cross-account role assumption
├── DatabaseService        // PostgreSQL connection and queries
└── S3Service             // CSV generation and S3 upload
```

#### Project Structure
```
lambda-java-maven/
├── pom.xml                     # Parent POM with dependency management
├── lambda-function/            # Lambda function module
│   ├── pom.xml                # Lambda function dependencies
│   └── src/main/java/
│       └── com/example/lambda/
│           ├── RDSDataExtractorHandler.java    # Main Lambda handler
│           ├── model/
│           │   └── DatabaseConfig.java        # Database configuration model
│           └── service/
│               ├── ParameterStoreService.java  # SSM operations
│               ├── CrossAccountService.java    # Cross-account access
│               ├── DatabaseService.java        # Database operations
│               └── S3Service.java             # S3 operations
└── integration-tests/          # Integration tests module
    ├── pom.xml                # Test dependencies
    ├── src/test/java/         # Cucumber step definitions
    └── src/test/resources/    # Feature files and test data
```

#### Dependencies
- **AWS SDK**: AWS service integrations (SSM, STS, S3)
- **PostgreSQL Driver**: Database connectivity
- **OpenCSV**: CSV file generation
- **Jackson**: JSON processing for configuration
- **SLF4J + Logback**: Logging framework

#### Lambda Input Format
```json
{
  "dbConfigParam": "/cross-account/db-config",
  "crossAccountRoleArn": "arn:aws:iam::222222222222:role/CrossAccountRDSRole",
  "externalId": "unique-external-id",
  "query": "SELECT * FROM users WHERE status = 'active'",
  "bucket": "data-extraction-bucket",
  "keyPrefix": "exports/users"
}
```

#### Lambda Response Format
```json
{
  "statusCode": 200,
  "body": {
    "message": "Data extraction completed successfully",
    "recordsProcessed": 1500,
    "s3Location": "s3://data-extraction-bucket/exports/users/data_export_20241225_143022.csv",
    "executionTime": "45.2 seconds"
  }
}
```

#### Build and Deployment
```bash
# Build the Lambda function
cd account-a/lambda-java-maven
mvn clean package

# Deploy using AWS CLI
aws lambda update-function-code \
  --function-name CrossAccountDataExtractor \
  --zip-file fileb://lambda-function/target/lambda-function-1.0.0.jar
```

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
   - Maven 3.6+ and Java 11+ (for Lambda function)
   - Docker (for integration testing)
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

## Configuration

Before deploying the infrastructure, you need to configure the environment variables and parameters.

### 1. Environment Configuration

Copy the example configuration file and update it with your values:

```bash
cp config.env.example config.env
# Edit config.env with your specific values
```

### 2. Key Configuration Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `ACCOUNT_A_ID` | AWS Account ID hosting Lambda | `111111111111` |
| `ACCOUNT_B_ID` | AWS Account ID hosting RDS | `222222222222` |
| `ACCOUNT_A_VPC_ID` | VPC ID in Account A | `vpc-0123456789abcdef0` |
| `ACCOUNT_B_VPC_ID` | VPC ID in Account B | `vpc-0987654321fedcba0` |
| `ACCOUNT_A_VPC_CIDR` | CIDR block for Account A | `10.0.0.0/16` |
| `ACCOUNT_B_VPC_CIDR` | CIDR block for Account B | `10.1.0.0/16` |

### 3. Load Configuration

```bash
source config.env
```

## Deployment Scripts

This repository provides multiple deployment options:

### 1. Enhanced Deployment Script (Recommended)

The enhanced deployment script (`deploy-enhanced.sh`) provides:
- ✅ Comprehensive validation and error handling
- ✅ Automatic placeholder replacement
- ✅ Progress tracking and colored output
- ✅ Rollback capabilities
- ✅ Support for environment variables

```bash
# Load configuration
source config.env

# Deploy infrastructure
./deploy-enhanced.sh deploy

# If something goes wrong, rollback
./deploy-enhanced.sh cleanup
```

### 2. Basic Deployment Script

The basic deployment script (`deploy.sh`) provides a simple deployment:

```bash
./deploy.sh
```

### 3. Manual Deployment

For granular control, you can deploy components individually using the step-by-step guide below.

## Testing and Validation

### 1. Pre-Deployment Validation

Before deploying, validate your configuration:

```bash
# Check AWS CLI configuration
aws sts get-caller-identity --profile account-a
aws sts get-caller-identity --profile account-b

# Validate VPC connectivity
aws ec2 describe-vpcs --vpc-ids $ACCOUNT_A_VPC_ID --profile account-a
aws ec2 describe-vpcs --vpc-ids $ACCOUNT_B_VPC_ID --profile account-b
```

### 2. Post-Deployment Testing

After deployment, test the cross-account connection:

```bash
# Test Lambda function
aws lambda invoke \
  --function-name RDSCrossAccountConnector \
  --payload '{
    "dbConfigParam": "/cross-account/db-config",
    "crossAccountRoleArn": "arn:aws:iam::222222222222:role/CrossAccountRDSRole",
    "externalId": "unique-external-id",
    "query": "SELECT COUNT(*) FROM information_schema.tables",
    "bucket": "data-extraction-bucket",
    "keyPrefix": "test"
  }' \
  response.json

# Check response
cat response.json
```

### 3. Lambda Function Testing

Test the Lambda function with different scenarios:

```bash
# Test with custom query
aws lambda invoke \
  --function-name RDSCrossAccountConnector \
  --payload '{
    "dbConfigParam": "/cross-account/db-config",
    "crossAccountRoleArn": "arn:aws:iam::222222222222:role/CrossAccountRDSRole",
    "externalId": "unique-external-id",
    "query": "SELECT username, email FROM users LIMIT 10",
    "bucket": "data-extraction-bucket",
    "keyPrefix": "exports/users"
  }' \
  response.json
```

## Integration Testing

### Overview

The project includes comprehensive integration tests using Cucumber, TestContainers, and LocalStack to verify the complete data extraction workflow.

### Test Framework
- **Cucumber**: BDD-style test scenarios in Gherkin syntax
- **TestContainers**: Containerized PostgreSQL database for testing
- **LocalStack**: Mock AWS services (S3, SSM, STS) for local testing
- **JUnit 5**: Test execution framework
- **Maven Failsafe**: Integration test execution and reporting

### Test Scenarios

The integration tests cover the following scenarios:

1. **Successful Data Extraction**
   - Valid cross-account credentials and configuration
   - Database connection and query execution
   - CSV generation and S3 upload verification

2. **Custom Query Execution**
   - SQL queries with column selection and filtering
   - Verification of query results and CSV structure

3. **Error Handling**
   - Invalid database credentials
   - S3 upload failures
   - Network connectivity issues
   - Graceful error handling and appropriate error messages

4. **Data Filtering and Validation**
   - SQL WHERE clause filtering
   - Record count validation
   - CSV content verification

### Running Integration Tests

```bash
# Navigate to the lambda function directory
cd account-a/lambda-java-maven

# Run integration tests
mvn clean verify -Pintegration-tests

# Run with debug output
mvn clean verify -Pintegration-tests -X

# Generate test reports
mvn clean verify -Pintegration-tests
# Reports available in integration-tests/target/cucumber-reports/
```

### Test Infrastructure

The integration tests automatically provision:

- **PostgreSQL Container**: Simulates cross-account RDS database with test data
- **LocalStack Container**: Provides S3, SSM, and STS services locally
- **Test Data**: Pre-loaded sample data for realistic testing scenarios

### Test Configuration

Key test configurations include:

- **Database**: PostgreSQL 13 with test schema and sample data
- **AWS Services**: LocalStack 2.2.0 with S3, SSM, STS services
- **Test Data**: Users and orders tables with various status values
- **Logging**: Detailed logs for debugging test failures

### Continuous Integration

Integration tests can be incorporated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Integration Tests
  run: |
    cd account-a/lambda-java-maven
    mvn clean verify -Pintegration-tests
    
- name: Publish Test Results
  uses: dorny/test-reporter@v1
  if: success() || failure()
  with:
    name: Integration Test Results
    path: 'account-a/lambda-java-maven/integration-tests/target/cucumber-reports/*.json'
    reporter: cucumber-json
```

For detailed information about the integration testing setup, see [Integration Tests README](account-a/lambda-java-maven/integration-tests/README.md).

## Troubleshooting
  --profile account-a \
  response.json

# Check the response
cat response.json
```

### 3. Network Connectivity Testing

Verify VPC peering and routing:

```bash
# Check peering connection status
aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=active" \
  --profile account-a

# Test network connectivity from Lambda subnet
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$ACCOUNT_A_VPC_ID" \
  --profile account-a
```

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

## Cost Optimization

### 1. Infrastructure Costs

| Component | Monthly Cost (Estimated) | Optimization Tips |
|-----------|-------------------------|-------------------|
| VPC Peering | $0 (no hourly charges) | No optimization needed |
| NAT Gateway | ~$45/month | Use NAT Instance for dev/test |
| Lambda | $0.20 per 1M requests | Monitor usage patterns |
| Parameter Store | Free (standard) | Use standard parameters |
| CloudWatch Logs | $0.50/GB ingested | Set appropriate retention |
| RDS | Varies by instance | Right-size instances |

### 2. Cost Optimization Strategies

1. **Use Reserved Instances**: For production RDS instances
2. **Implement Auto-Scaling**: For Lambda concurrency limits
3. **Monitor with AWS Cost Explorer**: Track cross-account data transfer
4. **Use Spot Instances**: For development environments
5. **Implement Lifecycle Policies**: For CloudWatch logs and S3 storage

### 3. Cost Monitoring

Set up billing alerts for:
- Total monthly spend exceeding $100
- Data transfer costs exceeding $10
- Lambda invocation costs exceeding $5

```bash
# Create billing alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "CrossAccountSpending" \
  --alarm-description "Alert when spending exceeds threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD
```

## Conclusion

This architecture provides a secure, scalable way to connect Lambda functions to RDS databases across AWS accounts. The use of temporary credentials, network isolation, and defense-in-depth security ensures your database remains protected while still being accessible to authorized applications.
# cross-accounts
