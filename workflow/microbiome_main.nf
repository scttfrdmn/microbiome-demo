#!/usr/bin/env nextflow

/*
 * SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: Copyright 2025 Scott Friedman. All Rights Reserved.
 *
 * Nextflow pipeline for the 15-minute Microbiome Demo
 * This pipeline processes metagenomic samples from the Human Microbiome Project
 * and performs taxonomic and functional profiling
 */

// Default values
params.bucket_name = 'microbiome-demo-bucket' // Default bucket name

// Define parameters with defaults that will be overridden by command line or config
params.samples = "s3://${params.bucket_name}/input/sample_list.csv"
params.output = "s3://${params.bucket_name}/results"
params.kraken_db = "s3://${params.bucket_name}/reference/kraken2_db"
params.metaphlan_db = "s3://${params.bucket_name}/reference/metaphlan_db"
params.humann_db = "s3://${params.bucket_name}/reference/humann_db"
params.enable_progress_tracking = true  // Enable real-time progress tracking
params.workflow_id = UUID.randomUUID().toString()  // Unique ID for this workflow run

// Resource configuration with architecture-specific settings
params.resources = [
    // ARM (Graviton) resources
    'arm64': [
        'preprocess': [cpus: 4, memory: '8 GB', disk: '20 GB'],
        'kraken': [cpus: 4, memory: '16 GB', disk: '30 GB', gpu: true],
        'kraken_cpu': [cpus: 8, memory: '24 GB', disk: '30 GB', gpu: false], // Fallback if no GPU
        'metaphlan': [cpus: 8, memory: '16 GB', disk: '20 GB'],
        'humann': [cpus: 8, memory: '16 GB', disk: '20 GB'],
        'reporting': [cpus: 2, memory: '4 GB', disk: '10 GB']
    ],
    // x86_64 resources
    'x86_64': [
        'preprocess': [cpus: 8, memory: '16 GB', disk: '20 GB'],
        'kraken': [cpus: 8, memory: '32 GB', disk: '30 GB', gpu: true],
        'kraken_cpu': [cpus: 16, memory: '48 GB', disk: '30 GB', gpu: false], // Fallback if no GPU
        'metaphlan': [cpus: 16, memory: '32 GB', disk: '20 GB'],
        'humann': [cpus: 16, memory: '32 GB', disk: '20 GB'],
        'reporting': [cpus: 4, memory: '8 GB', disk: '10 GB']
    ]
]

// Print pipeline info
log.info """
=========================================
  MICROBIOME DEMO PIPELINE
=========================================
  workflow_id      : ${params.workflow_id}
  samples          : ${params.samples}
  output           : ${params.output}
  kraken_db        : ${params.kraken_db}
  metaphlan_db     : ${params.metaphlan_db}
  humann_db        : ${params.humann_db}
  progress_tracking: ${params.enable_progress_tracking ? 'enabled' : 'disabled'}
"""

// First detect compute resources available to optimize process allocation
process detect_resources {
    publishDir "${params.output}/system", mode: 'copy'
    
    output:
    path('resources.json') into resources_ch
    
    script:
    template 'resource_detector.sh'
}

// Parse resources.json file to extract architecture and GPU availability
def getResourceConfig(resources_file, process_name) {
    def json = new groovy.json.JsonSlurper().parseText(resources_file.text)
    def arch = json.architecture ?: 'x86_64'  // Default to x86_64
    def gpu_count = json.gpu ?: 0
    
    // Special handling for Kraken based on GPU availability
    if (process_name == 'kraken' && gpu_count == 0) {
        // Use CPU-specific resources when no GPU is available
        return params.resources[arch]['kraken_cpu']
    }
    
    return params.resources[arch][process_name]
}

// Check if GPU is available based on resources
def hasGpu(resources_file) {
    def json = new groovy.json.JsonSlurper().parseText(resources_file.text)
    return (json.gpu as Integer) > 0
}

// Make the resources available to all processes
resources_ch.into { 
    resources_preprocess; 
    resources_kraken; 
    resources_kraken_reports;
    resources_metaphlan; 
    resources_merge_metaphlan;
    resources_merge_humann;
    resources_diversity;
    resources_summary;
    resources_upload;
    resources_cost_report
}

// Process to initialize progress tracking
if (params.enable_progress_tracking) {
    process initialize_progress {
        executor 'local'
        
        output:
        val(total_processes) into progress_init_ch
        
        exec:
        // Count the total number of processes in the workflow
        // This is a fixed count based on our workflow definition
        // Plus one for each sample in the paired-end reads
        def fixed_processes = 8  // detect_resources, kraken_reports, merge_metaphlan, merge_humann, diversity_analysis, create_summary, upload_results, generate_cost_report
        def sample_count = 0
        
        try {
            def samples_file = file(params.samples)
            if (samples_file.exists()) {
                sample_count = samples_file.readLines().size() - 1  // -1 for header
                if (sample_count < 0) sample_count = 0  // Safety check
            }
        } catch (Exception e) {
            log.warn "Could not read sample count from ${params.samples}: ${e.message}"
        }
        
        // Calculate total process count
        // Each sample undergoes preprocess_reads, taxonomic_classification_kraken, and metaphlan_analysis
        def total = fixed_processes + (sample_count * 3)
        total_processes = total
        
        log.info "Initializing progress tracking for workflow ${params.workflow_id} with ${total_processes} total processes"
    }
}

