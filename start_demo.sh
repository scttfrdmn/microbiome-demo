#!/bin/bash
# start_demo.sh - Launch the microbiome demo workflow

source ./config.sh

echo "==========================================="
echo "Starting Microbiome Demo"
echo "==========================================="
echo "Stack name: $STACK_NAME"
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "==========================================="

# Get Lambda function name from CloudFormation stack
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='OrchestratorLambdaArn'].OutputValue" \
  --output text)

if [ -z "$LAMBDA_FUNCTION" ]; then
  echo "Error: Could not find Lambda function in stack outputs"
  exit 1
fi

# Invoke the orchestrator Lambda function
echo "Invoking orchestrator function: $LAMBDA_FUNCTION"
aws lambda invoke \
  --function-name $LAMBDA_FUNCTION \
  --invocation-type Event \
  --payload '{"action": "start_demo"}' \
  response.json

# Get dashboard URL
DASHBOARD_URL=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='DashboardURL'].OutputValue" \
  --output text)

echo ""
echo "Demo started successfully!"
echo "Dashboard URL: $DASHBOARD_URL"
echo ""
echo "Please open the dashboard URL in your browser to monitor progress"
