#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# update_real_data.sh - Updates the dashboard data with real format data

set -e  # Exit on error

# Create summary.json from the test data
echo "Copying test microbiome summary data to summary.json..."
cp test_microbiome_summary.json summary.json

# Create realistic progress.json
echo "Creating progress.json with completed status..."
cat > progress.json << EOF
{
  "status": "COMPLETED",
  "time_elapsed": 900,
  "completed_samples": 100,
  "total_samples": 100,
  "sample_status": {
    "completed": 100,
    "running": 0,
    "pending": 0,
    "failed": 0
  },
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "job_id": "microbiome-demo-job-$(date +%s)"
}
EOF

# Create resources.json with realistic utilization data
echo "Creating resources.json with utilization data..."
cat > resources.json << EOF
{
  "utilization": [
    {"time": 890, "cpu": 47, "memory": 78, "gpu": 29},
    {"time": 891, "cpu": 44, "memory": 75, "gpu": 40},
    {"time": 892, "cpu": 44, "memory": 77, "gpu": 53},
    {"time": 893, "cpu": 46, "memory": 73, "gpu": 42},
    {"time": 894, "cpu": 51, "memory": 74, "gpu": 54},
    {"time": 895, "cpu": 52, "memory": 71, "gpu": 43},
    {"time": 896, "cpu": 51, "memory": 70, "gpu": 50},
    {"time": 897, "cpu": 53, "memory": 76, "gpu": 37},
    {"time": 898, "cpu": 50, "memory": 70, "gpu": 53},
    {"time": 899, "cpu": 51, "memory": 79, "gpu": 35}
  ],
  "instances": {
    "cpu": 8,
    "gpu": 2
  },
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "Data update complete!"
echo "You can now access the dashboard and it will use real data format"