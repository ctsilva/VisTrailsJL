# Using Quarto Filters for Notebook Parsing

Analysis of whether Quarto filters can simplify parsing workflow/package notebooks.

## What Quarto Filters Provide

### Execution Model

Quarto processes documents through:
```
.qmd file → Pandoc AST → Lua filters → Modified AST → Output (HTML/PDF/etc)
```

Filters can:
- ✅ Access code cell content
- ✅ Access cell attributes/options (`#| option: value`)
- ✅ Transform document structure
- ✅ Extract metadata
- ✅ Call external programs

### Lua Filter API

Can access cell directives:

```lua
function CodeBlock(el)
    -- Access cell code
    local code = el.text

    -- Access cell attributes (from #| directives)
    local module_name = el.attributes['module']
    local module_type = el.attributes['module-type']

    -- Can extract and process
    if module_name then
        -- Extract workflow definition
        process_module(module_name, code)
    end

    return el
end
```

## How This Could Help Us

### Option 1: Quarto as Parser

**Use Quarto filters to extract workflow definitions**:

```lua
-- workflow-extractor.lua

-- Accumulate workflow definition
local workflow_data = {
    modules = {},
    connections = {}
}

function CodeBlock(el)
    -- Check for module definition
    if el.attributes['module-id'] then
        local module = {
            id = el.attributes['module-id'],
            type = el.attributes['module-type'],
            params = parse_params(el.attributes['params']),
            code = el.text
        }
        table.insert(workflow_data.modules, module)
    end

    return el
end

function Pandoc(doc)
    -- After processing all cells, write workflow data
    local json = quarto.json.encode(workflow_data)
    local file = io.open("workflow_data.json", "w")
    file:write(json)
    file:close()

    return doc
end
```

**Then in Julia**:
```julia
# Run Quarto filter to extract data
run(`quarto render workflow.qmd --execute=false --to json`)

# Read extracted data
workflow_data = JSON.parsefile("workflow_data.json")

# Build pipeline from extracted data
pipeline = build_pipeline_from_data(workflow_data)
```

**Pros**:
- ✅ Quarto handles .qmd parsing
- ✅ Access to cell directives is built-in
- ✅ Well-tested infrastructure

**Cons**:
- ❌ Only works for .qmd files (not .ipynb)
- ❌ Requires Quarto installation
- ❌ Two-step process (Quarto → JSON → Julia)
- ❌ Lua filter is separate codebase to maintain

### Option 2: Quarto for .qmd, Custom for .ipynb

**Support both formats**:

```julia
function load_workflow(path::String)
    if endswith(path, ".qmd")
        # Use Quarto filter approach
        return load_workflow_from_qmd(path)
    elseif endswith(path, ".ipynb")
        # Use custom parser
        return load_workflow_from_ipynb(path)
    end
end
```

**Pros**:
- ✅ Best tool for each format
- ✅ Quarto for publication-ready documents
- ✅ Direct .ipynb parsing for Jupyter users

**Cons**:
- ⚠️ Two implementations to maintain
- ⚠️ Need to keep them in sync

### Option 3: Just Use .qmd (Not .ipynb)

**Simplify by only supporting Quarto**:

**Pros**:
- ✅ Single format to support
- ✅ Better for publications
- ✅ Can use Quarto's infrastructure

**Cons**:
- ❌ Loses Jupyter compatibility
- ❌ Many users prefer Jupyter
- ❌ Less interactive during development

## Key Insight: Quarto Filters Have Limitations

### Problem 1: .ipynb Files

Quarto filters work on **Pandoc AST**, which is created from `.qmd` files.

For `.ipynb` files:
```
.ipynb → Pandoc → AST → Filters
```

But **we need to parse .ipynb directly** to:
- Support Jupyter users
- Avoid rendering workflow
- Work without Quarto installed

### Problem 2: Execution vs Parsing

Quarto filters run during **rendering**:
```
.qmd → Execute Julia code → AST → Filters → HTML/PDF
```

We want to:
- **Parse** workflow structure (no execution needed)
- **Execute** workflow through interpreter (not Quarto)

Quarto's execution model doesn't match our needs.

### Problem 3: Two-Language System

Quarto filters are **Lua**, our system is **Julia**:

```
Lua filter → Extract data → Write JSON → Julia reads JSON
```

This adds complexity rather than reducing it.

## Better Approach: Parse .ipynb Directly in Julia

### Why Direct Parsing is Better

**.ipynb files are JSON**:
```json
{
  "cells": [
    {
      "cell_type": "code",
      "source": [
        "#| module-id: fetch_data\n",
        "#| module-type: basic:HTTPFile\n"
      ]
    }
  ]
}
```

**Parse in Julia directly**:
```julia
using JSON

# Read notebook
nb = JSON.parsefile("workflow.ipynb")

# Extract cells
for cell in nb["cells"]
    if cell["cell_type"] == "code"
        source = join(cell["source"], "")

        # Parse directives
        directives = parse_directives(source)

        # Build workflow
        if haskey(directives, "module-id")
            add_module!(workflow, directives)
        end
    end
end
```