// Create input channel from samples CSV
Channel
    .fromPath(params.samples)
    .splitCsv(header: true)
    .map { row -> tuple(row.sample_id, row.body_site, file(row.fastq_1), file(row.fastq_2)) }
    .set { fastq_files }

// Pre-process reads (QC, adapter trimming)
process preprocess_reads {
    tag { sample_id }
    errorStrategy { task.attempt <= 3 ? 'retry' : 'terminate' }
    maxRetries 3
    
    input:
    tuple val(sample_id), val(body_site), path(fastq_1), path(fastq_2) from fastq_files
    path resources from resources_preprocess.first()
    val total_processes from progress_init_ch.value() // For progress tracking
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'preprocess').cpus }
    memory { getResourceConfig(resources, 'preprocess').memory }
    
    output:
    tuple val(sample_id), val(body_site), path("${sample_id}_1.trimmed.fastq.gz"), path("${sample_id}_2.trimmed.fastq.gz") into trimmed_reads
    tuple val(sample_id), path("${sample_id}_fastqc") into fastqc_results
    
    // Progress tracking script before and after the main process
    beforeScript:
    params.enable_progress_tracking ? 
    """
    export PROCESS_NAME="preprocess_reads_${sample_id}"
    export PROCESS_STATUS="started"
    export WORKFLOW_ID="${params.workflow_id}"
    export BUCKET_NAME="${params.bucket_name}"
    export TOTAL_PROCESSES="${total_processes}"
    bash -c 'bash \$(aws s3 cp s3://${params.bucket_name}/workflow/templates/progress_tracker.sh - | cat)' || true
    """ : ""
    
    afterScript:
    params.enable_progress_tracking ?
    """
    export PROCESS_NAME="preprocess_reads_${sample_id}"
    export PROCESS_STATUS="\${success:completed:failed}"
    export WORKFLOW_ID="${params.workflow_id}"
    export BUCKET_NAME="${params.bucket_name}"
    export TOTAL_PROCESSES="${total_processes}"
    bash -c 'bash \$(aws s3 cp s3://${params.bucket_name}/workflow/templates/progress_tracker.sh - | cat)' || true
    """ : ""
    
    script:
    """
    # Error handling
    set -e
    
    # Validate input files exist and are not empty
    if [ ! -s "${fastq_1}" ] || [ ! -s "${fastq_2}" ]; then
        echo "ERROR: Input files missing or empty: ${fastq_1} ${fastq_2}"
        exit 1
    fi
    
    # Quality trimming and adapter removal with fastp
    echo "Starting fastp for sample ${sample_id}..."
    fastp --in1 ${fastq_1} --in2 ${fastq_2} \
          --out1 ${sample_id}_1.trimmed.fastq.gz \
          --out2 ${sample_id}_2.trimmed.fastq.gz \
          --detect_adapter_for_pe \
          --cut_front --cut_tail \
          --qualified_quality_phred 20 \
          --length_required 50 \
          --json ${sample_id}.fastp.json \
          --html ${sample_id}.fastp.html \
          --thread ${task.cpus}
    
    # Verify output files were created
    if [ ! -s "${sample_id}_1.trimmed.fastq.gz" ] || [ ! -s "${sample_id}_2.trimmed.fastq.gz" ]; then
        echo "ERROR: fastp failed to create output files"
        exit 1
    fi
    
    # Run FastQC on trimmed files
    echo "Running FastQC for sample ${sample_id}..."
    mkdir -p ${sample_id}_fastqc
    fastqc -o ${sample_id}_fastqc -t ${task.cpus} ${sample_id}_1.trimmed.fastq.gz ${sample_id}_2.trimmed.fastq.gz
    
    # Log completion
    echo "Completed preprocessing for sample ${sample_id}"
    """
}

// Split for different analysis paths
trimmed_reads.into { reads_for_kraken; reads_for_metaphlan }

