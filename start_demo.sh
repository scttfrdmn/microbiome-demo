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

# Get dashboard info from CloudFormation stack or use manual bucket if available
DASHBOARD_URL=$(get_stack_output "$STACK_NAME" "DashboardURL")
DASHBOARD_BUCKET=$(get_stack_output "$STACK_NAME" "DashboardBucketName")

# If not found in stack outputs, use our manually created bucket
if [ -z "$DASHBOARD_BUCKET" ]; then
  if [ -f "/tmp/dashboard_bucket.txt" ]; then
    DASHBOARD_BUCKET=$(cat /tmp/dashboard_bucket.txt)
    DASHBOARD_URL="http://${DASHBOARD_BUCKET}.s3-website-${REGION}.amazonaws.com"
    echo "Using manually created dashboard bucket: $DASHBOARD_BUCKET"
  else
    DASHBOARD_BUCKET="${BUCKET_NAME}-dashboard"
    DASHBOARD_URL="http://${DASHBOARD_BUCKET}.s3-website-${REGION}.amazonaws.com"
    echo "Creating new dashboard bucket: $DASHBOARD_BUCKET"
    run_aws s3api create-bucket --bucket $DASHBOARD_BUCKET --region $REGION
    run_aws s3 website $DASHBOARD_BUCKET --index-document index.html --error-document error.html
    run_aws s3api put-public-access-block --bucket $DASHBOARD_BUCKET --public-access-block-configuration '{"BlockPublicAcls": false, "IgnorePublicAcls": false, "BlockPublicPolicy": false, "RestrictPublicBuckets": false}'
    
    # Save bucket name for future reference
    echo "$DASHBOARD_BUCKET" > /tmp/dashboard_bucket.txt
  fi
fi

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

# Set the content types for special file types
CONTENT_TYPES=(
  "html:text/html"
  "css:text/css"
  "js:application/javascript"
  "json:application/json"
  "png:image/png"
  "jpg:image/jpeg"
  "svg:image/svg+xml"
)

# Configure the dashboard with correct paths
echo "Configuring dashboard with correct S3 paths..."
TEMP_CONFIG_FILE="/tmp/dashboard_config.js"
cp "./dashboard/js/dashboard_config.js" "$TEMP_CONFIG_FILE"

# Replace placeholders with actual values
sed -i.bak "s|{{DASHBOARD_BASE_URL}}|http://${DASHBOARD_BUCKET}.s3-website-${REGION}.amazonaws.com|g" "$TEMP_CONFIG_FILE"
sed -i.bak "s|{{BUCKET_NAME}}|${BUCKET_NAME}|g" "$TEMP_CONFIG_FILE"
sed -i.bak "s|{{ENVIRONMENT}}|production|g" "$TEMP_CONFIG_FILE"

# Copy the configured file back
cp "$TEMP_CONFIG_FILE" "./dashboard/js/dashboard_config.js"

# Copy dashboard files to the website bucket with appropriate content types
echo "Copying dashboard files to the website bucket..."
# First sync all files without content type
run_aws s3 sync --delete "./dashboard/" "s3://${DASHBOARD_BUCKET}/"

# Then set content types for specific file extensions
for CONTENT_TYPE in "${CONTENT_TYPES[@]}"; do
  EXT="${CONTENT_TYPE%%:*}"
  TYPE="${CONTENT_TYPE##*:}"
  echo "Setting content-type $TYPE for *.$EXT files..."
  
  # Find all files of this extension in the dashboard directory
  find "./dashboard" -type f -name "*.$EXT" | while read -r FILE; do
    # Get relative path
    REL_PATH="${FILE#./dashboard/}"
    # Upload with content-type
    run_aws s3 cp "$FILE" "s3://${DASHBOARD_BUCKET}/${REL_PATH}" --content-type "$TYPE"
  done
done

echo ""
echo "Demo started successfully!"
echo "Dashboard URL: $DASHBOARD_URL"
echo ""
echo "Please open the dashboard URL in your browser to monitor progress"
echo "Note: The dashboard is only accessible from your current IP address: ${CURRENT_IP%/32}"
echo ""
echo "The enhanced dashboard includes:"
echo "1. Simulation data refreshing (automatic and manual)"
echo "2. Download functionality for reports and charts"
echo "3. Enhanced tooltips with detailed information"
