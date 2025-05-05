#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
#
# Script to update the JSON data files with simulated real-time data

# Source configuration
if [ -f "../../config.sh" ]; then
  source ../../config.sh
else
  echo "Config file not found. Using default configuration."
  BUCKET_NAME="microbiome-demo-bucket-1746342697"
  REGION="us-east-1"
  AWS_PROFILE=""
fi

# Source AWS helper functions
if [ -f "../../aws_helper.sh" ]; then
  source ../../aws_helper.sh
else
  echo "AWS helper not found. Using direct AWS commands."
  run_aws() {
    if [ -n "$AWS_PROFILE" ]; then
      aws --profile "$AWS_PROFILE" --region "${REGION:-us-east-1}" "$@"
    else
      aws --region "${REGION:-us-east-1}" "$@"
    fi
  }
fi

# Paths for local data files
PROGRESS_FILE="progress.json"
SUMMARY_FILE="summary.json"
RESOURCES_FILE="resources.json"

# Paths in S3 bucket
S3_STATUS_PATH="status/progress.json"
S3_RESULTS_PATH="results/summary.json"
S3_RESOURCE_PATH="monitoring/resources.json"

# Initialize variables for tracking state
TIME_ELAPSED=0
COMPLETED_SAMPLES=0
STATUS="INITIALIZING"

# Update progress data
update_progress_data() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Increase time elapsed
  TIME_ELAPSED=$((TIME_ELAPSED + 5))
  
  # Update completed samples based on time
  if [ $TIME_ELAPSED -lt 900 ]; then
    # Gradually increase completed samples
    COMPLETED_SAMPLES=$(( (TIME_ELAPSED * 100) / 900 ))
  else
    COMPLETED_SAMPLES=100
    STATUS="COMPLETED"
  fi
  
  # Calculate running and pending samples
  local running_samples=$((15 - COMPLETED_SAMPLES / 10))
  if [ $running_samples -lt 0 ]; then
    running_samples=0
  fi
  
  local pending_samples=$((10 - COMPLETED_SAMPLES / 10))
  if [ $pending_samples -lt 0 ]; then
    pending_samples=0
  fi
  
  # Update progress.json
  cat > $PROGRESS_FILE << EOF
{
  "status": "$STATUS",
  "time_elapsed": $TIME_ELAPSED,
  "completed_samples": $COMPLETED_SAMPLES,
  "total_samples": 100,
  "sample_status": {
    "completed": $COMPLETED_SAMPLES,
    "running": $running_samples,
    "pending": $pending_samples,
    "failed": $((100 - COMPLETED_SAMPLES - running_samples - pending_samples > 0 ? 100 - COMPLETED_SAMPLES - running_samples - pending_samples : 0))
  },
  "timestamp": "$timestamp",
  "job_id": "microbiome-demo-job-1746342992"
}
EOF
}

