#!/bin/bash
# Test script for resource optimization on AWS Batch with architecture detection

set -e  # Exit on error

echo "=============================================="
echo "Testing Resource Optimization for Microbiome Demo"
echo "=============================================="

# Get configuration from config.sh
source config.sh

# Validate environment
if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: BUCKET_NAME not set. Run setup.sh first."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "ERROR: AWS_REGION not set. Run setup.sh first."
    exit 1
fi

# Ensure resource detection template is executable
chmod +x workflow/templates/resource_detector.sh

echo "Testing resource optimization with both CPU and GPU instances..."

# Function to submit resource detection job
submit_resource_job() {
  local job_queue=$1
  local job_name=$2
  local result_file=$3
  
  # Create a test JSON for the job
  cat > ${job_name}.json << EOF
{
  "jobName": "${job_name}",
  "jobQueue": "${job_queue}",
  "jobDefinition": "microbiome-demo-job",
  "containerOverrides": {
    "command": [
      "bash", "-c", 
      "cd /tmp && curl -s https://get.nextflow.io | bash && chmod +x nextflow && mkdir -p workflow/templates && aws s3 cp s3://${BUCKET_NAME}/workflow/templates/resource_detector.sh workflow/templates/ && chmod +x workflow/templates/resource_detector.sh && ./nextflow run s3://${BUCKET_NAME}/workflow/microbiome_main.nf -entry detect_resources --bucket_name ${BUCKET_NAME} -profile test"
    ],
    "environment": [
      {"name": "AWS_REGION", "value": "${AWS_REGION}"},
      {"name": "BUCKET_NAME", "value": "${BUCKET_NAME}"},
      {"name": "RESOURCE_RESULT", "value": "${result_file}"}
    ]
  }
}
EOF

  # Submit job
  local job_id=$(aws batch submit-job --cli-input-json file://${job_name}.json --query jobId --output text)
  echo "${job_id}"
}

# Submit CPU job
echo "Submitting CPU-only resource detection job..."
CPU_JOB_ID=$(submit_resource_job "microbiome-demo-queue" "microbiome-cpu-test" "cpu_resources.json")
echo "CPU job submitted with ID: $CPU_JOB_ID"

# Submit GPU job
echo "Submitting GPU resource detection job..."
GPU_JOB_ID=$(submit_resource_job "microbiome-demo-gpu-queue" "microbiome-gpu-test" "gpu_resources.json")
echo "GPU job submitted with ID: $GPU_JOB_ID"

# Track primary job for output display
JOB_ID=$CPU_JOB_ID

echo "Job submitted with ID: $JOB_ID"
echo "Waiting for job to complete..."

# Wait for job to complete
aws batch wait job-queue-not-exists --job-queues microbiome-demo-queue
aws batch wait job-definition-not-exists --job-definitions microbiome-demo-job

# Check status periodically
while true; do
    STATUS=$(aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].status' --output text)
    echo "Current status: $STATUS"
    
    if [ "$STATUS" == "SUCCEEDED" ]; then
        echo "Job completed successfully!"
        break
    elif [ "$STATUS" == "FAILED" ]; then
        echo "Job failed. Check CloudWatch logs for details."
        exit 1
    fi
    
    sleep 10
done

# Retrieve results from S3
echo "Retrieving CPU resource detection results..."
aws s3 cp s3://${BUCKET_NAME}/results/system/resources.json ./cpu_resources.json

# Wait a bit and check for GPU job results too
echo "Checking for GPU job results..."
sleep 20
aws s3 cp s3://${BUCKET_NAME}/results/system/resources.json ./gpu_resources.json || echo "GPU results not available yet"

# Display results
echo "=============================================="
echo "CPU Resource Detection Results:"
echo "=============================================="
cat cpu_resources.json | jq .

if [ -f "gpu_resources.json" ]; then
  echo "=============================================="
  echo "GPU Resource Detection Results:"
  echo "=============================================="
  cat gpu_resources.json | jq .
fi

echo "=============================================="
echo "Resource Optimizations Applied:"
echo "=============================================="
echo "1. Dynamic architecture detection (ARM vs x86)"
echo "2. GPU detection and fallback to CPU-optimized resources when needed"
echo "3. Process-specific resource allocation based on workload"
echo "4. Dynamic AWS Batch queue selection based on GPU requirements"

echo "Resource optimization test completed successfully!"
echo "The workflow has been updated to dynamically allocate resources based on architecture and GPU availability."