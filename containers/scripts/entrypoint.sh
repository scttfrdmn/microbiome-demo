#!/bin/bash
# entrypoint.sh - Container entrypoint script

set -e  # Exit on error

# Activate conda environment
source /opt/conda/etc/profile.d/conda.sh
conda activate microbiome

# Configure AWS credentials if provided
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Configuring AWS credentials..."
    mkdir -p ~/.aws
    
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF

    if [ -n "$AWS_DEFAULT_REGION" ]; then
        cat > ~/.aws/config << EOF
[default]
region = $AWS_DEFAULT_REGION
EOF
    fi
fi

# Display container info
echo "==========================================="
echo "Microbiome Demo Container"
echo "==========================================="
echo "Container version: 1.0.0"
echo "Python version: $(python --version 2>&1)"
echo "Working directory: $(pwd)"
echo "User: $(whoami)"
echo "Time: $(date)"
echo "==========================================="

# Check for tools
echo "Installed tools:"
echo "- Nextflow: $(nextflow -v 2>&1 | head -1)"
echo "- AWS CLI: $(aws --version 2>&1)"
if command -v kraken2 &> /dev/null; then
    echo "- Kraken2: $(kraken2 --version | head -1)"
fi
if command -v metaphlan &> /dev/null; then
    echo "- MetaPhlAn: $(metaphlan --version 2>&1)"
fi
if command -v humann &> /dev/null; then
    echo "- HUMAnN: $(humann --version 2>&1)"
fi
echo "==========================================="

# Execute the provided command
exec "$@"