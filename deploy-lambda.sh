#!/bin/bash

# Cross-Account RDS Lambda Deployment Selector
# This script helps you choose between Python and Java implementations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

show_banner() {
    echo "=================================================="
    echo "  Cross-Account RDS Lambda Deployment Selector"
    echo "=================================================="
    echo ""
}

show_implementations() {
    echo "Available Lambda implementations:"
    echo ""
    echo "1. 🐍 Python Implementation"
    echo "   - Simple RDS connection and query execution"
    echo "   - Lightweight and fast startup"
    echo "   - Good for basic database operations"
    echo "   - File: account-a/lambda/rds_connector.py"
    echo ""
    echo "2. ☕ Java Implementation"
    echo "   - Advanced data extraction with CSV export to S3"
    echo "   - Cross-account role assumption"
    echo "   - Configurable SQL queries"
    echo "   - Enterprise-grade error handling"
    echo "   - File: account-a/lambda-java/src/main/java/com/example/lambda/RDSDataExtractorHandler.java"
    echo ""
}

deploy_python() {
    log_header "Deploying Python Lambda Implementation"
    
    if [[ ! -f "account-a/lambda/rds_connector.py" ]]; then
        log_error "Python Lambda function not found"
        return 1
    fi
    
    log_info "Packaging Python Lambda function..."
    cd account-a/lambda
    
    # Install dependencies
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt -t . || {
            log_error "Failed to install Python dependencies"
            return 1
        }
    fi
    
    # Create deployment package
    zip -r lambda-function.zip . -x "*.pyc" "__pycache__/*" || {
        log_error "Failed to create deployment package"
        return 1
    }
    
    cd ../..
    
    # Deploy using AWS CLI
    log_info "Deploying Python Lambda function..."
    
    FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-RDSCrossAccountConnector}"
    ROLE_ARN="arn:aws:iam::${ACCOUNT_A_ID}:role/LambdaExecutionRole"
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --profile account-a &> /dev/null; then
        log_info "Updating existing Python Lambda function..."
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file fileb://account-a/lambda/lambda-function.zip \
            --profile account-a \
            --region "$AWS_REGION"
    else
        log_info "Creating new Python Lambda function..."
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$ROLE_ARN" \
            --handler rds_connector.lambda_handler \
            --zip-file fileb://account-a/lambda/lambda-function.zip \
            --timeout "${LAMBDA_TIMEOUT:-300}" \
            --memory-size "${LAMBDA_MEMORY_SIZE:-512}" \
            --environment file://account-a/lambda/environment-variables.json \
            --profile account-a \
            --region "$AWS_REGION"
    fi
    
    # Clean up
    rm -f account-a/lambda/lambda-function.zip
    
    log_info "Python Lambda deployment completed!"
}

deploy_java() {
    log_header "Deploying Java Lambda Implementation"
    
    if [[ ! -f "account-a/lambda-java/build.gradle" ]]; then
        log_error "Java Lambda project not found"
        return 1
    fi
    
    # Check Java version
    if ! command -v java &> /dev/null; then
        log_error "Java is not installed"
        return 1
    fi
    
    JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [[ "$JAVA_VERSION" -lt 11 ]]; then
        log_error "Java 11 or later is required (found Java $JAVA_VERSION)"
        return 1
    fi
    
    log_info "Using Java version: $(java -version 2>&1 | head -1)"
    
    cd account-a/lambda-java
    
    # Deploy S3 bucket first if needed
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        log_info "Creating S3 bucket if it doesn't exist..."
        if ! aws s3 ls "s3://$S3_BUCKET_NAME" --profile account-a &> /dev/null; then
            aws cloudformation create-stack \
                --stack-name data-extraction-bucket \
                --template-body file://../cloudformation/s3-data-extraction-bucket.yaml \
                --parameters ParameterKey=BucketName,ParameterValue="$S3_BUCKET_NAME" \
                --profile account-a \
                --region "$AWS_REGION" || log_warn "S3 bucket stack creation may have failed"
        fi
    fi
    
    # Run the Java deployment script
    if [[ -f "deploy-java-lambda.sh" ]]; then
        chmod +x deploy-java-lambda.sh
        ./deploy-java-lambda.sh
    else
        log_error "Java deployment script not found"
        return 1
    fi
    
    cd ../..
    
    log_info "Java Lambda deployment completed!"
}

