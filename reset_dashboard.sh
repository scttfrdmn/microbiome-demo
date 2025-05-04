#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# reset_dashboard.sh - Reset the dashboard state and create a new progress file

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
echo "Resetting dashboard state"
echo "==========================================="
echo "Data bucket: $BUCKET_NAME"
echo "Dashboard bucket: $DASHBOARD_BUCKET"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Generate a new job ID
RANDOM_JOB_ID="microbiome-demo-job-$(date +%s)-reset"
CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create a new progress.json showing the pipeline as initializing
PROGRESS_JSON='{
  "status": "INITIALIZING",
  "time_elapsed": 0,
  "completed_samples": 0,
  "total_samples": 100,
  "sample_status": {
    "completed": 0,
    "running": 0,
    "pending": 100,
    "failed": 0
  },
  "timestamp": "'$CURRENT_TIMESTAMP'",
  "job_id": "'$RANDOM_JOB_ID'"
}'

echo "$PROGRESS_JSON" > /tmp/progress.json

# Upload to both locations
echo "Uploading new progress.json with INITIALIZING status..."
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"

# Copy to data bucket as well to ensure continuous_data_update.sh picks it up
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Dashboard has been reset to INITIALIZING state with new job ID: $RANDOM_JOB_ID"
echo "The dashboard should now show 0% progress when refreshed."
echo ""
echo "To simulate a running pipeline, use copy_data_to_dashboard.sh"
echo "To view the dashboard, open the URL from start_demo.sh output"
echo "==========================================="