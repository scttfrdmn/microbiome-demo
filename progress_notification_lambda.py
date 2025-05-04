import json
import boto3
import os
import logging
import time
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to handle progress notifications from Nextflow workflow.
    
    This function is triggered by S3 events when progress files are updated.
    It processes the progress data and can send notifications or update dashboard data.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract bucket and key from the event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        
        logger.info(f"Processing update from {bucket}/{key}")
        
        # Only process progress.json updates
        if not key.endswith('progress.json'):
            logger.info(f"Skipping non-progress file: {key}")
            return {
                'statusCode': 200,
                'body': json.dumps('Skipped non-progress file')
            }
        
        # Get the workflow ID from the key
        # Expected format: progress/{workflow_id}/progress.json
        workflow_id = key.split('/')[1] if len(key.split('/')) >= 3 else 'unknown'
        
        # Download the progress file
        response = s3.get_object(Bucket=bucket, Key=key)
        progress_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Log progress information
        logger.info(f"Workflow {workflow_id} progress: {progress_data.get('percent_complete', 0)}% complete")
        logger.info(f"Status: {progress_data.get('status', 'unknown')}")
        logger.info(f"Elapsed time: {progress_data.get('elapsed_time_formatted', 'unknown')}")
        logger.info(f"Estimated remaining: {progress_data.get('estimated_remaining_formatted', 'unknown')}")
        
        # Prepare data for dashboard
        dashboard_data = {
            'timestamp': int(time.time()),
            'update_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'workflow_id': workflow_id,
            'percent_complete': progress_data.get('percent_complete', 0),
            'status': progress_data.get('status', 'unknown'),
            'elapsed_time': progress_data.get('elapsed_time_formatted', 'unknown'),
            'remaining_time': progress_data.get('estimated_remaining_formatted', 'unknown'),
            'processes': {
                'completed': progress_data.get('completed_count', 0),
                'total': progress_data.get('total_processes', 0)
            }
        }
        
        # Upload dashboard data for real-time display
        dashboard_key = f'dashboard/data/progress_{workflow_id}.json'
        s3.put_object(
            Bucket=bucket,
            Key=dashboard_key,
            Body=json.dumps(dashboard_data, indent=2),
            ContentType='application/json'
        )
        
        # Also update the latest progress file for the dashboard
        latest_key = 'dashboard/data/latest_progress.json'
        s3.put_object(
            Bucket=bucket,
            Key=latest_key,
            Body=json.dumps(dashboard_data, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Dashboard data updated at {dashboard_key} and {latest_key}")
        
        # If workflow completed, create a summary notification
        if progress_data.get('status') == 'completed':
            logger.info(f"Workflow {workflow_id} completed successfully!")
            
            # You could trigger additional actions here like:
            # - Send an SNS notification
            # - Update a DynamoDB table
            # - Trigger another Lambda function
        
        return {
            'statusCode': 200,
            'body': json.dumps('Progress update processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing progress update: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }