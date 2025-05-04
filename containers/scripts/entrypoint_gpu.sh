#!/bin/bash
# entrypoint_gpu.sh - GPU container entrypoint script

set -e  # Exit on error

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

# Check for GPU
if command -v nvidia-smi &> /dev/null; then
    echo "==========================================="
    echo "GPU Information:"
    nvidia-smi
    echo "==========================================="
else
    echo "WARNING: No GPU detected. This container is optimized for GPU usage."
fi

# Display container info
echo "==========================================="
echo "Microbiome Demo GPU Container"
echo "==========================================="
echo "Container version: 1.0.0"
echo "Working directory: $(pwd)"
echo "User: $(whoami)"
echo "Time: $(date)"
echo "==========================================="

# Check for Kraken2
echo "Tool versions:"
echo "- Kraken2: $(kraken2 --version 2>&1 | head -1)"
echo "- Bracken: $(bracken --version 2>&1 | head -1)"
echo "- AWS CLI: $(aws --version 2>&1)"
echo "==========================================="

# Execute the provided command
exec "$@"