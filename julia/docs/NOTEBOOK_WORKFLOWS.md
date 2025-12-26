# Notebook-Based Workflow System

A text-based approach to VisTrails workflows using Jupyter notebooks and Quarto, where notebook diffs translate to VisTrails actions.

## Vision

**Create a complete workflow system without a GUI** by representing workflows as executable notebooks:

- **Workflows = Notebooks** - Define modules and connections in notebook cells
- **Edits = Actions** - Notebook diffs become VisTrails action operations
- **Git = Version Control** - Git history is the version tree
- **Execution = Cell Execution** - Run notebooks to execute workflows
- **Provenance = Git + Outputs** - Full reproducibility via Git + cell outputs

## Design Philosophy

### Literate Workflows

Combine **documentation**, **workflow definition**, and **execution** in one file:

```julia
# Data Processing Pipeline

This workflow fetches COVID data from an API, processes it, and generates a plot.

## Step 1: Fetch Data

@module HTTPFile(
    url="https://api.covid19api.com/summary"
) => data

## Step 2: Process with Julia

@module JuliaSource(
    inputs=[data],
    code="""
    using JSON
    json = JSON.parse(data)
    countries = json["Countries"]
    top_5 = sort(countries, by=c->c["TotalConfirmed"], rev=true)[1:5]
    """
) => top_countries

## Step 3: Create Plot

@module JuliaSource(
    inputs=[top_countries],
    code="""
    using Plots
    names = [c["Country"] for c in top_countries]
    cases = [c["TotalConfirmed"] for c in top_countries]
    bar(names, cases, title="Top 5 Countries by COVID Cases")
    """
) => plot

## Execute
@execute
```

### Version Control Native

**Git commits = VisTrails versions:**

```bash
# Create initial workflow
git add covid_workflow.jl.ipynb
git commit -m "Initial COVID data workflow"
# This is VisTrails version 1

# Modify to add more countries
# Edit: top_5 -> top_10
git commit -m "Show top 10 countries instead of 5"
# This is VisTrails version 2

# Branch for different visualization
git checkout -b histogram
# Edit: bar() -> histogram()
git commit -m "Use histogram instead of bar chart"
# This is a branch in the version tree
```

### Plain Text = Collaborative

- **Review workflows** like code (GitHub PR, diff view)
- **Comment on changes** inline
- **Merge workflows** with standard git merge
- **No binary formats** - everything is readable

## Notebook Format Specification

### Cell Types

#### 1. Module Definition Cells

Define a module with parameters and connections:

**Syntax Option A: Macro-based (Julia-native)**

```julia
@module ModuleName(
    param1 = value1,
    param2 = value2,
    inputs = [upstream_module.output_port]
) => output_variable
```

**Syntax Option B: YAML metadata (Quarto-friendly)**

```julia
#| module: HTTPFile
#| params:
#|   url: "https://example.com/data.json"
#| outputs: data

# This cell defines an HTTPFile module
# The output will be available as 'data'
```

**Syntax Option C: Function-based (most flexible)**

```julia
data = HTTPFile(url="https://example.com/data.json")
```

#### 2. Connection Definition Cells

Explicitly define connections (optional, can be inferred):

```julia
@connect source_module.output_port => dest_module.input_port
```

Or implicit through variable usage:

```julia
# This module uses 'data' from previous module
result = JuliaSource(
    inputs=[data],  # Automatically creates connection
    code="..."
)
```

#### 3. Execution Cells

Execute the workflow:

```julia
@execute  # Execute entire workflow
@execute_from result  # Execute from specific module
```

#### 4. Documentation Cells

Standard markdown cells - ignored by workflow engine but essential for literate workflows:

```markdown
# Analysis Notes

This section processes the data using a rolling average...
```

### Example: Complete Notebook Workflow

```julia
# %% [markdown]
# # COVID-19 Data Analysis Workflow
#
# Fetches latest COVID data and generates visualizations.

# %% Define modules
using VisTrailsJL.Notebook

# Fetch data from API
@module HTTPFile(
    url = "https://api.covid19api.com/summary"
) => raw_data

# Parse JSON and extract countries
@module JuliaSource(
    inputs = [raw_data],
    code = """
    using JSON
    data = JSON.parse(raw_data)
    countries = data["Countries"]

    # Sort by total confirmed cases
    sorted = sort(countries, by=c->c["TotalConfirmed"], rev=true)
    top_n = sorted[1:10]
    """
) => top_countries

# Create bar chart
@module JuliaSource(
    inputs = [top_countries],
    code = """
    using Plots

    names = [c["Country"] for c in top_countries]
    cases = [c["TotalConfirmed"] for c in top_countries]

    bar(names, cases,
        title="Top 10 Countries by COVID-19 Cases",
        xlabel="Country",
        ylabel="Total Cases",
        legend=false,
        rotation=45)
    """
) => plot

# %% Execute workflow
results = @execute

# %% Display results
display(results[:plot])
```

