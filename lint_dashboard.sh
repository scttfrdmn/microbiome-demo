#!/bin/bash
# lint_dashboard.sh - Lint the dashboard JavaScript code

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

DASHBOARD_DIR="dashboard"

echo "==========================================="
echo "Dashboard JavaScript Linting"
echo "==========================================="

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}Warning: Node.js is not installed${NC}"
  echo "For JavaScript linting, please install Node.js: https://nodejs.org/"
  echo "After installing Node.js, run 'cd $DASHBOARD_DIR && npm install' to set up linting tools"
  exit 0
fi

# Check if package.json exists in dashboard directory
if [ ! -f "$DASHBOARD_DIR/package.json" ]; then
  echo -e "${YELLOW}Warning: $DASHBOARD_DIR/package.json not found${NC}"
  echo "The package.json file is required for linting"
  exit 0
fi

# Install dependencies if needed
if [ ! -d "$DASHBOARD_DIR/node_modules" ]; then
  echo "Installing JavaScript dependencies..."
  cd "$DASHBOARD_DIR" && npm install
  cd ..
fi

# Check if eslint is available
if [ ! -f "$DASHBOARD_DIR/node_modules/.bin/eslint" ]; then
  echo -e "${YELLOW}Warning: ESLint not found in node_modules${NC}"
  echo "Run 'cd $DASHBOARD_DIR && npm install' to install ESLint"
  exit 0
fi

# Run ESLint on dashboard JavaScript files
echo -e "\nLinting JavaScript files in $DASHBOARD_DIR/js/..."
if cd "$DASHBOARD_DIR" && npm run lint; then
  echo -e "\n${GREEN}✓ JavaScript code passed linting${NC}"
else
  echo -e "\n${YELLOW}⚠ ESLint found issues in JavaScript code${NC}"
  echo "To automatically fix fixable issues, run: cd $DASHBOARD_DIR && npm run lint:fix"
  exit_code=1
fi

# Check for browser compatibility issues
echo -e "\nChecking for browser compatibility issues..."
js_files=$(find "$DASHBOARD_DIR/js" -name "*.js" -type f)
for file in $js_files; do
  echo "Checking $file..."
  # Check for ES6 module syntax which might not be compatible with direct browser usage
  if grep -q "import " "$file" || grep -q "export " "$file"; then
    echo -e "${YELLOW}⚠ File contains ES6 module syntax which may require bundling for browser compatibility: $file${NC}"
  fi
  
  # Check for async/await which might need polyfills for older browsers
  if grep -q "async " "$file" || grep -q "await " "$file"; then
    echo -e "${YELLOW}⚠ File uses async/await which may need polyfills for older browsers: $file${NC}"
  fi
done

# Final result
if [ -z "$exit_code" ]; then
  echo -e "\n${GREEN}Dashboard code validation complete!${NC}"
  exit 0
else
  echo -e "\n${YELLOW}Some issues were found. Please address them before deploying.${NC}"
  exit 1
fi