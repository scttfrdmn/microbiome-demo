#!/bin/bash
# microbiome_setup.sh - Initial setup for the microbiome demo

set -e  # Exit on error

BUCKET_NAME=${1:-microbiome-demo-bucket-$(LC_CTYPE=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 10 | head -n 1)}
REGION=${2:-us-east-1}

echo "==========================================="
echo "Microbiome Demo Initial Setup"
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
  if [ "$REGION" = "us-east-1" ]; then
    aws s3 mb "s3://$BUCKET_NAME"
  else
    aws s3 mb "s3://$BUCKET_NAME" --region $REGION
  fi
  
  # Enable versioning for recovery
  aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled
  
  echo "Bucket created: $BUCKET_NAME"
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

# Create directories in S3 bucket
echo "Creating bucket structure..."
for dir in input reference results logs scripts; do
  aws s3api put-object --bucket $BUCKET_NAME --key $dir/
done

# Create configuration file for other scripts
cat > config.sh << EOF
#!/bin/bash
# Auto-generated configuration
BUCKET_NAME=$BUCKET_NAME
REGION=$REGION
STACK_NAME=microbiome-demo
EOF

chmod +x config.sh

# Create directories for local development
mkdir -p dashboard/css dashboard/js workflow/templates

# Create placeholders for important files
touch dashboard/index.html
touch dashboard/css/styles.css
touch dashboard/js/dashboard.js
touch workflow/main.nf
touch workflow/nextflow.config
touch workflow/templates/batch_init.sh
touch workflow/templates/cost_report.py

# Verify AWS service quotas
echo "Checking AWS service quotas..."
echo "Note: Some quotas may not be directly accessible via API. Manual verification may be required."

# Check EC2 vCPU limit
echo "Checking EC2 vCPU limits..."
VPC_LIMIT=$(aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --region $REGION \
  --query "Quota.Value" \
  --output text 2>/dev/null || echo "Unknown")

if [ "$VPC_LIMIT" != "Unknown" ] && [ $(echo "$VPC_LIMIT < 256" | bc -l) -eq 1 ]; then
  echo "⚠️ Warning: Your EC2 vCPU limit ($VPC_LIMIT) may be too low for this demo."
  echo "   Consider requesting a quota increase to at least 256 vCPUs."
  echo "   Visit: https://console.aws.amazon.com/servicequotas/"
else
  echo "✅ EC2 vCPU limit appears sufficient."
fi

# Check for GPU instance availability
echo "Checking GPU instance availability..."
GPU_COUNT=$(aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=g5g.xlarge,g5g.2xlarge" \
  --region $REGION \
  --query "length(InstanceTypeOfferings)" \
  --output text 2>/dev/null || echo "0")

if [ "$GPU_COUNT" -eq "0" ]; then
  echo "⚠️ Warning: GPU instances (g5g family) may not be available in region $REGION."
  echo "   Consider using a different region with GPU support."
  echo "   Recommended regions: us-east-1, us-west-2"
else
  echo "✅ GPU instances are available in your region."
fi

# Check AWS Batch service
echo "Checking AWS Batch service access..."
if ! aws batch describe-compute-environments --region $REGION &>/dev/null; then
  echo "⚠️ Warning: Unable to access AWS Batch service."
  echo "   Ensure your IAM permissions include Batch access."
else
  echo "✅ AWS Batch service is accessible."
fi

# Check Lambda service
echo "Checking AWS Lambda service access..."
if ! aws lambda list-functions --max-items 1 --region $REGION &>/dev/null; then
  echo "⚠️ Warning: Unable to access AWS Lambda service."
  echo "   Ensure your IAM permissions include Lambda access."
else
  echo "✅ AWS Lambda service is accessible."
fi

echo "==========================================="
echo "Setup completed successfully!"
echo "Configuration saved to config.sh"
echo ""
echo "Next steps:"
echo "1. Run ./prepare_microbiome_data.sh to prepare the data"
echo "2. Deploy the CloudFormation stack with AWS infrastructure"
echo "3. Check resources with ./check_resources.sh"
echo "4. Run a test with ./test_demo.sh"
echo "==========================================="
