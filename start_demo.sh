#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# start_demo.sh - Launch the microbiome demo workflow

# Source configuration if it exists
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
echo "Starting Microbiome Demo"
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

# Get Lambda function name from CloudFormation stack
LAMBDA_FUNCTION=$(get_stack_output "$STACK_NAME" "OrchestratorLambdaArn")

if [ -z "$LAMBDA_FUNCTION" ]; then
  echo "Error: Could not find Lambda function in stack outputs"
  exit 1
fi

# Invoke the orchestrator Lambda function
echo "Invoking orchestrator function: $LAMBDA_FUNCTION"
run_aws lambda invoke \
  --function-name $LAMBDA_FUNCTION \
  --invocation-type Event \
  --payload '{"action": "start_demo"}' \
  response.json

# Get dashboard URL
DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL")

echo ""
echo "Demo started successfully!"
echo "Dashboard URL: $DASHBOARD_URL"
echo ""
echo "Please open the dashboard URL in your browser to monitor progress"
