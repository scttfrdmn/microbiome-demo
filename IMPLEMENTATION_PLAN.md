# Updated Microbiome Demo Implementation Plan

This document outlines the methodical approach to get the full microbiome pipeline working with real-time dashboard updates.

## Project Management Guidelines

### Commit Strategy
- **Commit Regularly**: Create focused commits after completing logical units of work
- **Descriptive Messages**: Use clear, concise commit messages that explain the why, not just the what
- **Group Related Changes**: Keep commits focused on a single feature or fix
- **Commit Structure**:
  ```
  <type>: <summary>

  <detailed description of changes>
  <explanation of why these changes were made>

  🤖 Generated with [Claude Code](https://claude.ai/code)
  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- **Types**: Use prefixes like `fix:`, `feat:`, `docs:`, `refactor:`, `test:`, `chore:`

### Testing Approach
- **Unit Tests**: Create tests for individual components
- **Integration Tests**: Test interactions between components
- **Mini-Tests**: Implement small validation tests after each significant change
- **Test Structure**:
  1. Setup test environment/data
  2. Run the component being tested
  3. Verify results match expectations
  4. Clean up test artifacts

## Current Status
- ✅ Fixed "nextflow: executable file not found in $PATH" error on ARM Graviton instances
- ✅ Created basic installer script and job definition
- ✅ Developed deployment and testing scripts
- ✅ Implemented dynamic resource optimization for ARM/x86 architectures and GPU/CPU availability
- ✅ Implemented real-time progress tracking in Nextflow workflow
- ✅ Created Lambda function for progress notifications and dashboard updates
- ✅ Implemented S3 website hosting for the dashboard
- ✅ Created real-time progress visualization dashboard with auto-refresh
- ✅ Developed comprehensive setup and testing scripts

## Phase 1: Complete ARM Compatibility Fix (Already Started)
- Finalize simple job definition for validation
  - 🧪 **Mini-Test**: Run `test_graviton_fix.sh` to verify ARM compatibility
  - 💾 **Commit**: `fix: complete ARM compatibility for Nextflow execution`
- Update scripts to ensure consistent ARM compatibility 
  - 🧪 **Mini-Test**: Execute template rendering test with `bash -c "echo 'Template test' > workflow/templates/test.txt && cat workflow/templates/test.txt"`
  - 💾 **Commit**: `fix: ensure consistent ARM compatibility in all scripts`
- Test end-to-end execution of Nextflow
  - 🧪 **Mini-Test**: Run a simplified workflow with `./nextflow run workflow/microbiome_main.nf --help`
  - 💾 **Commit**: `test: verify end-to-end Nextflow execution on ARM architecture`

## Phase 2: Full Pipeline Execution
- Implement direct S3-to-S3 transfer of reference databases
  - Create Lambda function to copy data directly from AWS Open Data Archive to the demo S3 bucket
    - 🧪 **Mini-Test**: Test Lambda locally with `python -m unittest direct_reference_data_transfer_test.py`
    - 💾 **Commit**: `feat: add Lambda function for direct S3-to-S3 data transfer`
  - Configure proper IAM roles for cross-bucket access permissions
    - 🧪 **Mini-Test**: Verify permissions with `aws iam simulate-principal-policy`
    - 💾 **Commit**: `chore: configure IAM roles for cross-bucket data transfer`
  - Ensure no data is downloaded to the user's computer during this process
    - 🧪 **Mini-Test**: Run `setup_reference_data.sh --dry-run` to verify data path
    - 💾 **Commit**: `feat: implement direct database access without local downloads`
  - Set up direct access to Kraken2 database from genome-idx S3 bucket
    - 🧪 **Mini-Test**: Run `aws s3 ls s3://genome-idx/kraken/ --request-payer requester`
    - 💾 **Commit**: `feat: add direct access to Kraken2 database from open data archive`
  - Configure MetaPhlAn and HUMAnN databases access directly from public sources
    - 🧪 **Mini-Test**: Test database URL resolution with `curl -I <database-url>`
    - 💾 **Commit**: `feat: configure direct access to MetaPhlAn and HUMAnN databases`
- Implement dynamic resource optimization for Nextflow on AWS Batch
  - Add initial resource detection process at workflow start
    - 🧪 **Mini-Test**: Run `test_resource_detection.sh` on different instance types
    - 💾 **Commit**: `feat: add resource detection process to Nextflow workflow`
  - Configure architecture-specific (ARM/x86) resource requirements
    - 🧪 **Mini-Test**: Validate config with `nextflow config -profile test`
    - 💾 **Commit**: `feat: implement architecture-specific resource profiles`
  - Implement process-specific resource allocation based on detected architecture
    - 🧪 **Mini-Test**: Run simplified test process with `test_resource_allocation.sh`
    - 💾 **Commit**: `feat: add dynamic resource allocation based on architecture`
  - Document resource requirements in configuration for user customization
    - 🧪 **Mini-Test**: Verify documentation with `grep -r "resource" docs/`
    - 💾 **Commit**: `docs: document resource optimization strategies and configuration`
