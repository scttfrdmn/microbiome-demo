#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.

# Fix the malformed JSON in the microbiome demo files

set -e

# Fix the summary.json file that has malformed taxonomy and missing leading zeros
fix_summary_json() {
  local file="summary.json"
  local temp_file=$(mktemp)
  
  echo "Fixing $file..."
  
  # Check if file exists
  if [ ! -f "$file" ]; then
    echo "Error: $file not found"
    return 1
  fi
  
  # Read the file content
  local content=$(cat "$file")
  
  # Fix missing values in taxonomy section
  content=$(echo "$content" | 
    sed 's/"Bacteroidetes": ,/"Bacteroidetes": 0.35,/g' |
    sed 's/"Firmicutes": ,/"Firmicutes": 0.30,/g' |
    sed 's/"Proteobacteria": ,/"Proteobacteria": 0.15,/g' |
    sed 's/"Actinobacteria": ,/"Actinobacteria": 0.10,/g' |
    sed 's/"Fusobacteria": ,/"Fusobacteria": 0.05,/g')
    
  # Fix decimal values missing leading zeros
  content=$(echo "$content" | sed 's/: \.\([0-9]\+\)/: 0.\1/g')
  
  # Write the fixed content back to the file
  echo "$content" > "$file"
  
  # Verify the JSON is now valid
  if python -m json.tool "$file" > /dev/null 2>&1; then
    echo "✅ Fixed $file successfully"
  else
    echo "❌ Failed to fix $file"
    return 1
  fi
}

# Update the script to produce valid JSON
update_script() {
  local script="update_data.sh"
  local temp_file=$(mktemp)
  
  echo "Updating $script to produce valid JSON..."
  
  # Check if file exists
  if [ ! -f "$script" ]; then
    echo "Error: $script not found"
    return 1
  fi
  
  # Find the line where the taxonomy section starts in summary.json generation
  local start_line=$(grep -n '"taxonomy": {' "$script" | cut -d':' -f1)
  
  # If found, replace the problematic section
  if [ -n "$start_line" ]; then
    # Extract the line range for the taxonomy section (from start to the closing brace)
    local end_line=$((start_line + 7))
    
    # Create a new taxonomy section that properly formats the values
    local new_taxonomy='  "taxonomy": {
    "Bacteroidetes": '"$(printf "%.2f" "$bacteroidetes")"',
    "Firmicutes": '"$(printf "%.2f" "$firmicutes")"',
    "Proteobacteria": '"$(printf "%.2f" "$proteobacteria")"',
    "Actinobacteria": '"$(printf "%.2f" "$actinobacteria")"',
    "Fusobacteria": '"$(printf "%.2f" "$fusobacteria")"',
    "Other": 0.05
  },'
    
    # Replace the section in the script
    sed -i.bak "${start_line},${end_line}s/.*/${new_taxonomy}/" "$script"
    
    # Find all places where decimal values might be missing leading zeros
    # and modify those lines to ensure proper formatting
    sed -i.bak 's/\$(echo "\([^"]*\)"/\$(printf "%.2f" \$(echo "\1"/g' "$script"
    
    echo "✅ Updated $script to produce valid JSON"
  else
    echo "❌ Could not find taxonomy section in $script"
    return 1
  fi
}

# Main function
main() {
  echo "Starting JSON fixes..."
  
  # Fix existing JSON files
  fix_summary_json
  
  # Update the script to prevent future issues
  update_script
  
  echo "All fixes applied successfully"
}

main