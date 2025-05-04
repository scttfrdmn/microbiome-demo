#!/bin/bash
# Test script for dashboard integration with real-time progress tracking

set -e  # Exit on error

# Get configuration from config.sh
source config.sh

echo "=============================================="
echo "Testing Dashboard Integration"
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

if [ -z "$DASHBOARD_URL" ]; then
    echo "ERROR: DASHBOARD_URL not set. Run setup_dashboard.sh first."
    exit 1
fi

# Verify S3 website configuration is set
echo "Verifying S3 website configuration..."
WEBSITE_CONFIG=$(aws s3api get-bucket-website --bucket $BUCKET_NAME 2>/dev/null || echo "")

if [ -z "$WEBSITE_CONFIG" ]; then
    echo "ERROR: S3 website hosting not configured. Run setup_dashboard.sh first."
    exit 1
fi

echo "S3 website hosting is properly configured."

# Verify the CORS configuration
echo "Verifying CORS configuration..."
CORS_CONFIG=$(aws s3api get-bucket-cors --bucket $BUCKET_NAME 2>/dev/null || echo "")

if [ -z "$CORS_CONFIG" ]; then
    echo "WARNING: CORS configuration not found. Dashboard may not be able to fetch data."
else
    echo "CORS configuration is properly set."
fi

# Check if dashboard files exist
echo "Checking dashboard files..."
INDEX_EXISTS=$(aws s3 ls s3://$BUCKET_NAME/dashboard/real_time_dashboard.html 2>/dev/null || echo "")

if [ -z "$INDEX_EXISTS" ]; then
    echo "ERROR: Dashboard files not found. Run setup_dashboard.sh first."
    exit 1
fi

echo "Dashboard files are present in S3 bucket."

# Generate a unique workflow ID for testing
WORKFLOW_ID="test-dashboard-$(date +%s)"
echo "Using test workflow ID: $WORKFLOW_ID"

# Create a test progress data file
echo "Creating test progress data..."
mkdir -p dashboard_test

cat > dashboard_test/test_progress.json << EOF
{
  "timestamp": $(date +%s),
  "update_time": "$(date +'%Y-%m-%d %H:%M:%S')",
  "workflow_id": "${WORKFLOW_ID}",
  "percent_complete": 25,
  "status": "running",
  "elapsed_time": "00:05:30",
  "remaining_time": "00:16:30",
  "processes": {
    "completed": 3,
    "total": 12,
    "list": {
      "workflow_init": {
        "status": "completed",
        "last_updated": $(date +%s),
        "last_updated_human": "$(date +'%Y-%m-%d %H:%M:%S')"
      },
      "data_loading": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 120 )),
        "last_updated_human": "$(date -d '2 minutes ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "quality_control": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 60 )),
        "last_updated_human": "$(date -d '1 minute ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "taxonomic_classification": {
        "status": "running",
        "last_updated": $(date +%s),
        "last_updated_human": "$(date +'%Y-%m-%d %H:%M:%S')"
      }
    }
  },
  "start_time_human": "$(date -d '5 minutes 30 seconds ago' +'%Y-%m-%d %H:%M:%S')"
}
EOF

# Upload the test progress data to S3
echo "Uploading test progress data to S3..."
aws s3 cp dashboard_test/test_progress.json s3://$BUCKET_NAME/dashboard/data/latest_progress.json --content-type application/json
aws s3 cp dashboard_test/test_progress.json s3://$BUCKET_NAME/progress/$WORKFLOW_ID/progress.json --content-type application/json

echo "Test progress data uploaded."

# Display dashboard URL
echo "=============================================="
echo "Dashboard Integration Test Complete!"
echo "=============================================="
echo "Your dashboard is now available with test data at:"
echo "$DASHBOARD_URL/dashboard/real_time_dashboard.html"
echo
echo "Please open this URL in your browser to verify the dashboard is working correctly."
echo "=============================================="

# Wait a moment and update progress to 50%
sleep 5
echo "Updating progress to 50%..."

cat > dashboard_test/test_progress_50.json << EOF
{
  "timestamp": $(date +%s),
  "update_time": "$(date +'%Y-%m-%d %H:%M:%S')",
  "workflow_id": "${WORKFLOW_ID}",
  "percent_complete": 50,
  "status": "running",
  "elapsed_time": "00:10:15",
  "remaining_time": "00:10:15",
  "processes": {
    "completed": 6,
    "total": 12,
    "list": {
      "workflow_init": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 300 )),
        "last_updated_human": "$(date -d '5 minutes ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "data_loading": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 240 )),
        "last_updated_human": "$(date -d '4 minutes ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "quality_control": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 180 )),
        "last_updated_human": "$(date -d '3 minutes ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "taxonomic_classification": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 120 )),
        "last_updated_human": "$(date -d '2 minutes ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "functional_profiling": {
        "status": "completed",
        "last_updated": $(( $(date +%s) - 60 )),
        "last_updated_human": "$(date -d '1 minute ago' +'%Y-%m-%d %H:%M:%S')"
      },
      "diversity_analysis": {
        "status": "completed",
        "last_updated": $(date +%s),
        "last_updated_human": "$(date +'%Y-%m-%d %H:%M:%S')"
      },
      "result_summary": {
        "status": "running",
        "last_updated": $(date +%s),
        "last_updated_human": "$(date +'%Y-%m-%d %H:%M:%S')"
      }
    }
  },
  "start_time_human": "$(date -d '10 minutes 15 seconds ago' +'%Y-%m-%d %H:%M:%S')"
}
EOF

aws s3 cp dashboard_test/test_progress_50.json s3://$BUCKET_NAME/dashboard/data/latest_progress.json --content-type application/json
aws s3 cp dashboard_test/test_progress_50.json s3://$BUCKET_NAME/progress/$WORKFLOW_ID/progress.json --content-type application/json

echo "Progress updated to 50%. Check the dashboard to see the update!"

# Clean up
rm -rf dashboard_test

exit 0