#!/bin/bash

# Enhanced deployment script with validation and error handling
# Configuration - Update these values for your environment
ACCOUNT_A_ID="${ACCOUNT_A_ID:-111111111111}"
ACCOUNT_B_ID="${ACCOUNT_B_ID:-222222222222}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_A_VPC_ID="${ACCOUNT_A_VPC_ID:-vpc-12345}"
ACCOUNT_B_VPC_ID="${ACCOUNT_B_VPC_ID:-vpc-67890}"
ACCOUNT_A_VPC_CIDR="${ACCOUNT_A_VPC_CIDR:-10.0.0.0/16}"
ACCOUNT_B_VPC_CIDR="${ACCOUNT_B_VPC_CIDR:-10.1.0.0/16}"
EXTERNAL_ID="${EXTERNAL_ID:-$(uuidgen)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validation function
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if profiles exist
    if ! aws configure list --profile account-a &> /dev/null; then
        log_error "AWS CLI profile 'account-a' not configured"
        exit 1
    fi
    
    if ! aws configure list --profile account-b &> /dev/null; then
        log_error "AWS CLI profile 'account-b' not configured"
        exit 1
    fi
    
    # Check if required environment variables are set
    if [[ -z "$ACCOUNT_A_ID" || -z "$ACCOUNT_B_ID" ]]; then
        log_error "ACCOUNT_A_ID and ACCOUNT_B_ID must be set"
        exit 1
    fi
    
    log_info "Prerequisites validation passed"
}

# Function to update placeholders in files
update_placeholders() {
    log_info "Updating placeholder values in configuration files..."
    
    # Update Account IDs in policy files
    sed -i.bak "s/ACCOUNT_A_ID/$ACCOUNT_A_ID/g" account-a/iam/lambda-execution-policy.json
    sed -i.bak "s/ACCOUNT_B_ID/$ACCOUNT_B_ID/g" account-a/iam/lambda-execution-policy.json
    sed -i.bak "s/ACCOUNT_B_ID/$ACCOUNT_B_ID/g" account-b/iam/cross-account-rds-policy.json
    sed -i.bak "s/ACCOUNT_A_ID/$ACCOUNT_A_ID/g" account-b/iam/cross-account-rds-role-trust.json
    
    # Update external ID
    sed -i.bak "s/unique-external-id-12345/$EXTERNAL_ID/g" account-b/iam/cross-account-rds-role-trust.json
    
    log_info "Placeholder values updated successfully"
    log_info "External ID: $EXTERNAL_ID (save this for Lambda environment variable)"
}

# Function to create IAM roles with error handling
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # Account A - Lambda Execution Role
    log_info "Creating Lambda execution role in Account A..."
    if aws iam create-role \
        --role-name LambdaExecutionRole \
        --assume-role-policy-document file://account-a/iam/lambda-execution-role.json \
        --profile account-a \
        --region $REGION 2>/dev/null; then
        log_info "Lambda execution role created successfully"
    else
        log_warn "Lambda execution role may already exist"
    fi
    
    # Wait for role to be available
    sleep 5
    
    # Attach policy to Lambda role
    if aws iam put-role-policy \
        --role-name LambdaExecutionRole \
        --policy-name LambdaExecutionPolicy \
        --policy-document file://account-a/iam/lambda-execution-policy.json \
        --profile account-a \
        --region $REGION; then
        log_info "Lambda execution policy attached successfully"
    else
        log_error "Failed to attach Lambda execution policy"
        exit 1
    fi
    
    # Account B - Cross-Account RDS Access Role
    log_info "Creating cross-account RDS access role in Account B..."
    if aws iam create-role \
        --role-name CrossAccountRDSAccessRole \
        --assume-role-policy-document file://account-b/iam/cross-account-rds-role-trust.json \
        --profile account-b \
        --region $REGION 2>/dev/null; then
        log_info "Cross-account RDS access role created successfully"
    else
        log_warn "Cross-account RDS access role may already exist"
    fi
    
    # Wait for role to be available
    sleep 5
    
    # Attach policy to cross-account role
    if aws iam put-role-policy \
        --role-name CrossAccountRDSAccessRole \
        --policy-name CrossAccountRDSPolicy \
        --policy-document file://account-b/iam/cross-account-rds-policy.json \
        --profile account-b \
        --region $REGION; then
        log_info "Cross-account RDS policy attached successfully"
    else
        log_error "Failed to attach cross-account RDS policy"
        exit 1
    fi
}

# Function to deploy security groups
deploy_security_groups() {
    log_info "Deploying security groups..."
    
    # Deploy Lambda security group in Account A
    log_info "Deploying Lambda security group in Account A..."
    if aws cloudformation create-stack \
        --stack-name lambda-security-group \
        --template-body file://account-a/cloudformation/lambda-security-group.yaml \
        --parameters ParameterKey=VpcId,ParameterValue=$ACCOUNT_A_VPC_ID \
        --profile account-a \
        --region $REGION; then
        log_info "Lambda security group stack creation initiated"
    else
        log_warn "Lambda security group stack may already exist"
    fi
    
    # Deploy RDS security group in Account B using Terraform
    log_info "Deploying RDS security group in Account B using Terraform..."
    cd account-b/terraform
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f terraform.tfvars ]]; then
        cat > terraform.tfvars << EOF
