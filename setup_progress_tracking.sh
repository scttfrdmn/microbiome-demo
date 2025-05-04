#!/bin/bash
# Setup script for real-time progress tracking

set -e  # Exit on error

# Get configuration from config.sh
source config.sh

echo "=============================================="
echo "Setting up Real-Time Progress Tracking"
echo "=============================================="

# Validate environment
if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: BUCKET_NAME not set. Run setup.sh first."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "ERROR: AWS_REGION not set. Run setup.sh first."
    exit 1
fi

# Create progress tracking directories in S3 bucket
echo "Creating progress tracking directories in S3..."
aws s3api put-object --bucket $BUCKET_NAME --key progress/ --content-type application/json
aws s3api put-object --bucket $BUCKET_NAME --key progress/latest/ --content-type application/json
aws s3api put-object --bucket $BUCKET_NAME --key dashboard/data/ --content-type application/json

# Upload the progress tracker template to S3
echo "Uploading progress tracker template..."
aws s3 cp workflow/templates/progress_tracker.sh s3://$BUCKET_NAME/workflow/templates/progress_tracker.sh

# Deploy CloudFormation stack for progress tracking resources
echo "Deploying progress tracking infrastructure..."

# Prompt for optional notification email
read -p "Enter email for workflow notifications (leave blank to skip): " NOTIFICATION_EMAIL

# Deploy CloudFormation stack
aws cloudformation create-stack \
  --stack-name microbiome-progress-tracking \
  --template-body file://progress_tracking_cf.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=DataBucketName,ParameterValue=$BUCKET_NAME \
    ParameterKey=NotificationEmail,ParameterValue="$NOTIFICATION_EMAIL"

echo "Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete --stack-name microbiome-progress-tracking

# Get stack outputs
LAMBDA_ARN=$(aws cloudformation describe-stacks --stack-name microbiome-progress-tracking \
  --query "Stacks[0].Outputs[?OutputKey=='ProgressLambdaArn'].OutputValue" --output text)

# Configure S3 event notifications (can't be done directly in CloudFormation)
echo "Configuring S3 event notifications..."
aws s3api put-bucket-notification-configuration \
  --bucket $BUCKET_NAME \
  --notification-configuration "{
    \"LambdaFunctionConfigurations\": [
      {
        \"LambdaFunctionArn\": \"$LAMBDA_ARN\",
        \"Events\": [\"s3:ObjectCreated:*\"],
        \"Filter\": {
          \"Key\": {
            \"FilterRules\": [
              {
                \"Name\": \"prefix\",
                \"Value\": \"progress/\"
              },
              {
                \"Name\": \"suffix\",
                \"Value\": \"progress.json\"
              }
            ]
          }
        }
      }
    ]
  }"

# Initialize the progress dashboard data
echo "Initializing dashboard data..."
cat > initial_progress.json << EOF
{
  "timestamp": $(date +%s),
  "update_time": "$(date +'%Y-%m-%d %H:%M:%S')",
  "workflow_id": "none",
  "percent_complete": 0,
  "status": "waiting",
  "elapsed_time": "0s",
  "remaining_time": "unknown",
  "processes": {
    "completed": 0,
    "total": 0
  }
}
EOF

# Upload initial progress data
aws s3 cp initial_progress.json s3://$BUCKET_NAME/dashboard/data/latest_progress.json

echo "=============================================="
echo "Real-Time Progress Tracking Setup Complete!"
echo "=============================================="
echo "The system will now track workflow progress in real-time."
echo "Progress data is available at:"
echo "  s3://$BUCKET_NAME/progress/<workflow_id>/progress.json"
echo "  s3://$BUCKET_NAME/dashboard/data/latest_progress.json"
echo 
echo "This data will be used by the dashboard for visualization."
echo "=============================================="

# Clean up
rm -f initial_progress.json

exit 0