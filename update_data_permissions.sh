#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# update_data_permissions.sh - Add permissions to allow dashboard to access data files

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
echo "Updating data permissions for dashboard"
echo "==========================================="
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Create the bucket policy JSON
POLICY_FILE="/tmp/dashboard_data_policy.json"
cat > "$POLICY_FILE" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadForDashboardData",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}/status/progress.json",
        "arn:aws:s3:::${BUCKET_NAME}/results/summary/microbiome_summary.json",
        "arn:aws:s3:::${BUCKET_NAME}/monitoring/resources.json"
      ]
    }
  ]
}
EOF

# Apply the policy to the bucket
echo "Setting bucket policy to allow public access to dashboard data files..."
run_aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file://"$POLICY_FILE"

# Check if the operation was successful
if [ $? -eq 0 ]; then
  echo "Successfully updated bucket policy for $BUCKET_NAME"
  echo "Data files should now be accessible to the dashboard"
  echo "==========================================="
else
  echo "Failed to update bucket policy"
  echo "You may need to manually update the bucket policy in the AWS console"
  echo "==========================================="
  exit 1
fi

# Test accessing one of the files to verify success
echo "Testing access to data files..."
run_aws s3 ls "s3://${BUCKET_NAME}/status/" || echo "No status files found yet - pipeline may still be starting"
echo "==========================================="

echo "Creating sample data files for testing..."
# Create sample data files in the expected locations
echo "Creating progress.json..."
PROGRESS_JSON='{
  "status": "RUNNING",
  "time_elapsed": 120,
  "completed_samples": 25,
  "total_samples": 100,
  "sample_status": {
    "completed": 25,
    "running": 10,
    "pending": 65,
    "failed": 0
  },
  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
  "job_id": "microbiome-demo-job-'$(date +%s)'"
}'
echo "$PROGRESS_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json"

# Create directory for test summary data
mkdir -p /tmp/summary
cp dashboard/data/test_microbiome_summary.json /tmp/summary/microbiome_summary.json

# Upload to S3
echo "Uploading test summary data..."
run_aws s3 cp /tmp/summary/microbiome_summary.json "s3://${BUCKET_NAME}/results/summary/microbiome_summary.json"

# Create test resources data
RESOURCES_JSON='{
  "utilization": [
    {"time": 110, "cpu": 47, "memory": 78, "gpu": 29},
    {"time": 111, "cpu": 44, "memory": 75, "gpu": 40},
    {"time": 112, "cpu": 44, "memory": 77, "gpu": 53},
    {"time": 113, "cpu": 46, "memory": 73, "gpu": 42},
    {"time": 114, "cpu": 51, "memory": 74, "gpu": 54},
    {"time": 115, "cpu": 52, "memory": 71, "gpu": 43},
    {"time": 116, "cpu": 51, "memory": 70, "gpu": 50},
    {"time": 117, "cpu": 53, "memory": 76, "gpu": 37},
    {"time": 118, "cpu": 50, "memory": 70, "gpu": 53},
    {"time": 119, "cpu": 51, "memory": 79, "gpu": 35}
  ],
  "instances": {
    "cpu": 8,
    "gpu": 2
  },
  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
}'
echo "$RESOURCES_JSON" > /tmp/resources.json
run_aws s3 cp /tmp/resources.json "s3://${BUCKET_NAME}/monitoring/resources.json"

echo "Test data files have been created and uploaded to S3"
echo "The dashboard should now be able to access the data"
echo "==========================================="