### Alternative: Quarto Markdown Format

```markdown
---
title: COVID-19 Analysis
format: html
vistrails:
  workflow: true
  version: 1
---

# COVID-19 Data Pipeline

Fetch and visualize COVID-19 statistics.

## Fetch Data

```{julia}
#| module: HTTPFile
#| id: fetch_data
#| params:
#|   url: "https://api.covid19api.com/summary"
#| outputs: raw_data

# HTTPFile module - fetches data from URL
```

## Process Data

```{julia}
#| module: JuliaSource
#| id: process_data
#| inputs: [raw_data]
#| outputs: top_countries

using JSON
data = JSON.parse(raw_data)
countries = data["Countries"]
sorted = sort(countries, by=c->c["TotalConfirmed"], rev=true)
top_n = sorted[1:10]
```

## Visualize

```{julia}
#| module: JuliaSource
#| id: visualize
#| inputs: [top_countries]
#| outputs: plot

using Plots
names = [c["Country"] for c in top_countries]
cases = [c["TotalConfirmed"] for c in top_countries]

bar(names, cases, title="Top 10 Countries")
```
```

## Diff-to-Action Translation

The key innovation: **notebook diffs → VisTrails action operations**

### Diff Types and Operations

#### 1. Add Module (New Cell)

**Diff:**
```diff
+ @module HTTPFile(
+     url = "https://example.com/data.json"
+ ) => data
```

**VisTrails Action:**
```julia
Operation(
    type = :add_module,
    module_id = generate_id(),
    module_type = "HTTPFile",
    package = "org.vistrails.vistrails.basic",
    parameters = Dict("url" => "https://example.com/data.json")
)
```

#### 2. Delete Module (Removed Cell)

**Diff:**
```diff
- @module HTTPFile(
-     url = "https://example.com/old.json"
- ) => old_data
```

**VisTrails Action:**
```julia
Operation(
    type = :delete_module,
    module_id = old_data_id
)
```

#### 3. Modify Parameter

**Diff:**
```diff
  @module HTTPFile(
-     url = "https://example.com/old.json"
+     url = "https://example.com/new.json"
  ) => data
```

**VisTrails Action:**
```julia
Operation(
    type = :change_parameter,
    module_id = data_id,
    parameter_name = "url",
    old_value = "https://example.com/old.json",
    new_value = "https://example.com/new.json"
)
```

#### 4. Add Connection (New Input)

**Diff:**
```diff
  @module JuliaSource(
-     inputs = [],
+     inputs = [data],
      code = "..."
  ) => result
```

**VisTrails Action:**
```julia
Operation(
    type = :add_connection,
    connection_id = generate_id(),
    source_module = data_id,
    source_port = "self",
    dest_module = result_id,
    dest_port = "data"
)
```

#### 5. Change Code (Module Logic)

**Diff:**
```diff
  @module JuliaSource(
      inputs = [data],
      code = """
-     println(data)
+     processed = process(data)
      """
  ) => result
```

**VisTrails Action:**
```julia
Operation(
    type = :change_parameter,
    module_id = result_id,
    parameter_name = "source",
    old_value = "println(data)",
    new_value = "processed = process(data)"
)
```

### Algorithm: Diff to Actions