# Update summary data
update_summary_data() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Randomly adjust taxonomy values
  local bacteroidetes=$(printf "%.2f" $(echo "0.35 + $(( RANDOM % 10 - 5 )) / 100" | bc -l))
  local firmicutes=$(printf "%.2f" $(echo "0.30 + $(( RANDOM % 8 - 4 )) / 100" | bc -l))
  local proteobacteria=$(printf "%.2f" $(echo "0.15 + $(( RANDOM % 6 - 3 )) / 100" | bc -l))
  local actinobacteria=$(printf "%.2f" $(echo "0.10 + $(( RANDOM % 4 - 2 )) / 100" | bc -l))
  local fusobacteria=$(printf "%.2f" $(echo "0.05 + $(( RANDOM % 2 - 1 )) / 100" | bc -l))
  
  # Ensure values are positive
  bacteroidetes=$(printf "%.2f" $(echo "$bacteroidetes < 0.01 ? 0.01 : $bacteroidetes" | bc -l))
  firmicutes=$(printf "%.2f" $(echo "$firmicutes < 0.01 ? 0.01 : $firmicutes" | bc -l))
  proteobacteria=$(printf "%.2f" $(echo "$proteobacteria < 0.01 ? 0.01 : $proteobacteria" | bc -l))
  actinobacteria=$(printf "%.2f" $(echo "$actinobacteria < 0.01 ? 0.01 : $actinobacteria" | bc -l))
  fusobacteria=$(printf "%.2f" $(echo "$fusobacteria < 0.01 ? 0.01 : $fusobacteria" | bc -l))
  
  # Calculate sum
  local sum=$(printf "%.2f" $(echo "$bacteroidetes + $firmicutes + $proteobacteria + $actinobacteria + $fusobacteria" | bc -l))
  
  # Ensure sum is not zero to prevent division by zero
  if (( $(echo "$sum <= 0.01" | bc -l) )); then
    # If sum is too small, set default values
    bacteroidetes="0.35"
    firmicutes="0.30"
    proteobacteria="0.15"
    actinobacteria="0.10"
    fusobacteria="0.05"
  else
    # Normalize to 0.95 (remaining 0.05 will be 'Other')
    bacteroidetes=$(printf "%.2f" $(echo "$bacteroidetes / $sum * 0.95" | bc -l))
    firmicutes=$(printf "%.2f" $(echo "$firmicutes / $sum * 0.95" | bc -l))
    proteobacteria=$(printf "%.2f" $(echo "$proteobacteria / $sum * 0.95" | bc -l))
    actinobacteria=$(printf "%.2f" $(echo "$actinobacteria / $sum * 0.95" | bc -l))
    fusobacteria=$(printf "%.2f" $(echo "$fusobacteria / $sum * 0.95" | bc -l))
  fi
  
  # Calculate current cost based on time
  local current_cost=$(printf "%.2f" $(echo "scale=2; $TIME_ELAPSED / 900 * 2.5" | bc -l))
  
  # Generate diversity values with proper formatting
  local shannon=$(printf "%.14f" $(echo "4.2 + $RANDOM / 32767 * 0.2 - 0.1" | bc -l))
  local simpson=$(printf "%.14f" $(echo "0.9 + $RANDOM / 32767 * 0.1 - 0.05" | bc -l))
  local bray_curtis=$(printf "%.14f" $(echo "0.5 + $RANDOM / 32767 * 0.1 - 0.05" | bc -l))
  local jaccard=$(printf "%.14f" $(echo "0.4 + $RANDOM / 32767 * 0.1 - 0.05" | bc -l))
  
  # Calculate per sample cost with proper formatting
  # Prevent division by zero by checking COMPLETED_SAMPLES first
  local per_sample
  if [ "$COMPLETED_SAMPLES" -eq 0 ]; then
    per_sample="0.025" # Default value if no samples completed
  else
    per_sample=$(printf "%.3f" $(echo "scale=3; $current_cost / $COMPLETED_SAMPLES" | bc -l 2>/dev/null || echo "0.025"))
  fi
  
  # Update summary.json with proper JSON formatting
  cat > $SUMMARY_FILE << EOF
{
  "taxonomy": {
    "Bacteroidetes": $bacteroidetes,
    "Firmicutes": $firmicutes,
    "Proteobacteria": $proteobacteria,
    "Actinobacteria": $actinobacteria,
    "Fusobacteria": $fusobacteria,
    "Other": 0.05
  },
  "sample_counts": {
    "stool": $((42 + RANDOM % 5 - 2)),
    "anterior_nares": $((28 + RANDOM % 5 - 2)),
    "buccal_mucosa": $((35 + RANDOM % 5 - 2)),
    "other": $((15 + RANDOM % 5 - 2))
  },
  "diversity": {
    "alpha": {
      "shannon": $shannon,
      "simpson": $simpson
    },
    "beta": {
      "bray_curtis": $bray_curtis,
      "jaccard": $jaccard
    }
  },
  "cost": {
    "current": $current_cost,
    "estimated": 2.50,
    "per_sample": $per_sample,
    "standard_cloud": 120,
    "on_premises": 1800
  },
  "timestamp": "$timestamp"
}
EOF
}

