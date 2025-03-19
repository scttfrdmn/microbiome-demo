#!/bin/bash
# prepare_microbiome_data.sh
# Script to prepare the Human Microbiome Project data for the 15-minute Microbiome Demo

set -e  # Exit on error

# Source configuration if exists
if [ -f "./config.sh" ]; then
  source ./config.sh
else
  # Configuration
  BUCKET_NAME=${1:-microbiome-demo-bucket}  # Use provided bucket name or default
  REGION=${2:-us-east-1}  # Use provided region or default
fi

SAMPLE_COUNT=100  # Number of samples to include
SOURCE_BUCKET="s3://human-microbiome-project"
OUTPUT_PATH="s3://$BUCKET_NAME/input"
TEMP_DIR="./temp_data"

echo "========================================="
echo "Microbiome Demo Data Preparation"
echo "========================================="
echo "Target bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "Sample count: $SAMPLE_COUNT"
echo "========================================="

# Create local temp directory
mkdir -p $TEMP_DIR
cd $TEMP_DIR

echo "Creating S3 bucket if it doesn't exist..."
if ! aws s3 ls "s3://$BUCKET_NAME" 2>&1 > /dev/null; then
  aws s3 mb "s3://$BUCKET_NAME" --region $REGION
  echo "Bucket created: $BUCKET_NAME"
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

echo "Retrieving sample list from Human Microbiome Project..."
# Get list of available samples (focusing on gut microbiome)
aws s3 ls --recursive "${SOURCE_BUCKET}/HMASM/anterior_nares/" | grep "SRS.*fastq.gz$" > all_samples_nares.txt
aws s3 ls --recursive "${SOURCE_BUCKET}/HMASM/stool/" | grep "SRS.*fastq.gz$" > all_samples_stool.txt
aws s3 ls --recursive "${SOURCE_BUCKET}/HMASM/buccal_mucosa/" | grep "SRS.*fastq.gz$" > all_samples_buccal.txt

# Combine and filter to get paired-end samples
cat all_samples_*.txt | grep "_1.fastq.gz" > forward_reads.txt
sed 's/_1.fastq.gz/_2.fastq.gz/g' forward_reads.txt > reverse_reads.txt

# Verify paired files exist
while read -r forward; do
  reverse=$(echo "$forward" | sed 's/_1.fastq.gz/_2.fastq.gz/g')
  if grep -q "$reverse" all_samples_*.txt; then
    echo "$forward,$reverse" >> paired_samples.txt
  fi
done < forward_reads.txt

# Select a random subset of paired samples for the demo
echo "Selecting $SAMPLE_COUNT random samples..."
shuf -n $SAMPLE_COUNT paired_samples.txt > selected_samples.txt

# Create a CSV file with sample information
echo "sample_id,body_site,fastq_1,fastq_2" > sample_list.csv

echo "Processing sample information..."
while read -r line; do
  # Extract the file paths
  filepath1=$(echo "$line" | cut -d',' -f1 | awk '{print $4}')
  filepath2=$(echo "$line" | cut -d',' -f2 | awk '{print $4}')
  
  # Extract sample ID from the file path
  sample_id=$(basename "$filepath1" | sed 's/_1.fastq.gz//')
  
  # Determine body site from path
  if [[ "$filepath1" == *"stool"* ]]; then
    body_site="stool"
  elif [[ "$filepath1" == *"buccal_mucosa"* ]]; then
    body_site="buccal_mucosa"
  elif [[ "$filepath1" == *"anterior_nares"* ]]; then
    body_site="anterior_nares"
  else
    body_site="other"
  fi
  
  # Add to CSV
  echo "$sample_id,$body_site,${SOURCE_BUCKET}/$filepath1,${SOURCE_BUCKET}/$filepath2" >> sample_list.csv
done < selected_samples.txt

echo "Uploading sample list to S3..."
aws s3 cp sample_list.csv "${OUTPUT_PATH}/sample_list.csv"

# Create a manifest file for the CloudFormation template
echo "Creating resource manifest..."
cat > manifest.json << EOF
{
  "samples": {
    "count": $SAMPLE_COUNT,
    "source": "${OUTPUT_PATH}/sample_list.csv"
  },
  "reference_databases": {
    "kraken_db": "s3://genome-idx/kraken/k2_standard_20230605.tar.gz",
    "metaphlan_db": "s3://$BUCKET_NAME/reference/metaphlan_db",
    "humann_db": "s3://$BUCKET_NAME/reference/humann_db"
  }
}
EOF

# Upload manifest
aws s3 cp manifest.json "${OUTPUT_PATH}/manifest.json"

# Create a simple metadata file with information about body sites
echo "Creating body site metadata..."
cat > bodysite_info.json << EOF
{
  "body_sites": {
    "stool": "Gut microbiome sample from stool",
    "buccal_mucosa": "Oral microbiome sample from the cheek",
    "anterior_nares": "Nasal microbiome sample from the nostril",
    "posterior_fornix": "Vaginal microbiome sample",
    "supragingival_plaque": "Dental plaque microbiome sample"
  },
  "site_descriptions": {
    "stool": "Gut microbiomes typically show high diversity with Bacteroidetes and Firmicutes dominating",
    "buccal_mucosa": "Oral microbiomes are dominated by Streptococcus species",
    "anterior_nares": "Nasal microbiomes often contain Staphylococcus and Corynebacterium",
    "posterior_fornix": "Vaginal microbiomes are often dominated by Lactobacillus species",
    "supragingival_plaque": "Dental plaque contains complex biofilms with Streptococcus and Actinomyces"
  }
}
EOF

