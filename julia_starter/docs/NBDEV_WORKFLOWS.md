# nbdev-Style Workflow Representation

**Simpler approach**: Use nbdev's directive system (`#| directive`) for workflow definition instead of custom macros.

## Why nbdev is Perfect for VisTrails

### Key Advantages

1. **Established Pattern** - nbdev is proven in fastai/huggingface communities
2. **Just Comments** - Directives are comments, so notebooks run without any special support
3. **No Magic** - No macros, no meta-programming, just plain Julia code + annotations
4. **Tool Friendly** - Works with any notebook viewer (GitHub, JupyterLab, VS Code)
5. **Language Agnostic** - Same pattern works for Julia, Python, R

### nbdev Philosophy → VisTrails

| nbdev Concept | VisTrails Equivalent |
|---------------|---------------------|
| `#\| export` | `#\| module` - Define workflow module |
| `#\| hide` | Skip cell in workflow |
| `#\| test` | Validation/assertion modules |
| Literate programming | Document + execute workflows |
| Cell → Python module | Cell → Workflow module |
| Git diffs | Version tree actions |

## Directive-Based Workflow Syntax

### Basic Module Definition

```julia
#| module: HTTPFile
#| id: fetch_data
#| params:
#|   url: "https://api.covid19api.com/summary"
#| outputs: raw_data

# This cell defines an HTTPFile module
# The code is documentation/notes, not executed
# Only the directive metadata matters
```

**Key insight**: The cell content is **documentation**, the directives are **workflow definition**.

### Alternative: Code + Directive

```julia
#| module: JuliaSource
#| id: process_data
#| inputs: raw_data
#| outputs: top_countries

# This code WILL execute as part of the workflow
using JSON
data = JSON.parse(raw_data)
countries = data["Countries"]
top_countries = sort(countries, by=c->c["TotalConfirmed"], rev=true)[1:10]
```

**Flexibility**: Directives define the module, code is the parameter (for JuliaSource/PythonSource).

## Complete Example Workflow

```julia
# %% [markdown]
# # COVID-19 Data Analysis
#
# This workflow fetches COVID data and generates visualizations.

# %%
#| module: HTTPFile
#| id: fetch_covid_data
#| params:
#|   url: "https://api.covid19api.com/summary"
#| outputs: raw_data
#| description: Fetch latest COVID-19 statistics from API

# HTTPFile module - downloads JSON data from the COVID-19 API
# Output will be available as 'raw_data' variable in downstream modules

# %%
#| module: JuliaSource
#| id: parse_and_filter
#| inputs: raw_data
#| outputs: top_countries
#| description: Parse JSON and extract top 10 countries by cases

using JSON

# Parse the JSON response
data = JSON.parse(raw_data)
countries = data["Countries"]

# Sort by total confirmed cases and take top 10
sorted = sort(countries, by = c -> c["TotalConfirmed"], rev=true)
top_countries = sorted[1:10]

# %%
#| module: JuliaSource
#| id: create_visualization
#| inputs: top_countries
#| outputs: plot
#| description: Generate bar chart of top countries

using Plots

# Extract data for plotting
names = [c["Country"] for c in top_countries]
cases = [c["TotalConfirmed"] for c in top_countries]

# Create bar chart
plot = bar(names, cases,
    title = "Top 10 Countries by COVID-19 Cases",
    xlabel = "Country",
    ylabel = "Total Confirmed Cases",
    legend = false,
    rotation = 45,
    size = (800, 600)
)

# %%
#| workflow: execute
#| cache: true

# Execute the workflow defined above
# This cell triggers workflow execution when notebook runs
```

## Directive Specification

### Module Directives

#### Core Directives

```julia
#| module: <module_type>        # Required: HTTPFile, JuliaSource, PythonSource, etc.
#| id: <module_id>               # Optional: unique identifier (auto-generated if omitted)
#| package: <package_name>       # Optional: defaults based on module type
```

#### Connection Directives

