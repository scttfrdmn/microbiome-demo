# Troubleshooting Guide

This document provides solutions for common issues you might encounter when running the Microbiome Demo.

## Setup Issues

### Wrong stack name

**Symptom:** Error message about resources not being found when running `start_demo.sh` or other scripts.

**Solution:** Ensure the stack name in your `config.sh` matches the name you used when creating the CloudFormation stack. By default, this should be `microbiome-demo`.

### Missing or inaccessible S3 bucket

**Symptom:** Error messages about S3 bucket not found or access denied.

**Solution:**
1. Verify the bucket exists: `aws s3 ls s3://your-bucket-name`
2. Check your AWS CLI configuration: `aws sts get-caller-identity`
3. Run `setup.sh` again with the correct bucket name

## Dashboard Issues

### Dashboard doesn't load

**Symptom:** You see a blank screen when accessing the dashboard URL.

**Solution:**
1. Verify your CloudFormation stack has completed successfully
2. Check browser console for any JavaScript errors - the dashboard requires React and Recharts libraries
3. Make sure the browser can access the S3 bucket that hosts the dashboard

### Dashboard shows wrong data

**Symptom:** Dashboard shows incorrect or outdated information.

**Solution:**
1. Clear your browser cache
2. Verify the dashboard is pointing to the correct S3 bucket

## Nextflow Pipeline Issues

### Pipeline fails to start

**Symptom:** Errors when trying to run the Nextflow pipeline.

**Solution:**
1. Verify AWS Batch compute environments are active
2. Check that the job queues are in ENABLED state
3. Ensure the Docker container exists and is accessible

### Missing reference data

**Symptom:** Pipeline fails with errors about missing reference databases.

**Solution:**
1. Run `prepare_microbiome_data.sh` to properly set up reference data
2. Verify reference databases were correctly uploaded to S3
3. Check your `workflow/microbiome_nextflow.config` for correct reference paths

## AWS Batch Issues

### Insufficient resources

**Symptom:** Jobs queue but don't start running or fail with resource errors.

**Solution:**
1. Check your AWS service quotas, especially for EC2 and GPU instances
2. Request quota increases if needed in the AWS console
3. Consider modifying the Nextflow config to use smaller instances

### GPU acceleration not working

**Symptom:** Jobs run but take much longer than expected, especially taxonomic classification.

**Solution:**
1. Verify your AWS Batch GPU compute environment is properly configured
2. Check that the Kraken2 container properly supports GPU acceleration
3. Inspect the job logs for any GPU-related errors

## Cost Monitoring

**Recommendation:** Set up budget alerts in AWS to monitor costs if you're concerned about exceeding your budget.

```
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

## Need More Help?

If you're still experiencing issues after trying these troubleshooting steps, please:

1. Check the AWS Batch and CloudWatch logs for detailed error messages
2. Open an issue in the project repository with detailed information about your issue
3. Include the output of `./check_resources.sh` in your issue report