# Microbiome Demo Containers

This directory contains Docker container definitions for the Microbiome Demo. These containers are optimized for performance and reproducibility.

## Container Images

### 1. Base Image (`Dockerfile.base`)
- **Purpose**: Provides the foundation for all other containers
- **Contents**: Common dependencies, Miniconda, Python packages
- **Tag**: `microbiome-tools-base:latest`

### 2. Microbiome Tools Image (`Dockerfile.microbiome`)
- **Purpose**: Contains all microbiome analysis tools
- **Contents**: Kraken2, MetaPhlAn, HUMAnN, Nextflow
- **Tag**: `microbiome-tools:latest`

### 3. GPU-Accelerated Image (`Dockerfile.gpu`)
- **Purpose**: GPU-optimized container for taxonomic classification
- **Contents**: Kraken2 with GPU support, CUDA libraries
- **Tag**: `kraken2-gpu:latest`

## Building the Containers

To build all container images:

```bash
# Navigate to the containers directory
cd containers

# Build all images
./build.sh

# To build and push to a registry
./build.sh public.ecr.aws/your-registry true
```

## Container Scripts

The containers include several utility scripts:

### Entrypoint Scripts
- `entrypoint.sh`: Main container entry point
- `entrypoint_gpu.sh`: GPU container entry point

### Microbiome Scripts
- `download_kraken2_db.sh`: Downloads and prepares the Kraken2 database

### GPU Optimization
- `gpu_optimize.sh`: Configures optimal settings for GPU acceleration

## Using the Containers

### Basic Usage

```bash
# Run the microbiome tools container
docker run --rm -it microbiome-tools:latest

# Run the GPU container (with GPU passthrough)
docker run --rm --gpus all -it kraken2-gpu:latest
```

### Running Analysis

```bash
# Mount a data directory and run analysis
docker run --rm -v $(pwd)/data:/data microbiome-tools:latest \
  nextflow run main.nf --samples /data/sample_list.csv --output /data/results

# Run GPU-accelerated classification
docker run --rm --gpus all -v $(pwd)/data:/data kraken2-gpu:latest \
  kraken2 --db /reference/kraken2 --output /data/output.kraken --report /data/report.txt /data/sample.fastq
```

### Environment Variables

The containers recognize several environment variables:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`: AWS credentials
- `AWS_DEFAULT_REGION`: AWS region (default: us-east-1)
- `KRAKEN2_DB_PATH`: Path to Kraken2 database (default: /ref/kraken2)
- `METAPHLAN_DB_PATH`: Path to MetaPhlAn database (default: /ref/metaphlan)
- `HUMANN_DB_PATH`: Path to HUMAnN database (default: /ref/humann)
- `CUDA_VISIBLE_DEVICES`: GPU device selection (GPU container only)

## Performance Optimizations

These containers include several optimizations:

1. **Base image**:
   - Conda environments for dependency management
   - Python packages pre-installed for faster startup

2. **Microbiome tools**:
   - All tools pre-configured to work together
   - Reference database paths pre-configured
   - Nextflow integration

3. **GPU container**:
   - CUDA libraries and drivers included
   - GPU memory optimization settings
   - Multi-stage builds to minimize image size
   - Automatic GPU parameter tuning

## Customization

To customize the containers for your specific needs:

1. Modify the Dockerfiles as needed
2. Add additional scripts to the `scripts` directory
3. Update the build script with any new images
4. Rebuild the containers

## License

These container definitions are part of the Microbiome Demo project and are subject to the same licensing terms as the main project.