```julia
#| inputs: <var1>, <var2>, ...   # Input connections (comma-separated)
#| outputs: <var>                # Output variable name
```

#### Parameter Directives

```julia
#| params:                       # Parameters as YAML
#|   key1: value1
#|   key2: value2
```

Or inline:
```julia
#| param.url: "https://..."
#| param.threshold: 0.5
```

#### Metadata Directives

```julia
#| description: <text>           # Module description
#| position: [x, y]              # Layout position for GUI rendering
#| color: <color>                # Visual styling
```

### Workflow Directives

```julia
#| workflow: execute             # Execute entire workflow
#| workflow: execute_from <id>   # Execute from specific module
#| workflow: validate            # Validate workflow (no execution)
#| cache: true/false             # Enable/disable caching
```

### Special Directives

```julia
#| hide                          # Hide cell from workflow (documentation only)
#| test                          # Mark as test/validation cell
#| export: <filename>.vt         # Export workflow to .vt file
```

## How It Works: Directive Parsing

### Parser Implementation

```julia
"""
Parse nbdev-style directives from a notebook cell.
"""
function parse_cell_directives(cell_source::String)::Dict{String, Any}
    directives = Dict{String, Any}()

    for line in split(cell_source, '\n')
        # Match directive pattern: #| key: value
        m = match(r"^#\|\s*([^:]+):\s*(.*)$", strip(line))
        if m !== nothing
            key = strip(m.captures[1])
            value = strip(m.captures[2])

            # Handle nested parameters
            if key == "params"
                # Next lines are YAML params until non-directive
                directives["params"] = parse_yaml_block(...)
            elseif startswith(key, "param.")
                # Inline parameter: #| param.url: "..."
                param_name = key[7:end]
                if !haskey(directives, "params")
                    directives["params"] = Dict()
                end
                directives["params"][param_name] = parse_value(value)
            else
                directives[key] = parse_value(value)
            end
        end
    end

    return directives
end

"""
Parse a notebook cell into a workflow module.
"""
function parse_module_cell(cell)
    directives = parse_cell_directives(cell.source)

    # Must have 'module' directive
    if !haskey(directives, "module")
        return nothing
    end

    # Extract module type
    module_type = directives["module"]

    # Generate ID if not provided
    module_id = get(directives, "id", generate_id())

    # Extract parameters
    params = get(directives, "params", Dict())

    # For JuliaSource/PythonSource, code is the cell content (minus directives)
    if module_type in ["JuliaSource", "PythonSource"]
        code = extract_code_without_directives(cell.source)
        params["source"] = code
    end

    # Extract connections
    inputs = parse_input_connections(get(directives, "inputs", ""))
    outputs = get(directives, "outputs", nothing)

    # Create module instance
    return WorkflowModule(
        id = module_id,
        type = module_type,
        package = get(directives, "package", infer_package(module_type)),
        parameters = params,
        inputs = inputs,
        outputs = outputs,
        description = get(directives, "description", ""),
        position = get(directives, "position", nothing)
    )
end
```

### Workflow Builder

```julia
"""
Build a complete workflow from a notebook.
"""
function build_workflow_from_notebook(notebook_path::String)
    nb = read_notebook(notebook_path)

    modules = []
    connections = []

    for cell in nb.cells
        if cell.cell_type != "code"
            continue
        end

        # Parse module from cell
        mod = parse_module_cell(cell)
        if mod === nothing
            continue
        end

        push!(modules, mod)

        # Create connections from inputs
        for (input_var, port_name) in mod.inputs
            # Find source module that outputs this variable
            source_mod = find_module_by_output(modules, input_var)
            if source_mod !== nothing
                conn = Connection(
                    source_module = source_mod.id,
                    source_port = source_mod.outputs,
                    dest_module = mod.id,
                    dest_port = port_name
                )
                push!(connections, conn)
            end
        end
    end

    # Build pipeline
    pipeline = Pipeline()
    for mod in modules
        add_module_from_spec!(pipeline, mod)
    end
    for conn in connections
        add_connection!(pipeline, conn)
    end

    return pipeline
end
```

