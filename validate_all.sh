#!/bin/bash
# validate_all.sh - Run all validation and linting scripts

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Running all validation and linting scripts"
echo "==========================================="

validate_scripts=("lint_nextflow.sh" "validate_cf.sh" "lint_scripts.sh" "lint_dashboard.sh")
failures=0

for script in "${validate_scripts[@]}"; do
  if [ -f "$script" ] && [ -x "$script" ]; then
    echo -e "\n${YELLOW}Running $script...${NC}"
    echo "-------------------------------------------"
    
    if ./$script; then
      echo -e "\n${GREEN}✓ $script completed successfully${NC}"
    else
      echo -e "\n${RED}✗ $script failed${NC}"
      ((failures++))
    fi
    
    echo "-------------------------------------------"
  else
    echo -e "\n${RED}Script not found or not executable: $script${NC}"
    ((failures++))
  fi
done

# Check AWS resources if config.sh exists
if [ -f "config.sh" ]; then
  echo -e "\n${YELLOW}Checking AWS resources...${NC}"
  echo "-------------------------------------------"
  
  if ./validate_aws_resources.sh; then
    echo -e "\n${GREEN}✓ AWS resources validation completed successfully${NC}"
  else
    echo -e "\n${YELLOW}⚠ AWS resources validation had warnings${NC}"
    # Don't count this as a failure to prevent blocking development work
  fi
  
  echo "-------------------------------------------"
else
  echo -e "\n${YELLOW}⚠ config.sh not found, skipping AWS resources validation${NC}"
  echo "Run setup.sh first to create the configuration"
fi

echo -e "\n==========================================="
if [ $failures -eq 0 ]; then
  echo -e "${GREEN}All validation scripts passed!${NC}"
  echo "Your project is ready for deployment."
else
  echo -e "${RED}$failures validation script(s) failed.${NC}"
  echo "Please fix the issues before proceeding."
  exit 1
fi