# Update resource data
update_resource_data() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Get the current resource data
  local cpu_data=$(jq -r '.utilization[].cpu' $RESOURCES_FILE 2>/dev/null || echo "")
  local memory_data=$(jq -r '.utilization[].memory' $RESOURCES_FILE 2>/dev/null || echo "")
  local gpu_data=$(jq -r '.utilization[].gpu' $RESOURCES_FILE 2>/dev/null || echo "")
  
  # If we have existing data, use it to generate the next point
  if [ -n "$cpu_data" ]; then
    # Get the last values
    local last_cpu=$(echo "$cpu_data" | tail -n1)
    local last_memory=$(echo "$memory_data" | tail -n1)
    local last_gpu=$(echo "$gpu_data" | tail -n1)
    
    # Generate new values with small random changes and verify they are valid numbers
    if [[ ! "$last_cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      last_cpu=70 # Default if invalid
    fi
    if [[ ! "$last_memory" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      last_memory=75 # Default if invalid
    fi
    if [[ ! "$last_gpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      last_gpu=50 # Default if invalid
    fi
    
    # Safely calculate new values with error handling
    local new_cpu=$(echo "$last_cpu + $RANDOM % 11 - 5" | bc -l 2>/dev/null || echo 70)
    local new_memory=$(echo "$last_memory + $RANDOM % 9 - 4" | bc -l 2>/dev/null || echo 75)
    local new_gpu=$(echo "$last_gpu + $RANDOM % 13 - 6" | bc -l 2>/dev/null || echo 50)
    
    # Ensure values are in range with extra validation
    if [[ ! "$new_cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      new_cpu=70 # Default if calculation failed
    else
      new_cpu=$(echo "$new_cpu < 40 ? 40 : ($new_cpu > 95 ? 95 : $new_cpu)" | bc -l 2>/dev/null || echo 70)
    fi
    
    if [[ ! "$new_memory" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      new_memory=75 # Default if calculation failed
    else
      new_memory=$(echo "$new_memory < 40 ? 40 : ($new_memory > 95 ? 95 : $new_memory)" | bc -l 2>/dev/null || echo 75)
    fi
    
    if [[ ! "$new_gpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      new_gpu=50 # Default if calculation failed
    else
      new_gpu=$(echo "$new_gpu < 0 ? 0 : ($new_gpu > 95 ? 95 : $new_gpu)" | bc -l 2>/dev/null || echo 50)
    fi
    
    # If we're early in the simulation, GPU should be low or zero
    if [ $TIME_ELAPSED -lt 180 ]; then
      new_gpu=0
    fi
    
    # If we're in the middle of the simulation, GPU should be high
    if [ $TIME_ELAPSED -gt 300 ] && [ $TIME_ELAPSED -lt 600 ]; then
      # Safely increase GPU utilization with error handling
      new_gpu=$(echo "$new_gpu + 30" | bc -l 2>/dev/null || echo 80)
      
      # Ensure new_gpu is valid and capped at 95
      if [[ ! "$new_gpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        new_gpu=80 # Default if calculation failed
      else
        new_gpu=$(echo "$new_gpu > 95 ? 95 : $new_gpu" | bc -l 2>/dev/null || echo 80)
      fi
    fi
    
    # Create new utilization data with error handling
    # Get the last time value safely
    local last_time
    last_time=$(jq -r '.utilization[-1].time' $RESOURCES_FILE 2>/dev/null) || last_time=0
    
    # Ensure last_time is a valid number
    if [[ ! "$last_time" =~ ^[0-9]+$ ]]; then
      last_time=0
    fi
    
    local new_time=$((last_time + 1))
    local temp_file=$(mktemp)
    
    # Attempt to update JSON with jq, with error handling
    if ! jq --argjson new_time "$new_time" --argjson new_cpu "$new_cpu" --argjson new_memory "$new_memory" --argjson new_gpu "$new_gpu" \
      '.utilization = (.utilization[1:] + [{"time": $new_time, "cpu": $new_cpu, "memory": $new_memory, "gpu": $new_gpu}])' \
      $RESOURCES_FILE > "$temp_file" 2>/dev/null; then
      
      echo "Error updating utilization data with jq, creating fresh data"
      # Create a fresh resources file with valid structure if jq operation fails
      cat > "$temp_file" << EOF
{
  "utilization": [
    {"time": $((new_time-9)), "cpu": 60, "memory": 70, "gpu": 0},
    {"time": $((new_time-8)), "cpu": 65, "memory": 72, "gpu": 0},
    {"time": $((new_time-7)), "cpu": 70, "memory": 75, "gpu": 0},
    {"time": $((new_time-6)), "cpu": 75, "memory": 78, "gpu": 0},
    {"time": $((new_time-5)), "cpu": 80, "memory": 80, "gpu": 0},
    {"time": $((new_time-4)), "cpu": 85, "memory": 82, "gpu": 10},
    {"time": $((new_time-3)), "cpu": 82, "memory": 83, "gpu": 50},
    {"time": $((new_time-2)), "cpu": 78, "memory": 81, "gpu": 80},
    {"time": $((new_time-1)), "cpu": 75, "memory": 78, "gpu": 85},
    {"time": $new_time, "cpu": $new_cpu, "memory": $new_memory, "gpu": $new_gpu}
  ],
  "instances": {
    "cpu": 8,
    "gpu": 2
  }
}
EOF
    fi
    
    # Update timestamp safely
    if ! jq --arg timestamp "$timestamp" '.timestamp = $timestamp' "$temp_file" > $RESOURCES_FILE 2>/dev/null; then
      echo "Error adding timestamp to resources file, using simplified approach"
      # If jq fails, manually add the timestamp
      sed -i.bak 's/}$/,"timestamp":"'"$timestamp"'"}/' $RESOURCES_FILE
      rm -f "${RESOURCES_FILE}.bak"
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
  else
    # Create initial resource data if it doesn't exist
    cat > $RESOURCES_FILE << EOF
{
  "utilization": [
    {
      "time": 0,
      "cpu": 60,
      "memory": 70,
      "gpu": 0
    },
    {
      "time": 1,
      "cpu": 65,
      "memory": 72,
      "gpu": 0
    },
    {
      "time": 2,
      "cpu": 70,
      "memory": 75,
      "gpu": 0
    },
    {
      "time": 3,
      "cpu": 75,
      "memory": 78,
      "gpu": 0
    },
    {
      "time": 4,
      "cpu": 80,
      "memory": 80,
      "gpu": 0
    },
    {
      "time": 5,
      "cpu": 85,
      "memory": 82,
      "gpu": 10
    },
    {
      "time": 6,
      "cpu": 82,
      "memory": 83,
      "gpu": 50
    },
    {
      "time": 7,
      "cpu": 78,
      "memory": 81,
      "gpu": 80
    },
    {
      "time": 8,
      "cpu": 75,
      "memory": 78,
      "gpu": 85
    },
    {
      "time": 9,
      "cpu": 70,
      "memory": 75,
      "gpu": 82
    }
  ],
  "instances": {
    "cpu": 8,
    "gpu": 2
  },
  "timestamp": "$timestamp"
}
EOF
  fi
}

# Upload files to S3
upload_to_s3() {
  echo "Uploading data files to S3 bucket: $BUCKET_NAME"
  
  # Create directories in S3 if they don't exist
  run_aws s3api put-object --bucket "$BUCKET_NAME" --key "status/" --content-type "application/x-directory"
  run_aws s3api put-object --bucket "$BUCKET_NAME" --key "results/" --content-type "application/x-directory"
  run_aws s3api put-object --bucket "$BUCKET_NAME" --key "monitoring/" --content-type "application/x-directory"
  
  # Upload files with proper content type
  run_aws s3 cp "$PROGRESS_FILE" "s3://$BUCKET_NAME/$S3_STATUS_PATH" --content-type "application/json"
  run_aws s3 cp "$SUMMARY_FILE" "s3://$BUCKET_NAME/$S3_RESULTS_PATH" --content-type "application/json"
  run_aws s3 cp "$RESOURCES_FILE" "s3://$BUCKET_NAME/$S3_RESOURCE_PATH" --content-type "application/json"
  
  echo "Upload completed at $(date)"
}

# Main loop
main() {
  echo "Starting data update simulation"
  echo "Press Ctrl+C to stop"
  
  # Run the data update in a loop
  while true; do
    update_progress_data
    update_summary_data
    update_resource_data
    upload_to_s3
    
    # Exit if the simulation is complete
    if [ "$STATUS" = "COMPLETED" ]; then
      echo "Simulation completed"
      break
    fi
    
    # Sleep for a short time before the next update
    sleep 5
  done
}

# Check for jq dependency
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed."
  echo "Please install jq to continue."
  exit 1
fi

# Run the main function
main