# Workflow Definitions in Notebooks

Design for defining VisTrails workflows using notebooks with nbdev-style directives.

## Key Distinction

- **Package notebooks** (`packages/basic.ipynb`): Define module **types** (what modules CAN do)
- **Workflow notebooks** (`workflows/my_analysis.ipynb`): Define module **instances** and connections (what modules WILL do)

## Design Goals

1. ✅ **Git-native version control** - Workflow edits = git commits = VisTrails actions
2. ✅ **Literate workflows** - Mix documentation, workflow definition, and execution
3. ✅ **Compatible with .vt files** - Round-trip conversion
4. ✅ **Executable** - Run the notebook to execute the workflow
5. ✅ **Diff-able** - Cell changes map to VisTrails operations

## Basic Workflow Structure

### Simple Example

```julia
# %% [markdown]
# # COVID-19 Data Analysis
#
# Fetch COVID data from API and generate visualizations.

# %% [workflow-meta]
#| workflow: covid_analysis
#| version: 1
#| description: COVID-19 data analysis pipeline

# %% Fetch data
#| module-id: fetch_data
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://api.covid19api.com/summary"

# This cell defines a module instance
# Output will be available as 'fetch_data'

# %% Parse JSON
#| module-id: parse_json
#| module-type: julia:JuliaSource
#| inputs:
#|   raw_data: fetch_data.file

using JSON

# Get input
raw_data = get_input("raw_data")

# Parse and process
data = JSON.parse(raw_data)
countries = data["Countries"]
top_countries = sort(countries, by=c->c["TotalConfirmed"], rev=true)[1:10]

# Set output
set_output("top_countries", top_countries)

# %% Create visualization
#| module-id: create_plot
#| module-type: julia:JuliaSource
#| inputs:
#|   countries: parse_json.top_countries

using Plots

countries = get_input("countries")

names = [c["Country"] for c in countries]
cases = [c["TotalConfirmed"] for c in countries]

plot = bar(names, cases,
    title = "Top 10 Countries by COVID-19 Cases",
    xlabel = "Country",
    ylabel = "Total Cases",
    legend = false,
    rotation = 45
)

set_output("plot", plot)

# %% Execute workflow
#| execute

# Execute the workflow defined above
# Results will be cached and displayed
display(create_plot.plot)
```

## Directive Specification

### Workflow Metadata

```julia
#| workflow: <workflow_name>        # Optional: workflow identifier
#| version: <integer>               # Optional: version number
#| description: <text>              # Optional: workflow description
#| tags: <tag1>, <tag2>             # Optional: tags for this version
```

### Module Instance Definition

```julia
#| module-id: <unique_id>           # Required: unique identifier for this instance
#| module-type: <package:ModuleName> # Required: which module type to use
#| inputs:                          # Optional: input connections
#|   <port_name>: <source_id>.<output_port>
#| params:                          # Optional: parameter values
#|   <param_name>: <value>
#| position: [x, y]                 # Optional: layout position for GUI
```

### Execution Directive

```julia
#| execute                          # Execute entire workflow
#| execute-from: <module_id>        # Execute from specific module
#| cache: true/false                # Enable/disable caching (default: true)
```

## Two Styles: Declarative vs Imperative

### Style 1: Declarative (Pure Metadata)

Module definition is just directives, no code:

```julia
# %% Fetch data
#| module-id: fetch_data
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://api.example.com/data.json"

# Documentation only - no code needed
# The module type defines what this does

# %% Process data
#| module-id: process_data
#| module-type: basic:Constant
#| params:
#|   value: 42

# Another declarative module
```

**Use for**: Simple modules with fixed behavior (HTTPFile, constants, etc.)

### Style 2: Imperative (Code-Based)

For JuliaSource/PythonSource, cell code IS the module logic:

```julia
# %% Process data
#| module-id: process_data
#| module-type: julia:JuliaSource
#| inputs:
#|   data: fetch_data.file

# This code executes as the module's compute function
using DataFrames, CSV

data = get_input("data")
df = CSV.read(IOBuffer(data), DataFrame)
cleaned = dropmissing(df)

set_output("cleaned_data", cleaned)
```

**Use for**: Custom logic modules (JuliaSource, PythonSource)

## Connection Syntax

### Explicit Connections (Declarative)

```julia
#| inputs:
#|   input_port_name: source_module_id.output_port_name
```

Examples:
```julia
#| inputs:
#|   data: fetch_data.file
#|   threshold: config.value
```

### Implicit Connections (Variable-Based)

For JuliaSource, can use variable references:

