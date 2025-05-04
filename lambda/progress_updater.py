#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
#
# progress_updater.py - Lambda function for updating dashboard data with validation

import boto3
import json
import time
import logging
import os
import datetime
from typing import Dict, Any, List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize AWS clients
batch_client = boto3.client('batch')
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Get environment variables
DATA_BUCKET = os.environ.get('DATA_BUCKET', 'microbiome-demo-bucket')
DASHBOARD_BUCKET = os.environ.get('DASHBOARD_BUCKET', 'microbiome-demo-dashboard')
JOB_QUEUE = os.environ.get('JOB_QUEUE', 'microbiome-demo-queue')
PIPELINE_TABLE = os.environ.get('PIPELINE_TABLE', 'microbiome-demo-pipeline')

# Constants
VALID_STATUSES = ['SUBMITTED', 'RUNNING', 'SUCCEEDED', 'FAILED']
MAX_DEMO_RUNTIME_SECONDS = 15 * 60  # 15 minutes

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Handler for Lambda function to update dashboard data with validation
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Get current pipeline job status
        job_status, job_data = get_pipeline_job_status()
        
        # If we have a valid job, update the progress
        if job_status and job_data:
            # Update progress data with validation
            progress_data = generate_progress_data(job_status, job_data)
            
            # Save valid progress data
            save_progress_data(progress_data)
            
            # Update summary and resource data
            update_summary_data(job_status, job_data)
            update_resource_data(job_status, job_data)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Dashboard data updated successfully',
                    'job_status': job_status,
                    'progress': progress_data
                })
            }
        else:
            logger.warning("No active jobs found or unable to determine job status")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No active jobs found'
                })
            }
    
    except Exception as e:
        logger.error(f"Error updating dashboard data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': f'Error updating dashboard data: {str(e)}'
            })
        }

def get_pipeline_job_status() -> (str, Dict[str, Any]):
    """
    Get the status of the pipeline job from AWS Batch
    Returns a tuple of (status, job_data)
    """
    try:
        # List jobs in the queue
        response = batch_client.list_jobs(
            jobQueue=JOB_QUEUE,
            filters=[{'name': 'JOB_NAME', 'values': ['microbiome-demo-*']}]
        )
        
        # Get the most recent job
        jobs = sorted(response['jobSummaryList'], 
                     key=lambda x: x.get('createdAt', 0), 
                     reverse=True)
        
        if not jobs:
            # Check if we have a job in DynamoDB
            table = dynamodb.Table(PIPELINE_TABLE)
            response = table.scan(Limit=1)
            items = response.get('Items', [])
            
            if items:
                # Return the stored job status
                job_data = items[0]
                return job_data['status'], job_data
            
            return None, None
            
        # Get the most recent job
        job = jobs[0]
        job_id = job['jobId']
        
        # Get detailed job information
        detailed_job = batch_client.describe_jobs(jobs=[job_id])['jobs'][0]
        
        # Store job data in DynamoDB for persistence
        status = detailed_job['status']
        
        # Basic job data
        job_data = {
            'job_id': job_id,
            'status': status,
            'created_at': detailed_job.get('createdAt', 0),
            'started_at': detailed_job.get('startedAt', 0),
            'stopped_at': detailed_job.get('stoppedAt', 0)
        }
        
        # Update DynamoDB
        update_job_data_in_dynamodb(job_data)
        
        return status, job_data
        
    except Exception as e:
        logger.error(f"Error getting job status: {str(e)}")
        return None, None

def update_job_data_in_dynamodb(job_data: Dict[str, Any]) -> None:
    """
    Store job data in DynamoDB for persistence
    """
    try:
        table = dynamodb.Table(PIPELINE_TABLE)
        
        # Add timestamp for the record
        job_data['updated_at'] = int(time.time() * 1000)
        
        # Put item in DynamoDB
        table.put_item(Item=job_data)
        
    except Exception as e:
        logger.error(f"Error updating DynamoDB: {str(e)}")

