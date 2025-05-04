// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
//
// dashboard_config.js - Configuration for the microbiome dashboard

// Dashboard configuration
const DASHBOARD_CONFIG = {
  // Refresh interval in milliseconds
  refreshInterval: 5000,
  
  // Data paths - these will be dynamically replaced during deployment
  dataPaths: {
    // Use relative paths for local development
    localDevelopment: {
      progress: 'data/progress.json',
      summary: 'data/summary.json',
      resources: 'data/resources.json'
    },
    
    // Production S3 paths that will be populated during deployment
    production: {
      // The base URL and bucket will be populated by start_demo.sh
      baseUrl: 'http://microbiome-demo-dashboard-1746342992.s3-website-us-east-1.amazonaws.com',
      bucketName: 'microbiome-demo-bucket-1746342697',
      
      // Real data paths from Nextflow workflow
      progress: 'status/progress.json',
      summary: 'results/summary/microbiome_summary.json',
      resources: 'monitoring/resources.json'
    }
  },
  
  // Environment - set to 'production' to use real data from S3
  // Will be populated during deployment
  environment: 'production',
  
  // Flag to enable debugging
  debug: true,
  
  // Get the appropriate data URL based on environment
  getDataUrl: function(fileType) {
    // IMPORTANT: For both production and development
    // use the local paths - the data will be copied from
    // the real pipeline output to the dashboard bucket
    return this.dataPaths.localDevelopment[fileType];
  }
};

// Export the configuration
if (typeof module !== 'undefined') {
  module.exports = DASHBOARD_CONFIG;
}