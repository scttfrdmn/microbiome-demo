#!/bin/bash
# run_tests.sh - Run all the project's unit tests

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Running Unit Tests for Microbiome Demo"
echo "==========================================="

failures=0

# Python tests
echo -e "\n${YELLOW}Running Python unit tests...${NC}"
echo "-------------------------------------------"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed or not in PATH${NC}"
    echo "Please install Python 3: https://www.python.org/downloads/"
    exit 1
fi

# Run cost_report.py tests
echo "Testing cost_report.py..."
if python3 -m unittest workflow/templates/test_cost_report.py; then
    echo -e "${GREEN}✓ cost_report.py tests passed${NC}"
else
    echo -e "${RED}✗ cost_report.py tests failed${NC}"
    ((failures++))
fi

# Run any other Python tests here
# ...

# Final result
echo -e "\n==========================================="
if [ $failures -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$failures test suite(s) failed.${NC}"
    echo "Please fix the issues before proceeding."
    exit 1
fi