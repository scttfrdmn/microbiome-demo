#!/bin/bash
# validate_aws_resources.sh - Check that AWS resources needed for the demo are available

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

source ./config.sh

echo "==========================================="
echo "AWS Resources Validation for Microbiome Demo"
echo "==========================================="
echo "Stack name: $STACK_NAME"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "==========================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
  echo "Please install AWS CLI: https://aws.amazon.com/cli/"
  exit 1
fi

# Check AWS credentials
echo -e "\nChecking AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  echo -e "${GREEN}✓ Valid AWS credentials for account $ACCOUNT_ID${NC}"
else
  echo -e "${RED}✗ AWS credentials are not configured or invalid${NC}"
  echo "Run 'aws configure' to set up your credentials"
  exit 1
fi

# Check S3 bucket
echo -e "\nChecking S3 bucket..."
if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
  echo -e "${GREEN}✓ S3 bucket exists: $BUCKET_NAME${NC}"
  
  # Check bucket contents
  echo "Checking bucket contents..."
  for dir in "input" "reference"; do
    if aws s3 ls "s3://$BUCKET_NAME/$dir/" &>/dev/null; then
      echo -e "${GREEN}✓ Directory exists: $dir/${NC}"
    else
      echo -e "${YELLOW}⚠ Directory not found: $dir/${NC}"
      echo "Run 'prepare_microbiome_data.sh' to set up the required data"
    fi
  done
else
  echo -e "${YELLOW}⚠ S3 bucket not found: $BUCKET_NAME${NC}"
  echo "Run 'setup.sh' to create the bucket"
fi

# Check CloudFormation stack
echo -e "\nChecking CloudFormation stack..."
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &>/dev/null; then
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query "Stacks[0].StackStatus" --output text)
  echo -e "${GREEN}✓ CloudFormation stack exists: $STACK_STATUS${NC}"
  
  # Check stack resources
  echo "Checking key resources..."
  
  # Check AWS Batch resources
  BATCH_COMPUTE_ENV=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --region $REGION --query "StackResources[?ResourceType=='AWS::Batch::ComputeEnvironment'].PhysicalResourceId" --output text)
  if [ -n "$BATCH_COMPUTE_ENV" ]; then
    echo -e "${GREEN}✓ Batch compute environment: $BATCH_COMPUTE_ENV${NC}"
    
    # Check compute environment status
    CE_STATUS=$(aws batch describe-compute-environments --compute-environments $BATCH_COMPUTE_ENV --region $REGION --query "computeEnvironments[0].status" --output text)
    if [ "$CE_STATUS" == "VALID" ]; then
      echo -e "${GREEN}✓ Compute environment status: $CE_STATUS${NC}"
    else
      echo -e "${YELLOW}⚠ Compute environment status: $CE_STATUS${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ Batch compute environment not found${NC}"
  fi
  
  # Check GPU quota
  echo -e "\nChecking GPU quota..."
  GPU_QUOTA=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-2D60AC90 --region $REGION --query "Quota.Value" --output text 2>/dev/null || echo "Unknown")
  if [ "$GPU_QUOTA" != "Unknown" ]; then
    if (( $(echo "$GPU_QUOTA >= 4" | bc -l) )); then
      echo -e "${GREEN}✓ GPU quota sufficient: $GPU_QUOTA${NC}"
    else
      echo -e "${YELLOW}⚠ GPU quota may be insufficient: $GPU_QUOTA (need at least 4)${NC}"
      echo "Consider requesting a quota increase in the AWS console"
    fi
  else
    echo -e "${YELLOW}⚠ Could not determine GPU quota${NC}"
    echo "Verify manually in the AWS Service Quotas console"
  fi
  
  # Check vCPU quota
  echo "Checking vCPU quota..."
  VCPU_QUOTA=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region $REGION --query "Quota.Value" --output text 2>/dev/null || echo "Unknown")
  if [ "$VCPU_QUOTA" != "Unknown" ]; then
    if (( $(echo "$VCPU_QUOTA >= 256" | bc -l) )); then
      echo -e "${GREEN}✓ vCPU quota sufficient: $VCPU_QUOTA${NC}"
    else
      echo -e "${YELLOW}⚠ vCPU quota may be insufficient: $VCPU_QUOTA (need at least 256)${NC}"
      echo "Consider requesting a quota increase in the AWS console"
    fi
  else
    echo -e "${YELLOW}⚠ Could not determine vCPU quota${NC}"
    echo "Verify manually in the AWS Service Quotas console"
  fi
  
  # Check Lambda function
  LAMBDA_FUNCTION=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --region $REGION --query "StackResources[?ResourceType=='AWS::Lambda::Function'].PhysicalResourceId" --output text)
  if [ -n "$LAMBDA_FUNCTION" ]; then
    echo -e "${GREEN}✓ Lambda function exists: $LAMBDA_FUNCTION${NC}"
  else
    echo -e "${YELLOW}⚠ Lambda function not found${NC}"
  fi
  
else
  echo -e "${YELLOW}⚠ CloudFormation stack not found: $STACK_NAME${NC}"
  echo "Run 'aws cloudformation create-stack' to create the stack"
fi

# Check Docker containers
echo -e "\nChecking Docker container accessibility..."
for container in "$CONTAINER_REPO_CPU:$CONTAINER_TAG_CPU" "$CONTAINER_REPO_GPU:$CONTAINER_TAG_GPU"; do
  echo "Checking container: $container"
  # Just check if we can fetch the manifest without actually pulling
  if aws ecr-public describe-images --repository-name "${container%:*}" --region us-east-1 --query "imageDetails[?contains(imageTags, '${container##*:}')].imageTags" &>/dev/null; then
    echo -e "${GREEN}✓ Container exists and is accessible: $container${NC}"
  else
    echo -e "${YELLOW}⚠ Container might not exist or is not accessible: $container${NC}"
    echo "Verify container existence and permissions"
  fi
done

echo -e "\n${GREEN}AWS resources validation complete!${NC}"
echo "Fix any warnings or errors before running the demo."