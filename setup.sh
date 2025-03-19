#!/bin/bash
# setup.sh - Initial setup for the omics demo

set -e  # Exit on error

BUCKET_NAME=${1:-omics-demo-bucket-$(LC_CTYPE=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 10 | head -n 1)}
REGION=${2:-us-east-1}

echo "==========================================="
echo "Omics Demo Initial Setup"
echo "==========================================="
echo "Target bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "==========================================="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &>/dev/null; then
  echo "AWS CLI not configured. Please run 'aws configure' first."
  exit 1
fi

# Create S3 bucket if it doesn't exist
if ! aws s3 ls "s3://$BUCKET_NAME" 2>&1 > /dev/null; then
  echo "Creating S3 bucket: $BUCKET_NAME"
  aws s3 mb "s3://$BUCKET_NAME" --region $REGION
  
  # Enable versioning for recovery
  aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled
  
  echo "Bucket created: $BUCKET_NAME"
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

# Create configuration file for other scripts
cat > config.sh << EOF
#!/bin/bash
# Auto-generated configuration
BUCKET_NAME=$BUCKET_NAME
REGION=$REGION
STACK_NAME=omics-demo
EOF

chmod +x config.sh

echo "Setup complete! Configuration saved to config.sh"
echo "Next step: Run ./prepare_demo_data.sh to prepare the data"

# Create empty directories if they don't exist
mkdir -p dashboard/css dashboard/js workflow/templates
