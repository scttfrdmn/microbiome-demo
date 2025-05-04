#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# test_full_pipeline_cycle.sh - Test a complete pipeline cycle from init to completion

set -e  # Exit on error

# Source configuration
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
echo "Testing complete pipeline cycle"
echo "==========================================="
echo "Data bucket: $BUCKET_NAME"
echo "Dashboard bucket: $DASHBOARD_BUCKET"
echo "Region: $REGION"
if [ -n "$AWS_PROFILE" ]; then
  echo "AWS Profile: $AWS_PROFILE"
fi
echo "==========================================="

# Generate a unique job ID for this test
TEST_JOB_ID="microbiome-demo-job-cycle-test-$(date +%s)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Step 1: Create INITIALIZING state
echo "Step 1: Creating INITIALIZING state..."
INITIALIZING_JSON='{
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
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$INITIALIZING_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded INITIALIZING state (0%). Waiting 5 seconds..."
sleep 5

# Step 2: Create RUNNING state (25%)
echo "Step 2: Creating RUNNING state (25%)..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUNNING_25_JSON='{
  "status": "RUNNING",
  "time_elapsed": 225,
  "completed_samples": 25,
  "total_samples": 100,
  "sample_status": {
    "completed": 25,
    "running": 10,
    "pending": 65,
    "failed": 0
  },
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$RUNNING_25_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded RUNNING state (25%). Waiting 5 seconds..."
sleep 5

# Step 3: Create RUNNING state (50%)
echo "Step 3: Creating RUNNING state (50%)..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUNNING_50_JSON='{
  "status": "RUNNING",
  "time_elapsed": 450,
  "completed_samples": 50,
  "total_samples": 100,
  "sample_status": {
    "completed": 50,
    "running": 10,
    "pending": 40,
    "failed": 0
  },
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$RUNNING_50_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded RUNNING state (50%). Waiting 5 seconds..."
sleep 5

# Step 4: Create RUNNING state (75%)
echo "Step 4: Creating RUNNING state (75%)..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUNNING_75_JSON='{
  "status": "RUNNING",
  "time_elapsed": 675,
  "completed_samples": 75,
  "total_samples": 100,
  "sample_status": {
    "completed": 75,
    "running": 10,
    "pending": 15,
    "failed": 0
  },
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$RUNNING_75_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded RUNNING state (75%). Waiting 5 seconds..."
sleep 5

# Step 5: Create RUNNING state (95%)
echo "Step 5: Creating RUNNING state (95%)..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUNNING_95_JSON='{
  "status": "RUNNING",
  "time_elapsed": 855,
  "completed_samples": 95,
  "total_samples": 100,
  "sample_status": {
    "completed": 95,
    "running": 5,
    "pending": 0,
    "failed": 0
  },
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$RUNNING_95_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded RUNNING state (95%). Waiting 5 seconds..."
sleep 5

# Step 6: Create COMPLETED state (100%)
echo "Step 6: Creating COMPLETED state (100%)..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
  "timestamp": "'$TIMESTAMP'",
  "job_id": "'$TEST_JOB_ID'"
}'

echo "$COMPLETED_JSON" > /tmp/progress.json
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/data/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${DASHBOARD_BUCKET}/status/progress.json" --content-type "application/json"
run_aws s3 cp /tmp/progress.json "s3://${BUCKET_NAME}/status/progress.json" --content-type "application/json"

echo "Uploaded COMPLETED state (100%)."
echo "==========================================="
echo "Test completed successfully!"
echo "The dashboard has gone through a complete pipeline cycle"
echo "Job ID: $TEST_JOB_ID"
echo ""
echo "To start a new cycle, run this script again or use reset_dashboard.sh"
echo "==========================================="