# Getting Started with the Microbiome Demo

This guide will help you set up and run the Microbiome Demo, a system that demonstrates accelerated microbiome analysis on AWS.

## Prerequisites

Before starting, ensure you have:

1. **AWS Account** with permissions to:
   - Create CloudFormation stacks
   - Create IAM roles
   - Create and manage S3 buckets
   - Launch AWS Batch compute environments

2. **Local Environment**:
   - AWS CLI installed and configured
   - Git client
   - Bash shell

3. **AWS Quotas**:
   - 256+ vCPUs for AWS Batch (on-demand and spot)
   - 4+ GPU instances (g5g.2xlarge) in your region

## Setup Process

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-username/microbiome-demo.git
cd microbiome-demo
```

### Step 2: Run the Initial Setup

The setup script configures your environment and creates the necessary S3 bucket:

```bash
./setup.sh your-unique-bucket-name your-aws-region
```

For example:
```bash
./setup.sh microbiome-demo-bucket-123 us-east-1
```

This will:
- Create an S3 bucket with the specified name
- Configure versioning on the bucket
- Create a `config.sh` file with your settings

### Step 3: Prepare the Microbiome Data

Next, prepare the sample data and reference information:

```bash
./prepare_microbiome_data.sh
```

This script:
- Selects 100 metagenomic samples from the Human Microbiome Project
- Creates manifests and metadata files in your S3 bucket
- Prepares scripts for downloading reference databases

### Step 4: Deploy AWS Infrastructure

Deploy the CloudFormation stack to create all required AWS resources:

```bash
aws cloudformation create-stack \
  --stack-name microbiome-demo \
  --template-body file://cloudformation.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=DataBucketName,ParameterValue=your-unique-bucket-name
```

Wait for the stack creation to complete:

```bash
aws cloudformation wait stack-create-complete --stack-name microbiome-demo
```

### Step 5: Verify Resources

Verify that all resources were created correctly:

```bash
./check_resources.sh
```

This checks:
- S3 bucket accessibility
- AWS Batch compute environments and job queues
- IAM roles and permissions
- Lambda function

### Step 6: Run a Test Job

Before running the full demo, run a test job with a smaller dataset:

```bash
./test_demo.sh
```

This will process 5 samples to verify that everything is working correctly.

## Running the Demo

When you're ready to run the full demo:

```bash
./start_demo.sh
```

This will:
1. Invoke the orchestrator Lambda function
2. Begin processing all 100 samples in parallel
3. Display a dashboard URL for monitoring progress

## Monitoring Progress

Open the dashboard URL printed by the `start_demo.sh` script to monitor the demo's progress. The dashboard shows:

- Overall progress and time remaining
- CPU and GPU utilization
- Cost accrual
- Pipeline step completion status
- Real-time results visualization (as available)

## Common Issues

- **"No such bucket" error**: Ensure your bucket name is globally unique
- **GPU instance quota**: Check your AWS service quotas for g5g instances
- **"Role not found" error**: The CloudFormation stack may not have completed creating all resources

For more troubleshooting help, see the [Troubleshooting Guide](../../TROUBLESHOOTING.md).

## What's Next?

Once the demo is running successfully:

- Explore the [Architecture Overview](architecture.md) to understand how it works
- Check the [Cost Optimization Guide](cost-optimization.md) to understand the savings
- Learn how to [Customize the Analysis](customization.md) for your own data

## Cleanup

To avoid ongoing charges, delete all AWS resources when you're done:

```bash
aws cloudformation delete-stack --stack-name microbiome-demo
aws s3 rb s3://your-unique-bucket-name --force
```