## Execution Model

### Two Execution Modes

#### Mode 1: Notebook Execution (Interactive)

Run the notebook normally in Jupyter/IJulia:

```julia
# Cell 1: Module definition
#| module: HTTPFile
#| outputs: data
#| param.url: "https://example.com/data.json"

# Cell execution: registers module, doesn't fetch yet
println("Module 'data' registered")

# Cell 2: Processing
#| module: JuliaSource
#| inputs: data
#| outputs: result

processed = process(data)

# Cell execution: registers module, doesn't execute yet
println("Module 'result' registered")

# Cell 3: Execute workflow
#| workflow: execute

# NOW the workflow executes:
# - HTTPFile fetches data
# - JuliaSource processes it
# Results are cached and available

display(result)  # Access cached output
```

**Key**: Directive cells **register** modules, execution cell **runs** workflow.

#### Mode 2: Workflow Extraction (Batch)

Extract and execute workflow without running notebook:

```bash
# Extract workflow from notebook and execute
julia -e '
using VisTrailsJL.Notebook
workflow = build_workflow_from_notebook("analysis.ipynb")
results = execute_pipeline(workflow)
'

# Or use CLI tool
vt-notebook execute analysis.ipynb
vt-notebook export analysis.ipynb -o workflow.vt
```

## Diff-to-Action Translation

### Example: Parameter Change

**Before:**
```julia
#| module: HTTPFile
#| param.url: "https://api.example.com/v1/data"
#| outputs: data
```

**After:**
```julia
#| module: HTTPFile
#| param.url: "https://api.example.com/v2/data"
#| outputs: data
```

**Git diff:**
```diff
  #| module: HTTPFile
- #| param.url: "https://api.example.com/v1/data"
+ #| param.url: "https://api.example.com/v2/data"
  #| outputs: data
```

**VisTrails Action:**
```julia
Operation(
    type = :change_parameter,
    module_id = "data",
    parameter_name = "url",
    old_value = "https://api.example.com/v1/data",
    new_value = "https://api.example.com/v2/data"
)
```

### Example: Add Module

**Diff:**
```diff
+ #| module: JuliaSource
+ #| inputs: data
+ #| outputs: filtered
+
+ filtered = filter(x -> x > 0, data)
```

**Action:**
```julia
[
    Operation(
        type = :add_module,
        module_id = "filtered",
        module_type = "JuliaSource",
        package = "org.vistrails.vistrails.julia",
        parameters = Dict("source" => "filtered = filter(x -> x > 0, data)")
    ),
    Operation(
        type = :add_connection,
        source_module = "data",
        source_port = "self",
        dest_module = "filtered",
        dest_port = "data"
    )
]
```

## Comparison: Macros vs Directives

| Aspect | @module Macro | #\| Directives |
|--------|---------------|----------------|
| Syntax | `@module HTTPFile(...) => data` | `#\| module: HTTPFile` |
| Runs without tool | ❌ Needs macro loaded | ✅ Just comments |
| IDE support | Needs Julia-aware IDE | ✅ Works everywhere |
| GitHub rendering | May look weird | ✅ Looks clean |
| Error handling | Macro expansion errors | ✅ Parse errors easy to debug |
| Familiar to users | Julia-specific | ✅ nbdev pattern (Python) |
| Implementation complexity | Higher (macros) | Lower (string parsing) |

**Directives win on simplicity and portability!**

## Integration with Existing Tools

### Jupyter/JupyterLab

Notebooks work as-is:
- Directives are just comments
- Code executes normally
- Add VisTrailsJL extension for workflow view

### Pluto.jl

```julia
using VisTrailsJL.Notebook

#| module: HTTPFile
#| param.url: "https://example.com"
#| outputs: data

# Pluto tracks reactivity automatically
# VisTrails tracks workflow structure
```

