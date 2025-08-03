#!/bin/bash

# Cross-Account AWS Configuration Validation Script
# This script validates the configuration and prerequisites before deployment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
INFO_COUNT=0

# Logging functions
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    ((INFO_COUNT++))
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Validation functions
validate_aws_cli() {
    log_check "Validating AWS CLI installation and configuration..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        return 1
    fi
    
    log_info "AWS CLI is installed"
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    return 0
}

validate_aws_profiles() {
    log_check "Validating AWS profiles..."
    
    if ! aws configure list --profile account-a &> /dev/null; then
        log_error "AWS CLI profile 'account-a' is not configured"
        log_error "Run: aws configure --profile account-a"
        return 1
    fi
    
    if ! aws configure list --profile account-b &> /dev/null; then
        log_error "AWS CLI profile 'account-b' is not configured"
        log_error "Run: aws configure --profile account-b"
        return 1
    fi
    
    log_info "AWS profiles 'account-a' and 'account-b' are configured"
    return 0
}

validate_environment_variables() {
    log_check "Validating environment variables..."
    
    # Required variables
    local required_vars=(
        "ACCOUNT_A_ID"
        "ACCOUNT_B_ID"
        "AWS_REGION"
        "ACCOUNT_A_VPC_ID"
        "ACCOUNT_B_VPC_ID"
        "ACCOUNT_A_VPC_CIDR"
        "ACCOUNT_B_VPC_CIDR"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Environment variable $var is not set"
        else
            log_info "$var: ${!var}"
        fi
    done
    
    # Validate Account ID format
    if [[ -n "$ACCOUNT_A_ID" && ! "$ACCOUNT_A_ID" =~ ^[0-9]{12}$ ]]; then
        log_error "ACCOUNT_A_ID must be a 12-digit number"
    fi
    
    if [[ -n "$ACCOUNT_B_ID" && ! "$ACCOUNT_B_ID" =~ ^[0-9]{12}$ ]]; then
        log_error "ACCOUNT_B_ID must be a 12-digit number"
    fi
    
    # Validate VPC ID format
    if [[ -n "$ACCOUNT_A_VPC_ID" && ! "$ACCOUNT_A_VPC_ID" =~ ^vpc-[a-zA-Z0-9]+$ ]]; then
        log_error "ACCOUNT_A_VPC_ID must be in format vpc-xxxxxxxxx"
    fi
    
    if [[ -n "$ACCOUNT_B_VPC_ID" && ! "$ACCOUNT_B_VPC_ID" =~ ^vpc-[a-zA-Z0-9]+$ ]]; then
        log_error "ACCOUNT_B_VPC_ID must be in format vpc-xxxxxxxxx"
    fi
    
    # Validate CIDR format
    if [[ -n "$ACCOUNT_A_VPC_CIDR" && ! "$ACCOUNT_A_VPC_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "ACCOUNT_A_VPC_CIDR must be in CIDR format (e.g., 10.0.0.0/16)"
    fi
    
    if [[ -n "$ACCOUNT_B_VPC_CIDR" && ! "$ACCOUNT_B_VPC_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "ACCOUNT_B_VPC_CIDR must be in CIDR format (e.g., 10.1.0.0/16)"
    fi
    
    return 0
}

validate_aws_connectivity() {
    log_check "Validating AWS connectivity and permissions..."
    
    # Test Account A connectivity
    if aws sts get-caller-identity --profile account-a &> /dev/null; then
        ACCOUNT_A_ACTUAL=$(aws sts get-caller-identity --profile account-a --query Account --output text)
        log_info "Connected to Account A: $ACCOUNT_A_ACTUAL"
        
        if [[ -n "$ACCOUNT_A_ID" && "$ACCOUNT_A_ID" != "$ACCOUNT_A_ACTUAL" ]]; then
            log_warn "ACCOUNT_A_ID ($ACCOUNT_A_ID) doesn't match actual account ($ACCOUNT_A_ACTUAL)"
        fi
    else
        log_error "Cannot connect to AWS using profile 'account-a'"
    fi
    
    # Test Account B connectivity
    if aws sts get-caller-identity --profile account-b &> /dev/null; then
        ACCOUNT_B_ACTUAL=$(aws sts get-caller-identity --profile account-b --query Account --output text)
        log_info "Connected to Account B: $ACCOUNT_B_ACTUAL"
        
        if [[ -n "$ACCOUNT_B_ID" && "$ACCOUNT_B_ID" != "$ACCOUNT_B_ACTUAL" ]]; then
            log_warn "ACCOUNT_B_ID ($ACCOUNT_B_ID) doesn't match actual account ($ACCOUNT_B_ACTUAL)"
        fi
    else
        log_error "Cannot connect to AWS using profile 'account-b'"
    fi
    
    return 0
}

validate_vpc_configuration() {
    log_check "Validating VPC configuration..."
    
    # Check if VPCs exist
    if [[ -n "$ACCOUNT_A_VPC_ID" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$ACCOUNT_A_VPC_ID" --profile account-a --region "$AWS_REGION" &> /dev/null; then
            log_info "Account A VPC $ACCOUNT_A_VPC_ID exists"
            
            # Get actual CIDR
            ACTUAL_CIDR_A=$(aws ec2 describe-vpcs --vpc-ids "$ACCOUNT_A_VPC_ID" --profile account-a --region "$AWS_REGION" --query 'Vpcs[0].CidrBlock' --output text)
            if [[ -n "$ACCOUNT_A_VPC_CIDR" && "$ACCOUNT_A_VPC_CIDR" != "$ACTUAL_CIDR_A" ]]; then
                log_warn "Account A VPC CIDR mismatch: configured=$ACCOUNT_A_VPC_CIDR, actual=$ACTUAL_CIDR_A"
            else
                log_info "Account A VPC CIDR: $ACTUAL_CIDR_A"
            fi
        else
            log_error "Account A VPC $ACCOUNT_A_VPC_ID does not exist or is not accessible"
        fi
    fi
    
    if [[ -n "$ACCOUNT_B_VPC_ID" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$ACCOUNT_B_VPC_ID" --profile account-b --region "$AWS_REGION" &> /dev/null; then
            log_info "Account B VPC $ACCOUNT_B_VPC_ID exists"
            
            # Get actual CIDR
            ACTUAL_CIDR_B=$(aws ec2 describe-vpcs --vpc-ids "$ACCOUNT_B_VPC_ID" --profile account-b --region "$AWS_REGION" --query 'Vpcs[0].CidrBlock' --output text)
            if [[ -n "$ACCOUNT_B_VPC_CIDR" && "$ACCOUNT_B_VPC_CIDR" != "$ACTUAL_CIDR_B" ]]; then
                log_warn "Account B VPC CIDR mismatch: configured=$ACCOUNT_B_VPC_CIDR, actual=$ACTUAL_CIDR_B"
            else
                log_info "Account B VPC CIDR: $ACTUAL_CIDR_B"
            fi
        else
            log_error "Account B VPC $ACCOUNT_B_VPC_ID does not exist or is not accessible"
        fi
    fi
    
    # Check for CIDR overlap
    if [[ -n "$ACCOUNT_A_VPC_CIDR" && -n "$ACCOUNT_B_VPC_CIDR" ]]; then
        # Simple check - compare first two octets
        A_NETWORK=$(echo "$ACCOUNT_A_VPC_CIDR" | cut -d'.' -f1-2)
        B_NETWORK=$(echo "$ACCOUNT_B_VPC_CIDR" | cut -d'.' -f1-2)
        
        if [[ "$A_NETWORK" == "$B_NETWORK" ]]; then
            log_warn "VPC CIDR blocks may overlap: $ACCOUNT_A_VPC_CIDR and $ACCOUNT_B_VPC_CIDR"
            log_warn "This may cause routing issues with VPC peering"
        fi
    fi
    
    return 0
}

validate_tools() {
    log_check "Validating required tools..."
    
    # Check Terraform
    if command -v terraform &> /dev/null; then
        TF_VERSION=$(terraform version | head -1 | cut -d'v' -f2)
        log_info "Terraform is installed: $TF_VERSION"
    else
        log_warn "Terraform is not installed (required for RDS security group deployment)"
    fi
    
    # Check Python
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        log_info "Python3 is installed: $PYTHON_VERSION"
    else
        log_error "Python3 is not installed (required for Lambda function)"
    fi
    
    # Check jq (useful for JSON processing)
    if command -v jq &> /dev/null; then
        JQ_VERSION=$(jq --version)
        log_info "jq is installed: $JQ_VERSION"
    else
        log_warn "jq is not installed (recommended for JSON processing)"
    fi
    
    return 0
}

validate_file_structure() {
    log_check "Validating file structure..."
    
    local required_files=(
        "account-a/iam/lambda-execution-role.json"
        "account-a/iam/lambda-execution-policy.json"
        "account-a/lambda/rds_connector.py"
        "account-a/lambda/requirements.txt"
        "account-b/iam/cross-account-rds-role-trust.json"
        "account-b/iam/cross-account-rds-policy.json"
        "account-b/terraform/provider.tf"
        "account-b/terraform/rds-security-group.tf"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Found: $file"
        else
            log_error "Missing: $file"
        fi
    done
    
    return 0
}

validate_iam_permissions() {
    log_check "Validating IAM permissions..."
    
    # Check Account A permissions
    if aws iam get-user --profile account-a &> /dev/null; then
        log_info "Account A: IAM permissions are accessible"
    else
        log_warn "Account A: Cannot access IAM (may use roles instead of users)"
    fi
    
    # Check Account B permissions
    if aws iam get-user --profile account-b &> /dev/null; then
        log_info "Account B: IAM permissions are accessible"
    else
        log_warn "Account B: Cannot access IAM (may use roles instead of users)"
    fi
    
    return 0
}

# Main validation function
main() {
    echo "=========================================="
    echo "Cross-Account AWS Configuration Validator"
    echo "=========================================="
    echo ""
    
    validate_aws_cli
    validate_aws_profiles
    validate_environment_variables
    validate_aws_connectivity
    validate_vpc_configuration
    validate_tools
    validate_file_structure
    validate_iam_permissions
    
    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="
    echo -e "✅ Info messages: ${GREEN}$INFO_COUNT${NC}"
    echo -e "⚠️  Warnings: ${YELLOW}$WARNINGS${NC}"
    echo -e "❌ Errors: ${RED}$ERRORS${NC}"
    echo ""
    
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}✅ Validation passed! You can proceed with deployment.${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Please review warnings before proceeding.${NC}"
        fi
        exit 0
    else
        echo -e "${RED}❌ Validation failed! Please fix the errors before proceeding.${NC}"
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [--help]"
    echo ""
    echo "This script validates the cross-account AWS configuration."
    echo ""
    echo "Prerequisites:"
    echo "1. Load configuration: source config.env"
    echo "2. Configure AWS profiles: aws configure --profile account-a"
    echo "3. Configure AWS profiles: aws configure --profile account-b"
    echo ""
    echo "Options:"
    echo "  --help    Show this help message"
}

# Handle script arguments
case "${1:-validate}" in
    validate)
        main
        ;;
    --help)
        usage
        ;;
    *)
        echo "Invalid option: $1"
        usage
        exit 1
        ;;
esac