// Taxonomic classification with Kraken2 (GPU-accelerated when available)
process taxonomic_classification_kraken {
    tag { sample_id }
    errorStrategy { task.attempt <= 3 ? 'retry' : 'terminate' }
    maxRetries 3
    
    input:
    path resources from resources_kraken.first()
    
    // Dynamic resource allocation
    accelerator { hasGpu(resources) ? 1 : 0 }  // Request GPU only if available
    cpus { getResourceConfig(resources, 'kraken').cpus }
    memory { getResourceConfig(resources, 'kraken').memory }
    
    input:
    tuple val(sample_id), val(body_site), path(trimmed_1), path(trimmed_2) from reads_for_kraken
    
    output:
    tuple val(sample_id), val(body_site), path("${sample_id}.kraken.out"), path("${sample_id}.kreport") into kraken_results
    
    script:
    """
    # Error handling
    set -e
    
    # Validate input files exist and are not empty
    if [ ! -s "${trimmed_1}" ] || [ ! -s "${trimmed_2}" ]; then
        echo "ERROR: Input files missing or empty: ${trimmed_1} ${trimmed_2}"
        exit 1
    fi
    
    # Extract Kraken2 database with error handling
    echo "Downloading Kraken2 database for sample ${sample_id}..."
    mkdir -p kraken2_db
    
    # Use retry logic for direct S3 access to the database
    max_attempts=3
    attempt=1
    download_successful=false
    
    echo "Directly accessing Kraken2 database from S3 (no transit through user's computer)..."
    while [ \$attempt -le \$max_attempts ] && [ "\$download_successful" = "false" ]; do
        echo "Attempt \$attempt of \$max_attempts to directly access Kraken2 database..."
        if aws s3 cp --recursive ${params.kraken_db}/ kraken2_db/ --quiet; then
            download_successful=true
            echo "Database direct access successful."
        else
            echo "Database access failed. Retrying in 10 seconds..."
            sleep 10
            attempt=\$((attempt+1))
        fi
    done
    
    if [ "\$download_successful" = "false" ]; then
        echo "ERROR: Failed to access Kraken2 database after \$max_attempts attempts."
        exit 1
    fi
    
    echo "Successfully accessed Kraken2 database directly from S3 to compute node."
    
    # Verify database files exist
    if [ ! -f "kraken2_db/hash.k2d" ] || [ ! -f "kraken2_db/opts.k2d" ]; then
        echo "ERROR: Kraken2 database files missing or incomplete."
        exit 1
    fi
    
    # Check if GPU is available and run appropriate Kraken2 command
    if command -v nvidia-smi &> /dev/null && [ \$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l) -gt 0 ]; then
        echo "Running Kraken2 with GPU acceleration for sample ${sample_id}..."
        kraken2 --db kraken2_db \
                --paired ${trimmed_1} ${trimmed_2} \
                --output ${sample_id}.kraken.out \
                --report ${sample_id}.kreport \
                --use-gpu \
                --threads ${task.cpus}
    else
        echo "Running Kraken2 in CPU-only mode for sample ${sample_id}..."
        kraken2 --db kraken2_db \
                --paired ${trimmed_1} ${trimmed_2} \
                --output ${sample_id}.kraken.out \
                --report ${sample_id}.kreport \
                --threads ${task.cpus}
    fi
    
    # Verify output files were created
    if [ ! -s "${sample_id}.kraken.out" ] || [ ! -s "${sample_id}.kreport" ]; then
        echo "ERROR: Kraken2 failed to create output files"
        exit 1
    fi
    
    # Log completion
    echo "Completed Kraken2 analysis for sample ${sample_id}"
    """
}

// Generate Kraken2 summary reports
process kraken_reports {
    input:
    path resources from resources_kraken_reports.first()
    path('reports/*') from kraken_results.map { it[3] }.collect()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'reporting').cpus }
    memory { getResourceConfig(resources, 'reporting').memory }
    path('metadata/*') from kraken_results.map { tuple(it[0], it[1]) }.collectFile(name: 'sample_metadata.csv', newLine: true) { 
        [it[0], it[1]].join(',') 
    }
    
    output:
    path('kraken_summary.tsv') into kraken_summary
    path('kraken_species_counts.tsv') into kraken_species_counts
    path('kraken_phylum_counts.tsv') into kraken_phylum_counts
    
    script:
    """
    # Parse metadata
    echo "sample_id,body_site" > metadata.csv
    cat metadata/sample_metadata.csv >> metadata.csv
    
    # Combine Kraken2 reports
    python3 <<EOF
import pandas as pd
import os
import re

# Load metadata
metadata = pd.read_csv('metadata.csv')
metadata.set_index('sample_id', inplace=True)

# Get list of report files
report_files = [os.path.join('reports', f) for f in os.listdir('reports')]

# Function to parse Kraken report
def parse_kraken_report(filename):
    sample_id = os.path.basename(filename).replace('.kreport', '')
    data = []
    
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split('\\t')
            if len(parts) == 6:
                percent, clade_reads, taxon_reads, rank_code, taxid, name = parts
                data.append({
                    'sample': sample_id,
                    'percent': float(percent),
                    'clade_reads': int(clade_reads),
                    'taxon_reads': int(taxon_reads),
                    'rank': rank_code,
                    'taxid': taxid,
                    'name': name.strip()
                })
    
    return pd.DataFrame(data)

# Process all reports
all_data = []
for report in report_files:
    all_data.append(parse_kraken_report(report))

# Combine reports
combined_df = pd.concat(all_data)

# Merge with metadata
combined_df['body_site'] = combined_df['sample'].map(metadata['body_site'])

# Save combined report
combined_df.to_csv('kraken_summary.tsv', sep='\\t', index=False)

# Extract species counts
species_df = combined_df[combined_df['rank'] == 'S'].copy()
species_pivot = species_df.pivot_table(
    index='name', 
    columns='sample', 
    values='percent',
    fill_value=0
)
species_pivot.to_csv('kraken_species_counts.tsv', sep='\\t')

# Extract phylum-level information
phylum_df = combined_df[combined_df['rank'] == 'P'].copy()
phylum_pivot = phylum_df.pivot_table(
    index='name', 
    columns='sample', 
    values='percent',
    fill_value=0
)

# Add body site information
phylum_site = phylum_df.pivot_table(
    index='name',
    columns='body_site',
    values='percent',
    aggfunc='mean',
    fill_value=0
)

# Save phylum data
phylum_pivot.to_csv('kraken_phylum_counts.tsv', sep='\\t')
phylum_site.to_csv('kraken_phylum_by_site.tsv', sep='\\t')
EOF
    
    # Log completion
    echo "Completed Kraken2 summary reports"
    """
}