```julia
function notebook_diff_to_actions(old_notebook, new_notebook)
    actions = Operation[]

    # Parse both notebooks to extract modules
    old_modules = parse_notebook_modules(old_notebook)
    new_modules = parse_notebook_modules(new_notebook)

    # Find added modules (in new, not in old)
    for (id, mod) in new_modules
        if !haskey(old_modules, id)
            push!(actions, Operation(
                type = :add_module,
                module_id = id,
                module_type = mod.type,
                parameters = mod.parameters
            ))
        end
    end

    # Find deleted modules (in old, not in new)
    for (id, mod) in old_modules
        if !haskey(new_modules, id)
            push!(actions, Operation(
                type = :delete_module,
                module_id = id
            ))
        end
    end

    # Find modified modules (in both, but different)
    for (id, new_mod) in new_modules
        if haskey(old_modules, id)
            old_mod = old_modules[id]

            # Compare parameters
            for (param_name, new_value) in new_mod.parameters
                old_value = get(old_mod.parameters, param_name, nothing)
                if old_value != new_value
                    push!(actions, Operation(
                        type = :change_parameter,
                        module_id = id,
                        parameter_name = param_name,
                        old_value = old_value,
                        new_value = new_value
                    ))
                end
            end

            # Compare connections
            old_inputs = Set(old_mod.inputs)
            new_inputs = Set(new_mod.inputs)

            # Added connections
            for input in setdiff(new_inputs, old_inputs)
                push!(actions, Operation(
                    type = :add_connection,
                    source_module = input.module_id,
                    source_port = input.port,
                    dest_module = id,
                    dest_port = input.dest_port
                ))
            end

            # Removed connections
            for input in setdiff(old_inputs, new_inputs)
                push!(actions, Operation(
                    type = :delete_connection,
                    source_module = input.module_id,
                    source_port = input.port,
                    dest_module = id,
                    dest_port = input.dest_port
                ))
            end
        end
    end

    return actions
end
```

## Implementation Architecture

### Components to Build

```
julia/
├── src/
│   ├── notebook/
│   │   ├── parser.jl           # Parse notebook cells → modules
│   │   ├── macros.jl           # @module, @connect, @execute macros
│   │   ├── diff.jl             # Diff notebooks → actions
│   │   ├── executor.jl         # Execute notebook workflows
│   │   ├── serializer.jl       # Notebook → .vt, .vt → notebook
│   │   └── quarto.jl           # Quarto-specific support
│   └── ...
└── examples/
    └── notebooks/
        ├── simple_workflow.jl.ipynb
        ├── covid_analysis.qmd
        └── data_pipeline.jl.ipynb
```

### Core APIs

#### 1. Notebook Parser

```julia
"""
Parse a Jupyter notebook and extract workflow definition.
"""
function parse_notebook(notebook_path::String) -> Workflow
    nb = read_notebook(notebook_path)
    modules = []
    connections = []

    for cell in nb.cells
        if is_module_cell(cell)
            mod = parse_module_cell(cell)
            push!(modules, mod)

            # Extract implicit connections from inputs
            for input in mod.inputs
                conn = Connection(input.source, mod.id)
                push!(connections, conn)
            end
        elseif is_connection_cell(cell)
            conn = parse_connection_cell(cell)
            push!(connections, conn)
        end
    end

    return Workflow(modules, connections)
end
```

#### 2. Diff Engine

```julia
"""
Compare two notebook files and generate VisTrails actions.
"""
function diff_notebooks(old_path::String, new_path::String) -> Vector{Operation}
    old_workflow = parse_notebook(old_path)
    new_workflow = parse_notebook(new_path)

    return workflow_diff(old_workflow, new_workflow)
end

"""
Apply git diff to generate actions from commit history.
"""
function git_diff_to_actions(repo_path::String, commit1::String, commit2::String) -> Vector{Operation}
    # Use LibGit2 to get diff
    diff_text = git_diff(repo_path, commit1, commit2)

    # Parse diff to identify changed cells
    changed_cells = parse_git_diff(diff_text)

    # Convert to actions
    actions = diff_to_actions(changed_cells)

    return actions
end
```

#### 3. Notebook Executor

```julia
"""
Execute a notebook workflow and capture outputs.
"""
function execute_notebook(notebook_path::String; cache=true)
    # Parse workflow from notebook
    workflow = parse_notebook(notebook_path)

    # Execute using existing interpreter
    cache, exec_log = execute_pipeline(workflow.pipeline, cache_enabled=cache)

    # Write outputs back to notebook
    nb = read_notebook(notebook_path)
    for (module_id, result) in cache
        cell = find_module_cell(nb, module_id)
        if cell !== nothing
            cell.outputs = [format_output(result)]
        end
    end

    write_notebook(notebook_path, nb)

    return cache
end
```

#### 4. Bidirectional Conversion

