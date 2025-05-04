#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# copy_data_to_dashboard.sh - Copy data files from data bucket to dashboard bucket

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

# Get dashboard bucket name
DASHBOARD_BUCKET=$(cat /tmp/dashboard_bucket.txt 2>/dev/null || echo "${BUCKET_NAME}-dashboard")

echo "==========================================="
echo "Copying data files to dashboard bucket"
echo "==========================================="
echo "Data bucket: $BUCKET_NAME"
echo "Dashboard bucket: $DASHBOARD_BUCKET"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Create sample data files in the expected locations
echo "Creating test progress.json..."
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

# Create directory for test summary data
mkdir -p /tmp/summary
cp dashboard/data/test_microbiome_summary.json /tmp/summary/microbiome_summary.json

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

# Upload test files directly to the dashboard bucket
echo "Uploading test data files to dashboard bucket..."
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/summary/microbiome_summary.json "s3://${DASHBOARD_BUCKET}/data/summary.json" --content-type "application/json"
run_aws s3 cp /tmp/resources.json "s3://${DASHBOARD_BUCKET}/data/resources.json" --content-type "application/json"

echo "Test data files have been uploaded to the dashboard bucket"
echo "The dashboard should now be able to access the data"
echo "==========================================="