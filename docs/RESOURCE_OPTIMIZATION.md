# Nextflow Resource Optimization Strategies for AWS Batch

This document outlines strategies for dynamically adjusting Nextflow resource requests based on the instance type provided by AWS Batch, focusing on optimizing for ARM-based Graviton instances and handling GPU availability.

## The Problem

When running Nextflow workflows on AWS Batch, resource allocation often follows static patterns that don't account for the actual hardware provided by AWS Batch. This creates several issues:

1. **Resource Underutilization**: Static resource requests may not fully utilize available CPU, memory, and storage on more powerful instances
2. **Architecture Incompatibility**: Running on ARM architecture (like Graviton) requires architecture-aware resource allocation to prevent errors
3. **GPU Availability**: Some processes can use GPU acceleration when available, but need CPU fallback options
4. **Queue Selection**: Different hardware requirements need different job queues in AWS Batch

## Optimization Strategies

### 1. Environment Variable Detection

```nextflow
process someTask {
    // Dynamically set CPU based on environment
    cpus { System.getenv('CPU_COUNT') ? System.getenv('CPU_COUNT').toInteger() : 4 }
    
    // Dynamically set memory based on environment
    memory { System.getenv('MEM_SIZE') ? "${System.getenv('MEM_SIZE')}GB" : "8 GB" }
    
    script:
    """
    # Task commands here
    """
}
```

**Pros:**
- Simple implementation
- Works with any container image
- Can be configured at job definition level

**Cons:**
- Requires setting environment variables in Batch job definitions
- Not fully automated

### 2. AWS Batch Job Definition Templates

Create architecture-specific job definition templates:

```json
{
  "x86_64": {
    "jobDefinitionName": "microbiome-x86",
    "containerProperties": {
      "image": "microbiome-demo:latest",
      "resourceRequirements": [
        { "type": "VCPU", "value": "4" },
        { "type": "MEMORY", "value": "8192" }
      ],
      "environment": [
        { "name": "NXF_OPTS", "value": "-Xms1g -Xmx4g" }
      ]
    }
  },
  "arm64": {
    "jobDefinitionName": "microbiome-arm64",
    "containerProperties": {
      "image": "microbiome-demo:latest-arm64",
      "resourceRequirements": [
        { "type": "VCPU", "value": "4" },
        { "type": "MEMORY", "value": "8192" }
      ],
      "environment": [
        { "name": "NXF_OPTS", "value": "-Xms1g -Xmx4g" }
      ]
    }
  }
}
```

**Pros:**
- Complete architecture-specific optimization
- Enforces proper image selection

**Cons:**
- Requires maintaining multiple job definitions
- Less dynamic than runtime detection

### 3. Container Resource Auto-Detection

```nextflow
process detectResources {
    output:
    path 'resources.json'

    script:
    """
    #!/bin/bash
    echo '{' > resources.json
    
    # Detect CPU architecture
    if grep -q "aarch64" /proc/cpuinfo; then
        echo '  "architecture": "arm64",' >> resources.json
    else
        echo '  "architecture": "x86_64",' >> resources.json
    fi
    
    # Get available CPUs
    echo '  "cpu": '`nproc`',' >> resources.json
    
    # Get available memory in MB
    echo '  "memory": '`free -m | grep Mem | awk '{print \$2}'`',' >> resources.json
    
    # Get available disk space
    echo '  "disk": '`df -m /tmp | tail -1 | awk '{print \$4}'`'' >> resources.json
    echo '}' >> resources.json
    """
}

// Later processes can use this detected info
process someTask {
    input:
    path resources_json

    script:
    """
    # Parse resources.json and use it
    ARCH=\$(jq -r '.architecture' ${resources_json})
    CPU=\$(jq -r '.cpu' ${resources_json})
    MEM=\$(jq -r '.memory' ${resources_json})
    
    # Use architecture-specific commands
    if [ "\$ARCH" == "arm64" ]; then
        # ARM-specific optimizations
    else
        # x86 optimizations
    fi
    """
}
```

**Pros:**
- Fully dynamic detection at runtime
- Adapts to any instance type
- Can detect exact resources available

**Cons:**
- Adds complexity to workflow
- Requires detection step at beginning of pipeline

