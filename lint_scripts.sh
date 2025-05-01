#!/bin/bash
# lint_scripts.sh - Validate and check shell scripts

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "==========================================="
echo "Shell Script Validation and Linting"
echo "==========================================="

# Check for shellcheck
if ! command -v shellcheck &> /dev/null; then
  echo -e "${YELLOW}Warning: shellcheck not found${NC}"
  echo "For better validation, install shellcheck: https://github.com/koalaman/shellcheck#installing"
  HAS_SHELLCHECK=0
else
  HAS_SHELLCHECK=1
  SHELLCHECK_VERSION=$(shellcheck --version | grep "version" | awk '{print $3}')
  echo -e "Using shellcheck version: ${GREEN}$SHELLCHECK_VERSION${NC}"
fi

# Find all shell scripts
SCRIPT_FILES=$(find . -name "*.sh" -type f -not -path "*/\.*" | sort)
echo -e "\nFound $(echo "$SCRIPT_FILES" | wc -l | xargs) shell scripts to validate"

# Basic syntax checking for all scripts
for script in $SCRIPT_FILES; do
  echo -e "\nChecking ${YELLOW}$script${NC}..."
  
  # Check for shebang
  if ! head -n 1 "$script" | grep -q "^#!/.*sh"; then
    echo -e "${RED}✗ Missing shebang in $script${NC}"
    exit_code=1
  else
    echo -e "${GREEN}✓ Shebang found${NC}"
  fi
  
  # Check for executable permission
  if [ ! -x "$script" ]; then
    echo -e "${YELLOW}⚠ $script is not executable${NC}"
    echo "Consider running: chmod +x $script"
  else
    echo -e "${GREEN}✓ Has executable permissions${NC}"
  fi
  
  # Basic bash syntax check
  if bash -n "$script"; then
    echo -e "${GREEN}✓ Syntax is valid${NC}"
  else
    echo -e "${RED}✗ Syntax error in $script${NC}"
    exit_code=1
  fi
  
  # Run shellcheck if available
  if [ $HAS_SHELLCHECK -eq 1 ]; then
    echo "Running shellcheck..."
    if shellcheck "$script"; then
      echo -e "${GREEN}✓ Passed shellcheck validation${NC}"
    else
      echo -e "${YELLOW}⚠ shellcheck found issues${NC}"
      # Don't fail the script on shellcheck warnings, just notify
    fi
  fi
  
  # Check for error handling
  if grep -q "set -e" "$script"; then
    echo -e "${GREEN}✓ Found error handling with 'set -e'${NC}"
  else
    echo -e "${YELLOW}⚠ No 'set -e' found. Consider adding error handling${NC}"
  fi
  
  # Check for AWS credentials handling
  if grep -q "aws configure" "$script" || grep -q "aws sts get-caller-identity" "$script"; then
    echo -e "${GREEN}✓ Checks for AWS credentials${NC}"
  else
    echo -e "${YELLOW}⚠ Doesn't verify AWS credentials. Consider adding a check.${NC}"
  fi
done

# Final result
if [ -z "$exit_code" ]; then
  echo -e "\n${GREEN}All shell scripts passed basic validation!${NC}"
  exit 0
else
  echo -e "\n${RED}Some scripts have issues. Please fix them and run this script again.${NC}"
  exit 1
fi