```julia
"""
Convert .vt file to notebook format.
"""
function vistrail_to_notebook(vt_path::String, output_path::String; format=:jupyter)
    vt = load_vistrail(vt_path)
    pipeline = vt.pipelines[vt.current_version]

    nb = create_empty_notebook()

    # Add title cell
    add_markdown_cell!(nb, "# $(vt.name)")

    # Add module cells
    for (id, mod) in pipeline.modules
        cell_code = module_to_cell_code(mod)
        add_code_cell!(nb, cell_code)
    end

    # Add execution cell
    add_code_cell!(nb, "@execute")

    write_notebook(output_path, nb)
end

"""
Convert notebook to .vt file.
"""
function notebook_to_vistrail(notebook_path::String, output_path::String)
    workflow = parse_notebook(notebook_path)

    vt = Vistrail(basename(notebook_path))
    add_version!(vt, workflow.pipeline, notes="Imported from notebook")

    # If notebook has git history, import as version tree
    if is_git_tracked(notebook_path)
        import_git_history!(vt, notebook_path)
    end

    write_vistrail(output_path, vt)
end
```

### Module Definition Macro

```julia
"""
@module macro for defining workflow modules in notebooks.

Usage:
    @module HTTPFile(url="...") => data
    @module JuliaSource(inputs=[data], code="...") => result
"""
macro module(expr)
    # Parse expression: ModuleName(params...) => output
    if expr.head != :call || expr.args[1] != :(=>)
        error("@module syntax: @module ModuleName(params...) => output")
    end

    output_var = expr.args[3]
    module_expr = expr.args[2]

    # Extract module type and parameters
    module_type = module_expr.args[1]
    params = parse_parameters(module_expr.args[2:end])

    # Register module in notebook's workflow registry
    quote
        # Create module instance
        mod = create_module(
            type = $(QuoteNode(module_type)),
            parameters = $params,
            output_name = $(QuoteNode(output_var))
        )

        # Register in current workflow
        _notebook_workflow_register_module(mod)

        # Return nothing (module doesn't execute yet)
        nothing
    end |> esc
end
```

## Workflow Execution Model

### Two Execution Modes

#### Mode 1: Cell-by-Cell (Interactive)

Execute cells sequentially like a normal notebook:

```julia
# Cell 1: Define module
@module HTTPFile(url="https://example.com/data.json") => data
# → Registers module, doesn't execute

# Cell 2: Define processing
@module JuliaSource(inputs=[data], code="process(data)") => result
# → Registers module, doesn't execute

# Cell 3: Execute workflow
cache = @execute
# → Builds pipeline from registered modules
# → Executes with caching
# → Returns results

# Cell 4: Use results
println(cache[:result])
# → Access cached outputs like normal variables
```

#### Mode 2: Batch (Non-interactive)

Execute entire notebook as a workflow:

```bash
# Execute notebook workflow from command line
julia -e 'using VisTrailsJL.Notebook; execute_notebook("workflow.jl.ipynb")'

# Or use Quarto
quarto render workflow.qmd --execute
```

### Integration with IJulia/Pluto

Make workflows work seamlessly in Julia notebook environments:

```julia
# In Pluto.jl
using VisTrailsJL.Notebook

# Define workflow
data = @module HTTPFile(url="...")
result = @module JuliaSource(inputs=[data], code="...")

# Execute (Pluto will automatically re-execute on changes)
@execute
```

## Git Integration

### Automatic Version Tree from Git History

```julia
"""
Import git commit history as VisTrails version tree.
"""
function import_git_history(notebook_path::String) -> Vistrail
    repo = git_repository(notebook_path)
    commits = git_log(repo, file=notebook_path)

    vt = Vistrail(basename(notebook_path))
    commit_to_version = Dict{String, Int}()

    # Process commits in chronological order
    for commit in reverse(commits)
        # Get notebook content at this commit
        notebook_content = git_show(repo, commit.hash, notebook_path)

        # Parse workflow
        workflow = parse_notebook_content(notebook_content)

        # Determine parent version
        parent_id = if length(commit.parents) > 0
            parent_hash = commit.parents[1]
            get(commit_to_version, parent_hash, 0)
        else
            0
        end

        # Add version
        version_id = add_version!(
            vt,
            workflow.pipeline,
            parent_id,
            notes = commit.message,
            user = commit.author
        )

        commit_to_version[commit.hash] = version_id

        # Add git tag as VisTrails tag
        for tag in git_tags_for_commit(repo, commit.hash)
            add_tag!(vt, tag, version_id)
        end
    end

    return vt
end
```

