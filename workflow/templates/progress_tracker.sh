#!/bin/bash
# Progress tracker for Nextflow processes
# Reports process start/completion to a JSON file in S3

# Environment variables expected:
# PROCESS_NAME: Name of the current process
# PROCESS_STATUS: "started", "completed", or "failed"
# WORKFLOW_ID: Unique identifier for this workflow run
# BUCKET_NAME: S3 bucket to store progress data
# TOTAL_PROCESSES: Total number of processes expected in the workflow

set -e

# Calculate timestamp
TIMESTAMP=$(date +%s)
HUMAN_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# Create progress JSON
cat > progress_update.json << EOF
{
  "process": "${PROCESS_NAME}",
  "status": "${PROCESS_STATUS}",
  "timestamp": ${TIMESTAMP},
  "human_time": "${HUMAN_TIME}",
  "workflow_id": "${WORKFLOW_ID}"
}
EOF

# Log locally
echo "[Progress Tracker] ${PROCESS_NAME} ${PROCESS_STATUS} at ${HUMAN_TIME}"

# Upload to S3
# Use a consistent filename for the latest update
aws s3 cp progress_update.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/latest_update.json

# Also save with timestamp for history
aws s3 cp progress_update.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/updates/${TIMESTAMP}_${PROCESS_NAME}_${PROCESS_STATUS}.json

# If this is a process completion, update the master progress file
if [ "${PROCESS_STATUS}" == "completed" ] || [ "${PROCESS_STATUS}" == "failed" ]; then
  # Try to get the existing progress file, create new one if it doesn't exist
  aws s3 cp s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/progress.json ./existing_progress.json || {
    # Initialize progress file with workflow start info
    cat > existing_progress.json << EOF
{
  "workflow_id": "${WORKFLOW_ID}",
  "start_time": ${TIMESTAMP},
  "start_time_human": "${HUMAN_TIME}",
  "processes": {},
  "completed_count": 0,
  "total_processes": ${TOTAL_PROCESSES},
  "elapsed_seconds": 0,
  "estimated_remaining_seconds": 0,
  "percent_complete": 0,
  "status": "running"
}
EOF
  }

  # Update the progress file
  python3 - << EOF
import json
import time
import os
import math

# Load existing progress
with open('existing_progress.json', 'r') as f:
    progress = json.load(f)

# Get current process info
process_name = os.environ.get('PROCESS_NAME')
process_status = os.environ.get('PROCESS_STATUS')
timestamp = int(os.environ.get('TIMESTAMP', time.time()))

# Update process-specific info
if 'processes' not in progress:
    progress['processes'] = {}

progress['processes'][process_name] = {
    'status': process_status,
    'last_updated': timestamp,
    'last_updated_human': os.environ.get('HUMAN_TIME')
}

# Count completed processes
completed_count = sum(1 for p in progress['processes'].values() if p.get('status') == 'completed')
progress['completed_count'] = completed_count

# Calculate total processes from environment or existing value
total_processes = int(os.environ.get('TOTAL_PROCESSES', progress.get('total_processes', 0)))
progress['total_processes'] = total_processes

# Calculate percent complete (avoid division by zero)
if total_processes > 0:
    progress['percent_complete'] = round((completed_count / total_processes) * 100, 1)
else:
    progress['percent_complete'] = 0

# Calculate elapsed time
start_time = progress.get('start_time', timestamp)
progress['elapsed_seconds'] = timestamp - start_time

# Estimate remaining time based on completed work
if completed_count > 0 and completed_count < total_processes:
    avg_time_per_process = progress['elapsed_seconds'] / completed_count
    remaining_processes = total_processes - completed_count
    progress['estimated_remaining_seconds'] = math.ceil(avg_time_per_process * remaining_processes)
else:
    progress['estimated_remaining_seconds'] = 0

# Format times for human readability
def format_time(seconds):
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours > 0:
        return f"{hours}h {minutes}m {seconds}s"
    elif minutes > 0:
        return f"{minutes}m {seconds}s"
    else:
        return f"{seconds}s"

progress['elapsed_time_formatted'] = format_time(progress['elapsed_seconds'])
progress['estimated_remaining_formatted'] = format_time(progress['estimated_remaining_seconds'])

# Check if workflow is complete
if completed_count >= total_processes:
    progress['status'] = 'completed'
    progress['end_time'] = timestamp
    progress['end_time_human'] = os.environ.get('HUMAN_TIME')
    progress['total_runtime_seconds'] = progress['elapsed_seconds']
    progress['total_runtime_formatted'] = progress['elapsed_time_formatted']
    progress['percent_complete'] = 100

# Save updated progress
with open('updated_progress.json', 'w') as f:
    json.dump(progress, f, indent=2)
EOF

  # Upload updated progress file
  aws s3 cp updated_progress.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/progress.json
  
  # Also copy to a known location for the dashboard to easily find the latest run
  aws s3 cp updated_progress.json s3://${BUCKET_NAME}/progress/latest/progress.json
fi

# Clean up
rm -f progress_update.json
rm -f existing_progress.json
rm -f updated_progress.json 2>/dev/null || true

exit 0