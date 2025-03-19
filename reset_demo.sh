#!/bin/bash
# reset_demo.sh
# Quick recovery script for the demo in case of issues

set -e  # Exit on error

# Source configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
else
  BUCKET_NAME=${1:-omics-demo-bucket}
  REGION=${2:-us-east-1}
  STACK_NAME="omics-demo"
fi

echo "==========================================="
echo "Omics Demo Reset"
echo "==========================================="
echo "Stack name: $STACK_NAME"
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "==========================================="

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
CPU_JOB_QUEUE=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id CPUJobQueue \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

GPU_JOB_QUEUE=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id GPUJobQueue \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

# Cancel all running jobs
echo "Cancelling all running jobs..."
if [ "$CPU_JOB_QUEUE" != "NOT_FOUND" ]; then
  # Get all RUNNABLE and STARTING jobs
  CPU_JOBS=$(aws batch list-jobs \
    --job-queue "$CPU_JOB_QUEUE" \
    --job-status RUNNABLE STARTING RUNNING \
    --query "jobSummaryList[*].jobId" \
    --output text)
  
  # Cancel each job
  for JOB_ID in $CPU_JOBS; do
    echo "Cancelling job: $JOB_ID"
    aws batch terminate-job \
      --job-id "$JOB_ID" \
      --reason "Demo reset" \
      || echo "Could not cancel job $JOB_ID (may already be completed)"
  done
fi

if [ "$GPU_JOB_QUEUE" != "NOT_FOUND" ]; then
  # Get all RUNNABLE and STARTING jobs
  GPU_JOBS=$(aws batch list-jobs \
    --job-queue "$GPU_JOB_QUEUE" \
    --job-status RUNNABLE STARTING RUNNING \
    --query "jobSummaryList[*].jobId" \
    --output text)
  
  # Cancel each job
  for JOB_ID in $GPU_JOBS; do
    echo "Cancelling job: $JOB_ID"
    aws batch terminate-job \
      --job-id "$JOB_ID" \
      --reason "Demo reset" \
      || echo "Could not cancel job $JOB_ID (may already be completed)"
  done
fi

# Reset Lambda function configuration if needed
echo "Checking Lambda function configuration..."
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='OrchestratorLambdaArn'].OutputValue" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$LAMBDA_FUNCTION" != "NOT_FOUND" ]; then
  # Update Lambda environment variables to reset state
  aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --environment "Variables={RESET_TIMESTAMP=$(date +%s)}" \
    || echo "Could not update Lambda function configuration"
fi

# Check EC2 instance for dashboard
echo "Checking EC2 instance for dashboard..."
EC2_INSTANCE=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id DashboardInstance \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$EC2_INSTANCE" != "NOT_FOUND" ]; then
  # Get instance status
  INSTANCE_STATUS=$(aws ec2 describe-instance-status \
    --instance-ids "$EC2_INSTANCE" \
    --query "InstanceStatuses[0].InstanceStatus.Status" \
    --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [ "$INSTANCE_STATUS" == "ok" ]; then
    echo "Resetting dashboard instance..."
    # Send SSM command to reset dashboard
    aws ssm send-command \
      --instance-ids "$EC2_INSTANCE" \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=['sudo systemctl restart nginx']" \
      --comment "Reset dashboard for demo" \
      || echo "Could not reset dashboard (SSM may not be configured)"
  else
    echo "Dashboard instance is not running or not ready: $INSTANCE_STATUS"
  fi
fi

# Use pre-generated backup data if available
echo "Checking for backup data..."
if aws s3 ls "s3://$BUCKET_NAME/backup/" &>/dev/null; then
  confirm "Would you like to use pre-generated backup data for the demo?"
  
  # Copy backup data to results directory
  echo "Copying backup data to results directory..."
  aws s3 cp --recursive "s3://$BUCKET_NAME/backup/" "s3://$BUCKET_NAME/results/" \
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
