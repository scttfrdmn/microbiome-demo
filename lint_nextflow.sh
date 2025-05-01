#!/bin/bash
# lint_nextflow.sh - Validate and lint Nextflow scripts

set -e  # Exit on any error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Nextflow Linting and Validation"
echo "==========================================="

# Check if Nextflow is installed
if ! command -v nextflow &> /dev/null; then
  echo -e "${RED}Error: Nextflow is not installed or not in PATH${NC}"
  echo "Please install Nextflow: https://www.nextflow.io/docs/latest/getstarted.html"
  exit 1
fi

# Get Nextflow version
NF_VERSION=$(nextflow -v | awk '{print $3}')
echo -e "Using Nextflow version: ${GREEN}$NF_VERSION${NC}"

# Check all .nf files in the workflow directory
for nf_file in workflow/*.nf; do
  echo -e "\nLinting ${YELLOW}$nf_file${NC}..."
  
  # Run nextflow lint
  if nextflow lint "$nf_file"; then
    echo -e "${GREEN}✓ $nf_file passed linting${NC}"
  else
    echo -e "${RED}✗ $nf_file has linting issues${NC}"
    exit_code=1
  fi
  
  # Check for syntax errors by doing a dry run
  echo "Checking syntax with dry run..."
  if nextflow -C workflow/microbiome_nextflow.config -q run "$nf_file" -preview; then
    echo -e "${GREEN}✓ $nf_file syntax is valid${NC}"
  else
    echo -e "${RED}✗ $nf_file has syntax errors${NC}"
    exit_code=1
  fi
done

# Check config file
echo -e "\nValidating ${YELLOW}workflow/microbiome_nextflow.config${NC}..."
if nextflow -C workflow/microbiome_nextflow.config run -preview; then
  echo -e "${GREEN}✓ Config file is valid${NC}"
else
  echo -e "${RED}✗ Config file has errors${NC}"
  exit_code=1
fi

# Final result
if [ -z "$exit_code" ]; then
  echo -e "\n${GREEN}All Nextflow files passed validation!${NC}"
  exit 0
else
  echo -e "\n${RED}Some files have issues. Please fix them and run this script again.${NC}"
  exit 1
fi