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
    
    # For testing, create a simple file in S3
    action = event.get('action', 'test')
    
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
    else:
        # Submit a batch job
        print(f"Submitting job to queue: {job_queue}")
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
        
        job_id = response['jobId']
        print(f"Submitted job with ID: {job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully submitted job',
                'jobId': job_id
            })
        }