test_deployment() {
    local implementation=$1
    
    if [[ "$implementation" == "python" ]]; then
        FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-RDSCrossAccountConnector}"
    else
        FUNCTION_NAME="${JAVA_LAMBDA_FUNCTION_NAME:-RDSDataExtractorJava}"
    fi
    
    log_info "Testing $implementation Lambda function: $FUNCTION_NAME"
    
    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload '{"test": true}' \
        --profile account-a \
        --region "$AWS_REGION" \
        response.json
    
    if [[ $? -eq 0 ]]; then
        log_info "Lambda function test successful!"
        echo "Response:"
        cat response.json | jq '.' 2>/dev/null || cat response.json
    else
        log_error "Lambda function test failed"
        cat response.json
    fi
    
    rm -f response.json
}

interactive_menu() {
    show_banner
    show_implementations
    
    echo "Select implementation to deploy:"
    echo "1) Python (Simple RDS connection)"
    echo "2) Java (Advanced data extraction to S3)"
    echo "3) Deploy both implementations"
    echo "4) Test existing deployment"
    echo "5) Exit"
    echo ""
    read -p "Enter your choice (1-5): " choice
    
    case $choice in
        1)
            log_info "Selected: Python implementation"
            deploy_python
            if [[ $? -eq 0 ]]; then
                read -p "Test the deployment? (y/n): " test_choice
                if [[ "$test_choice" == "y" || "$test_choice" == "Y" ]]; then
                    test_deployment "python"
                fi
            fi
            ;;
        2)
            log_info "Selected: Java implementation"
            deploy_java
            if [[ $? -eq 0 ]]; then
                read -p "Test the deployment? (y/n): " test_choice
                if [[ "$test_choice" == "y" || "$test_choice" == "Y" ]]; then
                    test_deployment "java"
                fi
            fi
            ;;
        3)
            log_info "Selected: Deploy both implementations"
            deploy_python
            echo ""
            deploy_java
            ;;
        4)
            echo "Select implementation to test:"
            echo "1) Python"
            echo "2) Java"
            read -p "Enter choice (1-2): " test_impl
            case $test_impl in
                1) test_deployment "python" ;;
                2) test_deployment "java" ;;
                *) log_error "Invalid choice" ;;
            esac
            ;;
        5)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please select 1-5."
            interactive_menu
            ;;
    esac
}

validate_config() {
    log_info "Validating configuration..."
    
    if [[ -z "$ACCOUNT_A_ID" || -z "$ACCOUNT_B_ID" ]]; then
        log_error "ACCOUNT_A_ID and ACCOUNT_B_ID must be set"
        return 1
    fi
    
    if ! aws sts get-caller-identity --profile account-a &> /dev/null; then
        log_error "Cannot connect to AWS with profile 'account-a'"
        return 1
    fi
    
    if ! aws sts get-caller-identity --profile account-b &> /dev/null; then
        log_error "Cannot connect to AWS with profile 'account-b'"
        return 1
    fi
    
    log_info "Configuration validation passed"
    return 0
}

main() {
    # Load configuration if available
    if [[ -f "config.env" ]]; then
        source config.env
        log_info "Loaded configuration from config.env"
    else
        log_warn "config.env not found. Using default values."
        log_warn "Copy config.env.example to config.env and update values."
    fi
    
    # Validate configuration
    if ! validate_config; then
        exit 1
    fi
    
    # Parse command line arguments
    case "${1:-interactive}" in
        "python")
            deploy_python
            ;;
        "java")
            deploy_java
            ;;
        "both")
            deploy_python
            echo ""
            deploy_java
            ;;
        "test-python")
            test_deployment "python"
            ;;
        "test-java")
            test_deployment "java"
            ;;
        "interactive"|"")
            interactive_menu
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [python|java|both|test-python|test-java|interactive|help]"
            echo ""
            echo "Commands:"
            echo "  python       Deploy Python Lambda implementation"
            echo "  java         Deploy Java Lambda implementation"
            echo "  both         Deploy both implementations"
            echo "  test-python  Test Python Lambda function"
            echo "  test-java    Test Java Lambda function"
            echo "  interactive  Show interactive menu (default)"
            echo "  help         Show this help message"
            ;;
        *)
            log_error "Invalid option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
