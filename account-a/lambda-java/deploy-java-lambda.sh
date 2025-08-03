#!/bin/bash

# Build and deploy Java Lambda function for RDS data extraction

# Configuration
FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-RDSDataExtractorJava}"
RUNTIME="java11"
TIMEOUT="${LAMBDA_TIMEOUT:-300}"
MEMORY_SIZE="${LAMBDA_MEMORY_SIZE:-512}"
HANDLER="com.example.lambda.RDSDataExtractorHandler::handleRequest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [[ ! -f "build.gradle" ]]; then
    log_error "build.gradle not found. Please run this script from the lambda-java directory."
    exit 1
fi

# Load environment configuration if available
if [[ -f "../../config.env" ]]; then
    source ../../config.env
    log_info "Loaded configuration from config.env"
fi

log_info "Building Java Lambda function..."

# Build the project
if ./gradlew shadowJar; then
    log_info "Build completed successfully"
else
    log_error "Build failed"
    exit 1
fi

# Check if JAR file exists
JAR_FILE="build/libs/$(basename $(pwd)).jar"
if [[ ! -f "$JAR_FILE" ]]; then
    # Try alternative naming
    JAR_FILE=$(find build/libs -name "*.jar" | head -1)
    if [[ ! -f "$JAR_FILE" ]]; then
        log_error "JAR file not found in build/libs/"
        exit 1
    fi
fi

log_info "JAR file found: $JAR_FILE"

# Create S3 bucket if specified and doesn't exist
if [[ -n "$S3_BUCKET_NAME" ]]; then
    if ! aws s3 ls "s3://$S3_BUCKET_NAME" --profile account-a &> /dev/null; then
        log_info "Creating S3 bucket: $S3_BUCKET_NAME"
        aws s3 mb "s3://$S3_BUCKET_NAME" --profile account-a --region "$AWS_REGION"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET_NAME" \
            --versioning-configuration Status=Enabled \
            --profile account-a
            
        log_info "S3 bucket created and versioning enabled"
    else
        log_info "S3 bucket $S3_BUCKET_NAME already exists"
    fi
fi

# Get Lambda execution role ARN
LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_A_ID}:role/LambdaExecutionRole"

log_info "Deploying Lambda function: $FUNCTION_NAME"

# Check if function exists
if aws lambda get-function --function-name "$FUNCTION_NAME" --profile account-a &> /dev/null; then
    log_info "Updating existing Lambda function..."
    
    # Update function code
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$JAR_FILE" \
        --profile account-a \
        --region "$AWS_REGION"
    
    # Update environment variables
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment file://environment-variables.json \
        --timeout "$TIMEOUT" \
        --memory-size "$MEMORY_SIZE" \
        --profile account-a \
        --region "$AWS_REGION"
        
    log_info "Lambda function updated successfully"
    
else
    log_info "Creating new Lambda function..."
    
    # Create new function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime "$RUNTIME" \
        --role "$LAMBDA_ROLE_ARN" \
        --handler "$HANDLER" \
        --zip-file "fileb://$JAR_FILE" \
        --timeout "$TIMEOUT" \
        --memory-size "$MEMORY_SIZE" \
        --environment file://environment-variables.json \
        --profile account-a \
        --region "$AWS_REGION"
        
    log_info "Lambda function created successfully"
fi

# Configure VPC if subnet IDs are provided
if [[ -n "$ACCOUNT_A_PRIVATE_SUBNET_IDS" ]]; then
    log_info "Configuring VPC settings..."
    
    # Get security group ID
    LAMBDA_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=lambda-rds-cross-account-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --profile account-a \
        --region "$AWS_REGION")
    
    if [[ "$LAMBDA_SG_ID" != "None" && -n "$LAMBDA_SG_ID" ]]; then
        # Convert comma-separated subnet IDs to array format for AWS CLI
        SUBNET_IDS_ARRAY=$(echo "$ACCOUNT_A_PRIVATE_SUBNET_IDS" | sed 's/,/ /g')
        
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --vpc-config "SubnetIds=$ACCOUNT_A_PRIVATE_SUBNET_IDS,SecurityGroupIds=$LAMBDA_SG_ID" \
            --profile account-a \
            --region "$AWS_REGION"
            
        log_info "VPC configuration applied"
    else
        log_warn "Lambda security group not found. Skipping VPC configuration."
    fi
fi

# Test the function
log_info "Testing Lambda function..."
TEST_PAYLOAD='{"test": true}'

aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "$TEST_PAYLOAD" \
    --profile account-a \
    --region "$AWS_REGION" \
    response.json

if [[ $? -eq 0 ]]; then
    log_info "Lambda function invoked successfully"
    echo "Response:"
    cat response.json | jq '.' 2>/dev/null || cat response.json
    echo ""
else
    log_error "Lambda function invocation failed"
    cat response.json
fi

# Clean up
rm -f response.json

log_info "Deployment completed!"
log_info "Function Name: $FUNCTION_NAME"
log_info "Runtime: $RUNTIME"
log_info "Handler: $HANDLER"
log_info "Memory: ${MEMORY_SIZE}MB"
log_info "Timeout: ${TIMEOUT}s"

if [[ -n "$S3_BUCKET_NAME" ]]; then
    log_info "S3 Bucket: $S3_BUCKET_NAME"
fi
