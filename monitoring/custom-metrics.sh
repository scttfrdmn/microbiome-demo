#!/bin/bash
# custom-metrics.sh - Publish custom metrics to CloudWatch for Microbiome Demo

set -e  # Exit on error

# Source configuration
source ./config.sh

# Color codes for prettier output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Publishing Custom CloudWatch Metrics"
echo "==========================================="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "==========================================="

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS CLI not configured. Please run 'aws configure' first.${NC}"
  exit 1
fi

# Function to publish a custom metric
publish_metric() {
  local namespace=$1
  local metric_name=$2
  local value=$3
  local unit=$4
  local dimension_name=$5
  local dimension_value=$6
  
  echo -e "${YELLOW}Publishing metric: ${metric_name} = ${value} ${unit}${NC}"
  
  aws cloudwatch put-metric-data \
    --namespace "$namespace" \
    --metric-name "$metric_name" \
    --value "$value" \
    --unit "$unit" \
    --dimensions "${dimension_name}=${dimension_value}" \
    --region $REGION
    
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully published metric${NC}"
  else
    echo -e "${RED}Failed to publish metric${NC}"
  fi
}

# Get pipeline run metrics from S3
echo "Fetching pipeline metrics from S3..."
if aws s3 ls "s3://$BUCKET_NAME/results/summary/" &>/dev/null; then
  # Download the summary json 
  aws s3 cp "s3://$BUCKET_NAME/results/summary/microbiome_summary.json" /tmp/microbiome_summary.json
  
  if [ -f /tmp/microbiome_summary.json ]; then
    echo "Processing metrics from summary file..."
    
    # Extract metrics using jq if available, or grep otherwise
    if command -v jq &>/dev/null; then
      SPECIES_COUNT=$(jq -r '.taxonomic_profile.species_count' /tmp/microbiome_summary.json)
      SAMPLE_COUNT=$(jq -r '.taxonomic_profile.sample_count' /tmp/microbiome_summary.json)
      PATHWAY_COUNT=$(jq -r '.functional_profile.pathway_count' /tmp/microbiome_summary.json)
      SHANNON_DIVERSITY=$(jq -r '.diversity.alpha.shannon.mean' /tmp/microbiome_summary.json)
      CPU_HOURS=$(jq -r '.execution_metrics.cpu_hours' /tmp/microbiome_summary.json)
      GPU_HOURS=$(jq -r '.execution_metrics.gpu_hours' /tmp/microbiome_summary.json)
      WALL_CLOCK_MINUTES=$(jq -r '.execution_metrics.wall_clock_minutes' /tmp/microbiome_summary.json)
      
      # Calculate derived metrics
      SAMPLES_PER_MINUTE=$(bc <<< "scale=2; $SAMPLE_COUNT / $WALL_CLOCK_MINUTES")
      COST_PER_SAMPLE=$(bc <<< "scale=2; ${ESTIMATED_COST:-38.50} / $SAMPLE_COUNT")
    else
      echo "${YELLOW}jq not found, using grep for JSON parsing (less reliable)${NC}"
      SPECIES_COUNT=$(grep -o '"species_count":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      SAMPLE_COUNT=$(grep -o '"sample_count":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      PATHWAY_COUNT=$(grep -o '"pathway_count":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      SHANNON_DIVERSITY=$(grep -o '"mean":[0-9]*\.[0-9]*' /tmp/microbiome_summary.json | head -1 | cut -d':' -f2)
      CPU_HOURS=$(grep -o '"cpu_hours":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      GPU_HOURS=$(grep -o '"gpu_hours":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      WALL_CLOCK_MINUTES=$(grep -o '"wall_clock_minutes":[0-9]*' /tmp/microbiome_summary.json | cut -d':' -f2)
      
      # Calculate derived metrics
      SAMPLES_PER_MINUTE=$(bc <<< "scale=2; $SAMPLE_COUNT / $WALL_CLOCK_MINUTES")
      COST_PER_SAMPLE=$(bc <<< "scale=2; ${ESTIMATED_COST:-38.50} / $SAMPLE_COUNT")
    fi
    
    # Publish pipeline performance metrics
    publish_metric "MicrobiomeDemo/Pipeline" "SpeciesCount" "$SPECIES_COUNT" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Pipeline" "SampleCount" "$SAMPLE_COUNT" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Pipeline" "PathwayCount" "$PATHWAY_COUNT" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Pipeline" "ShannonDiversity" "$SHANNON_DIVERSITY" "None" "Demo" "$STACK_NAME"
    
    # Publish resource usage metrics
    publish_metric "MicrobiomeDemo/Resources" "CPUHours" "$CPU_HOURS" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Resources" "GPUHours" "$GPU_HOURS" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Resources" "WallClockMinutes" "$WALL_CLOCK_MINUTES" "Count" "Demo" "$STACK_NAME"
    
    # Publish performance metrics
    publish_metric "MicrobiomeDemo/Performance" "SamplesPerMinute" "$SAMPLES_PER_MINUTE" "Count" "Demo" "$STACK_NAME"
    publish_metric "MicrobiomeDemo/Performance" "CostPerSample" "$COST_PER_SAMPLE" "None" "Demo" "$STACK_NAME"
  else
    echo "${RED}Failed to download summary file from S3${NC}"
  fi
else
  echo "${YELLOW}No summary found in S3 bucket. Pipeline may not have completed yet.${NC}"
fi

# Get S3 bucket statistics
echo "Calculating S3 bucket statistics..."

# Get bucket size and object count
TOTAL_SIZE_BYTES=$(aws s3 ls s3://$BUCKET_NAME --recursive --summarize | grep "Total Size" | awk '{print $3}')
TOTAL_OBJECTS=$(aws s3 ls s3://$BUCKET_NAME --recursive --summarize | grep "Total Objects" | awk '{print $3}')

# Convert to more readable units
TOTAL_SIZE_MB=$(bc <<< "scale=2; $TOTAL_SIZE_BYTES / 1048576")  # Convert to MB

# Publish S3 metrics
publish_metric "MicrobiomeDemo/Storage" "BucketSizeMB" "$TOTAL_SIZE_MB" "Megabytes" "Bucket" "$BUCKET_NAME"
publish_metric "MicrobiomeDemo/Storage" "ObjectCount" "$TOTAL_OBJECTS" "Count" "Bucket" "$BUCKET_NAME"

# Get AWS Batch job statistics
echo "Calculating AWS Batch job statistics..."

# Get job counts for the last 24 hours
SUBMITTED_JOBS=$(aws batch list-jobs --job-queue ${JOB_QUEUE_CPU} --job-status SUBMITTED --region $REGION | grep -c '"jobId"' || echo 0)
RUNNING_JOBS=$(aws batch list-jobs --job-queue ${JOB_QUEUE_CPU} --job-status RUNNING --region $REGION | grep -c '"jobId"' || echo 0)
SUCCEEDED_JOBS=$(aws batch list-jobs --job-queue ${JOB_QUEUE_CPU} --job-status SUCCEEDED --region $REGION | grep -c '"jobId"' || echo 0)
FAILED_JOBS=$(aws batch list-jobs --job-queue ${JOB_QUEUE_CPU} --job-status FAILED --region $REGION | grep -c '"jobId"' || echo 0)

# Calculate success rate
TOTAL_COMPLETED_JOBS=$((SUCCEEDED_JOBS + FAILED_JOBS))
if [ $TOTAL_COMPLETED_JOBS -gt 0 ]; then
  SUCCESS_RATE=$(bc <<< "scale=2; ($SUCCEEDED_JOBS * 100) / $TOTAL_COMPLETED_JOBS")
else
  SUCCESS_RATE=0
fi

# Publish batch job metrics
publish_metric "MicrobiomeDemo/Batch" "SubmittedJobs" "$SUBMITTED_JOBS" "Count" "JobQueue" "${JOB_QUEUE_CPU}"
publish_metric "MicrobiomeDemo/Batch" "RunningJobs" "$RUNNING_JOBS" "Count" "JobQueue" "${JOB_QUEUE_CPU}"
publish_metric "MicrobiomeDemo/Batch" "SucceededJobs" "$SUCCEEDED_JOBS" "Count" "JobQueue" "${JOB_QUEUE_CPU}"
publish_metric "MicrobiomeDemo/Batch" "FailedJobs" "$FAILED_JOBS" "Count" "JobQueue" "${JOB_QUEUE_CPU}"
publish_metric "MicrobiomeDemo/Batch" "SuccessRate" "$SUCCESS_RATE" "Percent" "JobQueue" "${JOB_QUEUE_CPU}"

echo "==========================================="
echo "Custom metrics published successfully"
echo "==========================================="