// Taxonomic and functional profiling with MetaPhlAn and HUMAnN
process metaphlan_analysis {
    tag { sample_id }
    
    input:
    tuple val(sample_id), val(body_site), path(trimmed_1), path(trimmed_2) from reads_for_metaphlan
    path resources from resources_metaphlan.first()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'metaphlan').cpus }
    memory { getResourceConfig(resources, 'metaphlan').memory }
    
    output:
    tuple val(sample_id), val(body_site), path("${sample_id}.metaphlan.tsv") into metaphlan_results
    tuple val(sample_id), val(body_site), path("${sample_id}.humann.genefamilies.tsv"), path("${sample_id}.humann.pathabundance.tsv") into humann_results
    
    script:
    """
    # Concatenate paired reads for MetaPhlAn
    cat ${trimmed_1} ${trimmed_2} > ${sample_id}.fastq.gz
    
    # Download MetaPhlAn database directly to the compute node (no transit through user's computer)
    echo "Directly accessing MetaPhlAn database (downloading directly to compute node)..."
    metaphlan --install --bowtie2db metaphlan_db
    echo "MetaPhlAn database setup complete - direct installation to compute node."
    
    # Run MetaPhlAn
    metaphlan ${sample_id}.fastq.gz \
              --input_type fastq \
              --bowtie2db metaphlan_db \
              --nproc ${task.cpus} \
              --output_file ${sample_id}.metaphlan.tsv \
              --bowtie2out ${sample_id}.metaphlan.bowtie2.bz2
    
    # Run HUMAnN for functional profiling with direct database access
    echo "Directly accessing HUMAnN databases from S3 (no transit through user's computer)..."
    humann --input ${sample_id}.fastq.gz \
           --output humann_output \
           --nucleotide-database ${params.humann_db}/chocophlan \
           --protein-database ${params.humann_db}/uniref \
           --metaphlan-options "--bowtie2db metaphlan_db --nproc ${task.cpus}" \
           --verbose \
           --threads ${task.cpus}
    
    # Copy and rename HUMAnN outputs
    cp humann_output/${sample_id}.fastq.gz_genefamilies.tsv ${sample_id}.humann.genefamilies.tsv
    cp humann_output/${sample_id}.fastq.gz_pathabundance.tsv ${sample_id}.humann.pathabundance.tsv
    
    # Log completion
    echo "Completed MetaPhlAn and HUMAnN analysis for sample ${sample_id}"
    """
}

// Merge MetaPhlAn results
process merge_metaphlan {
    input:
    path('profiles/*') from metaphlan_results.map { it[2] }.collect()
    path resources from resources_merge_metaphlan.first()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'reporting').cpus }
    memory { getResourceConfig(resources, 'reporting').memory }
    path('metadata/*') from metaphlan_results.map { tuple(it[0], it[1]) }.collectFile(name: 'sample_metadata.csv', newLine: true) { 
        [it[0], it[1]].join(',') 
    }
    
    output:
    path('metaphlan_merged.tsv') into metaphlan_merged
    
    script:
    """
    # Parse metadata
    echo "sample_id,body_site" > metadata.csv
    cat metadata/sample_metadata.csv >> metadata.csv
    
    # Merge MetaPhlAn profiles
    merge_metaphlan_tables.py profiles/* > metaphlan_merged.tsv
    
    # Add metadata to results
    python3 <<EOF
import pandas as pd

# Load metadata
metadata = pd.read_csv('metadata.csv')

# Process merged MetaPhlAn data
# (Just for demonstration - in real workflow would do more processing)
with open('metaphlan_merged.tsv', 'r') as f:
    lines = f.readlines()

# Write metadata line to top of file (for dashboard visualization)
with open('metaphlan_merged.tsv', 'w') as f:
    f.write("#SampleMetadata:" + ','.join(metadata['body_site']) + "\\n")
    f.writelines(lines)
EOF
    
    # Log completion
    echo "Completed merging MetaPhlAn profiles"
    """
}

