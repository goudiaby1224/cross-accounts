# Integration Tests

This module contains integration tests for the cross-account RDS data extraction Lambda function using Cucumber, TestContainers, and LocalStack.

## Overview

The integration tests verify the complete workflow of:
1. Connecting to a cross-account RDS database
2. Extracting data using SQL queries
3. Converting data to CSV format
4. Uploading the CSV file to S3

## Test Infrastructure

### TestContainers
- **PostgreSQL**: Simulates the cross-account RDS database
- **LocalStack**: Simulates AWS services (S3, SSM, STS)

### Test Framework
- **Cucumber**: BDD-style test scenarios
- **JUnit 5**: Test execution framework
- **Maven Failsafe**: Integration test execution

## Running Tests

### Prerequisites
- Docker installed and running
- Java 11 or higher
- Maven 3.6 or higher

### Execute Integration Tests

```bash
# Run all integration tests
mvn clean verify -Pintegration-tests

# Run from project root
cd /Users/noelgoudiaby/cross-account-aws/account-a/lambda-java-maven
mvn clean verify -Pintegration-tests

# Run with debug output
mvn clean verify -Pintegration-tests -X
```

### Test Scenarios

The integration tests cover the following scenarios:

1. **Successful Data Extraction**
   - Valid credentials and configuration
   - Data extraction and CSV upload to S3
   - Verification of CSV structure and content

2. **Custom Query Execution**
   - Custom SQL queries with column selection
   - Filtered data extraction
   - Verification of query results

3. **Error Handling**
   - Invalid database credentials
   - S3 upload failures
   - Graceful error handling and responses

4. **Data Filtering**
   - SQL WHERE clause filtering
   - Record count validation
   - Filtered CSV content verification

## Test Configuration

### Environment Variables
The tests automatically configure the required environment using TestContainers:
- PostgreSQL database with test data
- LocalStack for AWS services
- Parameter Store with database configuration

### Test Data
Test data is automatically loaded from `test-data.sql`:
- Users table with sample user records
- Orders table with sample order data
- Various status values for filtering tests

## Test Reports

After running tests, reports are generated in:
- `target/cucumber-reports/`: Cucumber HTML reports
- `target/failsafe-reports/`: Maven Failsafe reports

## Debugging Tests

### Logs
- TestContainers logs show container startup and configuration
- Lambda function logs show execution details
- AWS SDK logs show service interactions

### Container Access
During test execution, you can access containers:
```bash
# List running containers
docker ps

# Access PostgreSQL container
docker exec -it <postgres-container-id> psql -U testuser -d testdb

# Access LocalStack logs
docker logs <localstack-container-id>
```

## Configuration Files

- `pom.xml`: Maven configuration with test dependencies
- `CucumberTestRunner.java`: Cucumber test suite configuration
- `TestInfrastructure.java`: TestContainers setup and configuration
- `DataExtractionSteps.java`: Cucumber step definitions
- `data-extraction.feature`: BDD test scenarios
- `test-data.sql`: Database initialization script
- `logback-test.xml`: Logging configuration for tests

## Troubleshooting

### Common Issues

1. **Docker Connection Issues**
   ```bash
   # Verify Docker is running
   docker info
   ```

2. **Port Conflicts**
   - TestContainers automatically assigns available ports
   - Check for conflicts with running services

3. **Memory Issues**
   - Ensure sufficient memory for containers
   - Adjust JVM heap size if needed

4. **Network Issues**
   - Verify Docker network configuration
   - Check firewall settings

### Test Debugging

1. **Enable Debug Logging**
   ```bash
   mvn clean verify -Pintegration-tests -Dlogback.level=DEBUG
   ```

2. **Container Inspection**
   ```bash
   # Check container logs
   docker logs <container-name>
   
   # Connect to PostgreSQL
   docker exec -it <postgres-container> psql -U testuser -d testdb
   ```

3. **LocalStack Services**
   ```bash
   # Check LocalStack status
   curl http://localhost:4566/health
   
   # List S3 buckets
   aws --endpoint-url=http://localhost:4566 s3 ls
   ```
