#!/usr/bin/env python3
"""
Test script for Lambda function error handling.
This script tests various error scenarios to ensure the Lambda function handles them gracefully.
"""

import json
import unittest
import os
import sys
from unittest.mock import patch, MagicMock

# Import the Lambda function
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import progress_notification_lambda as lambda_func

class TestLambdaErrorHandling(unittest.TestCase):
    
    def setUp(self):
        """Set up test fixtures"""
        # Create a valid S3 event
        self.valid_event = {
            "Records": [
                {
                    "eventVersion": "2.1",
                    "eventSource": "aws:s3",
                    "awsRegion": "us-east-1",
                    "eventTime": "2023-01-01T00:00:00.000Z",
                    "eventName": "ObjectCreated:Put",
                    "s3": {
                        "s3SchemaVersion": "1.0",
                        "configurationId": "test-config",
                        "bucket": {
                            "name": "test-bucket",
                            "ownerIdentity": {
                                "principalId": "A123456789"
                            },
                            "arn": "arn:aws:s3:::test-bucket"
                        },
                        "object": {
                            "key": "progress/test-workflow/progress.json",
                            "size": 1024,
                            "eTag": "test-etag",
                            "sequencer": "test-sequencer"
                        }
                    }
                }
            ]
        }
        
        # Sample progress data
        self.valid_progress_data = {
            "workflow_id": "test-workflow",
            "status": "running",
            "percent_complete": 50,
            "elapsed_seconds": 300,
            "elapsed_time_formatted": "00:05:00",
            "estimated_remaining_seconds": 300,
            "estimated_remaining_formatted": "00:05:00",
            "completed_count": 5,
            "total_processes": 10,
            "processes": {
                "process1": {"status": "completed"},
                "process2": {"status": "completed"},
                "process3": {"status": "running"}
            }
        }
        
    def test_invalid_event_structure(self):
        """Test handling of invalid event structure"""
        # Test with empty event
        with self.assertRaises(lambda_func.ProgressProcessingError):
            lambda_func.validate_event({})
        
        # Test with missing Records
        with self.assertRaises(lambda_func.ProgressProcessingError):
            lambda_func.validate_event({"NotRecords": []})
        
        # Test with empty Records
        with self.assertRaises(lambda_func.ProgressProcessingError):
            lambda_func.validate_event({"Records": []})
        
        # Test with missing s3 key
        with self.assertRaises(lambda_func.ProgressProcessingError):
            lambda_func.validate_event({"Records": [{"not_s3": {}}]})
    
    def test_extract_workflow_id(self):
        """Test extraction of workflow ID from key"""
        # Valid key
        self.assertEqual(
            lambda_func.extract_workflow_id("progress/test-workflow/progress.json"),
            "test-workflow"
        )
        
        # Invalid key format returns 'unknown'
        self.assertEqual(
            lambda_func.extract_workflow_id("some/invalid/path/structure"),
            "unknown"
        )
        
        # Empty key returns 'unknown'
        self.assertEqual(
            lambda_func.extract_workflow_id(""),
            "unknown"
        )
    
    @patch('progress_notification_lambda.s3')
    def test_get_progress_data_client_error(self, mock_s3):
        """Test handling of S3 client errors when getting progress data"""
        # Setup mock for NoSuchKey error
        error_response = {
            'Error': {
                'Code': 'NoSuchKey',
                'Message': 'The specified key does not exist.'
            }
        }
        
        mock_s3.get_object.side_effect = lambda_func.ClientError(
            error_response, 'GetObject')
        
        # Test that NoSuchKey error is properly raised
        with self.assertRaises(lambda_func.ProgressProcessingError) as cm:
            lambda_func.get_progress_data('test-bucket', 'progress/test-workflow/progress.json')
        
        self.assertIn("Progress file does not exist", str(cm.exception))
    
    @patch('progress_notification_lambda.s3')
    def test_get_progress_data_json_error(self, mock_s3):
        """Test handling of JSON parsing errors"""
        # Setup mock to return invalid JSON
        mock_response = MagicMock()
        mock_response['Body'].read.return_value = b'{ invalid json }'
        mock_s3.get_object.return_value = mock_response
        
        # Second call for backup should fail
        mock_s3.get_object.side_effect = [
            mock_response,
            lambda_func.ClientError({'Error': {'Code': 'NoSuchKey'}}, 'GetObject')
        ]
        
        # Should return default empty progress data
        result = lambda_func.get_progress_data('test-bucket', 'progress/test-workflow/progress.json')
        
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['percent_complete'], 0)
        self.assertEqual(result['processes']['completed'], 0)
        self.assertEqual(result['processes']['total'], 0)
    
    def test_prepare_dashboard_data(self):
        """Test dashboard data preparation with validation"""
        # Test with valid data
        result = lambda_func.prepare_dashboard_data(self.valid_progress_data, 'test-workflow')
        self.assertEqual(result['workflow_id'], 'test-workflow')
        self.assertEqual(result['status'], 'running')
        self.assertEqual(result['percent_complete'], 50)
        
        # Test with invalid percent complete
        invalid_data = self.valid_progress_data.copy()
        invalid_data['percent_complete'] = "not-a-number"
        result = lambda_func.prepare_dashboard_data(invalid_data, 'test-workflow')
        self.assertEqual(result['percent_complete'], 0)
        
        # Test with percent out of range
        invalid_data['percent_complete'] = 150
        result = lambda_func.prepare_dashboard_data(invalid_data, 'test-workflow')
        self.assertEqual(result['percent_complete'], 100)
        
        invalid_data['percent_complete'] = -10
        result = lambda_func.prepare_dashboard_data(invalid_data, 'test-workflow')
        self.assertEqual(result['percent_complete'], 0)
        
        # Test with invalid status
        invalid_data['status'] = 'invalid-status'
        result = lambda_func.prepare_dashboard_data(invalid_data, 'test-workflow')
        self.assertEqual(result['status'], lambda_func.DEFAULT_STATUS)
    
    @patch('progress_notification_lambda.s3')
    def test_update_dashboard_retry_logic(self, mock_s3):
        """Test retry logic in update_dashboard function"""
        # Setup mocks for testing retry
        
        # First call fails, second succeeds
        mock_s3.put_object.side_effect = [
            Exception("Simulated failure"),
            None  # Success
        ]
        
        # Should succeed after retry
        lambda_func.update_dashboard(
            'test-bucket',
            self.valid_progress_data,
            'test-workflow'
        )
        
        # Verify put_object was called twice
        self.assertEqual(mock_s3.put_object.call_count, 2)
        
    @patch('progress_notification_lambda.s3')
    def test_update_dashboard_max_retries(self, mock_s3):
        """Test max retry logic in update_dashboard function"""
        # Setup mocks for testing max retry
        
        # All calls fail
        mock_s3.put_object.side_effect = Exception("Simulated failure")
        
        # Should raise exception after max retries
        with self.assertRaises(lambda_func.ProgressProcessingError):
            lambda_func.update_dashboard(
                'test-bucket',
                self.valid_progress_data,
                'test-workflow',
                max_retries=2
            )
        
        # Verify put_object was called the expected number of times
        self.assertEqual(mock_s3.put_object.call_count, 2)
    
    @patch('progress_notification_lambda.sns')
    def test_send_notification(self, mock_sns):
        """Test SNS notification sending"""
        # Mock the SNS environment variable
        with patch.dict(os.environ, {'SNS_TOPIC_ARN': 'test-topic-arn'}):
            # Test with completed status
            result = lambda_func.send_notification(
                'completed',
                'test-workflow',
                self.valid_progress_data
            )
            
            # Verify SNS.publish was called
            mock_sns.publish.assert_called_once()
            self.assertTrue(result)
            
            # Reset mock
            mock_sns.reset_mock()
            
            # Test with non-notification status
            result = lambda_func.send_notification(
                'running',
                'test-workflow',
                self.valid_progress_data
            )
            
            # Verify SNS.publish was not called
            mock_sns.publish.assert_not_called()
            self.assertFalse(result)
    
    @patch('progress_notification_lambda.sns')
    def test_send_notification_missing_topic(self, mock_sns):
        """Test notification handling without SNS topic configured"""
        # No SNS topic configured
        result = lambda_func.send_notification(
            'completed',
            'test-workflow',
            self.valid_progress_data
        )
        
        # Should return False and not call SNS
        self.assertFalse(result)
        mock_sns.publish.assert_not_called()
    
    @patch('progress_notification_lambda.validate_event')
    @patch('progress_notification_lambda.extract_workflow_id')
    @patch('progress_notification_lambda.get_progress_data')
    @patch('progress_notification_lambda.prepare_dashboard_data')
    @patch('progress_notification_lambda.update_dashboard')
    @patch('progress_notification_lambda.send_notification')
    def test_lambda_handler_success_path(self, mock_send, mock_update, mock_prepare, 
                                        mock_get, mock_extract, mock_validate):
        """Test successful lambda_handler execution path"""
        # Setup mocks for successful execution
        mock_validate.return_value = ('test-bucket', 'progress/test-workflow/progress.json')
        mock_extract.return_value = 'test-workflow'
        mock_get.return_value = self.valid_progress_data
        mock_prepare.return_value = {'status': 'running', 'percent_complete': 50}
        mock_update.return_value = True
        mock_send.return_value = False  # Not completed
        
        # Call lambda_handler
        result = lambda_func.lambda_handler(self.valid_event, {})
        
        # Verify success response
        self.assertEqual(result['statusCode'], 200)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['workflow_id'], 'test-workflow')
        self.assertEqual(response_body['status'], 'running')
        self.assertEqual(response_body['percent_complete'], 50)
        
        # Verify each function was called
        mock_validate.assert_called_once()
        mock_extract.assert_called_once()
        mock_get.assert_called_once()
        mock_prepare.assert_called_once()
        mock_update.assert_called_once()
        
    @patch('progress_notification_lambda.validate_event')
    def test_lambda_handler_validation_error(self, mock_validate):
        """Test lambda_handler with validation error"""
        # Setup mock for validation error
        mock_validate.side_effect = lambda_func.ProgressProcessingError("Invalid event structure")
        
        # Call lambda_handler
        result = lambda_func.lambda_handler(self.valid_event, {})
        
        # Verify error response
        self.assertEqual(result['statusCode'], 400)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['error'], 'Progress processing error')
        self.assertEqual(response_body['message'], 'Invalid event structure')
    
    @patch('progress_notification_lambda.validate_event')
    def test_lambda_handler_unexpected_error(self, mock_validate):
        """Test lambda_handler with unexpected error"""
        # Setup mock for unexpected error
        mock_validate.side_effect = KeyError("Unexpected error")
        
        # Call lambda_handler
        result = lambda_func.lambda_handler(self.valid_event, {})
        
        # Verify error response
        self.assertEqual(result['statusCode'], 500)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['error'], 'Internal server error')
        self.assertIn('Unexpected error', response_body['message'])

if __name__ == '__main__':
    unittest.main()