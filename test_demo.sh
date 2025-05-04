#!/bin/bash
# test_demo.sh
# Script to run a test job with a small subset of samples

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
echo "Microbiome Demo Test Run"
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

# Check if test sample list exists
echo "Checking for test sample list..."
if ! run_aws s3 ls "s3://$BUCKET_NAME/input/test_sample_list.csv" &>/dev/null; then
  echo "❌ Test sample list not found: s3://$BUCKET_NAME/input/test_sample_list.csv"
  echo "Please run prepare_demo_data.sh first."
  exit 1
fi

# Get CloudFormation stack outputs
echo "Getting stack outputs..."
LAMBDA_FUNCTION=$(get_stack_output "$STACK_NAME" "OrchestratorLambdaArn" 2>/dev/null || echo "NOT_FOUND")

DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL" 2>/dev/null || echo "NOT_FOUND")

if [ "$LAMBDA_FUNCTION" == "NOT_FOUND" ]; then
  echo "❌ Lambda function not found in stack outputs"
  exit 1
fi

# Create test payload
echo "Creating test job payload..."
cat > test_payload.json << EOF
{
  "action": "test_demo",
  "parameters": {
    "sample_list": "s3://$BUCKET_NAME/input/test_sample_list.csv",
    "output_prefix": "test_run"
  }
}
EOF

# Invoke Lambda function to start test job
echo "Invoking Lambda function to start test job..."
run_aws lambda invoke \
  --function-name $LAMBDA_FUNCTION \
  --payload file://test_payload.json \
  response.json

# Check if Lambda invocation was successful
if [ $? -ne 0 ]; then
  echo "❌ Failed to invoke Lambda function"
  exit 1
fi

# Parse job ID from response
JOB_ID=$(grep -o '"jobId":"[^"]*"' response.json | cut -d'"' -f4)

if [ -z "$JOB_ID" ]; then
  echo "⚠️ No job ID found in Lambda response"
  echo "Response: $(cat response.json)"
else
  echo "✅ Test job submitted with ID: $JOB_ID"
fi

# Output dashboard URL
if [ "$DASHBOARD_URL" != "NOT_FOUND" ]; then
  echo ""
  echo "You can monitor the test job progress at:"
  echo "$DASHBOARD_URL"
  echo ""
  echo "The test job uses 5 samples and should complete in approximately 5 minutes."
else
  echo "⚠️ Dashboard URL not found in stack outputs"
fi

# Check AWS Batch job queue status
echo "Checking AWS Batch job queue status..."
CPU_JOB_QUEUE=$(run_aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id CPUJobQueue \
  --query "StackResources[0].PhysicalResourceId" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CPU_JOB_QUEUE" != "NOT_FOUND" ]; then
  run_aws batch describe-job-queues \
    --job-queues "$CPU_JOB_QUEUE" \
    --query "jobQueues[0].status" \
    --output text
else
  echo "⚠️ Could not find job queue in stack resources"
fi

# Wait for test job to start
echo ""
echo "Waiting for test job to start..."
sleep 10

# Poll job status a few times
for i in {1..5}; do
  if [ -n "$JOB_ID" ]; then
    JOB_STATUS=$(run_aws batch describe-jobs \
      --jobs "$JOB_ID" \
      --query "jobs[0].status" \
      --output text 2>/dev/null || echo "UNKNOWN")
    
    echo "Job status: $JOB_STATUS"
    
    if [ "$JOB_STATUS" == "SUCCEEDED" ]; then
      echo "✅ Test job completed successfully!"
      break
    elif [ "$JOB_STATUS" == "FAILED" ]; then
      echo "❌ Test job failed. Check the AWS Batch console for details."
      break
    fi
  fi
  
  if [ $i -lt 5 ]; then
    sleep 30
  fi
done

echo ""
echo "Test job is now running. It will take approximately 5 minutes to complete."
echo "You can check the final results in the S3 bucket:"
echo "s3://$BUCKET_NAME/results/test_run/"
echo ""
echo "If everything looks good, you're ready for the full demo!"
echo "Run ./start_demo.sh when you're ready to execute the full demonstration."
echo "==========================================="
