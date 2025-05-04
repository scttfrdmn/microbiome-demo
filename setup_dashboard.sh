#!/bin/bash
# Setup script for dashboard with S3 website hosting

set -e  # Exit on error

# Get configuration from config.sh
source config.sh

echo "=============================================="
echo "Setting up S3 Website Hosting for Dashboard"
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

# Enable S3 website hosting on the bucket
echo "Enabling S3 website hosting..."
aws s3 website s3://$BUCKET_NAME \
    --index-document index.html \
    --error-document error.html

# Set bucket policy to allow public read access for website hosting
echo "Setting bucket policy for website hosting..."
cat > website_bucket_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadForGetBucketObjects",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file://website_bucket_policy.json

# Configure CORS to allow dashboard to fetch data
echo "Configuring CORS for dashboard data access..."
cat > cors_configuration.json << EOF
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF

aws s3api put-bucket-cors \
    --bucket $BUCKET_NAME \
    --cors-configuration file://cors_configuration.json

# Create necessary directories in the bucket
echo "Creating dashboard directories..."
aws s3api put-object --bucket $BUCKET_NAME --key dashboard/ --content-type application/json
aws s3api put-object --bucket $BUCKET_NAME --key dashboard/data/ --content-type application/json
aws s3api put-object --bucket $BUCKET_NAME --key dashboard/css/ --content-type text/css
aws s3api put-object --bucket $BUCKET_NAME --key dashboard/js/ --content-type application/javascript

# Upload dashboard files
echo "Uploading dashboard files..."
aws s3 cp dashboard/real_time_dashboard.html s3://$BUCKET_NAME/dashboard/real_time_dashboard.html --content-type text/html
aws s3 cp dashboard/index.html s3://$BUCKET_NAME/dashboard/index.html --content-type text/html
aws s3 cp dashboard/css/styles.css s3://$BUCKET_NAME/dashboard/css/styles.css --content-type text/css
aws s3 cp dashboard/js/microbiome_dashboard.js s3://$BUCKET_NAME/dashboard/js/microbiome_dashboard.js --content-type application/javascript

# Create and upload a simple index.html that redirects to the dashboard
echo "Creating main redirect page..."
cat > index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Microbiome Demo Dashboard</title>
    <meta http-equiv="refresh" content="0; url=dashboard/real_time_dashboard.html">
</head>
<body>
    <p>Redirecting to <a href="dashboard/real_time_dashboard.html">Microbiome Dashboard</a>...</p>
</body>
</html>
EOF

aws s3 cp index.html s3://$BUCKET_NAME/index.html --content-type text/html

# Create and upload a simple error page
echo "Creating error page..."
cat > error.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Error - Microbiome Demo Dashboard</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 40px;
            background: #f8f9fa;
            color: #333;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: #fff;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        h1 {
            color: #d9534f;
        }
        a {
            color: #007bff;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Error - Page Not Found</h1>
        <p>The page you requested could not be found.</p>
        <p><a href="/">Return to Dashboard</a></p>
    </div>
</body>
</html>
EOF

aws s3 cp error.html s3://$BUCKET_NAME/error.html --content-type text/html

# Create initial dashboard data file
echo "Creating initial dashboard data file..."
cat > initial_dashboard_data.json << EOF
{
  "timestamp": $(date +%s),
  "update_time": "$(date +'%Y-%m-%d %H:%M:%S')",
  "workflow_id": "none",
  "percent_complete": 0,
  "status": "waiting",
  "elapsed_time": "00:00:00",
  "remaining_time": "--:--:--",
  "processes": {
    "completed": 0,
    "total": 0,
    "list": {}
  },
  "start_time_human": "Not started yet"
}
EOF

aws s3 cp initial_dashboard_data.json s3://$BUCKET_NAME/dashboard/data/latest_progress.json --content-type application/json

# Get the S3 website URL
WEBSITE_URL="http://$BUCKET_NAME.s3-website.$AWS_REGION.amazonaws.com"

echo "=============================================="
echo "Dashboard Setup Complete!"
echo "=============================================="
echo "Your dashboard is now available at:"
echo $WEBSITE_URL
echo
echo "Real-time progress tracking dashboard:"
echo "$WEBSITE_URL/dashboard/real_time_dashboard.html"
echo
echo "Results dashboard:"
echo "$WEBSITE_URL/dashboard/index.html"
echo "=============================================="

# Update the config.sh file with the dashboard URL
if ! grep -q "DASHBOARD_URL" config.sh; then
    echo "Updating config.sh with dashboard URL..."
    echo "# Dashboard URL" >> config.sh
    echo "DASHBOARD_URL=\"$WEBSITE_URL\"" >> config.sh
fi

# Clean up temporary files
rm -f website_bucket_policy.json cors_configuration.json index.html error.html initial_dashboard_data.json

exit 0