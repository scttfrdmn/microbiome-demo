import json
import boto3
import os
import time

s3 = boto3.client('s3')
batch = boto3.client('batch')

def lambda_handler(event, context):
    print("Received event: {}".format(json.dumps(event)))
    
    # Get environment variables
    data_bucket = os.environ['DATA_BUCKET']
    job_queue = os.environ['JOB_QUEUE']
    job_definition = os.environ['JOB_DEFINITION']
    
    # Get parameters from event
    action = event.get('action', 'test')
    samples = event.get('samples', 100)
    processing_time = event.get('processingTime', 15)
    
    if action == 'test':
        # Just create a test file
        response = s3.put_object(
            Bucket=data_bucket,
            Key='results/test_result.txt',
            Body='This is a test result file created by Lambda: {}'.format(time.time())
        )
        
        print(f"Created test file in S3")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Test file created in S3',
                'timestamp': time.time()
            })
        }
    elif action == 'start_demo':
        # Create a status file to initialize the dashboard
        init_status = {
            'status': 'SUBMITTED',
            'time_elapsed': 0,
            'completed_samples': 0,
            'total_samples': samples,
            'sample_status': {
                'completed': 0,
                'running': 0,
                'pending': samples,
                'failed': 0
            },
            'timestamp': time.strftime("%Y-%m-%dT%H:%M:%S.%fZ", time.gmtime()),
            'job_id': f"microbiome-demo-job-{int(time.time())}"
        }
        
        # Store initial status in S3
        s3.put_object(
            Bucket=data_bucket,
            Key='status/progress.json',
            Body=json.dumps(init_status),
            ContentType='application/json'
        )
        
        # Submit a batch job - IMPORTANT: Do NOT override the command parameter
        # Let the job definition's command handle Nextflow installation and execution
        print(f"Submitting job to queue: {job_queue}")
        
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
        
        job_id = response['jobId']
        print(f"Submitted job with ID: {job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully submitted job',
                'jobId': job_id,
                'samples': samples,
                'processingTime': processing_time
            })
        }
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'message': f'Unknown action: {action}'
            })
        }