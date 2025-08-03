# Java Lambda Function for Cross-Account RDS Data Extraction

This Java Lambda function connects to an RDS PostgreSQL database in a cross-account setup, extracts data, and saves it as a CSV file in an S3 bucket.

## Features

- ✅ Cross-account RDS access using IAM role assumption
- ✅ Secure credential management with Parameter Store
- ✅ Data extraction with configurable SQL queries
- ✅ CSV output with automatic timestamping
- ✅ S3 upload with encryption and versioning
- ✅ Comprehensive error handling and logging
- ✅ VPC support for secure networking

## Architecture

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│      Account A (Lambda)     │         │    Account B (RDS)          │
│                             │         │                             │
│  ┌─────────────────────┐   │         │   ┌──────────────────────┐ │
│  │   Java Lambda       │   │         │   │  PostgreSQL Database │ │
│  │                     │   │         │   │                      │ │
│  │ 1. Get DB config    │   │         │   │  ┌────────────────┐  │ │
│  │    from Parameter   │   │         │   │  │ Security Group │  │ │
│  │    Store            │   │  VPC    │   │  │ Port 5432      │  │ │
│  │                     │◄──┼─Peering─┼───┼─►│ from Account A │  │ │
│  │ 2. Assume role in   │   │         │   │  └────────────────┘  │ │
│  │    Account B        │   │         │   │                      │ │
│  │                     │   │         │   └──────────────────────┘ │
│  │ 3. Connect to RDS   │   │         │                             │
│  │    and extract data │   │         │   ┌──────────────────────┐ │
│  │                     │   │         │   │  Cross-Account Role │ │
│  │ 4. Upload CSV to S3 │   │         │   │                      │ │
│  └─────────────────────┘   │         │   │  Trust: Account A    │ │
│                             │         │   │  Lambda Role         │ │
│  ┌─────────────────────┐   │         │   │                      │ │
│  │   S3 Bucket         │   │         │   └──────────────────────┘ │
│  │   - Encrypted       │   │         │                             │
│  │   - Versioned       │   │         └─────────────────────────────┘
│  │   - Lifecycle rules │   │
│  └─────────────────────┘   │
│                             │
└─────────────────────────────┘
```

## Prerequisites

1. **Java 11** or later
2. **Gradle 7.6** or later
3. **AWS CLI** configured with profiles for both accounts
4. **Cross-account infrastructure** (VPC peering, IAM roles, security groups)

## Environment Variables

The Lambda function requires the following environment variables:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `S3_BUCKET_NAME` | S3 bucket for CSV output | `my-data-extraction-bucket` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ACCOUNT_B_ID` | AWS Account ID for RDS | `null` (same account) |
| `AWS_REGION` | AWS region | `us-east-1` |
| `CROSS_ACCOUNT_ROLE_NAME` | Role name in Account B | `CrossAccountRDSAccessRole` |
| `EXTERNAL_ID` | External ID for role assumption | `null` |
| `S3_KEY_PREFIX` | S3 key prefix for files | `extracts/daily` |
| `CSV_FILENAME_PREFIX` | CSV filename prefix | `data_extract` |
| `DB_QUERY` | SQL query to execute | Default: table list query |

## Parameter Store Configuration

The function reads database configuration from AWS Systems Manager Parameter Store:

| Parameter Name | Description | Type |
|----------------|-------------|------|
| `/myapp/db/username` | Database username | SecureString |
| `/myapp/db/password` | Database password | SecureString |
| `/myapp/db/database` | Database name | SecureString |
| `/myapp/db/instance_identifier` | RDS instance identifier | String |

### Setting Up Parameters

```bash
# Set database parameters
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

aws ssm put-parameter \
  --name "/myapp/db/database" \
  --value "postgres" \
  --type "SecureString" \
  --profile account-a

aws ssm put-parameter \
  --name "/myapp/db/instance_identifier" \
  --value "my-postgres-db" \
  --type "String" \
  --profile account-a
```

## Build and Deployment

### 1. Build the Project

```bash
cd account-a/lambda-java

# Build JAR file
./gradlew shadowJar
```

### 2. Deploy S3 Bucket (First Time)

```bash
# Deploy S3 bucket for data extraction
aws cloudformation create-stack \
  --stack-name data-extraction-bucket \
  --template-body file://../cloudformation/s3-data-extraction-bucket.yaml \
  --parameters ParameterKey=BucketName,ParameterValue=my-data-extraction \
  --profile account-a
```

### 3. Deploy Lambda Function

```bash
# Load configuration
source ../../config.env

# Deploy Lambda function
./deploy-java-lambda.sh
```

### 4. Manual Deployment (Alternative)

```bash
# Create function
aws lambda create-function \
  --function-name RDSDataExtractorJava \
  --runtime java11 \
  --role arn:aws:iam::ACCOUNT_A_ID:role/LambdaExecutionRole \
  --handler com.example.lambda.RDSDataExtractorHandler::handleRequest \
  --zip-file fileb://build/libs/lambda-java.jar \
  --timeout 300 \
  --memory-size 512 \
  --environment file://environment-variables.json \
  --profile account-a
```

## Testing

### 1. Unit Tests

```bash
# Run unit tests
./gradlew test
```

### 2. Integration Test

```bash
# Test Lambda function
aws lambda invoke \
  --function-name RDSDataExtractorJava \
  --payload '{}' \
  --profile account-a \
  response.json

# Check response
cat response.json | jq '.'
```