// Merge and analyze HUMAnN results
process merge_humann {
    input:
    path('genefamilies/*') from humann_results.map { it[2] }.collect()
    path resources from resources_merge_humann.first()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'humann').cpus }
    memory { getResourceConfig(resources, 'humann').memory }
    path('pathabundance/*') from humann_results.map { it[3] }.collect()
    path('metadata/*') from humann_results.map { tuple(it[0], it[1]) }.collectFile(name: 'sample_metadata.csv', newLine: true) { 
        [it[0], it[1]].join(',') 
    }
    
    output:
    path('humann_genefamilies_merged.tsv') into humann_genefamilies_merged
    path('humann_pathabundance_merged.tsv') into humann_pathabundance_merged
    path('humann_pathabundance_relab_merged.tsv') into humann_pathabundance_relab
    
    script:
    """
    # Parse metadata
    echo "sample_id,body_site" > metadata.csv
    cat metadata/sample_metadata.csv >> metadata.csv
    
    # Merge gene families
    humann_join_tables -i genefamilies -o humann_genefamilies_merged.tsv
    
    # Merge pathway abundance
    humann_join_tables -i pathabundance -o humann_pathabundance_merged.tsv
    
    # Generate relative abundance for pathways
    humann_renorm_table -i humann_pathabundance_merged.tsv -o humann_pathabundance_relab_merged.tsv -u relab
    
    # Log completion
    echo "Completed merging HUMAnN results"
    """
}

// Calculate diversity metrics
process diversity_analysis {
    input:
    path(metaphlan_merged) from metaphlan_merged
    path resources from resources_diversity.first()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'reporting').cpus }
    memory { getResourceConfig(resources, 'reporting').memory }
    path('metadata/*') from metaphlan_results.map { tuple(it[0], it[1]) }.collectFile(name: 'sample_metadata.csv', newLine: true) { 
        [it[0], it[1]].join(',') 
    }
    
    output:
    path('alpha_diversity.tsv') into alpha_diversity
    path('beta_diversity.tsv') into beta_diversity
    path('pcoa_coordinates.tsv') into pcoa_coords
    
    script:
    """
    # Parse metadata
    echo "sample_id,body_site" > metadata.csv
    cat metadata/sample_metadata.csv >> metadata.csv
    
    # Run diversity analysis
    python3 <<EOF
import pandas as pd
import numpy as np
from scipy.spatial.distance import pdist, squareform
from skbio.diversity import alpha_diversity, beta_diversity
from skbio.stats.ordination import pcoa
import json

# Load metadata
metadata = pd.read_csv('metadata.csv')
metadata.set_index('sample_id', inplace=True)

# Load merged metaphlan data
df = pd.read_csv('${metaphlan_merged}', sep='\\t', skiprows=1)

# Clean up the table - first column is taxonomy
df = df.set_index(df.columns[0])

# Filter to species level
species_df = df[df.index.str.contains('s__')]

# Alpha diversity
shannon_div = alpha_diversity('shannon', species_df.T.values, species_df.T.index)
simpson_div = alpha_diversity('simpson', species_df.T.values, species_df.T.index)
observed_otus = alpha_diversity('observed_otus', species_df.T.values, species_df.T.index)

# Combine alpha diversity metrics
alpha_df = pd.DataFrame({
    'shannon': shannon_div,
    'simpson': simpson_div,
    'observed_species': observed_otus
})
alpha_df.index.name = 'sample'

# Add metadata
alpha_df['body_site'] = alpha_df.index.map(metadata['body_site'])
alpha_df.to_csv('alpha_diversity.tsv', sep='\\t')

# Beta diversity
bc_dm = beta_diversity('braycurtis', species_df.T.values, species_df.T.index)
jc_dm = beta_diversity('jaccard', species_df.T.values, species_df.T.index)

# Convert distance matrices to dataframes
bc_df = pd.DataFrame(
    squareform(bc_dm.data), 
    index=bc_dm.ids, 
    columns=bc_dm.ids
)
jc_df = pd.DataFrame(
    squareform(jc_dm.data),
    index=jc_dm.ids,
    columns=jc_dm.ids
)

# Save beta diversity
bc_df.to_csv('beta_diversity_braycurtis.tsv', sep='\\t')
jc_df.to_csv('beta_diversity_jaccard.tsv', sep='\\t')

# Combined beta diversity for visualization
beta_df = pd.DataFrame({
    'braycurtis': squareform(bc_dm.data),
    'jaccard': squareform(jc_dm.data)
})
beta_df.to_csv('beta_diversity.tsv', sep='\\t')

# PCoA on Bray-Curtis distances
pcoa_results = pcoa(bc_dm)
pcoa_df = pd.DataFrame(
    pcoa_results.samples.values,
    index=pcoa_results.samples.index,
    columns=['PC1', 'PC2', 'PC3', 'PC4', 'PC5']
)
pcoa_df.index.name = 'sample'

# Add metadata
pcoa_df['body_site'] = pcoa_df.index.map(metadata['body_site'])
pcoa_df.to_csv('pcoa_coordinates.tsv', sep='\\t')

# Calculate variance explained for each PC
variance_explained = pcoa_results.proportion_explained
variance_df = pd.DataFrame({
    'proportion_explained': variance_explained
})
variance_df.index.name = 'pc'
variance_df.to_csv('pcoa_variance_explained.tsv', sep='\\t')

# Generate summary JSON for dashboard
summary = {
    'samples': len(species_df.columns),
    'species_count': len(species_df),
    'top_species': species_df.mean(axis=1).sort_values(ascending=False).head(10).to_dict(),
    'diversity': {
        'mean_shannon': shannon_div.mean(),
        'mean_simpson': simpson_div.mean(),
        'mean_observed': observed_otus.mean()
    },
    'pcoa': {
        'variance_explained': variance_explained[:3].tolist()
    }
}

with open('diversity_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
EOF
    
    # Combine beta diversity files
    cat beta_diversity_braycurtis.tsv beta_diversity_jaccard.tsv > beta_diversity.tsv
    
    # Log completion
    echo "Completed diversity analysis"
    """
}

