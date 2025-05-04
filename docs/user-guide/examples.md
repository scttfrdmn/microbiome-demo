# Microbiome Demo Examples

This document provides practical examples of how to use the Microbiome Demo for various common tasks and scenarios.

## Basic Examples

### Example 1: Running the Demo with Default Settings

The simplest way to run the demo is with the default settings:

```bash
# Set up with default settings
./setup.sh microbiome-demo-bucket-$(date +%s) us-east-1

# Prepare data
./prepare_microbiome_data.sh

# Deploy CloudFormation
aws cloudformation create-stack \
  --stack-name microbiome-demo \
  --template-body file://cloudformation.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=DataBucketName,ParameterValue=$(grep BUCKET_NAME config.sh | cut -d'=' -f2)

# Wait for stack creation
aws cloudformation wait stack-create-complete --stack-name microbiome-demo

# Run the demo
./start_demo.sh
```

### Example 2: Running a Small Test

To validate your setup without processing all 100 samples:

```bash
# Run the test with just 5 samples
./test_demo.sh
```

### Example 3: Monitoring and Checking Results

To check the status and results:

```bash
# Get the dashboard URL
DASHBOARD_URL=$(aws cloudformation describe-stacks \
  --stack-name microbiome-demo \
  --query "Stacks[0].Outputs[?OutputKey=='DashboardURL'].OutputValue" \
  --output text)
echo "Dashboard URL: $DASHBOARD_URL"

# Check the results in S3
aws s3 ls s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/results/

# Download specific results
aws s3 cp s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/results/summary/microbiome_summary.json ./
```

## Advanced Examples

### Example 4: Customizing Reference Databases

To use custom reference databases:

```bash
# Upload your custom Kraken database to S3
aws s3 cp custom_kraken_db/ s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/reference/custom_kraken_db/ --recursive

# Edit workflow/microbiome_nextflow.config
sed -i 's|kraken_db = "s3://.*|kraken_db = "s3://'"$(grep BUCKET_NAME config.sh | cut -d'=' -f2)"'/reference/custom_kraken_db"|' workflow/microbiome_nextflow.config

# Run with custom database
./start_demo.sh
```

### Example 5: Adding Your Own Samples

To analyze your own metagenomic samples:

```bash
# Create sample list CSV
cat > my_samples.csv << EOF
sample_id,body_site,fastq_1,fastq_2
sample1,gut,s3://my-data-bucket/sample1_R1.fastq.gz,s3://my-data-bucket/sample1_R2.fastq.gz
sample2,skin,s3://my-data-bucket/sample2_R1.fastq.gz,s3://my-data-bucket/sample2_R2.fastq.gz
sample3,oral,s3://my-data-bucket/sample3_R1.fastq.gz,s3://my-data-bucket/sample3_R2.fastq.gz
EOF

# Upload to S3
aws s3 cp my_samples.csv s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/input/my_samples.csv

# Edit workflow/microbiome_nextflow.config
sed -i 's|samples = "s3://.*|samples = "s3://'"$(grep BUCKET_NAME config.sh | cut -d'=' -f2)"'/input/my_samples.csv"|' workflow/microbiome_nextflow.config

# Run the pipeline
./start_demo.sh
```

### Example 6: Adjusting AWS Resources

To modify the compute resources for larger workloads:

```bash
# Update Batch compute environment
aws batch update-compute-environment \
  --compute-environment $(grep COMPUTE_ENV_CPU config.sh | cut -d'=' -f2) \
  --compute-resources "maxvCpus=512"

# Update GPU compute environment
aws batch update-compute-environment \
  --compute-environment $(grep COMPUTE_ENV_GPU config.sh | cut -d'=' -f2) \
  --compute-resources "maxvCpus=128"
```

## Integration Examples

### Example 7: Adding to CI/CD Pipeline

To integrate the demo into a CI/CD pipeline:

```yaml
# .github/workflows/run-microbiome-demo.yml
name: Run Microbiome Demo

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  run-demo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Run setup
        run: |
          ./setup.sh microbiome-demo-${{ github.run_id }} us-east-1
          ./prepare_microbiome_data.sh
      
      - name: Deploy CloudFormation
        run: |
          aws cloudformation create-stack \
            --stack-name microbiome-demo-${{ github.run_id }} \
            --template-body file://cloudformation.yaml \
            --capabilities CAPABILITY_IAM \
            --parameters ParameterKey=DataBucketName,ParameterValue=microbiome-demo-${{ github.run_id }}
          
          aws cloudformation wait stack-create-complete --stack-name microbiome-demo-${{ github.run_id }}
      
      - name: Run test job
        run: ./test_demo.sh
      
      - name: Clean up
        if: always()
        run: |
          aws cloudformation delete-stack --stack-name microbiome-demo-${{ github.run_id }}
          aws s3 rb s3://microbiome-demo-${{ github.run_id }} --force
```

