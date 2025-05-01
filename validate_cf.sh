#!/bin/bash
# validate_cf.sh - Validate CloudFormation template

set -e  # Exit on error

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TEMPLATE_FILE="cloudformation.yaml"
REGION=${1:-$(aws configure get region || echo "us-east-1")}

echo "==========================================="
echo "CloudFormation Template Validation"
echo "==========================================="
echo "Template: $TEMPLATE_FILE"
echo "Region: $REGION"
echo "==========================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
  echo "Please install AWS CLI: https://aws.amazon.com/cli/"
  exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo -e "${RED}Error: CloudFormation template file not found: $TEMPLATE_FILE${NC}"
  exit 1
fi

# Validate template syntax
echo -e "\nValidating CloudFormation template syntax..."
if aws cloudformation validate-template --template-body file://$TEMPLATE_FILE --region $REGION; then
  echo -e "${GREEN}✓ Template syntax is valid${NC}"
else
  echo -e "${RED}✗ Template has syntax errors${NC}"
  exit 1
fi

# Perform a more detailed check with cfn-lint if available
if command -v cfn-lint &> /dev/null; then
  echo -e "\nRunning cfn-lint for deeper validation..."
  if cfn-lint -t $TEMPLATE_FILE; then
    echo -e "${GREEN}✓ Template passed cfn-lint checks${NC}"
  else
    echo -e "${YELLOW}⚠ Template has cfn-lint warnings or errors${NC}"
    # Don't exit with error here as these might be just warnings
  fi
else
  echo -e "\n${YELLOW}⚠ cfn-lint not found. For more detailed validation, install with:${NC}"
  echo "pip install cfn-lint"
fi

# Check for unreferenced parameters
echo -e "\nChecking for unreferenced parameters..."
parameters=$(grep -A2 "Parameters:" $TEMPLATE_FILE | grep -v "Parameters:" | grep -v ":" | grep -v "-" | awk '{print $1}')
for param in $parameters; do
  if ! grep -q "!Ref $param" $TEMPLATE_FILE && ! grep -q "Ref: $param" $TEMPLATE_FILE; then
    echo -e "${YELLOW}⚠ Parameter $param appears to be unused${NC}"
  fi
done

# Check IAM role permissions (basic)
echo -e "\nChecking IAM role permissions..."
iam_roles=$(grep -n "AWS::IAM::Role" $TEMPLATE_FILE | cut -d ":" -f1)
for line in $iam_roles; do
  role_name=$(sed -n "$((line-1))p" $TEMPLATE_FILE | awk '{print $1}')
  echo -e "Found IAM role: ${YELLOW}$role_name${NC}"
done

# Estimate cost with AWS Pricing Calculator (this would be a good future enhancement)
echo -e "\n${YELLOW}Note:${NC} For cost estimation, upload this template to AWS CloudFormation console"
echo "or use the AWS Pricing Calculator."

echo -e "\n${GREEN}CloudFormation template validation complete!${NC}"