```julia
# %% Module A
#| module-id: module_a
result_a = 42

# %% Module B
#| module-id: module_b
#| depends: module_a    # Declares dependency

# Can use result_a here
result_b = result_a * 2
```

Parser infers: `module_b.inputs.result_a → module_a.outputs.result_a`

**Recommendation**: Start with explicit connections (clearer), add implicit later.

## Complete Example: Data Pipeline

```julia
# %% [markdown]
# # Gene Expression Analysis Pipeline
#
# This workflow analyzes RNA-seq data from public repositories.

# %% Workflow metadata
#| workflow: rna_seq_analysis
#| version: 1
#| description: RNA-seq data processing and visualization
#| tags: bioinformatics, rna-seq

# %% Download reference genome
#| module-id: download_genome
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/genome.fa.gz"
#| position: [100, 100]

# Downloads human reference genome

# %% Download RNA-seq reads
#| module-id: download_reads
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://sra.ncbi.nlm.nih.gov/SRR12345.fastq.gz"
#| position: [100, 200]

# Downloads sequencing reads from SRA

# %% Quality control
#| module-id: run_qc
#| module-type: julia:JuliaSource
#| inputs:
#|   reads: download_reads.file
#| position: [300, 200]

using FastQC

reads = get_input("reads")

# Run quality control
qc_report = run_fastqc(reads)

set_output("qc_report", qc_report)
set_output("passed_qc", qc_report.quality_score > 30)

# %% Conditional: Alignment (only if QC passed)
#| module-id: align_reads
#| module-type: control_flow:If
#| inputs:
#|   condition: run_qc.passed_qc
#|   true_port: download_genome.file
#|   false_port: error_message.message
#| position: [500, 200]

# Conditional execution based on QC results

# %% Alignment (when QC passes)
#| module-id: star_alignment
#| module-type: julia:JuliaSource
#| inputs:
#|   genome: download_genome.file
#|   reads: download_reads.file
#| position: [700, 200]

using STAR

genome = get_input("genome")
reads = get_input("reads")

# Run STAR aligner
aligned_bam = star_align(genome, reads, threads=8)

set_output("aligned_bam", aligned_bam)

# %% Count features
#| module-id: feature_counts
#| module-type: julia:JuliaSource
#| inputs:
#|   bam: star_alignment.aligned_bam
#| position: [900, 200]

using HTSeq

bam = get_input("bam")

# Count reads per gene
counts = htseq_count(bam, "genes.gtf")

set_output("gene_counts", counts)

# %% Differential expression
#| module-id: diff_expr
#| module-type: julia:JuliaSource
#| inputs:
#|   counts: feature_counts.gene_counts
#| position: [1100, 200]

using DESeq2

counts = get_input("counts")

# Run differential expression analysis
results = run_deseq2(counts, design = "~ condition")

set_output("de_genes", results)

# %% Visualization
#| module-id: create_volcano_plot
#| module-type: julia:JuliaSource
#| inputs:
#|   de_results: diff_expr.de_genes
#| position: [1300, 200]

using Plots

results = get_input("de_results")

# Create volcano plot
volcano = scatter(
    results.log2FoldChange,
    -log10.(results.pvalue),
    xlabel = "Log2 Fold Change",
    ylabel = "-Log10 p-value",
    title = "Volcano Plot"
)

set_output("volcano_plot", volcano)

# %% Execute workflow
#| execute
#| cache: true

# Execute the entire pipeline
# Results are cached, so re-running is fast
println("Pipeline complete!")
display(create_volcano_plot.volcano_plot)
```

## Mapping to VisTrails Concepts

### Notebook Cell → VisTrails Module Instance

**Notebook cell**:
```julia
#| module-id: fetch_data
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://example.com"
```

**VisTrails XML** (in .vt file):
```xml
<module id="1" name="HTTPFile" package="org.vistrails.vistrails.basic">
  <function name="url">
    <parameter val="https://example.com"/>
  </function>
</module>
```

**Perfect mapping!**

### Notebook Diff → VisTrails Action

**Before** (commit A):
```julia
#| module-id: fetch_data
#| params:
#|   url: "https://api.example.com/v1/data"
```

**After** (commit B):
```julia
#| module-id: fetch_data
#| params:
#|   url: "https://api.example.com/v2/data"
```

**Git diff**:
```diff
- #|   url: "https://api.example.com/v1/data"
+ #|   url: "https://api.example.com/v2/data"
```

**VisTrails Action**:
```julia
Action(
    id = 2,
    prev_id = 1,
    operations = [
        Operation(
            type = :change_parameter,
            module_id = "fetch_data",
            parameter_name = "url",
            old_value = "https://api.example.com/v1/data",
            new_value = "https://api.example.com/v2/data"
        )
    ]
)
```

