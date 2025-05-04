#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# deploy_lambda_updater.sh - Deploy the Lambda function for validating and updating dashboard data

set -e  # Exit on error

# Source configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
else
  echo "Error: config.sh not found. Please run setup.sh first."
  exit 1
fi

# Source AWS helper functions
if [ -f "./aws_helper.sh" ]; then
  source ./aws_helper.sh
else
  echo "Error: aws_helper.sh not found. Please run setup.sh first."
  exit 1
fi

echo "==========================================="
echo "Deploying Lambda Dashboard Updater"
echo "==========================================="
echo "Bucket: $BUCKET_NAME"
echo "Dashboard Bucket: ${BUCKET_NAME}-dashboard"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Create a temporary directory for the lambda package
TEMP_DIR="/tmp/lambda_package"
mkdir -p "$TEMP_DIR"

# Copy the lambda function to the package directory
cp "./lambda/progress_updater.py" "$TEMP_DIR/"

# Create zip package
echo "Creating Lambda deployment package..."
cd "$TEMP_DIR"
zip -r lambda_package.zip progress_updater.py
cd - > /dev/null

# Copy the package to S3
PACKAGE_S3_KEY="lambda/lambda_package.zip"
echo "Uploading Lambda package to S3..."
run_aws s3 cp "$TEMP_DIR/lambda_package.zip" "s3://$BUCKET_NAME/$PACKAGE_S3_KEY"

# Get the Lambda stack name
LAMBDA_STACK_NAME="${STACK_NAME}-lambda-updater"

# Check if the Lambda CloudFormation stack already exists
if check_stack_exists "$LAMBDA_STACK_NAME"; then
  echo "Updating existing Lambda stack: $LAMBDA_STACK_NAME"
  
  # Update the Lambda function code first
  FUNCTION_NAME="microbiome-demo-progress-updater"
  echo "Updating Lambda function code..."
  run_aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --s3-bucket "$BUCKET_NAME" \
    --s3-key "$PACKAGE_S3_KEY" \
    --publish \
    --region "$REGION"
  
  # Update the CloudFormation stack
  PARAMS="ParameterKey=DataBucketName,ParameterValue=$BUCKET_NAME"
  PARAMS="$PARAMS ParameterKey=DashboardBucketName,ParameterValue=${BUCKET_NAME}-dashboard"
  PARAMS="$PARAMS ParameterKey=JobQueueName,ParameterValue=${STACK_NAME}-queue"
  
  update_stack "$LAMBDA_STACK_NAME" "./lambda/lambda_updater.yaml" "$PARAMS"
else
  echo "Creating new Lambda stack: $LAMBDA_STACK_NAME"
  
  # Deploy with CloudFormation
  PARAMS="ParameterKey=DataBucketName,ParameterValue=$BUCKET_NAME"
  PARAMS="$PARAMS ParameterKey=DashboardBucketName,ParameterValue=${BUCKET_NAME}-dashboard"
  PARAMS="$PARAMS ParameterKey=JobQueueName,ParameterValue=${STACK_NAME}-queue"
  
  create_stack "$LAMBDA_STACK_NAME" "./lambda/lambda_updater.yaml" "$PARAMS"
  
  # Update the Lambda function code after creation
  FUNCTION_NAME="microbiome-demo-progress-updater"
  echo "Updating Lambda function code..."
  run_aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --s3-bucket "$BUCKET_NAME" \
    --s3-key "$PACKAGE_S3_KEY" \
    --publish \
    --region "$REGION"
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "==========================================="
echo "Lambda deployment completed successfully!"
echo "==========================================="
echo "The Lambda function will now update the dashboard data every minute,"
echo "ensuring consistent and validated data from the real pipeline."
echo ""
echo "To monitor the Lambda execution, check CloudWatch Logs:"
echo "https://console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/aws/lambda/$FUNCTION_NAME"
echo "==========================================="