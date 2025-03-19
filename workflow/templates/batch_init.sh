#!/bin/bash
# batch_init.sh
# Template for AWS Batch instance initialization

set -e  # Exit on error

# Log initialization start
echo "Starting AWS Batch instance initialization for Omics Demo"
echo "======================================================" >> /var/log/batch-init.log
echo "Initialization started at $(date)" >> /var/log/batch-init.log
echo "Instance type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)" >> /var/log/batch-init.log

# Update system packages
echo "Updating system packages..."
apt-get update -y >> /var/log/batch-init.log 2>&1
apt-get install -y \
  bc \
  curl \
  wget \
  pigz \
  awscli \
  zip \
  unzip \
  python3-pip \
  samtools \
  bcftools \
  tabix >> /var/log/batch-init.log 2>&1

# Create working directories
echo "Creating working directories..."
mkdir -p /tmp/references
mkdir -p /tmp/data
mkdir -p /tmp/results

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install boto3 pandas numpy matplotlib >> /var/log/batch-init.log 2>&1

# Set up AWS region
export AWS_DEFAULT_REGION="${AWS_BATCH_JOB_AWS_REGION:-us-east-1}"

# Pull container images in advance for faster job startup
echo "Pre-pulling Docker images..."
docker pull public.ecr.aws/lts/genomics-tools:latest >> /var/log/batch-init.log 2>&1
docker pull public.ecr.aws/lts/nextflow:latest >> /var/log/batch-init.log 2>&1

# Download reference files if this is a Graviton instance (ARM-based)
if grep -q "aarch64" /proc/cpuinfo; then
  echo "Detected ARM architecture (Graviton)..."
  
  # Download reference genome index for chromosome 20
  echo "Downloading reference genome index..."
  aws s3 cp ${REFERENCE_BUCKET:-s3://omics-demo-bucket}/input/demo_reference.fai /tmp/references/ >> /var/log/batch-init.log 2>&1
  
  # Set ARM-specific optimizations
  export MALLOC_ARENA_MAX=4
fi

# Set environment variables for Nextflow
export NXF_OPTS="-Xms512m -Xmx2g"
export NXF_ANSI_LOG=false

# Report success
echo "Instance initialization completed successfully at $(date)" >> /var/log/batch-init.log
echo "Batch instance ready for Omics Demo workloads"

# This script is used as a template and will be customized by CloudFormation
# The following placeholders will be replaced at deployment time:
# - ${REFERENCE_BUCKET} - S3 bucket containing reference data
# - ${AWS_BATCH_JOB_AWS_REGION} - AWS region for the Batch job