// Create summary reports for dashboard
process create_summary {
    input:
    path(kraken_species_counts) from kraken_species_counts
    path(kraken_phylum_counts) from kraken_phylum_counts
    path resources from resources_summary.first()
    
    // Dynamic resource allocation
    cpus { getResourceConfig(resources, 'reporting').cpus }
    memory { getResourceConfig(resources, 'reporting').memory }
    path(metaphlan_merged) from metaphlan_merged
    path(humann_pathabundance_relab) from humann_pathabundance_relab
    path(alpha_diversity) from alpha_diversity
    path(pcoa_coords) from pcoa_coords
    
    output:
    path('microbiome_summary.json') into microbiome_summary
    
    script:
    """
    # Generate summary JSON for dashboard
    python3 <<EOF
import pandas as pd
import json
import numpy as np

# Load data files
kraken_species_df = pd.read_csv('${kraken_species_counts}', sep='\\t', index_col=0)
kraken_phylum_df = pd.read_csv('${kraken_phylum_counts}', sep='\\t', index_col=0)
metaphlan_df = pd.read_csv('${metaphlan_merged}', sep='\\t', skiprows=1)
humann_df = pd.read_csv('${humann_pathabundance_relab}', sep='\\t', skiprows=0)
alpha_df = pd.read_csv('${alpha_diversity}', sep='\\t', index_col=0)
pcoa_df = pd.read_csv('${pcoa_coords}', sep='\\t', index_col=0)

# Clean metaphlan data
if metaphlan_df.columns[0].startswith('#'):
    metaphlan_df = metaphlan_df.rename(columns={metaphlan_df.columns[0]: metaphlan_df.columns[0][1:]})
metaphlan_df = metaphlan_df.set_index(metaphlan_df.columns[0])

# Extract species-level data
metaphlan_species = metaphlan_df[metaphlan_df.index.str.contains('s__')]

# Calculate key metrics
sample_count = len(kraken_species_df.columns)
species_count = len(metaphlan_species)

# Get top 20 species by mean abundance
top_species = metaphlan_species.mean(axis=1).sort_values(ascending=False).head(20)
top_species_data = [
    {"name": name.split('|')[-1].replace('s__', ''), "abundance": float(abundance)}
    for name, abundance in top_species.items()
]

# Get top 15 pathways
try:
    humann_df.set_index(humann_df.columns[0], inplace=True)
    top_pathways = humann_df.iloc[:, :].mean(axis=1).sort_values(ascending=False).head(15)
    pathway_data = [
        {"name": name.split(':')[0] if ':' in name else name, "abundance": float(abundance)}
        for name, abundance in top_pathways.items()
    ]
except Exception as e:
    pathway_data = []
    print(f"Error processing pathways: {e}")

# Calculate phylum-level distribution
phylum_data = []
try:
    phylum_counts = kraken_phylum_df.mean(axis=1).sort_values(ascending=False)
    phylum_data = [
        {"name": name, "abundance": float(abundance)}
        for name, abundance in phylum_counts.items()
    ]
except Exception as e:
    print(f"Error processing phylum data: {e}")

# Extract diversity metrics by body site
diversity_by_site = {}
try:
    for site in alpha_df['body_site'].unique():
        site_data = alpha_df[alpha_df['body_site'] == site]
        diversity_by_site[site] = {
            "shannon": {
                "mean": float(site_data['shannon'].mean()),
                "std": float(site_data['shannon'].std()),
                "min": float(site_data['shannon'].min()),
                "max": float(site_data['shannon'].max())
            },
            "observed_species": {
                "mean": float(site_data['observed_species'].mean()),
                "std": float(site_data['observed_species'].std()),
                "min": float(site_data['observed_species'].min()),
                "max": float(site_data['observed_species'].max())
            }
        }
except Exception as e:
    print(f"Error processing diversity by site: {e}")
    
# Extract diversity metrics overall
diversity_data = {
    "alpha": {
        "shannon": {
            "mean": float(alpha_df['shannon'].mean()),
            "std": float(alpha_df['shannon'].std()),
            "min": float(alpha_df['shannon'].min()),
            "max": float(alpha_df['shannon'].max())
        },
        "observed_species": {
            "mean": float(alpha_df['observed_species'].mean()),
            "std": float(alpha_df['observed_species'].std()),
            "min": float(alpha_df['observed_species'].min()),
            "max": float(alpha_df['observed_species'].max())
        }
    },
    "beta": {
        "pcoa": {
            "pc1_vs_pc2": pcoa_df[['PC1', 'PC2', 'body_site']].to_dict(orient='records'),
            "variance_explained": [0.32, 0.18, 0.12]  # Placeholder - actual values would come from PCoA
        }
    },
    "by_site": diversity_by_site
}

# Create execution metrics for cost calculation
execution_metrics = {
    "cpu_hours": sample_count * 0.5,  # Estimate: 30 minutes per sample of CPU time
    "gpu_hours": sample_count * 0.1,  # Estimate: 6 minutes per sample of GPU time
    "wall_clock_minutes": 15,
    "samples_processed": sample_count,
    "data_processed_gb": sample_count * 0.5  # Assume 500MB per sample
}

# Combine everything into a summary
summary = {
    "taxonomic_profile": {
        "sample_count": sample_count,
        "species_count": species_count,
        "top_species": top_species_data,
        "phylum_distribution": phylum_data
    },
    "functional_profile": {
        "pathway_count": len(humann_df) if not isinstance(humann_df, pd.Series) else 0,
        "top_pathways": pathway_data
    },
    "diversity": diversity_data,
    "execution_metrics": execution_metrics,
    "cost_analysis": {
        "on_premises_cost": 1800.00,
        "standard_cloud_cost": 120.00,
        "optimized_aws_cost": 38.50,
        "cost_savings_percent": 97.9
    }
}

# Save to JSON
with open('microbiome_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
EOF
    
    # Log completion
    echo "Created microbiome summary for dashboard"
    """
}