**Git commit becomes VisTrails version!**

## Version Control: Git Commits = VisTrails Versions

### Workflow Evolution

```bash
# Initial workflow
git commit -m "Initial COVID analysis workflow"
# This is VisTrails version 1

# Modify: change data source URL
git commit -m "Update to use v2 API"
# This is VisTrails version 2

# Branch: try different visualization
git checkout -b histogram
git commit -m "Use histogram instead of bar chart"
# This is a branch in the version tree

# Merge back
git checkout main
git merge histogram
# Version tree has merge node
```

### Git Log = Version Tree

```bash
$ git log --oneline --graph

* a3b4c5d (HEAD -> main) Merge histogram visualization
|\
| * f1e2d3c Use histogram instead of bar chart
* | c4d5e6f Add statistical analysis
|/
* b2c3d4e Update to use v2 API
* a1b2c3d Initial COVID analysis workflow
```

**This IS a VisTrails version tree!**

### Git Tags = VisTrails Tags

```bash
git tag -a "production_v1" -m "Production release v1"
git tag -a "paper_submission" -m "Version submitted with paper"
```

Maps directly to VisTrails tags!

## Diff-to-Action Examples

### 1. Add Module

**Diff**:
```diff
+ #| module-id: new_filter
+ #| module-type: julia:JuliaSource
+ #| inputs:
+ #|   data: fetch_data.file
+
+ filtered = filter(x -> x > 0, get_input("data"))
+ set_output("filtered", filtered)
```

**Actions**:
```julia
[
    Operation(
        type = :add_module,
        module_id = "new_filter",
        module_type = "julia:JuliaSource",
        parameters = Dict("source" => "filtered = filter(...)")
    ),
    Operation(
        type = :add_connection,
        source_module = "fetch_data",
        source_port = "file",
        dest_module = "new_filter",
        dest_port = "data"
    )
]
```

### 2. Delete Module

**Diff**:
```diff
- #| module-id: old_module
- #| module-type: basic:HTTPFile
- #| params:
- #|   url: "https://old.example.com"
```

**Action**:
```julia
Operation(
    type = :delete_module,
    module_id = "old_module"
)
```

### 3. Change Connection

**Diff**:
```diff
  #| module-id: processor
  #| inputs:
- #|   data: source_a.output
+ #|   data: source_b.output
```

**Actions**:
```julia
[
    Operation(
        type = :delete_connection,
        source_module = "source_a",
        dest_module = "processor"
    ),
    Operation(
        type = :add_connection,
        source_module = "source_b",
        dest_module = "processor"
    )
]
```

### 4. Modify Code (JuliaSource)

**Diff**:
```diff
  #| module-id: processor
  #| module-type: julia:JuliaSource

- result = process_v1(data)
+ result = process_v2(data)  # Use new algorithm
```

**Action**:
```julia
Operation(
    type = :change_parameter,
    module_id = "processor",
    parameter_name = "source",
    old_value = "result = process_v1(data)",
    new_value = "result = process_v2(data)  # Use new algorithm"
)
```

## Execution Model

### Interactive Execution (Cell-by-Cell)

Run cells sequentially in notebook:

```julia
# Cell 1: Define module
#| module-id: fetch_data
#| module-type: basic:HTTPFile
# Registers module, doesn't execute yet

# Cell 2: Define another module
#| module-id: process
#| module-type: julia:JuliaSource
# Registers module

# Cell 3: Execute workflow
#| execute
# NOW executes: fetch_data → process
# Results cached and available
```

### Batch Execution (CLI)

```bash
# Execute workflow notebook from command line
vt-notebook execute covid_analysis.ipynb

# With specific version (git commit)
vt-notebook execute covid_analysis.ipynb --commit a1b2c3d

# Export to .vt file
vt-notebook export covid_analysis.ipynb -o workflow.vt
```

### Partial Execution

```julia
#| execute-from: process_data
#| execute-to: create_plot

# Only execute modules from process_data to create_plot
# Useful for debugging or partial re-runs
```

## Conversion: Notebook ↔ .vt File

### Notebook → .vt File

```julia
using VisTrailsJL.Notebook

# Convert notebook to .vt file
notebook_to_vistrail("covid_analysis.ipynb", "covid_analysis.vt")

# With git history as version tree
notebook_to_vistrail(
    "covid_analysis.ipynb",
    "covid_analysis.vt",
    import_git_history = true
)
```

**Result**: .vt file compatible with Python VisTrails!

### .vt File → Notebook

