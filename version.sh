#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# version.sh - Semantic versioning utilities for Microbiome Demo

VERSION_FILE="./VERSION.txt"

# Function to get the current version
get_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "0.0.0"
  fi
}

# Function to update the version
update_version() {
  local version_type=$1
  local current_version=$(get_version)
  local major=$(echo "$current_version" | cut -d. -f1)
  local minor=$(echo "$current_version" | cut -d. -f2)
  local patch=$(echo "$current_version" | cut -d. -f3)
  
  case "$version_type" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "Error: Invalid version type. Use 'major', 'minor', or 'patch'"
      return 1
      ;;
  esac
  
  local new_version="${major}.${minor}.${patch}"
  echo "$new_version" > "$VERSION_FILE"
  echo "Version updated from $current_version to $new_version"
}

# Function to display version information
display_version() {
  local version=$(get_version)
  echo "Microbiome Demo version: $version"
}

# Only execute the script if it's not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Main script execution
  if [ $# -eq 0 ]; then
    display_version
    exit 0
  fi

  case "$1" in
    get)
      get_version
      ;;
    update)
      if [ $# -lt 2 ]; then
        echo "Error: Missing version type. Use 'major', 'minor', or 'patch'"
        exit 1
      fi
      update_version "$2"
      ;;
    display)
      display_version
      ;;
    *)
      echo "Usage: $0 [get|update <major|minor|patch>|display]"
      exit 1
      ;;
  esac

  exit 0
fi