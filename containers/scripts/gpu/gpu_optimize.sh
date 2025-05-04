#!/bin/bash
# gpu_optimize.sh - Optimize GPU settings for Kraken2

set -e  # Exit on error

# Check for GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo "Error: No GPU detected. This script requires an NVIDIA GPU."
    exit 1
fi

# Get GPU information
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader)
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)

echo "==================================="
echo "GPU Optimization for Kraken2"
echo "==================================="
echo "GPU Count: $GPU_COUNT"
echo "GPU Model: $GPU_NAME"
echo "GPU Memory: $GPU_MEMORY"
echo "==================================="

# Set optimization based on GPU memory
GPU_MEM_MB=$(echo $GPU_MEMORY | awk '{print $1}')

if [ $GPU_MEM_MB -ge 32000 ]; then
    # High-end GPU (32GB+)
    echo "Detected high-end GPU with 32GB+ memory"
    BATCH_SIZE=8
    PRELOAD_SIZE=256
elif [ $GPU_MEM_MB -ge 16000 ]; then
    # Mid-range GPU (16GB+)
    echo "Detected mid-range GPU with 16GB+ memory"
    BATCH_SIZE=4
    PRELOAD_SIZE=128
elif [ $GPU_MEM_MB -ge 8000 ]; then
    # Entry GPU (8GB+)
    echo "Detected entry-level GPU with 8GB+ memory"
    BATCH_SIZE=2
    PRELOAD_SIZE=64
else
    # Low memory GPU
    echo "Detected low memory GPU"
    BATCH_SIZE=1
    PRELOAD_SIZE=32
fi

# Export optimization variables
export KRAKEN2_GPU_BATCH_SIZE=$BATCH_SIZE
export KRAKEN2_GPU_PRELOAD_SIZE=$PRELOAD_SIZE
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}

echo "Optimized settings:"
echo "- KRAKEN2_GPU_BATCH_SIZE=$BATCH_SIZE"
echo "- KRAKEN2_GPU_PRELOAD_SIZE=$PRELOAD_SIZE"
echo "- CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "==================================="

# Apply system optimizations
echo "Applying system optimizations..."

# Set GPU mode to maximum performance if possible
if nvidia-smi --query-gpu=clocks.max.memory --format=csv,noheader &> /dev/null; then
    nvidia-smi -pm 1 || true  # Enable persistent mode
    nvidia-smi --auto-boost-default=0 || true  # Disable auto boost
    nvidia-smi -ac $(nvidia-smi --query-gpu=clocks.max.memory,clocks.max.graphics --format=csv,noheader | head -1 | sed 's/,/,/') || true  # Set max clocks
fi

echo "GPU optimization complete."