#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# test_dashboard_reset.sh - Test the dashboard reset functionality by simulating different states

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
echo "Testing dashboard reset functionality"
echo "==========================================="
echo "Data bucket: $BUCKET_NAME"
echo "Dashboard bucket: $DASHBOARD_BUCKET"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Step 1: Create a "COMPLETED" state progress file
echo "Step 1: Creating COMPLETED state progress file..."
COMPLETED_JOB_ID="microbiome-demo-job-completed-test"
CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

COMPLETED_JSON='{
  "status": "COMPLETED",
  "time_elapsed": 900,
  "completed_samples": 100,
  "total_samples": 100,
  "sample_status": {
    "completed": 100,
    "running": 0,
    "pending": 0,
    "failed": 0
  },
  "timestamp": "'$CURRENT_TIMESTAMP'",
  "job_id": "'$COMPLETED_JOB_ID'"
}'

echo "$COMPLETED_JSON" > /tmp/completed_progress.json

# Upload to both buckets
run_aws s3 cp /tmp/completed_progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/completed_progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/completed_progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded COMPLETED state. Please verify the dashboard shows 100% complete."
echo "Wait 10 seconds for the dashboard to refresh, then press Enter to continue..."
read -p ""

# Step 2: Create a new "RUNNING" state with a different job ID to test reset
echo "Step 2: Creating RUNNING state with a new job ID..."
NEW_JOB_ID="microbiome-demo-job-$(date +%s)-new-run"
CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

RUNNING_JSON='{
  "status": "RUNNING",
  "time_elapsed": 300,
  "completed_samples": 42,
  "total_samples": 100,
  "sample_status": {
    "completed": 42,
    "running": 10,
    "pending": 48,
    "failed": 0
  },
  "timestamp": "'$CURRENT_TIMESTAMP'",
  "job_id": "'$NEW_JOB_ID'"
}'

echo "$RUNNING_JSON" > /tmp/running_progress.json

# Upload to both buckets
run_aws s3 cp /tmp/running_progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/running_progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/running_progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded RUNNING state with new job ID. Please verify the dashboard resets and shows 42% complete."
echo "The dashboard should automatically reset due to the job ID change."
echo ""
echo "Test complete! If the dashboard properly resets from COMPLETED to RUNNING state,"
echo "the reset mechanism is working correctly."
echo "==========================================="