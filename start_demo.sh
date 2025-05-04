#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
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
echo "Starting Microbiome Demo v${VERSION:-unknown}"
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
  --cli-binary-format raw-in-base64-out \
  --payload '{"action": "start_demo"}' \
  response.json

# Get dashboard info from CloudFormation stack
DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL")
DASHBOARD_BUCKET=$(get_stack_output "$STACK_NAME" "DashboardBucketName")

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
echo "Setting bucket policy to restrict access to your IP..."
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
run_aws s3api put-bucket-policy --bucket "$DASHBOARD_BUCKET" --policy file:///tmp/bucket_policy.json

# Copy dashboard files to the website bucket
echo "Copying dashboard files to the website bucket..."
run_aws s3 sync --delete "./dashboard/" "s3://${DASHBOARD_BUCKET}/"

echo ""
echo "Demo started successfully!"
echo "Dashboard URL: $DASHBOARD_URL"
echo ""
echo "Please open the dashboard URL in your browser to monitor progress"
echo "Note: The dashboard is only accessible from your current IP address: ${CURRENT_IP%/32}"