vpc_id = "$ACCOUNT_B_VPC_ID"
account_a_vpc_cidr = "$ACCOUNT_A_VPC_CIDR"
aws_region = "$REGION"
EOF
        log_info "Created terraform.tfvars file"
    fi
    
    # Initialize and apply Terraform
    terraform init
    terraform plan -var-file="terraform.tfvars"
    
    if terraform apply -var-file="terraform.tfvars" -auto-approve; then
        log_info "RDS security group deployed successfully using Terraform"
    else
        log_error "Failed to deploy RDS security group using Terraform"
        exit 1
    fi
    
    cd ../..
}

# Function to setup Parameter Store
setup_parameter_store() {
    log_info "Setting up Parameter Store parameters..."
    
    # Create parameters in Account A
    aws ssm put-parameter \
        --name "/myapp/db/username" \
        --value "postgres" \
        --type "SecureString" \
        --description "Database username for RDS connection" \
        --profile account-a \
        --region $REGION \
        --overwrite || log_warn "Parameter /myapp/db/username may already exist"
    
    aws ssm put-parameter \
        --name "/myapp/db/database" \
        --value "postgres" \
        --type "SecureString" \
        --description "Database name for RDS connection" \
        --profile account-a \
        --region $REGION \
        --overwrite || log_warn "Parameter /myapp/db/database may already exist"
    
    aws ssm put-parameter \
        --name "/myapp/db/instance_identifier" \
        --value "my-postgres-db" \
        --type "String" \
        --description "RDS instance identifier" \
        --profile account-a \
        --region $REGION \
        --overwrite || log_warn "Parameter /myapp/db/instance_identifier may already exist"
    
    # Note: Password should be set manually or through AWS Secrets Manager
    log_warn "Please set the database password manually:"
    log_warn "aws ssm put-parameter --name '/myapp/db/password' --value 'your-secure-password' --type 'SecureString' --profile account-a --region $REGION"
}

# Function to wait for CloudFormation stacks
wait_for_stacks() {
    log_info "Waiting for CloudFormation stacks to complete..."
    
    # Wait for Lambda security group stack
    aws cloudformation wait stack-create-complete \
        --stack-name lambda-security-group \
        --profile account-a \
        --region $REGION
    
    if [[ $? -eq 0 ]]; then
        log_info "Lambda security group stack created successfully"
    else
        log_error "Lambda security group stack creation failed or timed out"
    fi
}

# Main deployment function
main() {
    log_info "Starting cross-account AWS infrastructure deployment..."
    log_info "Configuration:"
    log_info "  Account A ID: $ACCOUNT_A_ID"
    log_info "  Account B ID: $ACCOUNT_B_ID"
    log_info "  Region: $REGION"
    log_info "  Account A VPC: $ACCOUNT_A_VPC_ID"
    log_info "  Account B VPC: $ACCOUNT_B_VPC_ID"
    
    validate_prerequisites
    update_placeholders
    create_iam_roles
    deploy_security_groups
    setup_parameter_store
    wait_for_stacks
    
    log_info "Deployment completed successfully!"
    log_info "Next steps:"
    log_info "1. Set up VPC peering between accounts"
    log_info "2. Configure route tables for VPC peering"
    log_info "3. Set the database password in Parameter Store"
    log_info "4. Deploy the RDS instance in Account B"
    log_info "5. Deploy the Lambda function in Account A"
    log_info "6. Test the cross-account connection"
    
    log_info "External ID for Lambda environment: $EXTERNAL_ID"
}

# Cleanup function for rollback
cleanup() {
    log_warn "Starting cleanup/rollback..."
    
    # Delete CloudFormation stacks
    aws cloudformation delete-stack \
        --stack-name lambda-security-group \
        --profile account-a \
        --region $REGION 2>/dev/null
    
    # Terraform destroy
    cd account-b/terraform 2>/dev/null && terraform destroy -auto-approve -var-file="terraform.tfvars" 2>/dev/null
    cd ../.. 2>/dev/null
    
    # Delete IAM roles
    aws iam delete-role-policy \
        --role-name LambdaExecutionRole \
        --policy-name LambdaExecutionPolicy \
        --profile account-a 2>/dev/null
    
    aws iam delete-role \
        --role-name LambdaExecutionRole \
        --profile account-a 2>/dev/null
    
    aws iam delete-role-policy \
        --role-name CrossAccountRDSAccessRole \
        --policy-name CrossAccountRDSPolicy \
        --profile account-b 2>/dev/null
    
    aws iam delete-role \
        --role-name CrossAccountRDSAccessRole \
        --profile account-b 2>/dev/null
    
    log_info "Cleanup completed"
}

# Script usage
usage() {
    echo "Usage: $0 [deploy|cleanup|help]"
    echo "  deploy  - Deploy the cross-account infrastructure (default)"
    echo "  cleanup - Clean up/rollback the deployment"
    echo "  help    - Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  ACCOUNT_A_ID       - AWS Account ID for Lambda (required)"
    echo "  ACCOUNT_B_ID       - AWS Account ID for RDS (required)"
    echo "  AWS_REGION         - AWS Region (default: us-east-1)"
    echo "  ACCOUNT_A_VPC_ID   - VPC ID for Account A (default: vpc-12345)"
    echo "  ACCOUNT_B_VPC_ID   - VPC ID for Account B (default: vpc-67890)"
    echo "  ACCOUNT_A_VPC_CIDR - CIDR block for Account A VPC (default: 10.0.0.0/16)"
    echo "  ACCOUNT_B_VPC_CIDR - CIDR block for Account B VPC (default: 10.1.0.0/16)"
    echo "  EXTERNAL_ID        - External ID for role trust (auto-generated if not set)"
}

# Handle script arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    cleanup)
        cleanup
        ;;
    help)
        usage
        ;;
    *)
        echo "Invalid option: $1"
        usage
        exit 1
        ;;
esac
