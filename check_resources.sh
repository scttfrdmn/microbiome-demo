#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# check_resources.sh
# Script to verify AWS resources and quotas before running the demo

set -e  # Exit on error

# Source configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
else
  BUCKET_NAME=${1:-microbiome-demo-bucket}
  REGION=${2:-us-east-1}
  AWS_PROFILE=${3:-""}
  STACK_NAME="microbiome-demo"
fi

# Source AWS helper functions
if [ -f "./aws_helper.sh" ]; then
  source ./aws_helper.sh
else
  echo "Error: aws_helper.sh not found. Please run setup.sh first."
  exit 1
fi

echo "==========================================="
echo "Microbiome Demo Resource Check v${VERSION:-unknown}"
echo "==========================================="
echo "Stack name: $STACK_NAME"
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Check AWS credentials
check_aws_credentials || exit 1

# Check if CloudFormation stack exists and is in the correct state
echo "Checking CloudFormation stack..."
STACK_STATUS=$(run_aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "STACK_NOT_FOUND")

if [ "$STACK_STATUS" == "STACK_NOT_FOUND" ]; then
  echo "❌ Stack not found: $STACK_NAME"
  echo "Please deploy the stack first with: aws cloudformation create-stack --stack-name $STACK_NAME ..."
  exit 1
elif [[ ! "$STACK_STATUS" =~ ^(CREATE_COMPLETE|UPDATE_COMPLETE)$ ]]; then
  echo "❌ Stack is not in a valid state: $STACK_STATUS"
  echo "Please wait for the stack to complete or troubleshoot any issues."
  exit 1
else
  echo "✅ Stack is ready: $STACK_STATUS"
fi

# Check S3 bucket
echo "Checking S3 bucket..."
if ! run_aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
  echo "❌ S3 bucket not found: $BUCKET_NAME"
  exit 1
fi

# Check if sample list exists
if ! run_aws s3 ls "s3://$BUCKET_NAME/input/sample_list.csv" &>/dev/null; then
  echo "❌ Sample list not found: s3://$BUCKET_NAME/input/sample_list.csv"
  echo "Please run prepare_demo_data.sh first."
  exit 1
else
  echo "✅ Sample list is available"
fi

# Get AWS Batch compute environments
echo "Checking AWS Batch compute environments..."
BATCH_ENV_CPU=$(run_aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id GravitonComputeEnvironment \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

BATCH_ENV_GPU=$(run_aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id GpuComputeEnvironment \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$BATCH_ENV_CPU" == "NOT_FOUND" ] || [ "$BATCH_ENV_GPU" == "NOT_FOUND" ]; then
  echo "❌ Batch compute environments not found"
  exit 1
fi

# Check Batch compute environment status
CPU_ENV_STATUS=$(run_aws batch describe-compute-environments \
  --compute-environments $BATCH_ENV_CPU \
  --query "computeEnvironments[0].status" \
  --output text)

GPU_ENV_STATUS=$(run_aws batch describe-compute-environments \
  --compute-environments $BATCH_ENV_GPU \
  --query "computeEnvironments[0].status" \
  --output text)

if [ "$CPU_ENV_STATUS" != "VALID" ] || [ "$GPU_ENV_STATUS" != "VALID" ]; then
  echo "❌ Batch compute environments are not valid: CPU=$CPU_ENV_STATUS, GPU=$GPU_ENV_STATUS"
  exit 1
else
  echo "✅ Batch compute environments are ready"
fi

# Check AWS service quotas
echo "Checking AWS service quotas..."

# Check EC2 vCPU Limits
CPU_LIMIT=$(run_aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --query "Quota.Value" \
  --output text 2>/dev/null || echo "ERROR")

if [ "$CPU_LIMIT" == "ERROR" ]; then
  echo "⚠️ Could not check EC2 vCPU limits. Manual verification required."
elif [ $(echo "$CPU_LIMIT < 256" | bc -l) -eq 1 ]; then
  echo "⚠️ EC2 vCPU limit may be too low: $CPU_LIMIT (need at least 256)"
  echo "Request an increase through the Service Quotas console if needed."
else
  echo "✅ EC2 vCPU limit is sufficient: $CPU_LIMIT"
fi

# Check GPU instance limits
GPU_LIMIT=$(run_aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-B0FF1D5D \
  --query "Quota.Value" \
  --output text 2>/dev/null || echo "ERROR")

if [ "$GPU_LIMIT" == "ERROR" ]; then
  echo "⚠️ Could not check GPU instance limits. Manual verification required."
elif [ $(echo "$GPU_LIMIT < 4" | bc -l) -eq 1 ]; then
  echo "⚠️ GPU instance limit may be too low: $GPU_LIMIT (need at least 4)"
  echo "Request an increase through the Service Quotas console if needed."
else
  echo "✅ GPU instance limit is sufficient: $GPU_LIMIT"
fi

# Check Lambda function
echo "Checking Lambda orchestrator function..."
LAMBDA_FUNCTION=$(get_stack_output "$STACK_NAME" "OrchestratorLambdaArn" 2>/dev/null || echo "NOT_FOUND")

if [ "$LAMBDA_FUNCTION" == "NOT_FOUND" ]; then
  echo "❌ Lambda function not found in stack outputs"
  exit 1
else
  echo "✅ Lambda function is available: $LAMBDA_FUNCTION"
fi

# Check dashboard URL
echo "Checking dashboard URL..."
DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL" 2>/dev/null || echo "NOT_FOUND")

if [ "$DASHBOARD_URL" == "NOT_FOUND" ]; then
  echo "❌ Dashboard URL not found in stack outputs"
  exit 1
else
  echo "✅ Dashboard is available at: $DASHBOARD_URL"
  
  # Try to check if the dashboard is accessible
  if command -v curl &>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DASHBOARD_URL")
    if [ "$HTTP_CODE" -eq 200 ]; then
      echo "✅ Dashboard is accessible (HTTP 200)"
    else
      echo "⚠️ Dashboard may not be accessible (HTTP $HTTP_CODE)"
    fi
  else
    echo "⚠️ Install curl to verify dashboard accessibility"
  fi
fi

# Overall readiness check
echo ""
echo "==========================================="
echo "Resource Check Summary"
echo "==========================================="
echo "Stack: ✅"
echo "S3 Bucket: ✅"
echo "Sample Data: ✅"
echo "Batch Environments: ✅"
echo "Lambda Function: ✅"
echo "Dashboard: ✅"
echo ""
echo "✅ All required resources are ready for the demo!"
echo "You can start the demo with: ./start_demo.sh"
echo "==========================================="
