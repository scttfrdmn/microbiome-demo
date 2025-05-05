#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# continuous_data_update.sh - Continuously update dashboard data from real pipeline outputs

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
echo "Starting continuous dashboard data updates"
echo "==========================================="
echo "This script will update the dashboard data every 2 seconds."
echo "Press Ctrl+C to stop."
echo "==========================================="

count=0
while true; do
  # Call the copy data script with error handling
  echo "Update #$count: $(date)"
  if ! ./copy_data_to_dashboard.sh; then
    echo "ERROR: Failed to copy data to dashboard (attempt #$count)"
    echo "Will retry on next iteration"
    # Continue running despite errors to allow recovery
  fi
  
  # Every 3 runs, check pipeline status and detect new job IDs
  if [ $((count % 3)) -eq 0 ]; then
    # Track the current job ID to detect new runs
    CURRENT_JOB_ID=""
    if [ -f "/tmp/job_id.txt" ]; then
      CURRENT_JOB_ID=$(cat /tmp/job_id.txt)
    fi
    
    # Check if progress.json shows COMPLETED status or new job ID
    if [ -f "/tmp/progress.json" ]; then
      # First check for COMPLETED status with a direct grep
      if grep -q '"status":"COMPLETED"' /tmp/progress.json; then
        echo "==========================================="
        echo "Demo status: COMPLETED"
        echo "Pipeline has completed. Continuous updates are no longer needed."
        echo "The script will now terminate."
        echo "If you need to run a new pipeline, execute start_demo.sh again."
        echo "==========================================="
        # Clear the process ID file to indicate we've stopped gracefully
        echo "" > /tmp/update_process.pid 2>/dev/null || true
        exit 0
      fi
      
      # Extract status from progress.json
      PROGRESS_STATUS=$(grep -o '"status":"[^"]*"' /tmp/progress.json | cut -d':' -f2 | tr -d '"')
      
      # Extract job ID from progress.json if present
      NEW_JOB_ID=$(grep -o '"job_id":"[^"]*"' /tmp/progress.json | cut -d':' -f2 | tr -d '"')
      
      # Store new job ID if different
      if [ -n "$NEW_JOB_ID" ] && [ "$NEW_JOB_ID" != "$CURRENT_JOB_ID" ]; then
        echo "==========================================="
        echo "New job detected: $NEW_JOB_ID"
        echo "Previous job: $CURRENT_JOB_ID"
        echo "Updating job tracking for dashboard reset detection"
        echo "==========================================="
        echo "$NEW_JOB_ID" > /tmp/job_id.txt
      fi
      
      # Report status for other states
      echo "==========================================="
      echo "Demo status: $PROGRESS_STATUS"
      if [ "$PROGRESS_STATUS" = "INITIALIZING" ]; then
        echo "Pipeline is initializing. Empty chart data is being displayed."
      elif [ "$PROGRESS_STATUS" = "RUNNING" ]; then
        echo "Pipeline is running. Real-time data is being displayed."
      fi
      echo "To stop updates manually, press Ctrl+C."
      echo "==========================================="
    fi
  fi
  
  count=$((count + 1))
  sleep 2
done