### 3. Custom Query Test

```bash
# Test with custom query
CUSTOM_QUERY="SELECT schemaname, tablename, tableowner FROM pg_tables WHERE schemaname = 'public' LIMIT 10"

aws lambda update-function-configuration \
  --function-name RDSDataExtractorJava \
  --environment Variables="{
    \"S3_BUCKET_NAME\":\"my-data-extraction-bucket\",
    \"DB_QUERY\":\"$CUSTOM_QUERY\"
  }" \
  --profile account-a

# Invoke with custom query
aws lambda invoke \
  --function-name RDSDataExtractorJava \
  --payload '{}' \
  --profile account-a \
  response.json
```

## Output Format

The function generates CSV files with the following naming convention:

```
{CSV_FILENAME_PREFIX}_{YYYY-MM-DD_HH-mm-ss}_{random}.csv
```

Example: `data_extract_2023-07-31_14-30-45_1234.csv`

### S3 Structure

```
s3://my-data-extraction-bucket/
├── extracts/
│   └── daily/
│       ├── data_extract_2023-07-31_14-30-45_1234.csv
│       ├── data_extract_2023-07-31_15-00-12_5678.csv
│       └── ...
└── [other-prefixes]/
```

## Error Handling

The function handles various error scenarios:

1. **Missing Environment Variables**: Returns 500 with error details
2. **Parameter Store Access Denied**: Logs error and fails gracefully
3. **Cross-Account Role Assumption Failed**: Detailed error logging
4. **Database Connection Issues**: Comprehensive SQL error handling
5. **S3 Upload Failures**: Retry logic and detailed error messages

### Common Error Responses

```json
{
  "statusCode": 500,
  "error": "Failed to retrieve database configuration from Parameter Store",
  "errorType": "RuntimeException",
  "requestId": "uuid-request-id"
}
```

## Monitoring and Logging

### CloudWatch Logs

The function logs to CloudWatch with the log group:
`/aws/lambda/RDSDataExtractorJava`

### Key Metrics to Monitor

1. **Function Duration**: Should be under timeout limit
2. **Error Rate**: Monitor failed invocations
3. **S3 Upload Success**: Check S3 bucket for new files
4. **Database Connection Time**: Monitor connection latency

### CloudWatch Alarms

```bash
# Create alarm for function errors
aws cloudwatch put-metric-alarm \
  --alarm-name "RDSDataExtractor-Errors" \
  --alarm-description "Monitor Lambda function errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=RDSDataExtractorJava \
  --evaluation-periods 1
```

## Security Considerations

### 1. IAM Permissions
- Function uses least-privilege IAM policies
- Cross-account access limited to specific resources
- S3 access restricted to designated bucket

### 2. Network Security
- VPC deployment for secure database access
- Security groups allow only necessary traffic
- SSL/TLS enforcement for database connections

### 3. Data Protection
- S3 encryption at rest (AES-256)
- Parameter Store encryption for sensitive data
- Secure transport enforced for all communications

## Performance Optimization

### 1. Memory Configuration
- Recommended: 512MB for small datasets
- Increase to 1024MB+ for large datasets
- Monitor memory utilization in CloudWatch

### 2. Timeout Settings
- Default: 300 seconds (5 minutes)
- Adjust based on data volume and query complexity
- Maximum: 900 seconds (15 minutes)

### 3. Connection Pooling
- Current implementation uses single connection
- Consider connection pooling for high-frequency invocations
- Use RDS Proxy for production workloads

## Troubleshooting

### Common Issues

1. **"Unable to load AWS credentials"**
   - Check Lambda execution role permissions
   - Verify role trust relationship

2. **"Failed to assume cross-account role"**
   - Verify external ID matches
   - Check trust policy in Account B
   - Ensure role ARN is correct

3. **"Database connection timeout"**
   - Check VPC peering configuration
   - Verify security group rules
   - Ensure Lambda is in correct subnets

4. **"S3 access denied"**
   - Check bucket policy
   - Verify Lambda role has S3 permissions
   - Ensure bucket exists in correct region

### Debug Mode

Enable debug logging by setting log level:

```java
// Add to Lambda function environment variables
"LOG_LEVEL": "DEBUG"
```

## Cost Optimization

### Estimated Costs (Monthly)

- **Lambda Execution**: $0.20 per 1M requests
- **S3 Storage**: $0.023 per GB
- **Parameter Store**: Free for standard parameters
- **CloudWatch Logs**: $0.50 per GB ingested

### Optimization Tips

1. **Right-size Memory**: Monitor memory usage and adjust
2. **Optimize Queries**: Use efficient SQL queries
3. **Compress Output**: Consider gzip compression for large files
4. **Lifecycle Policies**: Set up S3 lifecycle rules for cost savings

## Future Enhancements

1. **Incremental Extraction**: Support for delta/incremental data extraction
2. **Multiple Formats**: Support for JSON, Parquet output formats
3. **Scheduling**: Integration with EventBridge for scheduled executions
4. **Data Validation**: Schema validation and data quality checks
5. **Notifications**: SNS notifications for success/failure events

## Contributing

1. **Code Style**: Follow Google Java Style Guide
2. **Testing**: Maintain test coverage above 80%
3. **Documentation**: Update README for any new features
4. **Security**: Run security scans before deployment