def generate_progress_data(job_status: str, job_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate validated progress data based on job status
    """
    # Get the total sample count
    total_samples = 100  # Default for demo
    
    # Calculate actual elapsed time
    now = int(time.time() * 1000)
    started_at = job_data.get('started_at', job_data.get('created_at', now))
    stopped_at = job_data.get('stopped_at', 0)
    
    if stopped_at > 0 and job_status in ['SUCCEEDED', 'FAILED']:
        elapsed_ms = stopped_at - started_at
    else:
        elapsed_ms = now - started_at
    
    # Convert to seconds and cap at max demo runtime
    elapsed_seconds = min(elapsed_ms // 1000, MAX_DEMO_RUNTIME_SECONDS)
    
    # Calculate progress based on elapsed time
    progress_percentage = min(100, (elapsed_seconds / MAX_DEMO_RUNTIME_SECONDS) * 100)
    completed_samples = min(total_samples, int((progress_percentage / 100) * total_samples))
    
    # Determine running samples based on status
    if job_status == 'SUCCEEDED':
        running_samples = 0
        pending_samples = 0
        failed_samples = 0
        completed_samples = total_samples
        status = "COMPLETED"
    elif job_status == 'FAILED':
        # Some samples failed
        running_samples = 0
        pending_samples = 0
        failed_samples = total_samples - completed_samples
        status = "FAILED"
    elif job_status == 'RUNNING':
        # Calculate reasonable values for running/pending
        running_samples = min(10, total_samples - completed_samples)
        pending_samples = total_samples - completed_samples - running_samples
        failed_samples = 0
        status = "RUNNING"
    else:  # SUBMITTED or any other state
        running_samples = 0
        pending_samples = total_samples
        failed_samples = 0
        completed_samples = 0
        status = "SUBMITTED"
    
    # Validate that the counts add up to total_samples
    if completed_samples + running_samples + pending_samples + failed_samples != total_samples:
        logger.warning("Sample counts don't add up to total, adjusting...")
        # Adjust pending samples to make counts add up
        pending_samples = total_samples - completed_samples - running_samples - failed_samples
    
    # Create progress data structure
    progress_data = {
        "status": status,
        "time_elapsed": elapsed_seconds,
        "completed_samples": completed_samples,
        "total_samples": total_samples,
        "sample_status": {
            "completed": completed_samples,
            "running": running_samples,
            "pending": pending_samples,
            "failed": failed_samples
        },
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "job_id": job_data['job_id']
    }
    
    # Validate the progress data
    validate_progress_data(progress_data)
    
    return progress_data

def validate_progress_data(data: Dict[str, Any]) -> None:
    """
    Validate progress data structure and values
    Raises ValueError if validation fails
    """
    # Check required fields
    required_fields = ["status", "time_elapsed", "completed_samples", 
                     "total_samples", "sample_status", "timestamp", "job_id"]
    
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")
    
    # Check status validity
    valid_statuses = ["SUBMITTED", "RUNNING", "COMPLETED", "FAILED"]
    if data["status"] not in valid_statuses:
        raise ValueError(f"Invalid status: {data['status']}")
    
    # Check consistency between status and counts
    status = data["status"]
    sample_status = data["sample_status"]
    
    if status == "COMPLETED" and sample_status["running"] > 0:
        # Fix the inconsistency
        logger.warning("Fixing inconsistency: COMPLETED status with running samples")
        sample_status["running"] = 0
        
    if status == "COMPLETED" and sample_status["pending"] > 0:
        # Fix the inconsistency
        logger.warning("Fixing inconsistency: COMPLETED status with pending samples")
        sample_status["pending"] = 0
    
    # Ensure counts add up to total
    total = data["total_samples"]
    count_sum = (sample_status["completed"] + sample_status["running"] + 
                sample_status["pending"] + sample_status["failed"])
    
    if count_sum != total:
        raise ValueError(f"Sample counts ({count_sum}) don't match total ({total})")
    
    # Check that time elapsed is reasonable
    if data["time_elapsed"] < 0 or data["time_elapsed"] > MAX_DEMO_RUNTIME_SECONDS:
        raise ValueError(f"Invalid time_elapsed: {data['time_elapsed']}")

def save_progress_data(progress_data: Dict[str, Any]) -> None:
    """
    Save progress data to S3 buckets
    """
    try:
        # Convert to JSON
        progress_json = json.dumps(progress_data, indent=2)
        
        # Save to data bucket for pipeline history
        s3_client.put_object(
            Bucket=DATA_BUCKET,
            Key=f"status/progress.json",
            Body=progress_json,
            ContentType='application/json'
        )
        
        # Save to dashboard bucket for display
        s3_client.put_object(
            Bucket=DASHBOARD_BUCKET,
            Key="data/progress.json",
            Body=progress_json,
            ContentType='application/json'
        )
        
        logger.info("Progress data saved successfully")
        
    except Exception as e:
        logger.error(f"Error saving progress data: {str(e)}")
        raise

def update_summary_data(job_status: str, job_data: Dict[str, Any]) -> None:
    """
    Update or generate summary data based on job status
    """
    try:
        # For simplicity in the demo, we'll use pre-generated data
        # but simulate gradual population of results
        
        # Try to get existing summary data from S3
        try:
            response = s3_client.get_object(
                Bucket=DATA_BUCKET,
                Key="results/summary/microbiome_summary.json"
            )
            summary_data = json.loads(response['Body'].read().decode('utf-8'))
        except:
            # Use example data if real data isn't available
            summary_data = generate_example_summary(job_status, job_data)
        
        # Validate summary data
        validate_summary_data(summary_data)
        
        # Save summary data to dashboard bucket
        s3_client.put_object(
            Bucket=DASHBOARD_BUCKET,
            Key="data/summary.json",
            Body=json.dumps(summary_data, indent=2),
            ContentType='application/json'
        )
        
        logger.info("Summary data updated successfully")
        
    except Exception as e:
        logger.error(f"Error updating summary data: {str(e)}")

def generate_example_summary(job_status: str, job_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate example summary data for testing
    """
    # In a real implementation, this would read data from the pipeline outputs
    # For the demo, we'll create a realistic dataset
    
    # Calculate progress percentage based on job data
    now = int(time.time() * 1000)
    started_at = job_data.get('started_at', job_data.get('created_at', now))
    elapsed_ms = now - started_at
    progress_percentage = min(100, (elapsed_ms / 1000 / MAX_DEMO_RUNTIME_SECONDS) * 100)
    
    # Basic taxonomy data
    phyla = [
        {"name": "Bacteroidetes", "abundance": 0.4532},
        {"name": "Firmicutes", "abundance": 0.3871},
        {"name": "Proteobacteria", "abundance": 0.0823},
        {"name": "Actinobacteria", "abundance": 0.0421},
        {"name": "Verrucomicrobia", "abundance": 0.0156},
        {"name": "Euryarchaeota", "abundance": 0.0087},
        {"name": "Fusobacteria", "abundance": 0.0065},
        {"name": "Other", "abundance": 0.0045}
    ]
    
    # Adjust abundances based on progress
    if progress_percentage < 50:
        # Gradually make data more complete as pipeline progresses
        for phylum in phyla:
            phylum["abundance"] *= (progress_percentage / 100)
    
    # Create taxonomy structure
    taxonomic_profile = {
        "sample_count": 100,
        "species_count": 3524,
        "phylum_distribution": phyla
    }
    
    # Create the full summary structure
    summary = {
        "taxonomic_profile": taxonomic_profile,
        "functional_profile": {
            "pathway_count": 897,
            "top_pathways": []
        },
        "diversity": {
            "alpha": {
                "shannon": {
                    "mean": 4.8623,
                    "std": 0.5421,
                    "min": 3.8754,
                    "max": 5.9821
                }
            },
            "beta": {},
            "by_site": {
                "stool": {},
                "buccal_mucosa": {},
                "anterior_nares": {}
            }
        },
        "execution_metrics": {
            "cpu_hours": 12.5 * (progress_percentage / 100),
            "gpu_hours": 2.3 * (progress_percentage / 100),
            "wall_clock_minutes": (progress_percentage / 100) * 15,
            "samples_processed": int((progress_percentage / 100) * 100),
            "data_processed_gb": 52.7 * (progress_percentage / 100)
        },
        "cost_analysis": {
            "on_premises_cost": 1800.00,
            "standard_cloud_cost": 120.00,
            "optimized_aws_cost": 38.50,
            "cost_savings_percent": 97.9
        }
    }
    
    return summary

def validate_summary_data(data: Dict[str, Any]) -> None:
    """
    Validate summary data structure and values
    Raises ValueError if validation fails
    """
    # Check required sections
    required_sections = ["taxonomic_profile", "functional_profile", 
                        "diversity", "execution_metrics"]
    
    for section in required_sections:
        if section not in data:
            raise ValueError(f"Missing required section: {section}")
    
    # Validate taxonomic profile
    taxonomic_profile = data["taxonomic_profile"]
    if "phylum_distribution" not in taxonomic_profile:
        raise ValueError("Missing phylum_distribution in taxonomic_profile")
    
    # Check that phylum abundances sum to approximately 1.0
    phyla = taxonomic_profile["phylum_distribution"]
    total_abundance = sum(p["abundance"] for p in phyla)
    if not (0.9 <= total_abundance <= 1.1):  # Allow some rounding error
        logger.warning(f"Phylum abundances sum to {total_abundance}, not ~1.0")
        
        # Normalize abundances to sum to 1.0
        for phylum in phyla:
            phylum["abundance"] = phylum["abundance"] / total_abundance
    
    # Validate execution metrics
    execution_metrics = data["execution_metrics"]
    required_metrics = ["cpu_hours", "gpu_hours", "wall_clock_minutes", 
                        "samples_processed", "data_processed_gb"]
    
    for metric in required_metrics:
        if metric not in execution_metrics:
            raise ValueError(f"Missing required metric: {metric}")
        
        # Check metric types
        if not isinstance(execution_metrics[metric], (int, float)):
            raise ValueError(f"Metric {metric} must be a number")

def update_resource_data(job_status: str, job_data: Dict[str, Any]) -> None:
    """
    Update resource utilization data
    """
    try:
        # Try to get existing resource data
        try:
            response = s3_client.get_object(
                Bucket=DASHBOARD_BUCKET,
                Key="data/resources.json"
            )
            resource_data = json.loads(response['Body'].read().decode('utf-8'))
            utilization = resource_data.get("utilization", [])
        except:
            # Start with empty utilization
            utilization = []
        
        # Calculate elapsed time in minutes
        now = int(time.time() * 1000)
        started_at = job_data.get('started_at', job_data.get('created_at', now))
        elapsed_minutes = (now - started_at) // 60000
        
        # Generate a new data point if the job is running
        if job_status in ['RUNNING', 'SUCCEEDED']:
            # Create realistic resource usage that varies over time
            time_point = len(utilization)
            
            # Calculate wave patterns for CPU and memory
            from math import sin, cos
            cpu_base = 50 + 20 * sin(time_point / 5)
            memory_base = 70 + 10 * cos(time_point / 7)
            
            # GPU usage starts later in the pipeline
            gpu_usage = 0
            if elapsed_minutes >= 3:  # GPU kicks in at 3 minutes
                gpu_usage = 40 + 15 * sin(time_point / 4)
            
            # Create new data point
            new_point = {
                "time": time_point,
                "cpu": round(cpu_base, 1),
                "memory": round(memory_base, 1),
                "gpu": round(gpu_usage, 1)
            }
            
            # Add to utilization array
            utilization.append(new_point)
            
            # Keep only the last 10 points for display
            if len(utilization) > 10:
                utilization = utilization[-10:]
        
        # Update the resource data
        updated_resource_data = {
            "utilization": utilization,
            "instances": {
                "cpu": 8,
                "gpu": 2
            },
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
        }
        
        # Validate resource data
        validate_resource_data(updated_resource_data)
        
        # Save to dashboard bucket
        s3_client.put_object(
            Bucket=DASHBOARD_BUCKET,
            Key="data/resources.json",
            Body=json.dumps(updated_resource_data, indent=2),
            ContentType='application/json'
        )
        
        # Also save to data bucket
        s3_client.put_object(
            Bucket=DATA_BUCKET,
            Key="monitoring/resources.json",
            Body=json.dumps(updated_resource_data, indent=2),
            ContentType='application/json'
        )
        
        logger.info("Resource data updated successfully")
        
    except Exception as e:
        logger.error(f"Error updating resource data: {str(e)}")

def validate_resource_data(data: Dict[str, Any]) -> None:
    """
    Validate resource utilization data
    Raises ValueError if validation fails
    """
    # Check required fields
    if "utilization" not in data:
        raise ValueError("Missing required field: utilization")
    
    if "instances" not in data:
        raise ValueError("Missing required field: instances")
    
    if "timestamp" not in data:
        raise ValueError("Missing required field: timestamp")
    
    # Validate utilization entries
    for point in data["utilization"]:
        required_metrics = ["time", "cpu", "memory", "gpu"]
        for metric in required_metrics:
            if metric not in point:
                raise ValueError(f"Missing metric in utilization point: {metric}")
        
        # Check ranges
        if not (0 <= point["cpu"] <= 100):
            raise ValueError(f"CPU utilization out of range: {point['cpu']}")
        
        if not (0 <= point["memory"] <= 100):
            raise ValueError(f"Memory utilization out of range: {point['memory']}")
        
        if not (0 <= point["gpu"] <= 100):
            raise ValueError(f"GPU utilization out of range: {point['gpu']}")

if __name__ == "__main__":
    # For local testing
    print("Testing lambda function locally")
    result = lambda_handler({}, None)
    print(json.dumps(result, indent=2))