#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# aws_helper.sh - AWS CLI helper functions with profile support

# Source the configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
fi

# Function to run AWS CLI commands with profile if specified
run_aws() {
  local cmd=$1
  shift
  
  if [ -n "$AWS_PROFILE" ]; then
    aws --profile "$AWS_PROFILE" $cmd "$@"
  else
    aws $cmd "$@"
  fi
}

# Helper function to check AWS credentials
check_aws_credentials() {
  if ! run_aws sts get-caller-identity &>/dev/null; then
    if [ -n "$AWS_PROFILE" ]; then
      echo "ERROR: AWS credentials not configured for profile '$AWS_PROFILE'."
      echo "Please run: aws configure --profile $AWS_PROFILE"
    else
      echo "ERROR: AWS credentials not configured."
      echo "Please run: aws configure"
    fi
    return 1
  fi
  return 0
}

# Helper function to create S3 bucket if it doesn't exist
ensure_s3_bucket() {
  local bucket_name=$1
  local region=${2:-$REGION}
  
  if ! run_aws s3 ls "s3://$bucket_name" &>/dev/null; then
    echo "Creating S3 bucket: $bucket_name in region $region"
    run_aws s3 mb "s3://$bucket_name" --region "$region"
    
    # Enable versioning for recovery
    run_aws s3api put-bucket-versioning \
      --bucket "$bucket_name" \
      --versioning-configuration Status=Enabled
    
    echo "Bucket created: $bucket_name"
    return 0
  else
    echo "Bucket already exists: $bucket_name"
    return 0
  fi
}

# Helper function to check if CloudFormation stack exists
check_stack_exists() {
  local stack_name=$1
  local region=${2:-$REGION}
  
  if run_aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Helper function to get CloudFormation stack outputs
get_stack_output() {
  local stack_name=$1
  local output_key=$2
  local region=${3:-$REGION}
  
  run_aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --region "$region" \
    --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
    --output text
}

# Helper function to create CloudFormation stack
create_stack() {
  local stack_name=$1
  local template_file=$2
  local parameters=$3
  local region=${4:-$REGION}
  local capabilities=${5:-CAPABILITY_IAM}
  
  echo "Creating CloudFormation stack: $stack_name"
  run_aws cloudformation create-stack \
    --stack-name "$stack_name" \
    --template-body "file://$template_file" \
    --capabilities "$capabilities" \
    --parameters $parameters \
    --region "$region"
    
  echo "Waiting for stack creation to complete..."
  run_aws cloudformation wait stack-create-complete \
    --stack-name "$stack_name" \
    --region "$region"
    
  echo "Stack $stack_name created successfully"
}

# Helper function to update CloudFormation stack
update_stack() {
  local stack_name=$1
  local template_file=$2
  local parameters=$3
  local region=${4:-$REGION}
  local capabilities=${5:-CAPABILITY_IAM}
  
  echo "Updating CloudFormation stack: $stack_name"
  run_aws cloudformation update-stack \
    --stack-name "$stack_name" \
    --template-body "file://$template_file" \
    --capabilities "$capabilities" \
    --parameters $parameters \
    --region "$region"
    
  echo "Waiting for stack update to complete..."
  run_aws cloudformation wait stack-update-complete \
    --stack-name "$stack_name" \
    --region "$region"
    
  echo "Stack $stack_name updated successfully"
}

# Helper function to delete CloudFormation stack
delete_stack() {
  local stack_name=$1
  local region=${2:-$REGION}
  
  echo "Deleting CloudFormation stack: $stack_name"
  run_aws cloudformation delete-stack \
    --stack-name "$stack_name" \
    --region "$region"
    
  echo "Waiting for stack deletion to complete..."
  run_aws cloudformation wait stack-delete-complete \
    --stack-name "$stack_name" \
    --region "$region"
    
  echo "Stack $stack_name deleted successfully"
}

# Helper function to copy files to/from S3
s3_copy() {
  local source=$1
  local destination=$2
  local options=${3:-""}
  
  echo "Copying: $source to $destination"
  run_aws s3 cp "$source" "$destination" $options
}

# Helper function to synchronize directories with S3
s3_sync() {
  local source=$1
  local destination=$2
  local options=${3:-""}
  
  echo "Syncing: $source with $destination"
  run_aws s3 sync "$source" "$destination" $options
}