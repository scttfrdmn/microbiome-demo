#!/usr/bin/env python3
# cost_report.py - Generate cost comparisons for the Microbiome Demo

import argparse
import json
import datetime
import os
import sys

def calculate_costs(cpu_hours, gpu_hours, data_gb, duration_minutes):
    """
    Calculate costs for the microbiome analysis workload.
    
    Args:
        cpu_hours: Total CPU instance hours
        gpu_hours: Total GPU instance hours
        data_gb: Amount of data processed in GB
        duration_minutes: Wall-clock duration in minutes
        
    Returns:
        Dictionary with cost calculations
    """
    # Cost rates (USD)
    rates = {
        'on_premises': {
            'cpu_hour': 1.20,        # Cost per CPU hour on-prem
            'gpu_hour': 5.00,        # Cost per GPU hour on-prem
            'storage_gb_month': 0.20, # Cost per GB-month of storage on-prem
            'setup_time_hours': 336.0 # Two weeks of setup time
        },
        'standard_cloud': {
            'cpu_hour': 0.40,        # Regular EC2 instances
            'gpu_hour': 1.50,        # Regular GPU instances
            'storage_gb_month': 0.10  # Regular S3 storage
        },
        'optimized_aws': {
            'graviton_spot_hour': 0.0408,  # c7g.2xlarge Spot
            'gpu_spot_hour': 0.50,         # g5g.2xlarge Spot
            'storage_gb_month': 0.02,      # S3 storage
            'data_transfer_gb': 0.01       # Data transfer
        }
    }
    
    # Calculate on-premises cost
    on_prem_compute = (cpu_hours * rates['on_premises']['cpu_hour']) + (gpu_hours * rates['on_premises']['gpu_hour'])
    on_prem_setup = rates['on_premises']['setup_time_hours'] * rates['on_premises']['cpu_hour']
    on_prem_storage = data_gb * rates['on_premises']['storage_gb_month'] * 0.25  # Assume 1 week storage = 0.25 months
    on_prem_total = on_prem_compute + on_prem_setup + on_prem_storage
    
    # Calculate standard cloud cost
    standard_compute = (cpu_hours * rates['standard_cloud']['cpu_hour']) + (gpu_hours * rates['standard_cloud']['gpu_hour'])
    standard_storage = data_gb * rates['standard_cloud']['storage_gb_month'] * 0.25  # Assume 1 week storage
    standard_total = standard_compute + standard_storage
    
    # Calculate optimized AWS cost
    optimized_compute = (cpu_hours * rates['optimized_aws']['graviton_spot_hour']) + (gpu_hours * rates['optimized_aws']['gpu_spot_hour'])
    optimized_storage = data_gb * rates['optimized_aws']['storage_gb_month'] * 0.25  # Assume 1 week storage
    optimized_transfer = data_gb * rates['optimized_aws']['data_transfer_gb']
    optimized_total = optimized_compute + optimized_storage + optimized_transfer
    
    # Calculate savings
    savings_vs_on_prem = on_prem_total - optimized_total
    savings_percent = (savings_vs_on_prem / on_prem_total) * 100
    
    return {
        "estimated_cost": {
            "compute": {
                "graviton_spot": round(cpu_hours * rates['optimized_aws']['graviton_spot_hour'], 2),
                "gpu_spot": round(gpu_hours * rates['optimized_aws']['gpu_spot_hour'], 2)
            },
            "storage": round(optimized_storage, 2),
            "data_transfer": round(optimized_transfer, 2),
            "total": round(optimized_total, 2)
        },
        "comparison": {
            "on_premises": round(on_prem_total, 2),
            "standard_cloud": round(standard_total, 2),
            "optimized_cloud": round(optimized_total, 2)
        },
        "savings": {
            "versus_on_premises": round(savings_vs_on_prem, 2),
            "percentage": round(savings_percent, 1),
            "time_saved": "336 hours (2 weeks)"
        }
    }

def get_nextflow_metrics():
    """Extract metrics from Nextflow environment variables if available"""
    return {
        'cpu_hours': float(os.environ.get('NEXTFLOW_CPU_HOURS', '50')),
        'gpu_hours': float(os.environ.get('NEXTFLOW_GPU_HOURS', '10')),
        'data_gb': float(os.environ.get('NEXTFLOW_DATA_SIZE_GB', '50')),
        'duration_minutes': float(os.environ.get('NEXTFLOW_DURATION_MINUTES', '15'))
    }

def main():
    parser = argparse.ArgumentParser(description='Generate cost report for Microbiome Demo')
    parser.add_argument('--cpu-hours', type=float, default=50.0,
                      help='Total CPU hours used (default: 50)')
    parser.add_argument('--gpu-hours', type=float, default=10.0,
                      help='Total GPU hours used (default: 10)')
    parser.add_argument('--data-gb', type=float, default=50.0,
                      help='Total data processed in GB (default: 50)')
    parser.add_argument('--duration-minutes', type=float, default=15.0,
                      help='Wall-clock duration in minutes (default: 15)')
    parser.add_argument('--output', default='cost_report.json',
                      help='Output JSON file (default: cost_report.json)')
    
    args = parser.parse_args()
    
    # Try to get metrics from Nextflow, otherwise use command line args
    try:
        metrics = get_nextflow_metrics()
    except:
        metrics = {
            'cpu_hours': args.cpu_hours,
            'gpu_hours': args.gpu_hours,
            'data_gb': args.data_gb,
            'duration_minutes': args.duration_minutes
        }
    
    # Calculate costs
    cost_data = calculate_costs(
        metrics['cpu_hours'],
        metrics['gpu_hours'],
        metrics['data_gb'],
        metrics['duration_minutes']
    )
    
    # Add metadata
    cost_data['metadata'] = {
        'generated_at': datetime.datetime.now().isoformat(),
        'cpu_hours': metrics['cpu_hours'],
        'gpu_hours': metrics['gpu_hours'],
        'data_gb': metrics['data_gb'],
        'duration_minutes': metrics['duration_minutes']
    }
    
    # Write to file
    with open(args.output, 'w') as f:
        json.dump(cost_data, f, indent=2)
    
    print(f"Cost report generated at: {args.output}")
    print(f"Total cost: ${cost_data['estimated_cost']['total']}")
    print(f"Savings vs. on-premises: {cost_data['savings']['percentage']}% (${cost_data['savings']['versus_on_premises']})")

if __name__ == "__main__":
    main()