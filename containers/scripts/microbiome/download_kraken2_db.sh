#!/bin/bash
# download_kraken2_db.sh - Download Kraken2 database

set -e  # Exit on error

DB_DIR="${1:-/ref/kraken2}"
DB_TYPE="${2:-standard}"  # standard, minikraken, etc.
DB_VERSION="${3:-k2_standard_20230605}"

echo "==================================="
echo "Downloading Kraken2 database"
echo "==================================="
echo "Database type: $DB_TYPE"
echo "Database version: $DB_VERSION"
echo "Output directory: $DB_DIR"
echo "==================================="

# Create output directory
mkdir -p $DB_DIR

# Set download URL based on database type
if [ "$DB_TYPE" == "standard" ]; then
  DOWNLOAD_URL="https://genome-idx.s3.amazonaws.com/kraken/$DB_VERSION.tar.gz"
elif [ "$DB_TYPE" == "minikraken" ]; then
  DOWNLOAD_URL="https://genome-idx.s3.amazonaws.com/kraken/k2_standard_08gb_20230605.tar.gz"
elif [ "$DB_TYPE" == "s3" ]; then
  # Use provided S3 path
  DOWNLOAD_URL="s3://$DB_VERSION"
else
  echo "Error: Unknown database type: $DB_TYPE"
  exit 1
fi

# Download and extract the database
echo "Downloading from $DOWNLOAD_URL..."

if [[ $DOWNLOAD_URL == s3://* ]]; then
  # Download from S3 bucket
  aws s3 cp --recursive $DOWNLOAD_URL $DB_DIR
else
  # Download from HTTP URL
  # Create a temporary directory
  TMP_DIR=$(mktemp -d)
  
  # Download to temporary directory
  cd $TMP_DIR
  wget -q --show-progress $DOWNLOAD_URL -O kraken2_db.tar.gz
  
  # Extract
  echo "Extracting database..."
  tar -xzf kraken2_db.tar.gz -C $DB_DIR --strip-components=1
  
  # Clean up
  rm -rf $TMP_DIR
fi

# Check database files
echo "Verifying database files..."
required_files=("hash.k2d" "opts.k2d" "taxo.k2d")
for file in "${required_files[@]}"; do
  if [ ! -f "$DB_DIR/$file" ]; then
    echo "Error: Missing required Kraken2 database file: $file"
    exit 1
  fi
done

# Build Bracken database from Kraken2 database
if command -v bracken-build &> /dev/null; then
  echo "Building Bracken database..."
  bracken-build -d $DB_DIR -t ${CPU_THREADS:-4} -k 35 -l 150
fi

echo "==================================="
echo "Kraken2 database ready at $DB_DIR"
echo "==================================="