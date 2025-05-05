# Microbiome Pipeline Solution Documentation

## Overview

This document describes the solution for fixing the microbiome analysis pipeline that was experiencing consistent failures and dashboard issues. Two main components were repaired:

1. Dashboard error handling and display
2. Pipeline job submission and execution

## Problem Summary

The pipeline was failing to run successfully due to the following issues:

1. **Lambda Function Issues:**
   - Lambda was overriding the job definition's command with its own command parameters
   - The override command was trying to directly run `nextflow` without installing it first
   - Pipeline jobs consistently failed with "nextflow: executable file not found in $PATH" errors

2. **Dashboard Issues:**
   - Dashboard would cycle between "Status: FAILED" and "Loading Pipeline"
   - Division by zero errors in update_data.sh script caused JSON corruption
   - Error handling was insufficient in data processing scripts

## Solution Implementation

### 1. Lambda Function Fix

The core issue was identified in the Lambda function code, which was overriding the job definition's command with its own direct `nextflow run` command, expecting Nextflow to be already installed.

**Original Lambda Code (Problematic):**
```python
response = batch.submit_job(
    jobName='microbiome-demo-{}'.format(int(time.time())),
    jobQueue=job_queue,
    jobDefinition=job_definition,
    containerOverrides={
        'command': [
            'nextflow',
            'run',
            'workflow/microbiome_main.nf',
            '-profile',
            'aws',
            '--samples',
            's3://{}/input/sample_list.csv'.format(data_bucket),
            '--output',
            's3://{}/results'.format(data_bucket),
            '--bucket_name',
            '{}'.format(data_bucket)
        ]
    }
)
```

**Fixed Lambda Code:**
```python
# Create environment variables for sample count and processing time
job_env = [
    {'name': 'SAMPLE_COUNT', 'value': str(samples)},
    {'name': 'PROCESSING_TIME', 'value': str(processing_time)},
    {'name': 'DATA_BUCKET', 'value': data_bucket}
]

response = batch.submit_job(
    jobName='microbiome-demo-{}'.format(int(time.time())),
    jobQueue=job_queue,
    jobDefinition=job_definition,
    containerOverrides={
        'environment': job_env
    }
)
```

Key changes:
1. Removed command override
2. Passed parameters as environment variables
3. Let job definition's command handle Nextflow installation and execution
4. Added proper progress.json initialization

### 2. Dashboard Error Handling Improvements

Fixed the division-by-zero and error handling issues in the dashboard data processing:

1. In `update_data.sh`:
   ```bash
   # Prevent division by zero by checking COMPLETED_SAMPLES first
   if [ "$COMPLETED_SAMPLES" -eq 0 ]; then
     per_sample="0.025" # Default value if no samples completed
   else
     per_sample=$(printf "%.3f" $(echo "scale=3; $current_cost / $COMPLETED_SAMPLES" | bc -l 2>/dev/null || echo "0.025"))
   fi
   ```

2. Added JSON validation before processing:
   ```bash
   # Ensure sum is not zero to prevent division by zero
   if (( $(echo "$sum <= 0.01" | bc -l) )); then
     # If sum is too small, set default values
     bacteroidetes="0.35"
     firmicutes="0.30"
     ...
   ```

3. Improved error handling for bc calculations:
   ```bash
   if [[ ! "$new_cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
     new_cpu=70 # Default if calculation failed
   else
     new_cpu=$(echo "$new_cpu < 40 ? 40 : ($new_cpu > 95 ? 95 : $new_cpu)" | bc -l 2>/dev/null || echo 70)
   fi
   ```

4. Added specific handling for the FAILED status in copy_data_to_dashboard.sh:
   ```bash
   if [ "$STATUS" = "INITIALIZING" ] || [ "$STATUS" = "FAILED" ]; then
     # We treat FAILED like INITIALIZING for data setup, but keep the FAILED status
     # This prevents cycling between FAILED and loading pipeline by providing valid
     # empty chart data structures
     ...
   ```

## Testing Verification

The solution was verified with multiple tests:

1. Pipeline successfully runs with different sample counts (10, 25, 35)
2. Jobs transition correctly from SUBMITTED to RUNNING state
3. Progress.json is properly updated with the correct status
4. Dashboard correctly displays the pipeline status without cycling

## Conclusion

The root cause of the pipeline failures was identified and fixed. The Lambda function no longer overrides the job definition's command, allowing the containerized job to properly install Nextflow before running it. Additionally, the dashboard error handling improvements prevent division by zero errors and ensure proper handling of the FAILED state to prevent cycling.

These changes allow the pipeline to successfully start, run, and complete with different sample counts and processing times, while providing real-time status updates to the dashboard.