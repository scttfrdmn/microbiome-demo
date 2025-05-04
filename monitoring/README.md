# Monitoring and Alerting for Microbiome Demo

This directory contains resources for monitoring the Microbiome Demo infrastructure and pipeline performance.

## Components

1. **CloudWatch Alarms** - Predefined alarms for infrastructure health
2. **Custom Metrics** - Pipeline-specific performance metrics
3. **Health Checks** - Script to verify system health
4. **Budget Monitoring** - Cost controls and alerts

## Setup

### 1. Deploy CloudWatch Alarms

```bash
# Deploy the CloudWatch alarms
aws cloudformation create-stack \
  --stack-name microbiome-monitoring \
  --template-body file://monitoring/cloudwatch-alarms.yaml \
  --parameters \
    ParameterKey=StackName,ParameterValue=microbiome-demo \
    ParameterKey=BucketName,ParameterValue=your-bucket-name \
    ParameterKey=AlertEmail,ParameterValue=your-email@example.com \
    ParameterKey=MaxSpendLimit,ParameterValue=50
```

### 2. Schedule Custom Metrics Collection

```bash
# Create an EventBridge rule to run custom-metrics.sh every 15 minutes
aws events put-rule \
  --name MicrobiomeDemoMetricsCollection \
  --schedule-expression "rate(15 minutes)"

# Set up the Lambda function for metrics collection (requires additional setup)
# Alternatively, run the script manually or via a cron job
```

### 3. Set Up Budget Alerts

```bash
# Create a AWS Budget with alerts
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://monitoring/budget.json \
  --notifications-with-subscribers file://monitoring/notifications.json
```

## Manual Health Check

To perform a manual health check of the infrastructure:

```bash
./monitoring/health-check.sh
```

This will check:
- CloudFormation stack status
- S3 bucket and required files
- AWS Batch compute environments and job queues
- Lambda function status

## Monitoring Dashboard

After deploying the CloudWatch alarms, a monitoring dashboard is created that provides visibility into:

1. **Resource Utilization**
   - CPU and memory usage for Batch jobs
   - GPU utilization
   
2. **Job Status**
   - Running, pending, and submitted jobs
   - Job success rate
   
3. **Pipeline Performance**
   - Samples processed per minute
   - Species identified
   - Diversity metrics
   
4. **Cost Monitoring**
   - Current AWS charges
   - Projected monthly cost
   - Cost per sample

You can access the dashboard at:
`https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name=microbiome-demo-monitoring`

## Custom Metrics

The `custom-metrics.sh` script publishes several pipeline-specific metrics:

### Taxonomic Analysis
- Species count
- Shannon diversity index

### Performance
- Samples processed per minute
- Wall clock time
- CPU/GPU hours consumed

### Cost
- Cost per sample
- Total demo cost

## Alerts

The following alerts are configured by default:

1. **Budget Alerts**
   - 80% of monthly budget consumed
   - Forecasted to exceed budget
   
2. **Resource Alerts**
   - High CPU utilization (>80%)
   - High memory utilization (>80%)
   - S3 bucket exceeds 50GB
   
3. **Error Alerts**
   - Lambda function errors
   - AWS Batch job failures

Alerts are sent to the email address specified during setup.