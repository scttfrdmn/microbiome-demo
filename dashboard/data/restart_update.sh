#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.

# Kill the existing update_data.sh process if running
echo "Looking for existing update_data.sh process..."
UPDATE_PID=$(ps aux | grep update_data.sh | grep -v grep | awk '{print $2}')

if [ -n "$UPDATE_PID" ]; then
  echo "Found update_data.sh process (PID: $UPDATE_PID). Stopping it..."
  kill $UPDATE_PID
  sleep 2
  
  # Make sure it's really dead
  if ps -p $UPDATE_PID > /dev/null; then
    echo "Process didn't exit gracefully. Forcing termination..."
    kill -9 $UPDATE_PID
    sleep 1
  fi
  
  echo "Process stopped."
else
  echo "No running update_data.sh process found."
fi

# Make sure the script is executable
chmod +x update_data.sh

# Start the update_data.sh script in the background
echo "Starting update_data.sh in the background..."
./update_data.sh > update_data.log 2>&1 &
NEW_PID=$!

echo "Started update_data.sh with PID: $NEW_PID"
echo "Logs will be written to update_data.log"

# Wait a moment for the script to start
sleep 2

# Check if it's running
if ps -p $NEW_PID > /dev/null; then
  echo "update_data.sh is running successfully."
else
  echo "Error: Failed to start update_data.sh. Check update_data.log for details."
  cat update_data.log
fi

echo "Done."