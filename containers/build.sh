#!/bin/bash
# build.sh - Build all Docker images for the Microbiome Demo

set -e  # Exit on error

# Image versions and tags
VERSION="1.0.0"
REGISTRY="${1:-public.ecr.aws/lts}"
PUSH=${2:-false}  # Whether to push images to registry

# Color codes for prettier output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Building Microbiome Demo Docker Images"
echo "==========================================="
echo "Registry: $REGISTRY"
echo "Version: $VERSION"
echo "Push: $PUSH"
echo "==========================================="

# Ensure required directories exist
if [ ! -d "scripts" ]; then
  echo -e "${RED}Error: scripts directory not found${NC}"
  echo "This script must be run from the 'containers' directory"
  exit 1
fi

# Function to build and tag an image
build_image() {
  local dockerfile=$1
  local image_name=$2
  local image_tag=$3
  
  echo -e "${YELLOW}Building $image_name:$image_tag...${NC}"
  
  # Build the image
  docker build -t "$image_name:$image_tag" -f "$dockerfile" .
  
  # Tag with registry
  if [ "$PUSH" = "true" ]; then
    local registry_tag="$REGISTRY/$image_name:$image_tag"
    echo -e "${YELLOW}Tagging as $registry_tag...${NC}"
    docker tag "$image_name:$image_tag" "$registry_tag"
  fi
  
  echo -e "${GREEN}Successfully built $image_name:$image_tag${NC}"
}

# Function to push an image to the registry
push_image() {
  local image_name=$1
  local image_tag=$2
  local registry_tag="$REGISTRY/$image_name:$image_tag"
  
  echo -e "${YELLOW}Pushing $registry_tag to registry...${NC}"
  
  # Login to ECR if the registry is ECR
  if [[ "$REGISTRY" == *"ecr.aws"* ]]; then
    echo "Logging in to Amazon ECR..."
    aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REGISTRY"
  fi
  
  # Push the image
  docker push "$registry_tag"
  
  echo -e "${GREEN}Successfully pushed $registry_tag${NC}"
}

# Create necessary directories for nextflow config
mkdir -p nextflow
touch nextflow/.placeholder

# Build base image
build_image "Dockerfile.base" "microbiome-tools-base" "$VERSION"
build_image "Dockerfile.base" "microbiome-tools-base" "latest"

# Build microbiome image
build_image "Dockerfile.microbiome" "microbiome-tools" "$VERSION"
build_image "Dockerfile.microbiome" "microbiome-tools" "latest"

# Build GPU image
build_image "Dockerfile.gpu" "kraken2-gpu" "$VERSION"
build_image "Dockerfile.gpu" "kraken2-gpu" "latest"

# Push images if requested
if [ "$PUSH" = "true" ]; then
  echo -e "${YELLOW}Pushing images to registry...${NC}"
  
  push_image "microbiome-tools-base" "$VERSION"
  push_image "microbiome-tools-base" "latest"
  push_image "microbiome-tools" "$VERSION"
  push_image "microbiome-tools" "latest"
  push_image "kraken2-gpu" "$VERSION"
  push_image "kraken2-gpu" "latest"
  
  echo -e "${GREEN}All images pushed successfully${NC}"
fi

echo "==========================================="
echo "Docker images built successfully"
echo "==========================================="
echo "Images:"
echo "- microbiome-tools-base:$VERSION"
echo "- microbiome-tools-base:latest"
echo "- microbiome-tools:$VERSION"
echo "- microbiome-tools:latest"
echo "- kraken2-gpu:$VERSION"
echo "- kraken2-gpu:latest"
echo "==========================================="