### 4. Dynamic AWS Batch Job Submission

Use AWS CLI within the workflow to determine optimal job configuration:

```nextflow
process submitDynamicJob {
    script:
    """
    # Get instance details from AWS Batch
    instance_type=\$(aws ec2 describe-instances --instance-ids \$AWS_BATCH_JOB_INSTANCE_ID --query 'Reservations[0].Instances[0].InstanceType' --output text)
    
    # Match instance type to resource allocation
    case \$instance_type in
        c6g*)
            # ARM Graviton optimization
            export CPUS=\$(nproc)
            export MEM_MB=\$(free -m | grep Mem | awk '{print \$2}')
            ;;
        c5*)
            # x86 optimization
            export CPUS=\$(nproc)
            export MEM_MB=\$(free -m | grep Mem | awk '{print \$2}')
            ;;
        *)
            # Default allocation
            export CPUS=4
            export MEM_MB=8192
            ;;
    esac
    
    # Submit nextflow job with these parameters
    nextflow run workflow.nf -with-env CPUS,MEM_MB
    """
}
```

**Pros:**
- Highly dynamic and instance-aware
- Can optimize for specific instance families

**Cons:**
- Requires AWS CLI in container
- More complex to implement and debug

### 5. Resource-Aware Process Definitions

```nextflow
// Define architecture-specific parameters in nextflow.config
params {
    resources {
        arm64 {
            kraken {
                cpus = 4
                memory = '7 GB'
                diskSpace = '20 GB'
            }
        }
        x86_64 {
            kraken {
                cpus = 8
                memory = '15 GB'
                diskSpace = '20 GB'
            }
        }
    }
}

// Get architecture at runtime
def getArch() {
    def proc = ['bash', '-c', 'grep -q "aarch64" /proc/cpuinfo && echo "arm64" || echo "x86_64"'].execute()
    proc.waitFor()
    return proc.text.trim()
}

// Use in processes
process kraken2Analysis {
    def arch = getArch()
    cpus params.resources[arch].kraken.cpus
    memory params.resources[arch].kraken.memory
    
    script:
    """
    # Kraken2 analysis commands
    """
}
```

**Pros:**
- Provides process-specific resource optimization
- Easily maintainable in configuration
- Can be very granular

**Cons:**
- Requires architecture detection mechanism
- Configuration can become complex

## GPU-Specific Optimization Strategies

In addition to architecture detection, optimizing for GPU availability requires special handling:

### 1. GPU Detection and Resource Allocation

```nextflow
// Detect GPU availability
def hasGpu(resources_file) {
    def json = new groovy.json.JsonSlurper().parseText(resources_file.text)
    return (json.gpu as Integer) > 0
}

// Use GPU conditionally in process
process gpuTask {
    accelerator { hasGpu(resources) ? 1 : 0 }  // Request GPU only if available
    
    script:
    """
    if command -v nvidia-smi &> /dev/null; then
        # GPU-specific command
        gpu_command --accelerate
    else
        # CPU fallback command
        cpu_command --threads ${task.cpus}
    fi
    """
}
```

### 2. Queue Selection Based on Hardware Requirements

```nextflow
process {
    withName: 'gpuTask' {
        queue = { task.accelerator > 0 ? 'gpu-queue' : 'cpu-queue' }
    }
}
```

### 3. Process-Specific GPU vs CPU Resource Sets

```nextflow
params.resources = [
    'x86_64': [
        'task_gpu': [cpus: 4, memory: '16 GB', gpu: true],
        'task_cpu': [cpus: 16, memory: '32 GB', gpu: false]  // More CPU/memory when no GPU
    ]
]

// Use appropriate resource set
def getResourceConfig(resources_file, process_name) {
    def json = new groovy.json.JsonSlurper().parseText(resources_file.text)
    def arch = json.architecture ?: 'x86_64'
    def gpu_count = json.gpu ?: 0
    
    if (process_name == 'task' && gpu_count == 0) {
        return params.resources[arch]['task_cpu']
    }
    
    return params.resources[arch][process_name]
}
```

## Recommended Implementation

For the microbiome demo, we implement a comprehensive approach:

1. **Initial Resource Detection Process**: Run a process at the start of the workflow that detects architecture, available resources, and GPU availability

