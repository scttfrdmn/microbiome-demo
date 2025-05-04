# Microbiome Demo Documentation

Welcome to the Microbiome Demo documentation. This directory contains comprehensive documentation for the 15-minute "Wow" Microbiome Demo on AWS.

## User Guide

Start with these guides to understand and use the Microbiome Demo:

1. [Getting Started](user-guide/getting-started.md) - Set up and run the demo
2. [Architecture Overview](user-guide/architecture.md) - How the demo works
3. [Cost Optimization](user-guide/cost-optimization.md) - How costs are minimized
4. [Customization Guide](user-guide/customization.md) - Adapt the demo for your needs
5. [Usage Examples](user-guide/examples.md) - Practical examples for common tasks

## Reference Documentation

For more detailed information, check these references:

- [Configuration Reference](../workflow/microbiome_nextflow.config) - Pipeline configuration
- [AWS Resources](../cloudformation.yaml) - CloudFormation template details
- [Monitoring Setup](../monitoring/README.md) - How to monitor the demo
- [Container Images](../containers/README.md) - Docker container documentation
- [Troubleshooting Guide](../TROUBLESHOOTING.md) - Solutions for common issues

## Getting Help

If you need assistance with the Microbiome Demo:

1. Check the [Troubleshooting Guide](../TROUBLESHOOTING.md) for common issues
2. Run the validation scripts for diagnostics
   ```bash
   ./validate_all.sh
   ```
3. Open an issue on the project's GitHub repository

## Contributing

We welcome contributions to improve the demo and documentation:

1. Fork the repository
2. Make your changes
3. Run the validation scripts to ensure everything works
4. Submit a pull request

## License

This project is released under the MIT License. See the [LICENSE](../LICENSE) file for details.