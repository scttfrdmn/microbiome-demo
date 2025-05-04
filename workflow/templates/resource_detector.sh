#!/bin/bash
# Resource detector script for Nextflow pipeline
# Detects architecture (ARM/x86) and available resources

set -e  # Exit on error

# Create output file
echo "Creating resource report..."
echo '{' > resources.json

# Detect CPU architecture
if grep -q "aarch64" /proc/cpuinfo; then
    echo '  "architecture": "arm64",' >> resources.json
    echo "Detected ARM64 (Graviton) architecture"
else
    echo '  "architecture": "x86_64",' >> resources.json
    echo "Detected x86_64 architecture"
fi

# Get total CPUs
CPU_COUNT=$(nproc)
echo "  \"cpu\": ${CPU_COUNT}," >> resources.json
echo "Available CPUs: ${CPU_COUNT}"

# Get total memory in MB
MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
echo "  \"memory\": ${MEM_TOTAL}," >> resources.json
echo "Available memory: ${MEM_TOTAL} MB"

# Calculate usable memory (80% of total)
MEM_USABLE=$(echo "$MEM_TOTAL * 0.8" | bc | cut -d. -f1)
echo "  \"usable_memory\": ${MEM_USABLE}," >> resources.json
echo "Usable memory (80%): ${MEM_USABLE} MB"

# Get available disk space in MB
DISK_SPACE=$(df -m /tmp | tail -1 | awk '{print $4}')
echo "  \"disk\": ${DISK_SPACE}," >> resources.json
echo "Available disk space: ${DISK_SPACE} MB"

# Check for GPUs
if command -v nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
    echo "  \"gpu\": ${GPU_COUNT}," >> resources.json
    echo "Available GPUs: ${GPU_COUNT}"
    
    # Get GPU model
    if [ "$GPU_COUNT" -gt 0 ]; then
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        echo "  \"gpu_model\": \"${GPU_MODEL}\"," >> resources.json
        echo "GPU model: ${GPU_MODEL}"
    fi
else
    echo "  \"gpu\": 0," >> resources.json
    echo "No GPUs detected"
fi

# Detect instance type if on AWS
if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
    PRODUCT_NAME=$(cat /sys/devices/virtual/dmi/id/product_name)
    echo "  \"product_name\": \"${PRODUCT_NAME}\"," >> resources.json
    echo "Product name: ${PRODUCT_NAME}"
fi

# Detect AWS Batch job info
if [ ! -z "$AWS_BATCH_JOB_ID" ]; then
    echo "  \"aws_batch_job_id\": \"${AWS_BATCH_JOB_ID}\"," >> resources.json
    echo "AWS Batch Job ID: ${AWS_BATCH_JOB_ID}"
fi

# Remove the trailing comma from the last line
sed -i '$ s/,$//' resources.json

# Close the JSON object
echo '}' >> resources.json

# Print summary
echo "Resource detection complete. Created resources.json"
cat resources.json