### Sync Git and VisTrails

Bidirectional sync between git commits and VisTrails versions:

```julia
# Git commit → VisTrails version
git commit -m "Add data processing step"
vt_sync import  # Imports latest commit as new version

# VisTrails version → Git commit
vt = add_version!(vt, modified_pipeline, notes="Changed parameter")
vt_sync export  # Creates git commit from version
```

## Use Cases

### Use Case 1: Scientific Paper Workflow

```markdown
---
title: "RNA-Seq Analysis Pipeline"
author: "Lab Team"
date: 2024-01-15
---

# RNA-Seq Analysis Pipeline

Reproducible analysis for Nature paper submission.

## Data Acquisition

```{julia}
#| module: HTTPFile
#| outputs: raw_reads

# Download sequencing reads from SRA
url = "https://sra.org/download/SRR12345"
```

## Quality Control

```{julia}
#| module: JuliaSource
#| inputs: [raw_reads]
#| outputs: qc_report

using FastQC
report = run_fastqc(raw_reads)
```

## Alignment

```{julia}
#| module: JuliaSource
#| inputs: [raw_reads]
#| outputs: aligned_bam

using STAR
aligned = align_star(raw_reads, genome="hg38")
```

**Results**: See supplementary_figures.pdf
```

### Use Case 2: Collaborative Data Analysis

```julia
# team_workflow.jl.ipynb

# Alice creates initial workflow
@module HTTPFile(url="https://api.data.gov/covid") => covid_data

# Bob adds processing (different branch)
# git checkout -b bob/add-visualization
@module JuliaSource(
    inputs=[covid_data],
    code="plot(covid_data)"
) => visualization

# Carol adds statistical analysis (different branch)
# git checkout -b carol/add-stats
@module JuliaSource(
    inputs=[covid_data],
    code="statistics(covid_data)"
) => stats

# Merge both branches
# git merge bob/add-visualization
# git merge carol/add-stats
# Now workflow has both visualization and stats!
```

### Use Case 3: Parameter Exploration

```julia
# Workflow defined once
@module HTTPFile(url="https://api.example.com/data") => data

@module JuliaSource(
    inputs=[data],
    code="""
    threshold = 0.5  # PARAMETER
    filtered = filter(x -> x > threshold, data)
    """
) => filtered_data

# Version 1: threshold = 0.5
git commit -m "Baseline: threshold 0.5"

# Version 2: threshold = 0.7
# Edit: threshold = 0.5 → 0.7
git commit -m "Experiment: threshold 0.7"

# Version 3: threshold = 0.3
# Edit: threshold = 0.7 → 0.3
git commit -m "Experiment: threshold 0.3"

# Compare results across versions
compare_versions([v1, v2, v3])
```

## Implementation Roadmap

### Phase 1: Core Parser and Macro System (1-2 weeks)

**Goal**: Parse notebooks and define @module macro

Tasks:
1. ✅ Read Jupyter .ipynb files (IJulia format)
2. ✅ Implement @module macro
3. ✅ Parse module definitions from cells
4. ✅ Extract connections from inputs
5. ✅ Build Pipeline from parsed modules
6. ✅ Basic tests

Deliverables:
- `src/notebook/parser.jl`
- `src/notebook/macros.jl`
- Working @module syntax
- Test suite

### Phase 2: Diff Engine (1-2 weeks)

**Goal**: Convert notebook diffs to VisTrails actions

Tasks:
1. ✅ Implement notebook diffing
2. ✅ Generate action operations from diffs
3. ✅ Handle all operation types (add/delete/modify)
4. ✅ Test with real notebook edits
5. ✅ LibGit2 integration for git diffs

Deliverables:
- `src/notebook/diff.jl`
- `diff_notebooks()` function
- `git_diff_to_actions()` function
- Diff tests

### Phase 3: Execution Engine (1 week)

**Goal**: Execute notebook workflows

Tasks:
1. ✅ Implement @execute macro
2. ✅ Hook into existing interpreter
3. ✅ Capture outputs back to notebook
4. ✅ Handle execution errors gracefully
5. ✅ Support incremental execution

Deliverables:
- `src/notebook/executor.jl`
- @execute macro
- Output capture
- Error handling

### Phase 4: Bidirectional Conversion (1 week)

**Goal**: Convert between .vt and notebook formats

