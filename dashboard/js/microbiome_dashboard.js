// MicrobiomeDashboard.js
import React, { useState, useEffect } from 'react';
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  ScatterChart,
  Scatter
} from 'recharts';

// Demo configuration
const DEMO_DURATION_MINUTES = 15;
const SAMPLE_COUNT = 100;
const GRAVITON_COST_PER_HOUR = 0.0408; // c7g.2xlarge Spot
const GPU_COST_PER_HOUR = 0.50;        // g5g.2xlarge Spot
const ON_PREM_COST = 1800;
const STANDARD_CLOUD_COST = 120;

// AWS services
const AWS = window.AWS;
AWS.config.region = 'us-east-1';

const MicrobiomeDashboard = () => {
  // State variables
  const [timeElapsed, setTimeElapsed] = useState(0);
  const [jobStatus, setJobStatus] = useState({});
  const [resourceUtilization, setResourceUtilization] = useState([]);
  const [costAccrued, setCostAccrued] = useState(0);
  const [analysisResults, setAnalysisResults] = useState(null);
  const [demoRunning, setDemoRunning] = useState(false);
  const [completedSamples, setCompletedSamples] = useState(0);
  const [activeTab, setActiveTab] = useState('progress');

  // Colors for charts
  const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884D8', 
                  '#82CA9D', '#FFCCCB', '#A569BD', '#5DADE2', '#58D68D'];
  
  // Body site colors
  const BODY_SITE_COLORS = {
    'stool': '#0088FE',       // Blue
    'buccal_mucosa': '#00C49F', // Green
    'anterior_nares': '#FFBB28', // Yellow/Orange
    'posterior_fornix': '#FF8042', // Orange/Red
    'supragingival_plaque': '#8884D8' // Purple
  };

  // Initialize demo
  useEffect(() => {
    // This would be replaced with real AWS SDK calls in production
    initializeDemo();
  }, []);

  // Simulated demo initialization
  const initializeDemo = () => {
    setJobStatus({
      status: 'INITIALIZING',
      message: 'Preparing resources...'
    });
    
    // Mock analysis results for demo
    const mockResults = {
      taxonomic_profile: {
        sample_count: 100,
        species_count: 842,
        top_species: [
          {name: "Bacteroides vulgatus", abundance: 12.8},
          {name: "Bacteroides dorei", abundance: 9.7},
          {name: "Faecalibacterium prausnitzii", abundance: 7.6},
          {name: "Escherichia coli", abundance: 5.4},
          {name: "Akkermansia muciniphila", abundance: 4.9},
          {name: "Bacteroides uniformis", abundance: 4.6},
          {name: "Eubacterium rectale", abundance: 3.9},
          {name: "Prevotella copri", abundance: 3.7},
          {name: "Roseburia intestinalis", abundance: 3.2},
          {name: "Alistipes putredinis", abundance: 2.8}
        ],
        phylum_distribution: [
          {name: "Bacteroidetes", abundance: 45.7},
          {name: "Firmicutes", abundance: 32.8},
          {name: "Proteobacteria", abundance: 12.4},
          {name: "Actinobacteria", abundance: 5.2},
          {name: "Verrucomicrobia", abundance: 3.9}
        ]
      },
      functional_profile: {
        pathway_count: 429,
        top_pathways: [
          {name: "GLYCOLYSIS", abundance: 8.2},
          {name: "PWY-6305: putrescine biosynthesis", abundance: 6.9},
          {name: "PWY-6737: starch degradation", abundance: 5.4},
          {name: "MET-SAM-PWY: methionine biosynthesis", abundance: 4.8},
          {name: "PENTOSE-P-PWY: pentose phosphate pathway", abundance: 4.3},
          {name: "PWY-5347: superpathway of L-methionine biosynthesis", abundance: 3.9},
          {name: "PWY-7221: guanosine ribonucleotides de novo biosynthesis", abundance: 3.6},
          {name: "PWY-7219: adenosine ribonucleotides de novo biosynthesis", abundance: 3.2},
          {name: "CALVIN-PWY: Calvin-Benson-Bassham cycle", abundance: 2.8}
        ]
      },
      diversity: {
        alpha: {
          shannon: {
            mean: 4.86,
            std: 0.42,
            min: 3.92,
            max: 5.74
          },
          observed_species: {
            mean: 214.6,
            std: 32.8,
            min: 142.0,
            max: 301.0
          }
        },
        beta: {
          pcoa: {
            pc1_vs_pc2: Array.from({ length: 100 }, (_, i) => {
              // Generate random clusters by body site
              const bodySites = ['stool', 'buccal_mucosa', 'anterior_nares'];
              const bodySite = bodySites[i % 3];
              
              // Generate clusters with different centers
              let x, y;
              if (bodySite === 'stool') {
                x = (Math.random() * 0.2) - 0.25;
                y = (Math.random() * 0.2) - 0.15;
              } else if (bodySite === 'buccal_mucosa') {
                x = (Math.random() * 0.2) + 0.1;
                y = (Math.random() * 0.2) + 0.1;
              } else {
                x = (Math.random() * 0.2) + 0.2;
                y = (Math.random() * 0.2) - 0.25;
              }
              
              return {
                PC1: x,
                PC2: y,
                sample: `Sample${i+1}`,
                body_site: bodySite
              };
            }),
            variance_explained: [0.32, 0.18, 0.12]
          }
        },
        by_site: {
          'stool': {
            shannon: { mean: 5.12, std: 0.32, min: 4.51, max: 5.74 },
            observed_species: { mean: 238.6, std: 28.4, min: 180.0, max: 301.0 }
          },
          'buccal_mucosa': {
            shannon: { mean: 4.62, std: 0.38, min: 3.92, max: 5.31 },
            observed_species: { mean: 198.3, std: 24.6, min: 152.0, max: 245.0 }
          },
          'anterior_nares': {
            shannon: { mean: 4.12, std: 0.41, min: 3.54, max: 4.89 },
            observed_species: { mean: 168.4, std: 22.8, min: 142.0, max: 220.0 }
          }
        }
      },
      execution_metrics: {
        cpu_hours: 50,
        gpu_hours: 10,
        wall_clock_minutes: 15,
        samples_processed: 100,
        data_processed_gb: 50
      },
      cost_analysis: {
        on_premises_cost: 1800.00,
        standard_cloud_cost: 120.00,
        optimized_aws_cost: 38.50,
        cost_savings_percent: 97.9
      }
    };
    
    // Set initial analysis results
    setAnalysisResults(mockResults);
  };

  // Start the demo
  const startDemo = () => {
    setDemoRunning(true);
    setTimeElapsed(0);
    setCompletedSamples(0);
    setCostAccrued(0);
    
    // Set initial job status
    setJobStatus({
      status: 'RUNNING',
      message: 'Processing microbiome samples...'
    });
    
    // Initialize resource utilization data
    setResourceUtilization([
      { time: 0, cpuCount: 0, cpuUtilization: 0, memoryUtilization: 0, gpuUtilization: 0 }
    ]);
  };

  // Update demo progress every second
  useEffect(() => {
    if (!demoRunning) return;
    
    const interval = setInterval(() => {
      setTimeElapsed(prev => {
        const newTime = prev + 1;
        
        // Update completed samples based on time
        if (newTime < DEMO_DURATION_MINUTES * 60 * 0.8) {
          setCompletedSamples(Math.min(
            SAMPLE_COUNT,
            Math.floor((newTime / (DEMO_DURATION_MINUTES * 60 * 0.7)) * SAMPLE_COUNT)
          ));
        } else {
          setCompletedSamples(SAMPLE_COUNT);
        }
        
        // Update cost based on resource usage
        const newCost = calculateCost(newTime);
        setCostAccrued(newCost);
        
        // Update resource utilization
        setResourceUtilization(prev => {
          const newData = [...prev];
          // Simulate resource usage pattern
          const timeMinutes = newTime / 60;
          const cpuCount = simulateCpuCount(timeMinutes);
          const cpuUtil = simulateUtilization(timeMinutes, 75, 95);
          const memUtil = simulateUtilization(timeMinutes, 60, 85);
          const gpuUtil = timeMinutes > 10 ? simulateUtilization(timeMinutes - 10, 80, 95) : 0;
          
          newData.push({
            time: timeMinutes,
            cpuCount,
            cpuUtilization: cpuUtil,
            memoryUtilization: memUtil,
            gpuUtilization: gpuUtil
          });
          
          // Keep only last 15 minutes of data
          return newData.slice(-15);
        });
        
        // End demo after specified duration
        if (newTime >= DEMO_DURATION_MINUTES * 60) {
          clearInterval(interval);
          setDemoRunning(false);
          setJobStatus({
            status: 'COMPLETED',
            message: 'Microbiome analysis completed successfully!'
          });
        }
        
        return newTime;
      });
    }, 1000);
    
    return () => clearInterval(interval);
  }, [demoRunning]);

  // Calculate demo cost
  const calculateCost = (timeSeconds) => {
    const timeHours = timeSeconds / 3600;
    const cpuTimeHours = timeHours * 50 / DEMO_DURATION_MINUTES; // Scale to total CPU hours
    const gpuTimeHours = timeHours * 10 / DEMO_DURATION_MINUTES; // Scale to total GPU hours
    
    const computeCost = cpuTimeHours * GRAVITON_COST_PER_HOUR + gpuTimeHours * GPU_COST_PER_HOUR;
    const storageCost = 0.02 * (timeSeconds / (DEMO_DURATION_MINUTES * 60));
    const transferCost = 0.01 * (timeSeconds / (DEMO_DURATION_MINUTES * 60));
    
    return computeCost + storageCost + transferCost;
  };

  // Simulate CPU instance scaling pattern
  const simulateCpuCount = (timeMinutes) => {
    if (timeMinutes < 1) return Math.floor(timeMinutes * 20);
    if (timeMinutes < 3) return Math.floor(20 + (timeMinutes - 1) * 70);
    if (timeMinutes < 8) return 160;
    if (timeMinutes < 10) return Math.floor(160 - (timeMinutes - 8) * 60);
    return Math.floor(40 - (Math.min(timeMinutes, 13) - 10) * 10);
  };

  // Simulate utilization metrics with some randomness
  const simulateUtilization = (timeMinutes, min, max) => {
    const baseUtil = min + Math.random() * (max - min);
    // Add some time-based variation
    return Math.min(100, baseUtil + Math.sin(timeMinutes) * 5);
  };

  // Format time as MM:SS
  const formatTime = (seconds) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  };