### Quarto

Perfect fit! Quarto already uses `#|` directives:

```markdown
---
title: "Analysis Report"
format: html
---

## Data Loading

```{julia}
#| module: HTTPFile
#| param.url: "https://data.gov/dataset.csv"
#| outputs: dataset

# Data loaded via HTTPFile module
```

## Results

```{julia}
#| echo: false
#| workflow: execute

# Execute and display results
display(dataset)
```
```

### VS Code Notebooks

Directives render as regular comments:
- No special extension needed
- Can add syntax highlighting for `#|` lines
- IntelliSense for known directives

## Implementation Roadmap (Simplified)

### Phase 1: Directive Parser (1 week)

**Goal**: Parse `#|` directives from notebook cells

**Tasks**:
1. Implement directive parser (regex-based)
2. Handle YAML-style nested params
3. Extract code vs directive content
4. Unit tests for all directive types

**Deliverables**:
- `src/notebook/directives.jl`
- `parse_cell_directives()` function
- Test suite

### Phase 2: Workflow Builder (1 week)

**Goal**: Build Pipeline from parsed directives

**Tasks**:
1. Convert parsed modules to Pipeline
2. Infer connections from inputs/outputs
3. Handle missing IDs (auto-generate)
4. Validate workflow (cycles, missing inputs)

**Deliverables**:
- `build_workflow_from_notebook()`
- Workflow validation
- Example notebooks

### Phase 3: Diff Engine (1 week)

**Goal**: Convert notebook diffs to actions

**Tasks**:
1. Diff two notebooks by directives
2. Generate add/delete/modify operations
3. Handle connection changes
4. Test with git diffs

**Deliverables**:
- `diff_notebooks()` function
- `git_diff_to_actions()` function
- Integration tests

### Phase 4: Execution (1 week)

**Goal**: Execute workflow from notebook

**Tasks**:
1. Parse `#| workflow: execute` directive
2. Build and execute pipeline
3. Cache results
4. Write outputs back to notebook

**Deliverables**:
- Workflow execution from notebook
- Output capture
- CLI tool: `vt-notebook execute`

### Phase 5: Bidirectional Conversion (1 week)

**Goal**: Convert .vt ↔ notebook

**Tasks**:
1. .vt → notebook with directives
2. Notebook → .vt file
3. Round-trip testing
4. Preserve all metadata

**Deliverables**:
- `vt_to_notebook()`
- `notebook_to_vt()`
- CLI tools

### Phase 6: Git Integration (1 week)

**Goal**: Import git history as version tree

**Tasks**:
1. Parse git log for notebook file
2. Extract directives from each commit
3. Generate actions from commit diffs
4. Build version tree

**Deliverables**:
- `import_git_history()`
- Git tag → VisTrails tag
- Documentation

**Total: 6 weeks** (vs 6-9 for macro approach)

## Syntax Examples

### Example 1: Simple Pipeline

```julia
#| module: HTTPFile
#| param.url: "https://example.com/data.csv"
#| outputs: raw_data

#| module: JuliaSource
#| inputs: raw_data
#| outputs: cleaned_data

using DataFrames, CSV
df = CSV.read(IOBuffer(raw_data), DataFrame)
cleaned_data = dropmissing(df)

#| module: JuliaSource
#| inputs: cleaned_data
#| outputs: plot

using Plots
plot = histogram(cleaned_data.value, bins=50)

#| workflow: execute
```

### Example 2: Branching Workflow

```julia
#| module: HTTPFile
#| outputs: data
#| param.url: "https://api.example.com/data"

# Branch 1: Statistics
#| module: JuliaSource
#| inputs: data
#| outputs: stats

using Statistics
stats = (mean=mean(data), std=std(data))

# Branch 2: Visualization
#| module: JuliaSource
#| inputs: data
#| outputs: plot

using Plots
plot = histogram(data)

# Execute both branches
#| workflow: execute
```

### Example 3: Conditional Logic

