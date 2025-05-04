#!/bin/bash
# Test script for real-time progress tracking

set -e  # Exit on error

# Get configuration from config.sh
source config.sh

echo "=============================================="
echo "Testing Real-Time Progress Tracking"
echo "=============================================="

# Validate environment
if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: BUCKET_NAME not set. Run setup.sh first."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "ERROR: AWS_REGION not set. Run setup.sh first."
    exit 1
fi

# Generate a unique workflow ID for testing
WORKFLOW_ID="test-$(date +%s)"
echo "Using test workflow ID: $WORKFLOW_ID"

# Create progress directories
mkdir -p progress_test

# Function to simulate a process and update progress
update_progress() {
    local process_name=$1
    local status=$2
    local total_processes=10  # Total processes for this test
    
    # Create timestamped values
    local timestamp=$(date +%s)
    local human_time=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Create progress update file
    cat > progress_test/progress_update.json << EOF
{
  "process": "${process_name}",
  "status": "${status}",
  "timestamp": ${timestamp},
  "human_time": "${human_time}",
  "workflow_id": "${WORKFLOW_ID}"
}
EOF

    # Upload to S3
    aws s3 cp progress_test/progress_update.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/latest_update.json
    aws s3 cp progress_test/progress_update.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/updates/${timestamp}_${process_name}_${status}.json
    
    echo "[$(date '+%H:%M:%S')] Updated progress: ${process_name} ${status}"
    
    # If process completed, update the master progress file
    if [ "${status}" == "completed" ] || [ "${status}" == "failed" ]; then
        # Try to get existing progress file, create new one if doesn't exist
        aws s3 cp s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/progress.json progress_test/existing_progress.json 2>/dev/null || {
            # Initialize progress file
            cat > progress_test/existing_progress.json << EOF
{
  "workflow_id": "${WORKFLOW_ID}",
  "start_time": ${timestamp},
  "start_time_human": "${human_time}",
  "processes": {},
  "completed_count": 0,
  "total_processes": ${total_processes},
  "elapsed_seconds": 0,
  "estimated_remaining_seconds": 0,
  "percent_complete": 0,
  "status": "running"
}
EOF
        }
        
        # Build a simple Python script to update the progress
        python3 -c "
import json
import time
import os
import math

# Load existing progress
with open('progress_test/existing_progress.json', 'r') as f:
    progress = json.load(f)

# Get process info
process_name = '${process_name}'
process_status = '${status}'
timestamp = ${timestamp}

# Update process info
if 'processes' not in progress:
    progress['processes'] = {}

progress['processes'][process_name] = {
    'status': process_status,
    'last_updated': timestamp,
    'last_updated_human': '${human_time}'
}

# Count completed processes
completed_count = sum(1 for p in progress['processes'].values() if p.get('status') == 'completed')
progress['completed_count'] = completed_count

# Calculate percent complete
total_processes = ${total_processes}
progress['total_processes'] = total_processes
if total_processes > 0:
    progress['percent_complete'] = round((completed_count / total_processes) * 100, 1)
else:
    progress['percent_complete'] = 0

# Calculate elapsed time
start_time = progress.get('start_time', timestamp)
progress['elapsed_seconds'] = timestamp - start_time

# Estimate remaining time
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
        return f'{hours}h {minutes}m {seconds}s'
    elif minutes > 0:
        return f'{minutes}m {seconds}s'
    else:
        return f'{seconds}s'

progress['elapsed_time_formatted'] = format_time(progress['elapsed_seconds'])
progress['estimated_remaining_formatted'] = format_time(progress['estimated_remaining_seconds'])

# Check if workflow is complete
if completed_count >= total_processes:
    progress['status'] = 'completed'
    progress['end_time'] = timestamp
    progress['end_time_human'] = '${human_time}'
    progress['total_runtime_seconds'] = progress['elapsed_seconds']
    progress['total_runtime_formatted'] = progress['elapsed_time_formatted']
    progress['percent_complete'] = 100.0

# Save updated progress
with open('progress_test/updated_progress.json', 'w') as f:
    json.dump(progress, f, indent=2)
"
        
        # Upload updated progress file
        aws s3 cp progress_test/updated_progress.json s3://${BUCKET_NAME}/progress/${WORKFLOW_ID}/progress.json
        
        # Also copy to latest location
        aws s3 cp progress_test/updated_progress.json s3://${BUCKET_NAME}/progress/latest/progress.json
    fi
}

echo "Starting simulated workflow progress updates..."

# Initialize workflow
update_progress "workflow_init" "started"
sleep 2

# Process 1: data loading
update_progress "data_loading" "started"
sleep 3
update_progress "data_loading" "completed"
sleep 1

# Process 2: quality control
update_progress "quality_control" "started"
sleep 4
update_progress "quality_control" "completed"
sleep 1

# Process 3: taxonomic classification
update_progress "taxonomic_classification" "started"
sleep 5
update_progress "taxonomic_classification" "completed"
sleep 1

# Process 4: functional profiling
update_progress "functional_profiling" "started"
sleep 5
update_progress "functional_profiling" "completed"
sleep 1

# Process 5: diversity analysis
update_progress "diversity_analysis" "started"
sleep 3
update_progress "diversity_analysis" "completed"
sleep 1

# Process 6: results summary
update_progress "results_summary" "started"
sleep 2
update_progress "results_summary" "completed"
sleep 1

# Process 7: visualization
update_progress "visualization" "started"
sleep 3
update_progress "visualization" "completed"
sleep 1

# Process 8: cost calculation
update_progress "cost_calculation" "started"
sleep 2
update_progress "cost_calculation" "completed"
sleep 1

# Process 9: results upload
update_progress "results_upload" "started"
sleep 3
update_progress "results_upload" "completed"
sleep 1

# Process 10: workflow completion
update_progress "workflow_completion" "started"
sleep 2
update_progress "workflow_completion" "completed"

# Final workflow status update
update_progress "workflow_complete" "completed"

echo "Test completed!"
echo "Progress data is available at:"
echo "  s3://$BUCKET_NAME/progress/$WORKFLOW_ID/progress.json"
echo "  s3://$BUCKET_NAME/progress/latest/progress.json"

# Check if Lambda function has processed the data
echo "Checking for dashboard data updates..."
sleep 5  # Give Lambda time to process

aws s3 ls s3://$BUCKET_NAME/dashboard/data/

echo "=============================================="
echo "Real-Time Progress Tracking Test Complete!"
echo "=============================================="

# Clean up
rm -rf progress_test

exit 0