2. **Process-Specific Resource Strategies**: Define both architecture-specific and GPU/CPU-specific resource requirements for each major process (Kraken2, MetaPhlAn, HUMAnN)

3. **Dynamic Queue Selection**: Select appropriate AWS Batch queues based on detected hardware requirements

4. **Runtime Command Adaptation**: Modify commands at runtime to use GPU flags when available and CPU-optimized approaches when not

5. **Fallback Defaults**: Provide sensible defaults for each process when specific architectures aren't detected

6. **Configuration Documentation**: Document the resource requirements for each architecture and GPU/CPU scenario

By implementing this approach, the microbiome demo efficiently utilizes resources on both ARM Graviton and x86 instances, with or without GPU acceleration, preventing both under-utilization and out-of-memory errors while maximizing performance.

## Implementation Learnings and Best Practices

During the implementation of resource optimization in this project, we discovered several important patterns and considerations:

### 1. Separate Resource Detection From Main Workflow

Running a dedicated resource detection process at the very beginning of the workflow provides several advantages:
- Centralizes hardware detection logic
- Makes resource information available to all subsequent processes
- Avoids redundant detection in each process
- Creates a consistent record of the execution environment

```nextflow
process detect_resources {
    publishDir "${params.output}/system", mode: 'copy'
    
    output:
    path('resources.json') into resources_ch
    
    script:
    template 'resource_detector.sh'
}

// Fan out the resource channel to all processes that need it
resources_ch.into { 
    resources_process1; 
    resources_process2;
    // etc.
}
```

### 2. Avoid Process Definition Errors

When adding input for resource files to existing processes, ensure you don't duplicate the `input:` keyword which can cause parsing errors. The correct pattern is:

```nextflow
process some_process {
    input:
    tuple val(id), path(file1), path(file2) from data_channel
    path resources from resources_channel.first()
    
    // Rest of process definition
}
```

### 3. Evaluate Resource Parameters at Runtime

Use closure syntax `{ }` rather than direct values to ensure parameters are evaluated at runtime:

```nextflow
// This works correctly - evaluated at runtime with current resource info
process dynamic_process {
    cpus { getResourceConfig(resources, 'process_name').cpus }
    memory { getResourceConfig(resources, 'process_name').memory }
    accelerator { hasGpu(resources) ? 1 : 0 }
}

// This doesn't work as expected - evaluated once at workflow parsing time
process static_process {
    cpus getResourceConfig(resources, 'process_name').cpus  // WRONG!
}
```

### 4. Use `.first()` for Resource Files

When a resource file needs to be used by multiple processes, use `.first()` on the channel to ensure the file is consumed properly:

```nextflow
input:
path resources from resources_channel.first()
```

### 5. Test on Different Environments

Create test scripts that validate the resource optimization on different environments:
- Test with and without GPU
- Test on ARM and x86 architectures
- Verify correct queue selection based on detected resources

### 6. Script-Level Checks Add Redundancy

Even with process-level resource allocation, include script-level checks for increased reliability:

```bash
# First check at process definition level
accelerator { hasGpu(resources) ? 1 : 0 }

# Second check in the script itself for redundancy
if command -v nvidia-smi &> /dev/null && [ $(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l) -gt 0 ]; then
    # GPU command
else
    # CPU fallback command
fi
```

### 7. Queue Selection Complexity

Dynamically selecting queues based on detected resources requires careful coordination with AWS Batch:
```nextflow
withName: 'gpu_process' {
    queue = { task.accelerator > 0 ? 'gpu-queue' : 'cpu-queue' }
}
```

Ensure both queues are properly configured in AWS Batch with appropriate compute environments.

### 8. Simplify Configuration Management

Structure your resource configuration to make it easy to add new architectures or process types:

```nextflow
params.resources = [
    'arm64': [
        'process1': [cpus: 4, memory: '8 GB'],
        'process2': [cpus: 8, memory: '16 GB']
    ],
    'x86_64': [
        'process1': [cpus: 8, memory: '16 GB'],
        'process2': [cpus: 16, memory: '32 GB']
    ]
]
```

This approach makes it easy to add new architecture types (e.g., 'amd64') or new process types without major code changes.