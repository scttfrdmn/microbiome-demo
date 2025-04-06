# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup & Execution
- **Setup**: `./setup.sh <bucket-name> <region>`
- **Data Preparation**: `./prepare_microbiome_data.sh`
- **Run Demo**: `./start_demo.sh`
- **Test**: `./test_demo.sh`
- **Reset Demo**: `./reset_demo.sh`
- **Check Resources**: `./check_resources.sh`

### Nextflow Commands
- **Run Full Pipeline**: `nextflow run workflow/microbiome_main.nf -profile aws`
- **Run with Test Data**: `nextflow run workflow/microbiome_main.nf -profile test`
- **Run Single Process**: `nextflow run workflow/microbiome_main.nf -entry <process_name>`
- **Lint Workflow**: `nextflow lint workflow/microbiome_main.nf`

## Code Style Guidelines

- **Shell Scripts**: Use `set -e` for error handling; include descriptive section headers
- **Python**: Follow PEP 8; order imports (stdlib, external, local); use try/except blocks
- **Nextflow**: camelCase for process names; snake_case for variables; 4-space indentation
- **Variable Naming**: 
  - Data variables: descriptive of content (e.g., `fastq_files`, `kraken_results`)
  - AWS resources: prefix with `microbiome-demo-`
- **Error Handling**: Always check exit codes in shell scripts; log errors with context
- **Documentation**: Document parameters, expected outputs, and complex operations
- **Patterns**: Group data processing by analysis type (taxonomic, functional, diversity)