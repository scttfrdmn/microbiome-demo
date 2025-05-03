# Microbiome Demo Documentation

This documentation provides detailed information about the 15-minute Microbiome Demo on AWS.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation Guide](#installation-guide)
4. [Usage Guide](#usage-guide)
5. [Technical Details](#technical-details)
6. [Troubleshooting](#troubleshooting)
7. [Development Guide](#development-guide)
8. [FAQ](#faq)

## Overview

The Microbiome Demo showcases how AWS cloud resources can dramatically accelerate microbiome research while optimizing costs. The demo processes 100 metagenomic samples from the Human Microbiome Project in parallel, performing:

- Taxonomic classification with GPU-accelerated Kraken2
- Functional profiling with MetaPhlAn and HUMAnN
- Diversity analysis across different body sites
- Cost comparisons between on-premises and optimized cloud approaches

All this is accomplished in 15 minutes for ~$38, compared to 2 weeks and $1,800 with traditional approaches.

## Architecture

### System Components

1. **Nextflow Pipeline**: Manages the workflow execution
2. **AWS Batch**: Handles compute resources
   - CPU Instances: c7g family (ARM-based Graviton3)
   - GPU Instances: g5g family (ARM-based GPU instances)
3. **S3**: Stores input data, reference databases, and results
4. **Lambda**: Orchestrates the workflow
5. **CloudWatch**: Monitors and logs execution
6. **Dashboard**: Visualizes progress and results in real-time

### Architecture Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   S3 Bucket │     │AWS Batch CPU│     │ CloudWatch  │
│  (Storage)  │◄────┤  Compute    │────►│ (Monitoring)│
└─────────────┘     └─────────────┘     └─────────────┘
       ▲                   ▲                   ▲
       │                   │                   │
       ▼                   │                   │
┌─────────────┐            │                   │
│   Lambda    │────────────┘                   │
│(Orchestrator)│                               │
└─────────────┘                               │
       ▲                                      │
       │                                      │
       ▼                                      │
┌─────────────┐            ┌─────────────┐    │
│    S3 Web   │◄───────────┤ AWS Batch   │    │
│  Dashboard  │            │ GPU Compute │────┘
└─────────────┘            └─────────────┘
```

## Installation Guide

### Prerequisites

- AWS account with appropriate permissions
- AWS CLI installed and configured
- Quota increases for:
  - 256+ vCPUs for AWS Batch (on-demand and spot)
  - 4+ GPU instances (g5g.2xlarge) in your region
- Git
- Bash shell environment

### Setup Process

1. Clone the repository:
   ```
   git clone https://github.com/your-username/microbiome-demo.git
   cd microbiome-demo
   ```

2. Run the initial setup script:
   ```
   ./setup.sh your-unique-bucket-name your-aws-region
   ```

3. Prepare the microbiome data:
   ```
   ./prepare_microbiome_data.sh
   ```

4. Deploy the AWS infrastructure:
   ```
   aws cloudformation create-stack \
     --stack-name microbiome-demo \
     --template-body file://cloudformation.yaml \
     --capabilities CAPABILITY_IAM \
     --parameters ParameterKey=DataBucketName,ParameterValue=your-unique-bucket-name
   ```

5. Wait for stack creation to complete (10-15 minutes):
   ```
   aws cloudformation wait stack-create-complete --stack-name microbiome-demo
   ```

6. Verify resources are properly configured:
   ```
   ./check_resources.sh
   ```

For more detailed information, check the [installation troubleshooting guide](../TROUBLESHOOTING.md).

## Usage Guide

### Running the Demo

1. Run a test job to ensure everything works:
   ```
   ./test_demo.sh
   ```

2. When ready for your presentation, start the demo:
   ```
   ./start_demo.sh
   ```

3. Open the dashboard URL printed by the start_demo.sh script to monitor progress.

4. If you encounter issues during the demo, reset it:
   ```
   ./reset_demo.sh
   ```

### Accessing Results

The analysis results are stored in the S3 bucket specified during setup:

- Taxonomic classification: `s3://your-bucket-name/results/taxonomic/`
- Functional profiling: `s3://your-bucket-name/results/functional/`
- Diversity analysis: `s3://your-bucket-name/results/diversity/`
- Summary: `s3://your-bucket-name/results/summary/`

### Cleaning Up

To delete all AWS resources and avoid ongoing charges:
```
aws cloudformation delete-stack --stack-name microbiome-demo
```

## Technical Details

### Nextflow Workflow

The main workflow file is `workflow/microbiome_main.nf` which defines the following processes:

1. `preprocess_reads`: Quality control and adapter trimming
2. `taxonomic_classification_kraken`: GPU-accelerated species identification
3. `kraken_reports`: Generate taxonomic summary reports
4. `metaphlan_analysis`: Marker gene-based profiling
5. `merge_metaphlan`: Combine MetaPhlAn results
6. `merge_humann`: Analyze functional profiles
7. `diversity_analysis`: Calculate alpha and beta diversity
8. `create_summary`: Generate dashboard visualizations
9. `upload_results`: Upload results to S3
10. `generate_cost_report`: Calculate cost savings

### AWS Resources

The CloudFormation template creates the following resources:

- VPC with public and private subnets
- Security groups for AWS Batch
- IAM roles for Batch, Lambda, and EC2 instances
- S3 bucket for data storage
- AWS Batch compute environments for CPU and GPU
- AWS Batch job queues and job definitions
- Lambda function for orchestration
- CloudWatch dashboard for monitoring

### Dashboard

The dashboard is built with:

- React for UI components
- Recharts for data visualization
- AWS SDK for JavaScript to interact with AWS services

## Troubleshooting

See the [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) file for common issues and solutions.

## Development Guide

### Project Structure

```
microbiome-demo/
├── cloudformation.yaml          # AWS infrastructure definition
├── config.sh                     # Configuration settings
├── dashboard/                    # Web UI
│   ├── css/                      # Styles
│   ├── index.html                # Main HTML page
│   └── js/                       # JavaScript files
├── prepare_microbiome_data.sh    # Data preparation script
├── README.md                     # Main documentation
├── setup.sh                      # Initial setup script
├── start_demo.sh                 # Demo launcher
├── test_demo.sh                  # Testing script
├── TROUBLESHOOTING.md            # Troubleshooting guide
└── workflow/                     # Nextflow workflow
    ├── microbiome_main.nf        # Main workflow definition
    ├── microbiome_nextflow.config # Nextflow configuration
    └── templates/                # Script templates
        ├── batch_init.sh         # Batch initialization
        └── cost_report.py        # Cost calculation
```

### Validation Scripts

The project includes several validation scripts:

- `validate_all.sh`: Runs all validation scripts
- `lint_nextflow.sh`: Validates Nextflow files
- `validate_cf.sh`: Checks CloudFormation template
- `lint_scripts.sh`: Lints shell scripts
- `validate_aws_resources.sh`: Checks AWS resources
- `lint_dashboard.sh`: Validates JavaScript code
- `run_tests.sh`: Runs unit tests

### Adding New Features

To add new features to the pipeline:

1. Modify the Nextflow workflow in `workflow/microbiome_main.nf`
2. Update the dashboard in `dashboard/js/microbiome_dashboard.js`
3. Run validation scripts to ensure your changes are valid
4. Test the changes with `./test_demo.sh`
5. Create a pull request with your changes

## FAQ

### How much does it cost to run the demo?

The demo costs approximately $38 for a complete run of 100 samples. This includes:
- Compute costs (AWS Batch)
- Storage costs (S3)
- Data transfer costs

### How long does the demo take to run?

The demo is designed to complete in 15 minutes.

### What metagenomic samples are used?

The demo uses 100 samples from the Human Microbiome Project, covering different body sites including gut (stool), oral (buccal mucosa), and nasal (anterior nares) microbiomes.

### What reference databases are used?

- Kraken2 standard database for taxonomic classification
- MetaPhlAn database for marker gene-based profiling
- HUMAnN database for functional profiling

### Can I customize the demo?

Yes, you can modify the demo by:
- Changing the number of samples in `config.sh`
- Using different reference databases
- Adding new analysis processes to the Nextflow workflow
- Customizing the dashboard visualization

### What if I need more than 15 minutes for my demo?

You can adjust the runtime by modifying the `DEMO_DURATION_MINUTES` parameter in `config.sh`.