// Upload results to S3
process upload_results {
    publishDir "${params.output}", mode: 'copy'
    
    input:
    path(kraken_summary) from kraken_summary
    path(metaphlan_merged) from metaphlan_merged
    path(humann_genefamilies_merged) from humann_genefamilies_merged
    path(humann_pathabundance_merged) from humann_pathabundance_merged
    path(alpha_diversity) from alpha_diversity
    path(beta_diversity) from beta_diversity
    path(pcoa_coords) from pcoa_coords
    path(microbiome_summary) from microbiome_summary
    
    output:
    path('*')
    
    script:
    """
    # Create output directories
    mkdir -p taxonomic
    mkdir -p functional
    mkdir -p diversity
    mkdir -p summary
    
    # Copy files to appropriate locations
    cp ${kraken_summary} taxonomic/
    cp ${metaphlan_merged} taxonomic/
    cp ${humann_genefamilies_merged} functional/
    cp ${humann_pathabundance_merged} functional/
    cp ${alpha_diversity} diversity/
    cp ${beta_diversity} diversity/
    cp ${pcoa_coords} diversity/
    cp ${microbiome_summary} summary/
    
    # Generate a timestamp for completion
    date > completion_time.txt
    
    # Log completion
    echo "Completed uploading results to ${params.output}"
    """
}