```julia
# Convert .vt file to notebook
vistrail_to_notebook("workflow.vt", "workflow.ipynb")

# Specify which version to export
vistrail_to_notebook(
    "workflow.vt",
    "workflow.ipynb",
    version = 42  # Export specific version
)
```

## Layout and Positioning

### Automatic Layout (Default)

If no positions specified, use automatic layout:

```julia
#| module-id: module_a
# Position auto-calculated
```

### Manual Layout (GUI Compatibility)

For .vt file compatibility, can specify positions:

```julia
#| module-id: module_a
#| position: [100, 200]  # x, y coordinates

#| module-id: module_b
#| position: [300, 200]
```

### Grid Layout Helper

```julia
#| layout: grid
#| grid-spacing: 200

# Modules arranged in grid automatically
```

## Quarto Integration

Workflow notebooks work great with Quarto for reports:

````markdown
---
title: "COVID-19 Analysis Report"
author: "Data Science Team"
date: 2024-01-15
format:
  html:
    code-fold: true
---

# Introduction

This report presents our analysis of COVID-19 data...

## Data Collection

```{julia}
#| module-id: fetch_data
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://api.covid19api.com/summary"
#| echo: false

# Data fetched from API
```

## Analysis

```{julia}
#| module-id: analyze
#| module-type: julia:JuliaSource
#| inputs:
#|   data: fetch_data.file

using Statistics
data = get_input("data")
summary_stats = describe(data)
set_output("stats", summary_stats)
```

### Results

The analysis shows that...

```{julia}
#| execute
#| echo: false

# Execute workflow and display results
display(analyze.stats)
```
````

**Quarto renders** to beautiful HTML/PDF with embedded workflow execution!

## Advanced Features

### 1. Subworkflows

```julia
#| module-id: preprocess
#| module-type: workflow:Subworkflow
#| params:
#|   notebook: "preprocessing.ipynb"
#| inputs:
#|   raw_data: fetch_data.file

# Execute another notebook as a module
```

### 2. Loops/Iteration

```julia
#| module-id: process_all
#| module-type: control_flow:Map
#| inputs:
#|   list: data_sources.urls
#|   function: fetch_and_process.pipeline

# Apply subworkflow to each item in list
```

### 3. Conditional Execution

```julia
#| module-id: check_quality
#| module-type: control_flow:If
#| inputs:
#|   condition: qc_results.passed
#|   true_port: continue_pipeline.input
#|   false_port: error_handler.input
```

### 4. Parameter Exploration

```julia
#| module-id: sweep_threshold
#| module-type: paramexplore:ParameterSweep
#| params:
#|   parameter: threshold
#|   values: [0.1, 0.5, 1.0, 2.0]
#| inputs:
#|   pipeline: analysis.workflow

# Run workflow with different threshold values
```

## Benefits Summary

### For Users

1. ✅ **Familiar notebooks** - Use Jupyter/VSCode/Pluto
2. ✅ **Git-native versioning** - Standard tools (GitHub, git)
3. ✅ **Literate workflows** - Documentation + code + execution
4. ✅ **No GUI required** - Complete system without UI
5. ✅ **Publication-ready** - Quarto integration

### For Developers

1. ✅ **Simple implementation** - Parse comments, no macros
2. ✅ **Clear mapping** - Cell → Module, Diff → Action
3. ✅ **Standard tools** - Git, Jupyter, no custom VCS
4. ✅ **Testable** - Unit tests for each component
5. ✅ **Extensible** - Easy to add new features

### For Collaboration

1. ✅ **GitHub-native** - PR, review, merge workflows
2. ✅ **Readable diffs** - See exactly what changed
3. ✅ **Merge-friendly** - Standard git merge
4. ✅ **Comment inline** - Review in GitHub
5. ✅ **Reproducible** - Git commit = exact workflow state

## Implementation Phases

### Phase 1: Parser (2 weeks)
- Parse workflow directives
- Build Pipeline from notebook
- Basic module instance creation
- Connection resolution

### Phase 2: Diff Engine (2 weeks)
- Compare notebook versions
- Generate VisTrails operations
- Git diff integration
- Action replay

### Phase 3: Execution (1 week)
- `#| execute` directive
- Cache management
- Output capture
- Error handling

### Phase 4: Conversion (2 weeks)
- Notebook → .vt export
- .vt → Notebook import
- Git history → Version tree
- Round-trip testing

### Phase 5: Advanced (2 weeks)
- Subworkflows
- Control flow support
- Parameter exploration
- Quarto integration

**Total: 9 weeks**

## Next Steps

Now we have designs for both:
1. ✅ **Package definitions** - Define module types
2. ✅ **Workflow definitions** - Use modules in pipelines

**Should I start implementing the parser?** Or refine the design further?
