#!/usr/bin/env python3
# test_cost_report.py - Unit tests for cost_report.py

import unittest
import os
import sys
import json
import tempfile
from unittest.mock import patch, MagicMock

# Add the parent directory to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import the module to test
from templates.cost_report import calculate_costs, get_nextflow_metrics, main

class TestCostReport(unittest.TestCase):
    """Test cases for the cost_report.py module"""

    def test_calculate_costs(self):
        """Test the calculate_costs function with various inputs"""
        # Test with zero values
        result = calculate_costs(0, 0, 0, 0)
        self.assertEqual(result['estimated_cost']['total'], 0.0)
        
        # Test with normal values
        result = calculate_costs(50, 10, 50, 15)
        
        # Check that all required keys exist
        self.assertIn('estimated_cost', result)
        self.assertIn('comparison', result)
        self.assertIn('savings', result)
        
        # Check estimated cost fields
        self.assertIn('compute', result['estimated_cost'])
        self.assertIn('storage', result['estimated_cost'])
        self.assertIn('data_transfer', result['estimated_cost'])
        self.assertIn('total', result['estimated_cost'])
        
        # Check comparison fields
        self.assertIn('on_premises', result['comparison'])
        self.assertIn('standard_cloud', result['comparison'])
        self.assertIn('optimized_cloud', result['comparison'])
        
        # Check savings fields
        self.assertIn('versus_on_premises', result['savings'])
        self.assertIn('percentage', result['savings'])
        
        # Verify computation for specific values
        self.assertAlmostEqual(result['estimated_cost']['compute']['graviton_spot'], 50 * 0.0408, places=2)
        self.assertAlmostEqual(result['estimated_cost']['compute']['gpu_spot'], 10 * 0.50, places=2)
        
        # Verify that on-premises cost is greater than optimized cloud cost
        self.assertGreater(result['comparison']['on_premises'], result['comparison']['optimized_cloud'])
        
        # Check savings percentage is positive
        self.assertGreater(result['savings']['percentage'], 0)

    @patch('os.environ')
    def test_get_nextflow_metrics(self, mock_environ):
        """Test the get_nextflow_metrics function"""
        # Set up mock environment variables
        mock_environ.get.side_effect = lambda key, default: {
            'NEXTFLOW_CPU_HOURS': '100',
            'NEXTFLOW_GPU_HOURS': '20',
            'NEXTFLOW_DATA_SIZE_GB': '75',
            'NEXTFLOW_DURATION_MINUTES': '30'
        }.get(key, default)
        
        # Call the function
        metrics = get_nextflow_metrics()
        
        # Verify results
        self.assertEqual(metrics['cpu_hours'], 100.0)
        self.assertEqual(metrics['gpu_hours'], 20.0)
        self.assertEqual(metrics['data_gb'], 75.0)
        self.assertEqual(metrics['duration_minutes'], 30.0)
        
        # Test with default values
        mock_environ.get.side_effect = lambda key, default: default
        metrics = get_nextflow_metrics()
        
        # Verify default results
        self.assertEqual(metrics['cpu_hours'], 50.0)
        self.assertEqual(metrics['gpu_hours'], 10.0)
        self.assertEqual(metrics['data_gb'], 50.0)
        self.assertEqual(metrics['duration_minutes'], 15.0)

    @patch('argparse.ArgumentParser.parse_args')
    @patch('builtins.open', new_callable=unittest.mock.mock_open)
    @patch('json.dump')
    def test_main_function(self, mock_json_dump, mock_open, mock_parse_args):
        """Test the main function with command line arguments"""
        # Mock the parsed arguments
        mock_args = MagicMock()
        mock_args.cpu_hours = 60.0
        mock_args.gpu_hours = 15.0
        mock_args.data_gb = 80.0
        mock_args.duration_minutes = 20.0
        mock_args.output = 'test_output.json'
        mock_parse_args.return_value = mock_args
        
        # Call the main function
        with patch('os.environ', {}):  # Ensure no environment variables affect the test
            main()
        
        # Verify the file was opened for writing
        mock_open.assert_called_once_with('test_output.json', 'w')
        
        # Verify json.dump was called
        self.assertTrue(mock_json_dump.called)
        
        # Extract the first argument (the cost data)
        cost_data = mock_json_dump.call_args[0][0]
        
        # Verify the data structure
        self.assertIn('estimated_cost', cost_data)
        self.assertIn('comparison', cost_data)
        self.assertIn('metadata', cost_data)
        
        # Verify the metadata contains the input parameters
        self.assertEqual(cost_data['metadata']['cpu_hours'], 60.0)
        self.assertEqual(cost_data['metadata']['gpu_hours'], 15.0)
        self.assertEqual(cost_data['metadata']['data_gb'], 80.0)
        self.assertEqual(cost_data['metadata']['duration_minutes'], 20.0)

if __name__ == '__main__':
    unittest.main()