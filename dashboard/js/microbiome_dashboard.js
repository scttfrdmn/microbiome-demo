// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: Copyright 2025 Scott Friedman, All Rights Reserved.
//
// MicrobiomeDashboard.js
// Note: This file is retained for compatibility with older versions of the dashboard.
// The main dashboard functionality is now inline in index.html to improve loading performance.

const {
  useState, 
  useEffect,
  useRef
} = React;

// SVG icons
const DownloadIcon = () => (
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
        <polyline points="7 10 12 15 17 10"></polyline>
        <line x1="12" y1="15" x2="12" y2="3"></line>
    </svg>
);

const RefreshIcon = () => (
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="23 4 23 10 17 10"></polyline>
        <polyline points="1 20 1 14 7 14"></polyline>
        <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
    </svg>
);

// Demo configuration
const DEMO_DURATION_MINUTES = 15;
const SAMPLE_COUNT = 100;
const GRAVITON_COST_PER_HOUR = 0.0408; // c7g.2xlarge Spot
const GPU_COST_PER_HOUR = 0.50;        // g5g.2xlarge Spot
const ON_PREM_COST = 1800;
const STANDARD_CLOUD_COST = 120;

// Process real data from the Nextflow pipeline's microbiome_summary.json
const processMicrobiomeSummary = (summaryData) => {
  console.log('Processing real data from microbiome_summary.json');
  
  // Extract taxonomic profile data
  const taxonomicProfile = summaryData.taxonomic_profile || {};
  const taxonomyData = taxonomicProfile.phylum_distribution || [];
  
  // Convert to the format expected by our charts
  const formattedTaxonomyData = taxonomyData.map(item => ({
    name: item.name,
    value: Math.round(item.abundance * 100) // Convert to percentage
  }));
  
  // Extract diversity metrics
  const diversity = summaryData.diversity || {};
  
  // Extract sample counts by body site
  const bodySites = {
    stool: 0,
    anterior_nares: 0,
    buccal_mucosa: 0,
    other: 0
  };
  
  // Count samples by body site if available
  if (diversity.by_site) {
    const siteKeys = Object.keys(diversity.by_site);
    const totalSamples = taxonomicProfile.sample_count || 100;
    const samplesPerSite = Math.ceil(totalSamples / siteKeys.length);
    
    siteKeys.forEach(site => {
      if (bodySites.hasOwnProperty(site)) {
        bodySites[site] = samplesPerSite;
      } else {
        bodySites.other += samplesPerSite;
      }
    });
  }
  
  // Extract cost analysis data
  const costData = summaryData.cost_analysis || {
    on_premises_cost: 1800.00,
    standard_cloud_cost: 120.00,
    optimized_aws_cost: 38.50,
    cost_savings_percent: 97.9
  };
  
  // Extract execution metrics
  const executionMetrics = summaryData.execution_metrics || {
    cpu_hours: 10,
    gpu_hours: 2,
    wall_clock_minutes: 15,
    samples_processed: taxonomicProfile.sample_count || 100,
    data_processed_gb: 50
  };
  
  return {
    taxonomyData: formattedTaxonomyData,
    sampleCounts: bodySites,
    diversity: diversity,
    executionMetrics: executionMetrics,
    costData: {
      current: costData.optimized_aws_cost || 38.50,
      estimated: costData.optimized_aws_cost || 38.50,
      perSample: (costData.optimized_aws_cost / executionMetrics.samples_processed) || 0.385,
      comparison: {
        demo: costData.optimized_aws_cost || 38.50,
        standard: costData.standard_cloud_cost || 120.00,
        onPremises: costData.on_premises_cost || 1800.00
      }
    }
  };
};

// Generate report data for download
const generateReportData = (data) => {
  const { taxonomyData, sampleCounts, statusCounts, resourceData, costData, timeElapsed, completedSamples, status } = data;
  const reportDate = new Date().toISOString().split('T')[0];
  let report = `Microbiome Analysis Report - ${reportDate}\n`;
  report += `===================================\n\n`;
  report += `SUMMARY\n`;
  report += `-----------------\n`;
  report += `Total samples: 100\n`;
  report += `Completed samples: ${completedSamples}\n`;
  report += `Job status: ${status}\n`;
  report += `Total time elapsed: ${formatTime(timeElapsed)}\n`;
  report += `Current cost: $${costData.current.toFixed(2)}\n\n`;
  
  report += `TAXONOMY ANALYSIS\n`;
  report += `-----------------\n`;
  taxonomyData.forEach(item => {
      report += `${item.name}: ${item.value}%\n`;
  });
  report += `\n`;
  
  report += `SAMPLE DISTRIBUTION\n`;
  report += `-----------------\n`;
  Object.entries(sampleCounts).forEach(([key, value]) => {
      report += `${key.replace('_', ' ')}: ${value}\n`;
  });
  report += `\n`;
  
  report += `PROCESSING STATUS\n`;
  report += `-----------------\n`;
  Object.entries(statusCounts).forEach(([key, value]) => {
      report += `${key}: ${value}\n`;
  });
  report += `\n`;
  
  report += `RESOURCE UTILIZATION\n`;
  report += `-----------------\n`;
  report += `Last measurements:\n`;
  const lastResource = resourceData[resourceData.length - 1];
  report += `CPU: ${lastResource.cpu.toFixed(1)}%\n`;
  report += `Memory: ${lastResource.memory.toFixed(1)}%\n`;
  report += `GPU: ${lastResource.gpu.toFixed(1)}%\n\n`;
  
  report += `COST ANALYSIS\n`;
  report += `-----------------\n`;
  report += `Current cost: $${costData.current.toFixed(2)}\n`;
  report += `Estimated total: $${costData.estimated.toFixed(2)}\n`;
  report += `Cost per sample: $${costData.perSample.toFixed(3)}\n\n`;
  report += `Comparison:\n`;
  report += `This demo: $${costData.comparison.demo.toFixed(2)}\n`;
  report += `Standard cloud: $${costData.comparison.standard.toFixed(2)}\n`;
  report += `On-premises: $${costData.comparison.onPremises.toFixed(2)}\n\n`;
  
  report += `Generated by Microbiome Demo Dashboard\n`;
  
  return report;
};

// Format time as MM:SS
const formatTime = (seconds) => {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
};

// Main dashboard component
// Note: Implementation is now in index.html for faster loading
function MicrobiomeDashboard() {
  // State variables
  const [activeTab, setActiveTab] = React.useState('progress');
  const [demoRunning, setDemoRunning] = React.useState(true);
  const [completedSamples, setCompletedSamples] = React.useState(75);
  const [timeElapsed, setTimeElapsed] = React.useState(300); // 5 minutes
  const [status, setStatus] = React.useState('RUNNING');
  const [isUpdating, setIsUpdating] = React.useState(false);
  const [lastUpdated, setLastUpdated] = React.useState(new Date());
  
  // Redirect to the main dashboard
  React.useEffect(() => {
    console.log('This version is deprecated. Using enhanced dashboard in index.html');
  }, []);
  
  return (
    <div className="container">
      <div className="header">
        <h1>Microbiome Analysis Dashboard</h1>
        <p>Loading enhanced dashboard...</p>
      </div>
    </div>
  );
}

export default MicrobiomeDashboard;