### Example 8: Exporting Results for Further Analysis

To export results for analysis in R or Python:

```bash
# Create a directory for the results
mkdir -p analysis_data

# Download taxonomic profiles
aws s3 cp s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/results/taxonomic/ analysis_data/taxonomic/ --recursive

# Download diversity metrics
aws s3 cp s3://$(grep BUCKET_NAME config.sh | cut -d'=' -f2)/results/diversity/ analysis_data/diversity/ --recursive

# Example R script for analysis
cat > analyze_results.R << 'EOF'
# Load libraries
library(phyloseq)
library(ggplot2)
library(vegan)

# Read taxonomic data
tax_data <- read.table("analysis_data/taxonomic/metaphlan_merged.tsv", 
                      header=TRUE, sep="\t", row.names=1)

# Read diversity data
div_data <- read.table("analysis_data/diversity/alpha_diversity.tsv",
                      header=TRUE, sep="\t")

# Create plots
pdf("microbiome_analysis_results.pdf", width=10, height=8)

# Alpha diversity boxplot by body site
ggplot(div_data, aes(x=body_site, y=shannon, fill=body_site)) +
  geom_boxplot() +
  theme_minimal() +
  labs(title="Shannon Diversity by Body Site", x="Body Site", y="Shannon Index")

# More analysis code...
dev.off()
EOF

# Run the R script
Rscript analyze_results.R
```

## Advanced Workflow Examples

### Example 9: Custom Analysis Steps

To add a custom analysis step to the Nextflow workflow:

```groovy
// Add this to workflow/microbiome_main.nf

// Define a new process for strain-level analysis
process strain_level_analysis {
    cpus 4
    memory '8 GB'
    tag { sample_id }
    
    input:
    tuple val(sample_id), val(body_site), path(kraken_output), path(kraken_report) from kraken_results
    
    output:
    tuple val(sample_id), path("${sample_id}.strains.txt") into strain_results
    
    script:
    """
    # Custom strain-level analysis with Bracken
    bracken -d ${params.kraken_db} \
            -i ${kraken_report} \
            -o ${sample_id}.strains.txt \
            -r 150 \
            -l S \
            -t ${task.cpus}
    """
}

// Add a merging process for the strain results
process merge_strain_results {
    cpus 2
    memory '4 GB'
    
    input:
    path('strains/*') from strain_results.map { it[1] }.collect()
    
    output:
    path('strain_summary.tsv') into strain_summary
    
    script:
    """
    # Combine strain results
    combine_bracken_outputs.py --files strains/* -o strain_summary.tsv
    """
}
```

### Example 10: AWS Batch Custom Job Definition

To create a custom job definition for specialized tasks:

```bash
# Create a job definition JSON
cat > job-definition.json << EOF
{
  "jobDefinitionName": "microbiome-specialized-job",
  "type": "container",
  "containerProperties": {
    "image": "public.ecr.aws/lts/microbiome-tools:latest",
    "vcpus": 8,
    "memory": 32768,
    "command": ["nextflow", "run", "main.nf"],
    "jobRoleArn": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/microbiome-demo-batch-job-role",
    "volumes": [
      {
        "host": {
          "sourcePath": "/tmp"
        },
        "name": "tmp"
      }
    ],
    "mountPoints": [
      {
        "containerPath": "/tmp",
        "readOnly": false,
        "sourceVolume": "tmp"
      }
    ],
    "environment": [
      {
        "name": "S3_BUCKET",
        "value": "$(grep BUCKET_NAME config.sh | cut -d'=' -f2)"
      }
    ]
  }
}
EOF

# Register the job definition
aws batch register-job-definition --cli-input-json file://job-definition.json
```

## Conclusion

These examples demonstrate the flexibility of the Microbiome Demo for various use cases. You can combine and adapt them to suit your specific research requirements. For more complex scenarios, refer to the [Customization Guide](customization.md) or consult the [Architecture Overview](architecture.md).