```julia
#| module: HTTPFile
#| outputs: data
#| param.url: "https://api.example.com/sensor"

#| module: If
#| inputs: data
#| outputs: alert
#| param.condition: "data.temperature > 100"
#| param.true_value: "ALERT: High temperature!"
#| param.false_value: "Temperature normal"

#| workflow: execute
```

### Example 4: Documentation-Rich

```markdown
# Genomic Analysis Pipeline

This notebook analyzes RNA-seq data from experiment #1234.

## Step 1: Download Reference Genome

We use the human reference genome (hg38) from NCBI.
```

```julia
#| module: HTTPFile
#| description: Download human reference genome (hg38)
#| param.url: "https://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/hg38.fa.gz"
#| outputs: genome
```

```markdown
## Step 2: Download RNA-Seq Reads

Paired-end sequencing data from sample A.
```

```julia
#| module: HTTPFile
#| description: Download RNA-seq reads (sample A, read 1)
#| param.url: "https://sra.ncbi.nlm.nih.gov/SRR12345_1.fastq.gz"
#| outputs: reads_1

#| module: HTTPFile
#| description: Download RNA-seq reads (sample A, read 2)
#| param.url: "https://sra.ncbi.nlm.nih.gov/SRR12345_2.fastq.gz"
#| outputs: reads_2
```

```markdown
## Step 3: Alignment

Align reads to reference genome using STAR aligner.
```

```julia
#| module: JuliaSource
#| description: Run STAR alignment
#| inputs: genome, reads_1, reads_2
#| outputs: aligned_bam

using STAR
aligned_bam = star_align(genome, reads_1, reads_2, threads=8)
```

```markdown
## Execute Pipeline

Run the complete analysis pipeline.
```

```julia
#| workflow: execute
#| cache: true
```

## Advanced Features

### Parameterized Workflows

Use Quarto/nbdev parameters:

```yaml
---
params:
  data_url: "https://default.example.com/data"
  threshold: 0.5
---
```

```julia
#| module: HTTPFile
#| param.url: !expr params.data_url
#| outputs: data

#| module: JuliaSource
#| inputs: data
#| outputs: filtered

threshold = params.threshold
filtered = filter(x -> x > threshold, data)
```

### Subworkflows

```julia
#| module: Workflow
#| param.notebook: "preprocessing.ipynb"
#| outputs: preprocessed_data

# Execute another notebook as a subworkflow

#| module: JuliaSource
#| inputs: preprocessed_data
#| outputs: analyzed_data

# Continue with analysis
```

### Caching Control

```julia
#| module: HTTPFile
#| param.url: "https://api.example.com/data"
#| cache: false  # Always re-fetch (don't cache)
#| outputs: fresh_data

#| module: JuliaSource
#| inputs: fresh_data
#| cache: true  # Cache expensive computation
#| outputs: result

# Expensive computation here
```

## Benefits Summary

### For Users
- ✅ Familiar notebook interface
- ✅ Works without special tools (just comments)
- ✅ Git-friendly (plain text diffs)
- ✅ Self-documenting (literate programming)
- ✅ Easy to learn (nbdev pattern)

### For Developers
- ✅ Simple implementation (string parsing)
- ✅ No macros, no DSL
- ✅ Standard tools (Jupyter, git, Quarto)
- ✅ Easy to debug (just comments)
- ✅ Language agnostic (works for Python too!)

### For Collaboration
- ✅ GitHub renders nicely
- ✅ Standard PR/review workflow
- ✅ Merge conflicts are readable
- ✅ Comments inline with code
- ✅ Reproducible (git commit = exact version)

## Next Steps

**Immediate**:
1. Implement directive parser
2. Create example notebook
3. Test workflow building

**Then**:
4. Add execution support
5. Implement diff engine
6. Git integration

**Start with**: Phase 1 - Directive Parser (1 week)

This approach is **simpler, cleaner, and more aligned with existing practices** than custom macros!
