#!/bin/bash
# health-check.sh - Check health of Microbiome Demo services

set -e  # Exit on error

# Source configuration
source ./config.sh

# Color codes for prettier output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Microbiome Demo Health Check"
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

# Initialize status flag
health_issues=0

# Function to check service status
check_service() {
  local service_name=$1
  local command=$2
  local expected_status=$3
  
  echo -e "${YELLOW}Checking $service_name...${NC}"
  
  local status=$(eval "$command")
  
  if [[ "$status" == "$expected_status" ]]; then
    echo -e "${GREEN}✓ $service_name is healthy ($status)${NC}"
    return 0
  else
    echo -e "${RED}✗ $service_name is not healthy (Expected: $expected_status, Got: $status)${NC}"
    health_issues=$((health_issues + 1))
    return 1
  fi
}

# Check CloudFormation stack status
check_stack() {
  echo -e "${YELLOW}Checking CloudFormation stack...${NC}"
  
  local stack_status=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
    echo -e "${GREEN}✓ Stack is healthy ($stack_status)${NC}"
    return 0
  elif [[ "$stack_status" == "NOT_FOUND" ]]; then
    echo -e "${RED}✗ Stack not found. Please create the stack first.${NC}"
    health_issues=$((health_issues + 1))
    return 1
  else
    echo -e "${RED}✗ Stack is in state: $stack_status${NC}"
    health_issues=$((health_issues + 1))
    return 1
  fi
}

# Check S3 bucket status
check_s3_bucket() {
  echo -e "${YELLOW}Checking S3 bucket...${NC}"
  
  if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ S3 bucket exists and is accessible${NC}"
    
    # Check required directories
    for dir in "input" "reference" "results"; do
      if aws s3 ls "s3://$BUCKET_NAME/$dir/" &>/dev/null; then
        echo -e "${GREEN}  ✓ Directory $dir exists${NC}"
      else
        echo -e "${YELLOW}  ⚠ Directory $dir does not exist${NC}"
      fi
    done
    
    # Check required files
    if aws s3 ls "s3://$BUCKET_NAME/input/sample_list.csv" &>/dev/null; then
      echo -e "${GREEN}  ✓ Sample list exists${NC}"
    else
      echo -e "${RED}  ✗ Sample list is missing${NC}"
      health_issues=$((health_issues + 1))
    fi
    
    return 0
  else
    echo -e "${RED}✗ S3 bucket does not exist or is not accessible${NC}"
    health_issues=$((health_issues + 1))
    return 1
  fi
}

# Check AWS Batch compute environments
check_batch_compute_environments() {
  echo -e "${YELLOW}Checking AWS Batch compute environments...${NC}"
  
  local cpu_env_status=$(aws batch describe-compute-environments --compute-environments ${COMPUTE_ENV_CPU} --region $REGION --query "computeEnvironments[0].status" --output text 2>/dev/null || echo "NOT_FOUND")
  local gpu_env_status=$(aws batch describe-compute-environments --compute-environments ${COMPUTE_ENV_GPU} --region $REGION --query "computeEnvironments[0].status" --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [[ "$cpu_env_status" == "VALID" ]]; then
    echo -e "${GREEN}✓ CPU compute environment is healthy${NC}"
  else
    echo -e "${RED}✗ CPU compute environment status: $cpu_env_status${NC}"
    health_issues=$((health_issues + 1))
  fi
  
  if [[ "$gpu_env_status" == "VALID" ]]; then
    echo -e "${GREEN}✓ GPU compute environment is healthy${NC}"
  else
    echo -e "${RED}✗ GPU compute environment status: $gpu_env_status${NC}"
    health_issues=$((health_issues + 1))
  fi
}

# Check AWS Batch job queues
check_batch_job_queues() {
  echo -e "${YELLOW}Checking AWS Batch job queues...${NC}"
  
  local cpu_queue_status=$(aws batch describe-job-queues --job-queues ${JOB_QUEUE_CPU} --region $REGION --query "jobQueues[0].status" --output text 2>/dev/null || echo "NOT_FOUND")
  local gpu_queue_status=$(aws batch describe-job-queues --job-queues ${JOB_QUEUE_GPU} --region $REGION --query "jobQueues[0].status" --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [[ "$cpu_queue_status" == "VALID" ]]; then
    echo -e "${GREEN}✓ CPU job queue is healthy${NC}"
  else
    echo -e "${RED}✗ CPU job queue status: $cpu_queue_status${NC}"
    health_issues=$((health_issues + 1))
  fi
  
  if [[ "$gpu_queue_status" == "VALID" ]]; then
    echo -e "${GREEN}✓ GPU job queue is healthy${NC}"
  else
    echo -e "${RED}✗ GPU job queue status: $gpu_queue_status${NC}"
    health_issues=$((health_issues + 1))
  fi
}

# Check Lambda function
check_lambda() {
  echo -e "${YELLOW}Checking Lambda function...${NC}"
  
  # Get Lambda function name from CloudFormation stack
  local lambda_function=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='OrchestratorLambdaArn'].OutputValue" \
    --output text \
    --region $REGION)
  
  if [ -z "$lambda_function" ]; then
    echo -e "${RED}✗ Lambda function not found in stack outputs${NC}"
    health_issues=$((health_issues + 1))
    return 1
  fi
  
  # Extract function name from ARN
  local function_name=$(echo $lambda_function | awk -F: '{print $7}')
  
  # Check if the function exists
  if aws lambda get-function --function-name $function_name --region $REGION &>/dev/null; then
    echo -e "${GREEN}✓ Lambda function exists${NC}"
    
    # Check recent errors
    local error_count=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda \
      --metric-name Errors \
      --dimensions Name=FunctionName,Value=$function_name \
      --start-time $(date -u -v -1d +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 86400 \
      --statistics Sum \
      --region $REGION \
      --query "Datapoints[0].Sum" \
      --output text 2>/dev/null || echo "0")
    
    if [[ "$error_count" == "0" ]]; then
      echo -e "${GREEN}✓ No Lambda errors in the last 24 hours${NC}"
    else
      echo -e "${RED}✗ Lambda has $error_count error(s) in the last 24 hours${NC}"
      health_issues=$((health_issues + 1))
    fi
    
    return 0
  else
    echo -e "${RED}✗ Lambda function $function_name does not exist${NC}"
    health_issues=$((health_issues + 1))
    return 1
  fi
}

# Run all checks
check_stack
check_s3_bucket
check_batch_compute_environments
check_batch_job_queues
check_lambda

# Final health assessment
echo "==========================================="
if [ $health_issues -eq 0 ]; then
  echo -e "${GREEN}All systems are healthy!${NC}"
  exit 0
else
  echo -e "${RED}Found $health_issues health issue(s)${NC}"
  echo "Please resolve these issues before running the demo."
  exit 1
fi