# Upload body site metadata
aws s3 cp bodysite_info.json "${OUTPUT_PATH}/bodysite_info.json"

# Calculate body site distribution for our sample
echo "Calculating body site distribution..."
awk -F',' 'NR>1 {site[$2]++} END {for (s in site) print s","site[s]}' sample_list.csv > bodysite_counts.csv
aws s3 cp bodysite_counts.csv "${OUTPUT_PATH}/bodysite_counts.csv"

# Download reduced Kraken2 database for demo purposes
echo "Preparing reference databases..."
mkdir -p reference

# Create placeholder for Kraken2 database download script
cat > download_kraken2_db.sh << EOF
#!/bin/bash
# Download latest Kraken2 standard database (8GB)
mkdir -p kraken2_db
cd kraken2_db
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20230605.tar.gz
tar -xzf k2_standard_20230605.tar.gz
aws s3 cp --recursive ./ s3://$BUCKET_NAME/reference/kraken2_db/
cd ..
EOF

# Create placeholder for MetaPhlAn database download script
cat > download_metaphlan_db.sh << EOF
#!/bin/bash
# Download MetaPhlAn database using the metaphlan utility
pip install metaphlan
metaphlan --install --bowtie2db metaphlan_db
aws s3 cp --recursive metaphlan_db/ s3://$BUCKET_NAME/reference/metaphlan_db/
EOF

# Create placeholder for HUMAnN database download script
cat > download_humann_db.sh << EOF
#!/bin/bash
# Download HUMAnN databases
pip install humann
humann_databases --download chocophlan full humann_db
humann_databases --download uniref uniref90_diamond humann_db
aws s3 cp --recursive humann_db/ s3://$BUCKET_NAME/reference/humann_db/
EOF

# Make scripts executable
chmod +x download_kraken2_db.sh download_metaphlan_db.sh download_humann_db.sh

# Upload database download scripts to S3
aws s3 cp download_kraken2_db.sh "${OUTPUT_PATH}/scripts/download_kraken2_db.sh"
aws s3 cp download_metaphlan_db.sh "${OUTPUT_PATH}/scripts/download_metaphlan_db.sh"
aws s3 cp download_humann_db.sh "${OUTPUT_PATH}/scripts/download_humann_db.sh"

# Create a README for the bucket
cat > README.md << EOF
# Microbiome Demo Dataset

This bucket contains data for the 15-minute Microbiome Demo showcasing AWS cloud capabilities for metagenomic analysis.

## Contents

- /input/ - Input data including sample list and metadata
- /results/ - Analysis results from the demo pipeline
- /reports/ - Cost reports and performance metrics
- /reference/ - Reference databases for microbiome analysis

## Sample Information

The demo uses $SAMPLE_COUNT samples from the Human Microbiome Project, focusing on different body sites including gut (stool), oral (buccal mucosa), and nasal (anterior nares) microbiomes.

## Reference Databases

This demo requires several reference databases:
- Kraken2 standard database for taxonomic classification
- MetaPhlAn database for marker gene-based profiling
- HUMAnN database for functional profiling

Scripts to download these databases are provided in the /input/scripts/ directory.
EOF

aws s3 cp README.md "s3://$BUCKET_NAME/README.md"

# Create template batch job script for custom initialization
cat > batch_init.sh << EOF
#!/bin/bash
# Initialization script for AWS Batch instances

# Install any additional tools needed
apt-get update
apt-get install -y samtools bcftools tabix python3-pip

# Install bioinformatics tools
pip3 install biopython numpy pandas matplotlib seaborn

# Pre-cache commonly used Docker images
docker pull public.ecr.aws/lts/microbiome-tools:latest
docker pull public.ecr.aws/lts/kraken2-gpu:latest

# Report successful initialization
echo "Batch instance initialization complete"
EOF

aws s3 cp batch_init.sh "${OUTPUT_PATH}/batch_init.sh"

# Create a test dataset with only 5 samples for quick testing
echo "Creating test dataset..."
head -n 6 sample_list.csv > test_sample_list.csv
aws s3 cp test_sample_list.csv "${OUTPUT_PATH}/test_sample_list.csv"

# Clean up
cd ..
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR

echo "========================================="
echo "Data preparation completed successfully!"
echo "========================================="
echo "Sample list: ${OUTPUT_PATH}/sample_list.csv"
echo "Database scripts: ${OUTPUT_PATH}/scripts/"
echo "Manifest: ${OUTPUT_PATH}/manifest.json"
echo ""
echo "Next steps:"
echo "1. Download reference databases using provided scripts (if needed)"
echo "2. Deploy the CloudFormation stack"
echo "3. Run a test job with 5 samples"
echo "4. Prepare for the full demo"
echo "========================================="
