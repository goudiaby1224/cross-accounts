#!/bin/bash

# Configuration
ACCOUNT_A_ID="111111111111"
ACCOUNT_B_ID="222222222222"
REGION="us-east-1"

echo "Deploying cross-account AWS infrastructure..."

# Account A setup
echo "Setting up Account A (Lambda)..."
aws iam create-role \
  --role-name LambdaExecutionRole \
  --assume-role-policy-document file://account-a/iam/lambda-execution-role.json \
  --profile account-a

aws iam put-role-policy \
  --role-name LambdaExecutionRole \
  --policy-name LambdaExecutionPolicy \
  --policy-document file://account-a/iam/lambda-execution-policy.json \
  --profile account-a

# Account B setup
echo "Setting up Account B (RDS)..."
aws iam create-role \
  --role-name CrossAccountRDSAccessRole \
  --assume-role-policy-document file://account-b/iam/cross-account-rds-role-trust.json \
  --profile account-b

aws iam put-role-policy \
  --role-name CrossAccountRDSAccessRole \
  --policy-name CrossAccountRDSPolicy \
  --policy-document file://account-b/iam/cross-account-rds-policy.json \
  --profile account-b

# Deploy security groups
echo "Deploying security groups..."
aws cloudformation create-stack \
  --stack-name lambda-security-group \
  --template-body file://account-a/cloudformation/lambda-security-group.yaml \
  --parameters ParameterKey=VpcId,ParameterValue=vpc-12345 \
  --profile account-a

aws cloudformation create-stack \
  --stack-name rds-security-group \
  --template-body file://account-b/cloudformation/rds-security-group.yaml \
  --parameters ParameterKey=VpcId,ParameterValue=vpc-67890 \
  --profile account-b

echo "Deployment complete!"
