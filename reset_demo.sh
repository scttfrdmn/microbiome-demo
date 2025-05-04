#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
#
# reset_demo.sh
# Quick recovery script for the demo in case of issues

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
echo "Microbiome Demo Reset v${VERSION:-unknown}"
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

# Function to confirm action
confirm() {
  read -p "$1 (y/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
  fi
}

# Confirm reset
confirm "This will cancel all running jobs and reset the demo. Continue?"

# Get AWS Batch job queues
echo "Getting AWS Batch job queues..."
CPU_JOB_QUEUE=$(run_aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id CPUJobQueue \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

GPU_JOB_QUEUE=$(run_aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id GPUJobQueue \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

# Cancel all running jobs
echo "Cancelling all running jobs..."
if [ "$CPU_JOB_QUEUE" != "NOT_FOUND" ]; then
  # Get all RUNNABLE, STARTING, and RUNNING jobs
  CPU_JOBS=$(run_aws batch list-jobs \
    --job-queue "$CPU_JOB_QUEUE" \
    --job-status RUNNABLE \
    --query "jobSummaryList[*].jobId" \
    --output text)
  
  # Add STARTING jobs
  CPU_JOBS="$CPU_JOBS $(run_aws batch list-jobs \
    --job-queue "$CPU_JOB_QUEUE" \
    --job-status STARTING \
    --query "jobSummaryList[*].jobId" \
    --output text)"
    
  # Add RUNNING jobs
  CPU_JOBS="$CPU_JOBS $(run_aws batch list-jobs \
    --job-queue "$CPU_JOB_QUEUE" \
    --job-status RUNNING \
    --query "jobSummaryList[*].jobId" \
    --output text)"
  
  # Cancel each job
  for JOB_ID in $CPU_JOBS; do
    echo "Cancelling job: $JOB_ID"
    run_aws batch terminate-job \
      --job-id "$JOB_ID" \
      --reason "Demo reset" \
      || echo "Could not cancel job $JOB_ID (may already be completed)"
  done
fi

if [ "$GPU_JOB_QUEUE" != "NOT_FOUND" ]; then
  # Get all RUNNABLE, STARTING, and RUNNING jobs
  GPU_JOBS=$(run_aws batch list-jobs \
    --job-queue "$GPU_JOB_QUEUE" \
    --job-status RUNNABLE \
    --query "jobSummaryList[*].jobId" \
    --output text)
    
  # Add STARTING jobs
  GPU_JOBS="$GPU_JOBS $(run_aws batch list-jobs \
    --job-queue "$GPU_JOB_QUEUE" \
    --job-status STARTING \
    --query "jobSummaryList[*].jobId" \
    --output text)"
    
  # Add RUNNING jobs
  GPU_JOBS="$GPU_JOBS $(run_aws batch list-jobs \
    --job-queue "$GPU_JOB_QUEUE" \
    --job-status RUNNING \
    --query "jobSummaryList[*].jobId" \
    --output text)"
  
  # Cancel each job
  for JOB_ID in $GPU_JOBS; do
    echo "Cancelling job: $JOB_ID"
    run_aws batch terminate-job \
      --job-id "$JOB_ID" \
      --reason "Demo reset" \
      || echo "Could not cancel job $JOB_ID (may already be completed)"
  done
fi

# Reset Lambda function configuration if needed
echo "Checking Lambda function configuration..."
LAMBDA_FUNCTION=$(get_stack_output "$STACK_NAME" "OrchestratorLambdaArn" 2>/dev/null || echo "NOT_FOUND")

if [ "$LAMBDA_FUNCTION" != "NOT_FOUND" ]; then
  # Update Lambda environment variables to reset state
  run_aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --environment "Variables={RESET_TIMESTAMP=$(date +%s)}" \
    || echo "Could not update Lambda function configuration"
fi

# Check dashboard bucket and refresh the dashboard
echo "Checking dashboard bucket..."
DASHBOARD_BUCKET=$(get_stack_output "$STACK_NAME" "DashboardBucketName" 2>/dev/null || echo "NOT_FOUND")

if [ "$DASHBOARD_BUCKET" != "NOT_FOUND" ]; then
  echo "Refreshing dashboard data..."
  
  # Get current IP for bucket policy
  CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
  if [ -z "$CURRENT_IP" ]; then
    echo "Warning: Could not determine your current IP address for dashboard access."
    echo "Using fallback access method."
    CURRENT_IP="0.0.0.0/0"  # Allow from any IP as fallback
  else
    echo "Restricting dashboard access to your IP: $CURRENT_IP"
    CURRENT_IP="$CURRENT_IP/32"  # Convert to CIDR notation
  fi

  # Create and set the bucket policy for IP restriction
  echo "Updating bucket policy to restrict access to your IP..."
  cat > /tmp/bucket_policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObjectForSpecificIP",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${DASHBOARD_BUCKET}/*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": "${CURRENT_IP}"
        }
      }
    }
  ]
}
EOF

  # Apply the bucket policy
  run_aws s3api put-bucket-policy --bucket "$DASHBOARD_BUCKET" --policy file:///tmp/bucket_policy.json || echo "Could not update bucket policy"
  
  # Refresh dashboard files
  if [ -d "./dashboard/" ]; then
    echo "Re-uploading dashboard files..."
    run_aws s3 sync --delete "./dashboard/" "s3://${DASHBOARD_BUCKET}/" || echo "Could not sync dashboard files"
  else
    echo "Dashboard directory not found - skipping file sync"
  fi
  
  # Display dashboard URL
  DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL" 2>/dev/null || echo "NOT_FOUND")
  if [ "$DASHBOARD_URL" != "NOT_FOUND" ]; then
    echo "Dashboard URL: $DASHBOARD_URL"
    echo "Note: The dashboard is only accessible from your current IP address: ${CURRENT_IP%/32}"
  fi
else
  echo "Dashboard bucket not found in stack outputs"
fi

# Use pre-generated backup data if available
echo "Checking for backup data..."
if run_aws s3 ls "s3://$BUCKET_NAME/backup/" &>/dev/null; then
  confirm "Would you like to use pre-generated backup data for the demo?"
  
  # Copy backup data to results directory
  echo "Copying backup data to results directory..."
  run_aws s3 cp --recursive "s3://$BUCKET_NAME/backup/" "s3://$BUCKET_NAME/results/" \
    || echo "Could not copy backup data"
fi

echo ""
echo "==========================================="
echo "Demo reset completed!"
echo "==========================================="
echo "Next steps:"
echo "1. Verify the dashboard is accessible"
echo "2. Start the demo with: ./start_demo.sh"
echo "==========================================="