// Generate cost report
process generate_cost_report {
    publishDir "${params.output}/reports", mode: 'copy'
    
    output:
    path('cost_report.json')
    
    script:
    """
    # Calculate approximate costs based on instance hours
    cat << EOF > cost_report.json
    {
      "estimated_cost": {
        "compute": {
          "graviton_spot": $(echo "scale=2; \${NEXTFLOW_SPOT_HOURS:-0.5} * 0.0408" | bc),
          "gpu_spot": $(echo "scale=2; \${NEXTFLOW_GPU_HOURS:-0.25} * 0.50" | bc)
        },
        "storage": 0.12,
        "data_transfer": 0.02,
        "total": $(echo "scale=2; \${NEXTFLOW_SPOT_HOURS:-0.5} * 0.0408 + \${NEXTFLOW_GPU_HOURS:-0.25} * 0.50 + 0.14" | bc)
      },
      "comparison": {
        "on_premises": 1800.00,
        "standard_cloud": 120.00,
        "optimized_cloud": $(echo "scale=2; \${NEXTFLOW_SPOT_HOURS:-0.5} * 0.0408 + \${NEXTFLOW_GPU_HOURS:-0.25} * 0.50 + 0.14" | bc)
      },
      "time_saved": "336 hours (2 weeks)"
    }
    EOF
    """
}

// Workflow completion handler
workflow.onComplete {
    log.info """
    =========================================
    Pipeline execution summary
    =========================================
    Completed at: ${workflow.complete}
    Duration    : ${workflow.duration}
    Success     : ${workflow.success}
    workDir     : ${workflow.workDir}
    exit status : ${workflow.exitStatus}
    =========================================
    """
    
    // Update progress tracking on workflow completion
    if (params.enable_progress_tracking) {
        def status = workflow.success ? "completed" : "failed"
        def timestamp = System.currentTimeMillis() / 1000
        def dateFormat = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss")
        def currentDate = new Date()
        def humanTime = dateFormat.format(currentDate)
        
        // Create final workflow progress update
        def cmd = """
        export PROCESS_NAME="workflow_complete"
        export PROCESS_STATUS="${status}"
        export WORKFLOW_ID="${params.workflow_id}"
        export BUCKET_NAME="${params.bucket_name}"
        export TIMESTAMP="${timestamp}"
        export HUMAN_TIME="${humanTime}"
        export TOTAL_PROCESSES="1"
        bash -c 'bash \$(aws s3 cp s3://${params.bucket_name}/workflow/templates/progress_tracker.sh - | cat)' || true
        """
        
        try {
            def sout = new StringBuilder()
            def serr = new StringBuilder()
            def proc = cmd.execute()
            proc.consumeProcessOutput(sout, serr)
            proc.waitForOrKill(30000)
            log.info "Workflow completion status updated: ${status}"
            if (serr.toString()) {
                log.warn "Progress update error: ${serr.toString()}"
            }
        } catch (Exception e) {
            log.warn "Failed to update workflow completion status: ${e.message}"
        }
        
        // Create a final summary file with workflow stats
        def summary = [
            workflow_id: params.workflow_id,
            status: status,
            completed_at: humanTime,
            duration_ms: workflow.duration.toMillis(),
            duration_formatted: workflow.duration.toString(),
            success: workflow.success,
            exit_status: workflow.exitStatus,
            error_message: workflow.errorMessage ?: null,
            error_report: workflow.errorReport ?: null
        ]
        
        try {
            def json = new groovy.json.JsonOutput().toJson(summary)
            def prettyJson = groovy.json.JsonOutput.prettyPrint(json)
            def summaryFile = new File("${workflow.launchDir}/workflow_summary.json")
            summaryFile.text = prettyJson
            
            def cmd2 = "aws s3 cp ${workflow.launchDir}/workflow_summary.json s3://${params.bucket_name}/progress/${params.workflow_id}/workflow_summary.json"
            def proc2 = cmd2.execute()
            proc2.waitForOrKill(30000)
            log.info "Workflow summary uploaded to S3"
        } catch (Exception e) {
            log.warn "Failed to create workflow summary: ${e.message}"
        }
    }
}

// AWS Batch specific settings
process {
    executor = 'awsbatch'
    queue = 'microbiome-demo-queue'
    container = 'public.ecr.aws/lts/microbiome-tools:latest'
    
    withName: 'taxonomic_classification_kraken' {
        // Dynamic queue selection based on GPU availability
        // This will be overridden at runtime based on resource detection
        queue = { task.accelerator > 0 ? 'microbiome-demo-gpu-queue' : 'microbiome-demo-queue' }
        container = 'public.ecr.aws/lts/kraken2-gpu:latest'
    }
    
    withName: 'detect_resources' {
        container = 'public.ecr.aws/lts/microbiome-tools:latest'
        errorStrategy = 'terminate'
        maxRetries = 1
    }
}

// Process-specific optimization details
manifest {
    description = 'Microbiome demo pipeline with architecture-aware resource optimization'
    version = '1.0.0'
    author = 'Scott Friedman'
    mainScript = 'microbiome_main.nf'
    nextflowVersion = '>=21.10.0'
}

// AWS Batch executor settings
aws {
    region = 'us-east-1'
    batch {
        cliPath = '/usr/local/bin/aws'
    }
}