- Create a production job definition that runs the full pipeline with access to these databases
  - 🧪 **Mini-Test**: Validate job definition with `aws batch register-job-definition --cli-input-json file://job-definition.json --dry-run`
  - 💾 **Commit**: `feat: create production job definition for full pipeline`
- Configure proper IAM roles for cross-service access to read from the open data archive
  - 🧪 **Mini-Test**: Test permissions with AWS CLI policy simulator
  - 💾 **Commit**: `chore: configure IAM roles for open data archive access`
- Test full pipeline execution with sample data
  - 🧪 **Mini-Test**: Execute `test_full_pipeline.sh` with small sample dataset
  - 💾 **Commit**: `test: verify full pipeline execution with sample data`

## Phase 3: Real-Time Progress Tracking (Implemented)
- ✅ Add progress tracking mechanism to Nextflow workflow (`beforeScript` and `afterScript` in each process)
  - 🧪 **Mini-Test**: Verify hooks with `grep -r "beforeScript\|afterScript" workflow/`
  - 💾 **Commit**: `feat: add progress tracking hooks to Nextflow workflow`
- ✅ Implement workflow.onComplete handler to publish final workflow status
  - 🧪 **Mini-Test**: Test handler with `nextflow run workflow/microbiome_main.nf --help`
  - 💾 **Commit**: `feat: implement workflow completion handler for status updates`
- ✅ Implement JSON-based progress metrics format with:
  - ✅ Elapsed time (actual runtime)
  - ✅ Process completion percentages
  - ✅ Accurate remaining time based on completed work
  - 🧪 **Mini-Test**: Validate JSON format with `jq . test_progress.json`
  - 💾 **Commit**: `feat: create comprehensive JSON progress metrics format`
- ✅ Create CloudFormation template for progress tracking resources
  - 🧪 **Mini-Test**: Validate template with `aws cloudformation validate-template --template-body file://progress_tracking_cf.yaml`
  - 💾 **Commit**: `infra: add CloudFormation template for progress tracking resources`
- ✅ Develop Lambda function to transform progress data for dashboard updates
  - 🧪 **Mini-Test**: Test Lambda locally with SAM or Lambda test event
  - 💾 **Commit**: `feat: implement Lambda function for progress data transformation`
- ✅ Configure S3 event notifications to trigger Lambda on progress updates
  - 🧪 **Mini-Test**: Test notifications with `aws s3api put-bucket-notification-configuration --dry-run`
  - 💾 **Commit**: `chore: configure S3 event notifications for progress updates`
- ✅ Create setup and test scripts for progress tracking
  - 🧪 **Mini-Test**: Run `test_progress_tracking.sh` in dry-run mode
  - 💾 **Commit**: `feat: add setup and test scripts for progress tracking system`

## Phase 4: Dashboard Integration (Implemented)
- ✅ Use S3 website hosting directly (no CloudFront) for faster deployment
  - 🧪 **Mini-Test**: Validate S3 website configuration with `aws s3api get-bucket-website`
  - 💾 **Commit**: `infra: configure S3 website hosting for dashboard`
- ✅ Configure proper S3 bucket CORS and website hosting settings
  - 🧪 **Mini-Test**: Test CORS with `curl -I -X OPTIONS -H "Origin: http://example.com" <bucket-url>`
  - 💾 **Commit**: `chore: set up CORS and website hosting for S3 bucket`
- ✅ Create real-time progress tracking dashboard with interactive visualizations
  - 🧪 **Mini-Test**: Validate HTML with W3C validator or local browser testing
  - 💾 **Commit**: `feat: implement real-time progress tracking dashboard`
- ✅ Implement automatic refresh using JavaScript (10 second intervals)
  - 🧪 **Mini-Test**: Verify refresh with browser developer tools network monitoring
  - 💾 **Commit**: `feat: add automatic refresh to dashboard`
- ✅ Add manual refresh capability with visual feedback
  - 🧪 **Mini-Test**: Test manual refresh functionality in browser
  - 💾 **Commit**: `feat: implement manual refresh with visual feedback`
- ✅ Create progress timeline and completion charts
  - 🧪 **Mini-Test**: Validate chart rendering with test data
  - 💾 **Commit**: `feat: add interactive progress charts to dashboard`
- ✅ Display process status with intuitive status indicators
  - 🧪 **Mini-Test**: Test status indicators with different process states
  - 💾 **Commit**: `feat: implement intuitive status indicators for processes`
- ✅ Ensure Lambda has direct write access to dashboard assets
  - 🧪 **Mini-Test**: Verify Lambda permissions with policy simulator
  - 💾 **Commit**: `chore: configure Lambda permissions for dashboard updates`
- ✅ Create setup and testing scripts for dashboard integration
  - 🧪 **Mini-Test**: Run `test_dashboard_integration.sh` in dry-run mode
  - 💾 **Commit**: `feat: add setup and test scripts for dashboard integration`