**This is simpler than Quarto filters!**

## Hybrid Approach (Recommended)

### For .qmd files: Let Quarto handle execution

```julia
# workflow.qmd with executable cells
```

```bash
# User runs with Quarto
quarto render workflow.qmd
```

**VisTrails provides**:
- Custom Quarto extension for workflow visualization
- Lua filter to enhance rendering
- Extract workflow metadata for provenance

### For .ipynb files: Parse directly in Julia

```julia
# Direct parsing (no Quarto needed)
workflow = load_workflow_from_ipynb("workflow.ipynb")
execute_workflow(workflow)
```

**VisTrails provides**:
- Pure Julia parser
- Works without Quarto
- Better for Jupyter users

## Recommendation

**Don't use Quarto filters for parsing**. Here's why:

### Parsing .ipynb is Simple

The original implementation plan is actually **simpler**:

```julia
# Week 1, Day 1: Parse .ipynb (JSON format)
nb = JSON.parsefile("workflow.ipynb")

for cell in nb["cells"]
    source = join(cell["source"], "")
    directives = parse_directives(source)  # Simple regex
    # ... build workflow
end
```

**This is ~50 lines of Julia code!**

Quarto filter approach would be:
1. Write Lua filter (50+ lines of Lua)
2. Run Quarto to extract JSON
3. Read JSON in Julia
4. Build workflow

**More steps, not fewer.**

### Where Quarto DOES Help

Quarto is excellent for:

1. **Publication-ready documents**:
   ```qmd
   ---
   title: "RNA-Seq Analysis Report"
   format: html
   ---

   # Introduction

   ```{julia}
   #| module-id: fetch_data
   # Workflow definition
   ```

   # Results

   The analysis shows...
   ```

2. **Custom rendering extensions**:
   ```lua
   -- visualize-workflow.lua
   function CodeBlock(el)
       if el.attributes['workflow'] then
           -- Render workflow diagram inline
           return create_workflow_diagram(el)
       end
   end
   ```

3. **Documentation generation**:
   - Render workflow as flowchart
   - Show module documentation
   - Display execution results

## Revised Implementation Plan

### Keep Original Plan for Parsing

**Weeks 1-2**: Parse .ipynb directly (simple JSON + regex)
- No Quarto dependency
- Works with Jupyter
- Pure Julia implementation

### Add Quarto Integration (Optional)

**After core is working**, add Quarto features:

**Week 12 (Optional): Quarto Extensions**

1. **Workflow visualization filter** (2 days)
   ```lua
   -- Render workflow diagrams in documents
   function CodeBlock(el)
       if el.attributes['workflow'] == 'true' then
           return render_workflow_svg(el)
       end
   end
   ```

2. **Module documentation filter** (1 day)
   ```lua
   -- Auto-generate module docs
   function CodeBlock(el)
       if el.attributes['module'] then
           return create_module_docs(el)
       end
   end
   ```

3. **Example Quarto templates** (2 days)
   - Workflow report template
   - Package documentation template
   - Tutorial template

**This is additive, not required!**

## Conclusion

**Don't use Quarto filters for parsing**:
- ❌ More complex than direct parsing
- ❌ Doesn't work for .ipynb files
- ❌ Adds dependency
- ❌ Two-language system (Lua + Julia)

**DO use Quarto for**:
- ✅ Publication-ready documents
- ✅ Enhanced rendering
- ✅ Documentation generation
- ✅ Optional extension (after core works)

**Stick with original plan**: Parse .ipynb directly in Julia. It's simpler!

## Code Comparison

### Original Approach (Simple)

```julia
# parse_notebook.jl
using JSON

function parse_notebook(path::String)
    nb = JSON.parsefile(path)

    for cell in nb["cells"]
        if cell["cell_type"] == "code"
            source = join(cell["source"], "")
            directives = parse_directives(source)

            if haskey(directives, "module-id")
                # Build workflow
            end
        end
    end
end

function parse_directives(source::String)
    directives = Dict{String, Any}()

    for line in split(source, '\n')
        m = match(r"^#\|\s*([^:]+):\s*(.*)$", line)
        if m !== nothing
            directives[m.captures[1]] = m.captures[2]
        end
    end

    return directives
end
```

**~30 lines of clear Julia code**

### Quarto Filter Approach (Complex)

```lua
-- workflow-extractor.lua (separate file)
local workflow = {modules = {}}

function CodeBlock(el)
    if el.attributes['module-id'] then
        table.insert(workflow.modules, {
            id = el.attributes['module-id'],
            type = el.attributes['module-type']
        })
    end
    return el
end

function Pandoc(doc)
    local json = quarto.json.encode(workflow)
    local file = io.open("workflow.json", "w")
    file:write(json)
    file:close()
    return doc
end
```

```julia
# load_from_quarto.jl
function load_workflow_from_qmd(path::String)
    # Run Quarto filter
    run(`quarto render $path --execute=false --to json`)

    # Read extracted data
    data = JSON.parsefile("workflow.json")

    # Build workflow
    # ...
end
```

**More code, more steps, external dependency**

The original approach is clearly simpler!
