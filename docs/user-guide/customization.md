# Customizing the Microbiome Demo

This guide explains how to customize the Microbiome Demo for your specific requirements, datasets, or analysis workflows.

## Table of Contents

1. [Using Your Own Data](#using-your-own-data)
2. [Modifying Analysis Parameters](#modifying-analysis-parameters)
3. [Adding New Analysis Steps](#adding-new-analysis-steps)
4. [Customizing the Dashboard](#customizing-the-dashboard)
5. [Adjusting AWS Resources](#adjusting-aws-resources)
6. [Optimizing for Different Workloads](#optimizing-for-different-workloads)

## Using Your Own Data

The demo is configured to use Human Microbiome Project data by default, but you can use your own metagenomic data.

### Creating a Custom Sample List

1. Create a CSV file with the following format:

```csv
sample_id,body_site,fastq_1,fastq_2
sample1,gut,s3://your-bucket/data/sample1_1.fastq.gz,s3://your-bucket/data/sample1_2.fastq.gz
sample2,skin,s3://your-bucket/data/sample2_1.fastq.gz,s3://your-bucket/data/sample2_2.fastq.gz
```

2. Upload the file to your S3 bucket:

```bash
aws s3 cp sample_list.csv s3://your-bucket/input/sample_list.csv
```

3. Modify the Nextflow configuration to use your sample list:

```bash
# Edit workflow/microbiome_nextflow.config
params {
    samples = "s3://your-bucket/input/sample_list.csv"
    # ... other parameters
}
```

### Uploading Your Data to S3

If your data is not already in S3, upload it:

```bash
# Create a directory structure
mkdir -p raw_data

# Upload your FASTQ files
aws s3 cp raw_data/ s3://your-bucket/data/ --recursive
```

### Sample Format Requirements

- FASTQ files must be gzipped (`.fastq.gz` extension)
- Paired-end data should have `_1` and `_2` suffixes
- Sample IDs should be unique and contain only alphanumeric characters and underscores

## Modifying Analysis Parameters

You can customize various analysis parameters to tailor the analysis to your needs.

### Editing Nextflow Configuration

The main configuration file is `workflow/microbiome_nextflow.config`. Common parameters to adjust include:

```groovy
params {
    // Reference databases
    kraken_db = "s3://your-bucket/reference/custom_kraken_db"
    metaphlan_db = "s3://your-bucket/reference/custom_metaphlan_db"
    
    // Tool parameters
    kraken_confidence = 0.1  // Confidence threshold for Kraken2
    humann_identity_threshold = 90  // HUMAnN sequence identity threshold
    
    // Resources
    max_memory = 32.GB  // Maximum memory for any process
    max_cpus = 16       // Maximum CPUs for any process
}
```

### Process-Specific Parameters

Individual processes can be customized in the Nextflow workflow file (`workflow/microbiome_main.nf`):

```groovy
process taxonomic_classification_kraken {
    // Customize resources
    cpus 8
    memory '32 GB'
    
    // Customize parameters in the script section
    script:
    """
    kraken2 --db ${params.kraken_db} \
            --confidence ${params.kraken_confidence} \
            --threads ${task.cpus} \
            # Additional customizations...
    """
}
```

## Adding New Analysis Steps

You can extend the pipeline by adding new analysis steps.

### Adding a New Process

To add a new analysis step, edit `workflow/microbiome_main.nf`:

1. Define a new input channel:

```groovy
Channel
    .fromPath(params.new_reference)
    .set { new_reference_channel }
```

2. Create a new process:

```groovy
process new_analysis_step {
    cpus 4
    memory '8 GB'
    tag { sample_id }
    
    input:
    tuple val(sample_id), path(results_file) from previous_results
    path reference from new_reference_channel
    
    output:
    tuple val(sample_id), path("${sample_id}.new_results.txt") into new_results
    
    script:
    """
    # Your analysis commands here
    new_tool --input ${results_file} \
             --reference ${reference} \
             --output ${sample_id}.new_results.txt
    """
}
```

3. Connect the new process to the workflow:

```groovy
// Feed the results to the next step
new_results.into { for_summary; for_visualization }
```

### Using Custom Containers

If your new step requires additional tools, create a custom Docker container:

1. Create a new Dockerfile in the `containers` directory
2. Build and push the container
3. Update the Nextflow configuration to use your container:

```groovy
process {
    withName: 'new_analysis_step' {
        container = 'your-registry/custom-container:latest'
    }
}
```

## Customizing the Dashboard

The dashboard can be customized to display different visualizations or metrics.

### Modifying the UI

Edit `dashboard/js/microbiome_dashboard.js` to customize the interface:

```javascript
// Add a new visualization component
const NewVisualization = () => {
  const data = /* process your data */;
  
  return (
    <div className="p-4 bg-white rounded shadow">
      <h3 className="text-lg font-semibold mb-4">New Analysis Results</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data}>
          {/* Chart configuration */}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};

// Add it to your main component
const MicrobiomeDashboard = () => {
  // ...existing code
  
  return (
    <div>
      {/* Other components */}
      <NewVisualization />
    </div>
  );
};
```

### Adding New Data Sources

To include new data in the dashboard:

1. Modify the pipeline to generate the data in a suitable format (JSON/CSV)
2. Update the Lambda function to upload this data to the right location
3. Add code to fetch and display the data in the dashboard

## Adjusting AWS Resources

You can customize the AWS resources used by the demo.

### Modifying CloudFormation Template

Edit `cloudformation.yaml` to adjust the infrastructure:

```yaml
GravitonComputeEnvironment:
  Type: AWS::Batch::ComputeEnvironment
  Properties:
    ComputeResources:
      # Increase maximum vCPUs
      MaxvCpus: 512
      # Add more instance types
      InstanceTypes:
        - c7g.large
        - c7g.xlarge
        - c7g.2xlarge
        - c7g.4xlarge
```

### Customizing AWS Batch Settings

For finer-grained control, modify job queues and compute environments:

```bash
# Example: Update a compute environment
aws batch update-compute-environment \
  --compute-environment microbiome-demo-cpu-env \
  --compute-resources "maxvCpus=512,desiredvCpus=0"
```

## Optimizing for Different Workloads

The demo can be optimized for various workload types.

### For Larger Datasets

When processing many samples (500+):

1. Increase the Batch compute environment's maxvCpus:
   ```yaml
   MaxvCpus: 1000
   ```

2. Use a larger instance for the Nextflow head job:
   ```yaml
   NextflowJobDefinition:
     Properties:
       ContainerProperties:
         ResourceRequirements:
           - Type: VCPU
             Value: "4"
           - Type: MEMORY
             Value: "16384"
   ```

3. Adjust the S3 bucket lifecycle policy for longer storage:
   ```yaml
   LifecycleConfiguration:
     Rules:
       - ExpirationInDays: 90
   ```

### For GPU-Intensive Workloads

When focusing on GPU-accelerated steps:

1. Increase the number of GPU instances:
   ```yaml
   GpuComputeEnvironment:
     Properties:
       ComputeResources:
         MaxvCpus: 128  # Support more GPUs
         InstanceTypes:
           - g5g.2xlarge
           - g5g.4xlarge
           - g5g.8xlarge
   ```

2. Update the GPU container to better utilize the hardware:
   ```dockerfile
   # In Dockerfile.gpu
   ENV CUDA_VISIBLE_DEVICES=0,1,2,3  # For multi-GPU instances
   ```

### Memory-Intensive Analyses

For analyses requiring more memory:

1. Add memory-optimized instances:
   ```yaml
   InstanceTypes:
     - r7g.large
     - r7g.xlarge
     - r7g.2xlarge
   ```

2. Update process memory requirements:
   ```groovy
   process memory_intensive_step {
     memory { 16.GB * task.attempt }
     maxRetries 3
     
     // Memory increases with each retry attempt
   }
   ```

## Conclusion

By following these customization guidelines, you can adapt the Microbiome Demo for a wide range of research applications while maintaining its performance and cost advantages. For further assistance, refer to the [Troubleshooting Guide](../../TROUBLESHOOTING.md) or open an issue on the GitHub repository.