Tasks:
1. ✅ Implement notebook → .vt conversion
2. ✅ Implement .vt → notebook conversion
3. ✅ Preserve all metadata
4. ✅ Test round-trip conversion
5. ✅ Command-line tools

Deliverables:
- `src/notebook/serializer.jl`
- `vt_to_notebook()`
- `notebook_to_vt()`
- CLI tools

### Phase 5: Git Integration (1-2 weeks)

**Goal**: Sync git history with VisTrails version tree

Tasks:
1. ✅ Parse git commit history
2. ✅ Import commits as versions
3. ✅ Generate actions from commit diffs
4. ✅ Handle branches and merges
5. ✅ Import git tags as VisTrails tags
6. ⚠️ Export VisTrails versions as commits (optional)

Deliverables:
- Git history import
- Branch/merge support
- Tag synchronization
- Documentation

### Phase 6: Quarto Support (1 week)

**Goal**: Support Quarto markdown format

Tasks:
1. ✅ Parse Quarto .qmd files
2. ✅ Extract module metadata from chunk options
3. ✅ Generate Quarto output with results
4. ✅ Integration with quarto render
5. ✅ Documentation and examples

Deliverables:
- `src/notebook/quarto.jl`
- Quarto examples
- Rendering integration

### Phase 7: Polish and Documentation (1 week)

**Goal**: Make system production-ready

Tasks:
1. ✅ Comprehensive tests
2. ✅ User documentation
3. ✅ Tutorial notebooks
4. ✅ Example workflows
5. ✅ Performance optimization

Deliverables:
- Test coverage > 80%
- User guide
- 5+ example notebooks
- Performance benchmarks

## Timeline

**Total: 6-9 weeks**

More achievable than GUI development because:
- Leverages existing parser/interpreter
- Uses standard tools (Jupyter, Git)
- Less UI/UX complexity
- Incremental development

## Success Criteria

v1.0 Notebook System is successful if:

1. ✅ Can define workflows in Jupyter notebooks using @module macro
2. ✅ Can execute workflows from notebooks
3. ✅ Git diffs on notebooks generate correct VisTrails actions
4. ✅ Can convert .vt files to notebooks
5. ✅ Can convert notebooks to .vt files (round-trip)
6. ✅ Git commit history imports as version tree
7. ✅ Works with both Jupyter (.ipynb) and Quarto (.qmd)
8. ✅ Execution results written back to notebook
9. ✅ Compatible with existing VisTrails .vt files
10. ✅ Documentation and examples available

## Advantages Over GUI Approach

| Aspect | Notebook System | GUI System |
|--------|----------------|------------|
| Development time | 6-9 weeks | 8-11 weeks |
| Version control | Native (git) | Custom integration needed |
| Collaboration | Standard (PR, diff, merge) | Custom tools needed |
| Documentation | Literate programming built-in | Separate from workflow |
| Reproducibility | Git commit = exact state | Need export/import |
| Learning curve | Familiar (notebooks) | New interface to learn |
| Extensibility | Just Julia code | Need UI components |
| Offline work | Fully offline | Need server |

## Example: Complete Workflow Lifecycle

```bash
# 1. Create workflow notebook
jupyter notebook my_analysis.jl.ipynb

# 2. Define workflow (in notebook)
@module HTTPFile(url="...") => data
@module JuliaSource(inputs=[data], code="...") => result
@execute

# 3. Save notebook (automatic via Jupyter)

# 4. Commit to git
git add my_analysis.jl.ipynb
git commit -m "Initial data analysis workflow"

# 5. Modify workflow
# Edit parameter in notebook: url="old" -> url="new"

# 6. Commit change
git commit -am "Updated data source URL"

# 7. Convert to .vt format (for compatibility)
julia -e 'using VisTrailsJL.Notebook; notebook_to_vistrail("my_analysis.jl.ipynb", "my_analysis.vt")'

# 8. Import git history as version tree
julia -e 'using VisTrailsJL.Notebook; vt = import_git_history("my_analysis.jl.ipynb"); write_vistrail("my_analysis.vt", vt)'

# 9. View in Python VisTrails (compatibility check)
python vistrails/run.py my_analysis.vt
```

## Next Steps

**Immediate:**
1. Implement notebook parser (Phase 1)
2. Create @module macro
3. Build basic example notebook

**Then:**
4. Implement diff engine
5. Add execution support
6. Create documentation

**Start with:** Phase 1 - Core Parser and Macro System
