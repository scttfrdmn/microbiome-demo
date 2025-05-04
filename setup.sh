#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
#
# setup.sh - Initial setup for the microbiome demo

set -e  # Exit on error

# Source version information
if [ -f "./version.sh" ]; then
  source ./version.sh
  VERSION=$(get_version)
else
  VERSION="unknown"
fi

BUCKET_NAME=${1:-microbiome-demo-bucket-$(LC_CTYPE=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 10 | head -n 1)}
REGION=${2:-us-east-1}
AWS_PROFILE=${3:-""}  # Optional AWS profile, empty for default profile

echo "==========================================="
echo "Microbiome Demo Initial Setup v$VERSION"
echo "==========================================="
echo "Target bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "AWS Profile: ${AWS_PROFILE:-Default}"
echo "==========================================="

# Define AWS CLI command prefix with profile if specified
AWS_CMD="aws"
if [ -n "$AWS_PROFILE" ]; then
  AWS_CMD="aws --profile $AWS_PROFILE"
fi

# Check AWS CLI configuration
if ! $AWS_CMD sts get-caller-identity &>/dev/null; then
  if [ -n "$AWS_PROFILE" ]; then
    echo "AWS CLI not configured for profile '$AWS_PROFILE'. Please run 'aws configure --profile $AWS_PROFILE' first."
  else
    echo "AWS CLI not configured. Please run 'aws configure' first."
  fi
  exit 1
fi

# Create S3 bucket if it doesn't exist
if ! $AWS_CMD s3 ls "s3://$BUCKET_NAME" 2>&1 > /dev/null; then
  echo "Creating S3 bucket: $BUCKET_NAME"
  $AWS_CMD s3 mb "s3://$BUCKET_NAME" --region $REGION
  
  # Enable versioning for recovery
  $AWS_CMD s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled
  
  echo "Bucket created: $BUCKET_NAME"
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

# Create configuration file for other scripts
cat > config.sh << EOF
#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
#
# Auto-generated configuration for Microbiome Demo

# Core configuration
BUCKET_NAME=$BUCKET_NAME
REGION=$REGION
STACK_NAME=microbiome-demo
AWS_PROFILE="$AWS_PROFILE"  # AWS CLI profile to use, empty for default

# Version information
VERSION="$VERSION"
EOF

chmod +x config.sh

echo "Setup complete! Configuration saved to config.sh"
echo "Next step: Run ./prepare_microbiome_data.sh to prepare the data"

# Create empty directories if they don't exist
mkdir -p dashboard/css dashboard/js workflow/templates
