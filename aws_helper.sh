#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
#
# aws_helper.sh - AWS CLI helper functions with profile support

# Source the configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
fi

# Source version information if version.sh exists and VERSION is not set
if [ -z "$VERSION" ] && [ -f "./version.sh" ]; then
  source ./version.sh
  VERSION=$(get_version)
fi

# Function to run AWS CLI commands with profile if specified
run_aws() {
  local cmd=$1
  shift
  
  if [ -n "$AWS_PROFILE" ]; then
    aws --profile "$AWS_PROFILE" --region "${REGION:-us-east-1}" $cmd "$@"
  else
    aws --region "${REGION:-us-east-1}" $cmd "$@"
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

# Helper function to add tags to resources
add_tags() {
  local resource_arn=$1
  local project_tag=${2:-"microbiome-demo"}
  local environment_tag=${3:-"demo"}
  local owner_tag=${4:-"microbiome-team"}
  
  echo "Adding tags to resource: $resource_arn"
  run_aws tags tag-resources \
    --resource-arn-list "$resource_arn" \
    --tags "Project=$project_tag,Environment=$environment_tag,Owner=$owner_tag"
}

# Helper function to add tags to S3 bucket
tag_s3_bucket() {
  local bucket_name=$1
  local project_tag=${2:-"microbiome-demo"}
  local environment_tag=${3:-"demo"}
  local owner_tag=${4:-"microbiome-team"}
  
  echo "Adding tags to S3 bucket: $bucket_name"
  run_aws s3api put-bucket-tagging \
    --bucket "$bucket_name" \
    --tagging "TagSet=[{Key=Project,Value=$project_tag},{Key=Environment,Value=$environment_tag},{Key=Owner,Value=$owner_tag}]"
}

# Helper function to find resources by tag
find_resources_by_tag() {
  local tag_key=$1
  local tag_value=$2
  local region=${3:-$REGION}
  
  echo "Finding resources with tag $tag_key=$tag_value in region $region"
  run_aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=$tag_key,Values=$tag_value" \
    --region "$region" \
    --query "ResourceTagMappingList[*].ResourceARN" \
    --output text
}

# Helper function to clean up resources by tag
cleanup_resources_by_tag() {
  local tag_key="Project"
  local tag_value=${1:-"microbiome-demo"}
  local regions=${2:-"us-east-1 us-west-2"}
  
  echo "=== Cleaning up resources with tag $tag_key=$tag_value ==="
  
  for region in $regions; do
    echo "Scanning region $region..."
    
    # Find CloudFormation stacks
    echo "Finding CloudFormation stacks..."
    local stacks=$(run_aws cloudformation list-stacks \
      --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
      --region "$region" \
      --query "StackSummaries[?contains(StackName, '$tag_value')].StackName" \
      --output text)
    
    for stack in $stacks; do
      echo "Deleting stack: $stack in region $region"
      run_aws cloudformation delete-stack --stack-name "$stack" --region "$region"
      run_aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$region" || echo "Stack deletion failed or is taking longer than expected"
    done
    
    # Find CloudFront distributions
    echo "Finding CloudFront distributions..."
    if [ "$region" = "us-east-1" ]; then
      local distributions=$(run_aws cloudfront list-distributions \
        --query "DistributionList.Items[?contains(Comment, '$tag_value')].Id" \
        --output text)
      
      for dist_id in $distributions; do
        echo "Disabling CloudFront distribution: $dist_id"
        # Get the ETag and Config
        local etag=$(run_aws cloudfront get-distribution-config --id "$dist_id" --query "ETag" --output text)
        # Create a temporary file with the distribution config
        run_aws cloudfront get-distribution-config --id "$dist_id" --query "DistributionConfig" > temp_dist_config.json
        # Modify the configuration to disable it
        sed -i '' 's/"Enabled": true/"Enabled": false/' temp_dist_config.json || echo "Failed to modify distribution config"
        # Update the distribution
        run_aws cloudfront update-distribution --id "$dist_id" --if-match "$etag" --distribution-config file://temp_dist_config.json || echo "Failed to disable distribution"
        # Clean up
        rm -f temp_dist_config.json
        echo "Waiting for distribution to be disabled before deleting..."
        sleep 30
        echo "Note: Distribution disabling is in progress. It may take 15-30 minutes to complete."
        echo "After it's disabled, you can delete it with: aws cloudfront delete-distribution --id $dist_id --if-match <new-etag>"
      done
    fi
    
    # Find and empty S3 buckets
    echo "Finding S3 buckets..."
    local buckets=$(run_aws s3api list-buckets \
      --query "Buckets[?contains(Name, '$tag_value')].Name" \
      --output text)
    
    for bucket in $buckets; do
      echo "Emptying and deleting bucket: $bucket"
      run_aws s3 rm "s3://$bucket" --recursive || echo "Failed to empty bucket or bucket is already empty"
      # Try to delete bucket versions if it's versioned
      run_aws s3api delete-bucket --bucket "$bucket" || echo "Failed to delete bucket. It may not be empty or might have versioned objects."
    done
  done
  
  echo "=== Resource cleanup completed ==="
  echo "Note: Some resources like CloudFront distributions may still be in the process of being deleted."
  echo "You can check the AWS console to monitor their status."
}