## Phase 5: Testing and Production Readiness
- Implement comprehensive error handling
  - Add try/catch blocks to all Lambda functions
    - 🧪 **Mini-Test**: Test error handling with invalid inputs
    - 💾 **Commit**: `fix: add comprehensive error handling to Lambda functions`
  - Implement graceful fallbacks in Nextflow processes
    - 🧪 **Mini-Test**: Simulate failures and verify recovery
    - 💾 **Commit**: `fix: implement graceful error handling in Nextflow processes`
  - Create error boundary for dashboard components
    - 🧪 **Mini-Test**: Test dashboard with malformed data
    - 💾 **Commit**: `fix: add error boundaries to dashboard components`
- Add alerting for pipeline failures
  - Configure SNS notifications for critical errors
    - 🧪 **Mini-Test**: Trigger test notification with `aws sns publish`
    - 💾 **Commit**: `feat: add SNS notifications for pipeline failures`
  - Implement CloudWatch alarms for workflow monitoring
    - 🧪 **Mini-Test**: Validate alarm configuration with `aws cloudwatch describe-alarms`
    - 💾 **Commit**: `feat: configure CloudWatch alarms for workflow monitoring`
  - Add dashboard alerts for failed processes
    - 🧪 **Mini-Test**: Test alert rendering with simulated failures
    - 💾 **Commit**: `feat: implement visual alerts for failed processes`
- Create detailed documentation
  - Write comprehensive README with architecture overview
    - 🧪 **Mini-Test**: Validate instructions by following them on a clean environment
    - 💾 **Commit**: `docs: create comprehensive README with architecture overview`
  - Document configuration options and customization
    - 🧪 **Mini-Test**: Verify documentation by applying sample configurations
    - 💾 **Commit**: `docs: add configuration and customization documentation`
  - Create troubleshooting guide
    - 🧪 **Mini-Test**: Validate guide by resolving common issues
    - 💾 **Commit**: `docs: add troubleshooting guide with common issues`
- Performance optimization for dashboard and pipeline
  - Optimize Lambda function execution time
    - 🧪 **Mini-Test**: Benchmark Lambda performance with test events
    - 💾 **Commit**: `perf: optimize Lambda function execution time`
  - Minimize dashboard network requests and payload size
    - 🧪 **Mini-Test**: Analyze network performance with browser dev tools
    - 💾 **Commit**: `perf: optimize dashboard network performance`
  - Implement resource-efficient Nextflow processes
    - 🧪 **Mini-Test**: Compare resource usage before and after optimization
    - 💾 **Commit**: `perf: optimize resource usage in Nextflow processes`

## Phase 6: Deployment and Maintenance
- Create master deployment script
  - Combine all setup scripts into a single master script
    - 🧪 **Mini-Test**: Run deployment with `--dry-run` flag
    - 💾 **Commit**: `feat: create comprehensive deployment script`
  - Add validation checks before deployment
    - 🧪 **Mini-Test**: Test validation with invalid configurations
    - 💾 **Commit**: `fix: add pre-deployment validation checks`
  - Create rollback mechanism for failed deployments
    - 🧪 **Mini-Test**: Simulate deployment failure and verify rollback
    - 💾 **Commit**: `feat: implement rollback mechanism for deployments`
- Implement versioning and updates
  - Add version tracking for deployed components
    - 🧪 **Mini-Test**: Verify version tracking in deployed resources
    - 💾 **Commit**: `chore: implement version tracking for components`
  - Create update script for seamless upgrades
    - 🧪 **Mini-Test**: Test updates from previous to current version
    - 💾 **Commit**: `feat: add seamless update mechanism`
  - Document upgrade procedures
    - 🧪 **Mini-Test**: Follow upgrade documentation in test environment
    - 💾 **Commit**: `docs: document upgrade procedures`
- Monitoring and maintenance
  - Setup resource utilization monitoring
    - 🧪 **Mini-Test**: Verify CloudWatch metrics collection
    - 💾 **Commit**: `feat: configure resource utilization monitoring`
  - Implement automated backups
    - 🧪 **Mini-Test**: Test backup and restore functionality
    - 💾 **Commit**: `feat: add automated backup system`
  - Create maintenance scripts for routine tasks
    - 🧪 **Mini-Test**: Verify each maintenance script operation
    - 💾 **Commit**: `feat: implement routine maintenance scripts`

## Implementation Notes
- The progress time elapsed and estimated time remaining should be based on real time from the start of the pipeline computation to its end
- Estimated time remaining should be calculated based on actual progress only from already completed work and the time it took
- Access to the web page's directory where updates are dropped should be accessible to the Lambdas directly
- No client-side hacks for transferring progress data
- Using S3 website hosting instead of CloudFront for faster demo deployment
- Use actual reference data from AWS open data archive - no placeholders or simulated data
- All data transfers must occur directly from AWS Open Data Archive to the demo S3 bucket (no transit through user's computer)
- Ensure proper IAM permissions for accessing the AWS open data resources
- Use AWS Lambda or Batch for any computation needed to prepare reference databases