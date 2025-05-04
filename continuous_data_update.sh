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
echo "This script will update the dashboard data every 10 seconds."
echo "Press Ctrl+C to stop."
echo "==========================================="

count=0
while true; do
  # Call the copy data script
  echo "Update #$count: $(date)"
  ./copy_data_to_dashboard.sh
  
  # Every 3 runs, check if the demo is complete, but don't stop updating
  if [ $((count % 3)) -eq 0 ]; then
    # Check if progress.json shows COMPLETED status
    if [ -f "/tmp/progress.json" ]; then
      PROGRESS_STATUS=$(grep -o '"status":"[^"]*"' /tmp/progress.json | cut -d':' -f2 | tr -d '"')
      if [ "$PROGRESS_STATUS" = "COMPLETED" ]; then
        echo "==========================================="
        echo "Demo status: COMPLETED"
        echo "Continuous updates will keep running to allow for new demo runs."
        echo "To stop updates manually, press Ctrl+C."
        echo "==========================================="
      fi
    fi
  fi
  
  count=$((count + 1))
  sleep 2
done