// Format cost as USD
  const formatCost = (cost) => {
    return `$${cost.toFixed(2)}`;
  };
  
  // Progress tab component
  const ProgressTab = () => (
    <div className="mt-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-2">Time Elapsed</h3>
          <div className="text-3xl font-bold">{formatTime(timeElapsed)} / {DEMO_DURATION_MINUTES}:00</div>
          <div className="h-2 w-full bg-gray-200 rounded mt-2">
            <div 
              className="h-2 bg-blue-500 rounded" 
              style={{ width: `${Math.min(100, (timeElapsed / (DEMO_DURATION_MINUTES * 60)) * 100)}%` }}
            ></div>
          </div>
        </div>
        
        <div className="p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-2">Cost Accrued</h3>
          <div className="text-3xl font-bold">{formatCost(costAccrued)}</div>
          <div className="mt-2 text-sm text-gray-500">Estimated total: {formatCost(38.50)}</div>
        </div>
      </div>
      
      <div className="mt-4 p-4 bg-white rounded shadow">
        <h3 className="text-lg font-semibold mb-2">Sample Processing</h3>
        <div className="flex justify-between mb-1">
          <span>{completedSamples} of {SAMPLE_COUNT} metagenomic samples</span>
          <span>{Math.floor((completedSamples / SAMPLE_COUNT) * 100)}%</span>
        </div>
        <div className="h-4 w-full bg-gray-200 rounded">
          <div 
            className="h-4 bg-green-500 rounded" 
            style={{ width: `${(completedSamples / SAMPLE_COUNT) * 100}%` }}
          ></div>
        </div>
      </div>
      
      <div className="mt-4 p-4 bg-white rounded shadow">
        <h3 className="text-lg font-semibold mb-4">Pipeline Progress</h3>
        <div className="space-y-4">
          <div>
            <div className="flex justify-between mb-1">
              <span>Quality Control</span>
              <span>{Math.min(100, Math.floor((timeElapsed / (DEMO_DURATION_MINUTES * 60)) * 100 * 3))}%</span>
            </div>
            <div className="h-2 w-full bg-gray-200 rounded">
              <div 
                className="h-2 bg-blue-500 rounded" 
                style={{ width: `${Math.min(100, Math.floor((timeElapsed / (DEMO_DURATION_MINUTES * 60)) * 100 * 3))}%` }}
              ></div>
            </div>
          </div>
          
          <div>
            <div className="flex justify-between mb-1">
              <span>Taxonomic Classification (GPU)</span>
              <span>{Math.max(0, Math.min(100, Math.floor(((timeElapsed - 180) / (DEMO_DURATION_MINUTES * 60)) * 100 * 5)))}%</span>
            </div>
            <div className="h-2 w-full bg-gray-200 rounded">
              <div 
                className="h-2 bg-red-500 rounded" 
                style={{ width: `${Math.max(0, Math.min(100, Math.floor(((timeElapsed - 180) / (DEMO_DURATION_MINUTES * 60)) * 100 * 5)))}%` }}
              ></div>
            </div>
          </div>
          
          <div>
            <div className="flex justify-between mb-1">
              <span>Functional Analysis</span>
              <span>{Math.max(0, Math.min(100, Math.floor(((timeElapsed - 300) / (DEMO_DURATION_MINUTES * 60)) * 100 * 4)))}%</span>
            </div>
            <div className="h-2 w-full bg-gray-200 rounded">
              <div 
                className="h-2 bg-green-500 rounded" 
                style={{ width: `${Math.max(0, Math.min(100, Math.floor(((timeElapsed - 300) / (DEMO_DURATION_MINUTES * 60)) * 100 * 4)))}%` }}
              ></div>
            </div>
          </div>
          
          <div>
            <div className="flex justify-between mb-1">
              <span>Diversity Analysis</span>
              <span>{Math.max(0, Math.min(100, Math.floor(((timeElapsed - 500) / (DEMO_DURATION_MINUTES * 60)) * 100 * 6)))}%</span>
            </div>
            <div className="h-2 w-full bg-gray-200 rounded">
              <div 
                className="h-2 bg-purple-500 rounded" 
                style={{ width: `${Math.max(0, Math.min(100, Math.floor(((timeElapsed - 500) / (DEMO_DURATION_MINUTES * 60)) * 100 * 6)))}%` }}
              ></div>
            </div>
          </div>
        </div>
      </div>
      
      <div className="mt-4 p-4 bg-white rounded shadow">
        <h3 className="text-lg font-semibold mb-4">Resource Utilization</h3>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={resourceUtilization}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="time" label={{ value: 'Time (minutes)', position: 'insideBottom', offset: -5 }} />
            <YAxis yAxisId="left" label={{ value: 'CPU Count', angle: -90, position: 'insideLeft' }} />
            <YAxis yAxisId="right" orientation="right" label={{ value: 'Utilization %', angle: -90, position: 'insideRight' }} />
            <Tooltip />
            <Legend />
            <Line yAxisId="left" type="monotone" dataKey="cpuCount" stroke="#8884d8" name="CPU Count" />
            <Line yAxisId="right" type="monotone" dataKey="cpuUtilization" stroke="#82ca9d" name="CPU Utilization %" />
            <Line yAxisId="right" type="monotone" dataKey="memoryUtilization" stroke="#ffc658" name="Memory Utilization %" />
            <Line yAxisId="right" type="monotone" dataKey="gpuUtilization" stroke="#ff8042" name="GPU Utilization %" />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
  
  // Cost analysis component
  const CostTab = () => {
    const costData = [
      { name: 'CPU (Graviton)', value: costAccrued * 0.65 },
      { name: 'GPU', value: costAccrued * 0.25 },
      { name: 'Storage', value: costAccrued * 0.07 },
      { name: 'Data Transfer', value: costAccrued * 0.03 }
    ];
    
    const costComparisonData = [
      { name: 'On-Premises', value: analysisResults?.cost_analysis?.on_premises_cost || 1800 },
      { name: 'Standard Cloud', value: analysisResults?.cost_analysis?.standard_cloud_cost || 120 },
      { name: 'Optimized Cloud', value: costAccrued > 0 ? costAccrued : (analysisResults?.cost_analysis?.optimized_aws_cost || 38.50) }
    ];
    
    const savingsPercentage = ((costComparisonData[0].value - costComparisonData[2].value) / costComparisonData[0].value * 100).toFixed(1);
    
    return (
      <div className="mt-4">
        <div className="p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-2">Cost Breakdown</h3>
          <div className="grid grid-cols-2 gap-4">
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={costData}
                  cx="50%"
                  cy="50%"
                  labelLine={true}
                  outerRadius={100}
                  fill="#8884d8"
                  dataKey="value"
                  label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
                >
                  {costData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip formatter={(value) => formatCost(value)} />
              </PieChart>
            </ResponsiveContainer>
            
            <div className="flex flex-col justify-center">
              <div className="mb-4">
                <h4 className="font-semibold">Total Cost</h4>
                <div className="text-3xl font-bold">{formatCost(costAccrued > 0 ? costAccrued : 38.50)}</div>
              </div>
              
              <div>
                <h4 className="font-semibold">Savings vs. On-Premises</h4>
                <div className="text-3xl font-bold">{savingsPercentage}%</div>
                <div className="text-sm text-gray-500">({formatCost(costComparisonData[0].value - costComparisonData[2].value)})</div>
              </div>
            </div>
          </div>
        </div>
        
        <div className="mt-4 p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-4">Cost Comparison</h3>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={costComparisonData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="name" />
              <YAxis tickFormatter={(value) => formatCost(value)} />
              <Tooltip formatter={(value) => formatCost(value)} />
              <Bar dataKey="value" fill="#8884d8" />
            </BarChart>
          </ResponsiveContainer>
        </div>
        
        <div className="mt-4 p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-2">GPU Acceleration Impact</h3>
          <div className="grid grid-cols-2 gap-4">
            <div className="p-3 bg-gray-100 rounded">
              <div className="text-sm text-gray-500">CPU-Only Classification Time</div>
              <div className="text-2xl font-bold">62 minutes</div>
            </div>
            
            <div className="p-3 bg-gray-100 rounded">
              <div className="text-sm text-gray-500">GPU-Accelerated Time</div>
              <div className="text-2xl font-bold">1 minute</div>
            </div>
          </div>
          <div className="mt-3 text-sm text-gray-600">
            Kraken2 taxonomic classification with GPU acceleration achieves a 62x speedup,
            dramatically reducing the most compute-intensive step in the pipeline.
          </div>
        </div>
      </div>
    );
  };
  
  // Results component
  const ResultsTab = () => {
    if (!analysisResults) {
      return (
        <div className="mt-4 p-4 bg-white rounded shadow">
          <div className="text-center py-10">
            <div className="text-gray-500">Analysis in progress...</div>
          </div>
        </div>
      );
    }
    
    const { taxonomic_profile, functional_profile, diversity } = analysisResults;
    
    return (
      <div className="mt-4">
        <div className="p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-4">Taxonomic Profile</h3>
          
          <div className="grid grid-cols-2 gap-4 mb-4">
            <div className="p-3 bg-gray-100 rounded">
              <div className="text-sm text-gray-500">Species Identified</div>
              <div className="text-2xl font-bold">{taxonomic_profile.species_count.toLocaleString()}</div>
            </div>
            
            <div className="p-3 bg-gray-100 rounded">
              <div className="text-sm text-gray-500">Samples Analyzed</div>
              <div className="text-2xl font-bold">{taxonomic_profile.sample_count}</div>
            </div>
          </div>
          
          <h4 className="font-semibold mb-2 mt-4">Top 10 Species</h4>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart 
              data={taxonomic_profile.top_species}
              layout="vertical"
              margin={{ top: 5, right: 30, left: 150, bottom: 5 }}
            >
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" />
              <YAxis type="category" dataKey="name" width={140} />
              <Tooltip formatter={(value) => `${value.toFixed(1)}%`} />
              <Bar dataKey="abundance" fill="#82ca9d" />
            </BarChart>
          </ResponsiveContainer>
          
          <h4 className="font-semibold mb-2 mt-6">Phylum Distribution</h4>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie
                data={taxonomic_profile.phylum_distribution}
                cx="50%"
                cy="50%"
                outerRadius={80}
                fill="#8884d8"
                dataKey="abundance"
                label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(1)}%`}
              >
                {taxonomic_profile.phylum_distribution.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip formatter={(value) => `${value.toFixed(1)}%`} />
            </PieChart>
          </ResponsiveContainer>
        </div>
        
        <div className="mt-4 p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-4">Functional Profile</h3>
          <h4 className="font-semibold mb-2">Top Metabolic Pathways</h4>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart 
              data={functional_profile.top_pathways}
              layout="vertical"
              margin={{ top: 5, right: 30, left: 150, bottom: 5 }}
            >
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" />
              <YAxis type="category" dataKey="name" width={140} />
              <Tooltip formatter={(value) => `${value.toFixed(1)}%`} />
              <Bar dataKey="abundance" fill="#8884d8" />
            </BarChart>
          </ResponsiveContainer>
        </div>
        
        <div className="mt-4 p-4 bg-white rounded shadow">
          <h3 className="text-lg font-semibold mb-4">Diversity Analysis</h3>
          
          <div className="grid grid-cols-3 gap-4 mb-4">
            {Object.entries(diversity.by_site).map(([site, metrics]) => (
              <div key={site} className="p-3 bg-gray-100 rounded">
                <div className="text-sm text-gray-500">{site.replace('_', ' ')}</div>
                <div className="text-2xl font-bold">{metrics.shannon.mean.toFixed(2)}</div>
                <div className="text-xs text-gray-500">Shannon Diversity</div>
              </div>
            ))}
          </div>
          
          <h4 className="font-semibold mb-2 mt-4">PCoA Analysis by Body Site</h4>
          <ResponsiveContainer width="100%" height={300}>
            <ScatterChart
              margin={{ top: 20, right: 20, bottom: 10, left: 10 }}
            >
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis 
                type="number" 
                dataKey="PC1" 
                name="PC1" 
                label={{ value: `PC1 (${diversity.beta.pcoa.variance_explained[0] * 100}%)`, position: 'bottom' }} 
              />
              <YAxis 
                type="number" 
                dataKey="PC2" 
                name="PC2" 
                label={{ value: `PC2 (${diversity.beta.pcoa.variance_explained[1] * 100}%)`, angle: -90, position: 'left' }} 
              />
              <Tooltip cursor={{ strokeDasharray: '3 3' }} 
                       formatter={(value, name, props) => [value.toFixed(3), name]}
                       labelFormatter={(value) => `Sample: ${value}`}
              />
              <Legend />
              
              {/* Create separate scatter series for each body site */}
              {Object.keys(BODY_SITE_COLORS).map(site => {
                const siteData = diversity.beta.pcoa.pc1_vs_pc2.filter(
                  sample => sample.body_site === site
                );
                
                return siteData.length > 0 ? (
                  <Scatter 
                    key={site}
                    name={site.replace('_', ' ')}
                    data={siteData}
                    fill={BODY_SITE_COLORS[site]}
                  />
                ) : null;
              })}
            </ScatterChart>
          </ResponsiveContainer>
          <div className="text-sm text-gray-600 mt-2">
            PCoA plot showing clear clustering of samples by body site, demonstrating that
            microbial communities are highly specific to their host environment.
          </div>
        </div>
      </div>
    );
  };
  
  return (
    <div className="container mx-auto p-4">
      <div className="bg-white rounded shadow p-4 mb-4">
        <div className="flex justify-between items-center">
          <h2 className="text-xl font-bold">AWS Microbiome Analysis Dashboard</h2>
          
          <div className="flex items-center">
            <div className={`mr-4 px-3 py-1 rounded-full ${
              jobStatus.status === 'COMPLETED' ? 'bg-green-100 text-green-800' :
              jobStatus.status === 'RUNNING' ? 'bg-blue-100 text-blue-800' :
              'bg-yellow-100 text-yellow-800'
            }`}>
              {jobStatus.status}
            </div>
            
            {!demoRunning && jobStatus.status !== 'COMPLETED' && (
              <button
                onClick={startDemo}
                className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
              >
                Start Demo
              </button>
            )}
          </div>
        </div>
        
        {jobStatus.message && (
          <div className="mt-2 text-sm text-gray-500">{jobStatus.message}</div>
        )}
      </div>
      
      <div className="bg-white rounded shadow overflow-hidden">
        <div className="flex border-b">
          <button
            className={`px-4 py-2 ${activeTab === 'progress' ? 'bg-blue-500 text-white' : 'bg-gray-100'}`}
            onClick={() => setActiveTab('progress')}
          >
            Progress
          </button>
          <button
            className={`px-4 py-2 ${activeTab === 'cost' ? 'bg-blue-500 text-white' : 'bg-gray-100'}`}
            onClick={() => setActiveTab('cost')}
          >
            Cost Analysis
          </button>
          <button
            className={`px-4 py-2 ${activeTab === 'results' ? 'bg-blue-500 text-white' : 'bg-gray-100'}`}
            onClick={() => setActiveTab('results')}
          >
            Results
          </button>
        </div>
        
        <div className="p-4">
          {activeTab === 'progress' && <ProgressTab />}
          {activeTab === 'cost' && <CostTab />}
          {activeTab === 'results' && <ResultsTab />}
        </div>
      </div>
    </div>
  );
};

export default MicrobiomeDashboard;
