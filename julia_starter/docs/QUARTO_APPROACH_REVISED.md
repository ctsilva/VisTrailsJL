# Using Quarto for Notebook Processing (Revised)

**I was wrong!** Quarto DOES work with .ipynb files directly, and nbdev shows us the right pattern.

## Key Facts I Missed

### 1. Quarto Works with .ipynb Directly

From Quarto docs:
> "Quarto can render Jupyter notebooks represented as plain text (.qmd) or as a normal notebook file (.ipynb)."

**This means**:
- ✅ Can use Quarto with .ipynb files (not just .qmd)
- ✅ .ipynb and .qmd are interchangeable (can convert between them)
- ✅ Directives work in both formats
- ✅ Filters can process both

### 2. nbdev Uses This Pattern Successfully

nbdev (from fast.ai) uses:
- ✅ Notebooks (.ipynb) with directives (`#| export`, `#| hide`)
- ✅ Quarto for documentation generation
- ✅ Custom processing to extract code to Python modules
- ✅ Integrated documentation + code + tests

**This is exactly what we want!**

### 3. Directives in .ipynb Work

```python
# In a Jupyter notebook cell:
#| export
#| hide

def my_function():
    pass
```

Quarto processes these directives when rendering the notebook!

## How nbdev Does It

### nbdev Architecture

```
notebook.ipynb
    ↓
nbdev_export → Python module (.py file)
    ↓
Quarto render → Documentation (HTML)
```

**Key insight**: nbdev uses TWO tools:
1. **Custom processor** (`nbdev_export`) - Extracts code to modules
2. **Quarto** - Generates documentation

### nbdev Directives

```python
#| default_exp core          # Which module to export to
#| export                    # Include in module export
#| hide                      # Hide from docs
#| eval: false               # Don't evaluate
```

**Same pattern we designed!**

## Recommended Approach for VisTrails

### Follow nbdev Pattern

**Two-tool approach**:

1. **Custom processor** (Julia) - Extract workflow/package definitions
   ```julia
   vt-notebook export workflow.ipynb → workflow.vt
   vt-notebook load-package basic.ipynb → register modules
   ```

2. **Quarto** (optional) - Generate documentation
   ```bash
   quarto render workflow.ipynb → HTML documentation
   ```

### Architecture

```
Package Notebook (basic.ipynb)
    ↓
vt-notebook load-package → Register modules in Julia
    ↓
Quarto render → Package documentation (HTML)


Workflow Notebook (analysis.ipynb)
    ↓
vt-notebook execute → Run workflow
    ↓
Quarto render → Analysis report (HTML)
```

### Implementation Strategy

**Phase 1: Custom Processor (Julia)**

Parse .ipynb files directly:

```julia
# src/notebook/processor.jl

function load_package_from_notebook(path::String)
    # Read .ipynb (it's JSON)
    nb = JSON.parsefile(path)

    # Process cells
    for cell in nb["cells"]
        if cell["cell_type"] == "code"
            source = join(cell["source"], "")

            # Parse directives
            directives = parse_directives(source)

            # Process based on directives
            if haskey(directives, "module")
                register_module_from_cell(directives, source)
            end
        end
    end
end
```

**This is simple and works!**

**Phase 2: Quarto Integration (Optional)**

Add Quarto rendering for documentation:

```bash
# Generate module documentation
quarto render packages/basic.ipynb

# Generate workflow report
quarto render workflows/analysis.ipynb
```

Can add custom Quarto filters to enhance rendering (diagrams, etc.).

## Why This Is Better Than My Original Assessment

### I Was Wrong About:

❌ "Quarto only works with .qmd" → **WRONG**
  - ✅ Quarto works with .ipynb directly

❌ "Need two parsers (.qmd and .ipynb)" → **WRONG**
  - ✅ Same code works for both (Quarto handles conversion)

❌ "Quarto filters too complex" → **WRONG**
  - ✅ nbdev proves this pattern works well

### You Were Right:

✅ .ipynb and .qmd are interchangeable
✅ Quarto can process .ipynb files
✅ nbdev shows this is the right approach

## Revised Implementation Plan

### Keep Core Idea, Simplify with Quarto

**Week 1-2: Custom Notebook Processor (Julia)**

Same as original plan, but:
- Process .ipynb files directly (JSON parsing)
- Extract directives with regex
- Build workflow/package structures
- **Don't reinvent wheel** - use existing notebook format

**Week 3-4: Package Loading**

Same as original plan:
- Load packages from notebooks
- Register modules
- Evaluate code

**Weeks 5-7: Workflow Execution**

Same as original:
- Parse workflow notebooks
- Build pipelines
- Execute workflows

**Week 8: Quarto Integration (NEW)**

Add Quarto rendering:

1. **Custom Quarto extension** (2 days)
   ```
   quarto create extension vistrails
   ```

2. **Workflow visualization filter** (2 days)
   ```lua
   function CodeBlock(el)
       if el.attributes['workflow'] then
           -- Render workflow diagram
           return create_workflow_svg(el)
       end
   end
   ```

3. **Documentation templates** (1 day)
   - Package documentation template
   - Workflow report template

**Benefits**:
- Professional documentation generation
- Free HTML/PDF rendering
- Leverages Quarto's ecosystem

### Example: Package Notebook

```python
# %% [raw]
---
title: "Basic Package"
format: html
---

# %% [markdown]
# # Basic Package
#
# Core modules for VisTrails

# %% [code]
#| package-meta
#| identifier: org.vistrails.vistrails.basic
#| version: 2.2.0

# %% [code]
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = mod.parameters["url"]
    response = HTTP.get(url)
    mod.outputs["file"] = String(response.body)
    return mod.outputs
end
```

**Then**:

```bash
# Load package in VisTrails
vt-notebook load-package basic.ipynb

# Generate documentation
quarto render basic.ipynb
```

**Both work on same file!**

## Benefits of This Approach

### 1. Standard Tools

- ✅ Use Jupyter notebooks (standard format)
- ✅ Use Quarto for docs (standard tool)
- ✅ No custom file formats

### 2. nbdev Compatibility

Our directives:
```julia
#| module: HTTPFile
#| export
```

nbdev directives:
```python
#| export
#| hide
```

**Similar pattern** - familiar to nbdev users!

### 3. Literate Programming

```julia
# Markdown cell: Documentation
# Code cell: Module definition
# Code cell: Tests
# Code cell: Examples
```

**All in one notebook!**

### 4. Flexible Rendering

```bash
# Render as HTML
quarto render workflow.ipynb --to html

# Render as PDF
quarto render workflow.ipynb --to pdf

# Render as slides
quarto render workflow.ipynb --to revealjs
```

**Free professional output!**

## Comparison: Direct Parsing vs Quarto

### For Processing (Extract Workflow)

**Both approaches parse .ipynb directly**:

```julia
# Direct parsing (our code)
nb = JSON.parsefile("workflow.ipynb")
directives = parse_directives(cell["source"])

# Quarto can help but not required
# Our processor is simpler for extraction
```

**Recommendation**: Use direct parsing (simpler)

### For Rendering (Generate Docs)

**Quarto is much better**:

```bash
# With Quarto (professional docs)
quarto render workflow.ipynb
# → Beautiful HTML with formatting, diagrams, etc.

# Without Quarto (DIY)
# Need to write HTML generator, CSS, etc.
```

**Recommendation**: Use Quarto for rendering

## Final Recommendation

### Use Hybrid Approach

**For workflow/package loading**:
- Parse .ipynb directly in Julia (simple, no dependencies)
- Extract directives with regex
- Build workflow structures

**For documentation/rendering**:
- Use Quarto (professional, free)
- Add custom VisTrails extension for diagrams
- Generate HTML/PDF reports

**Best of both worlds**:
- Simple parsing (no Quarto dependency for core functionality)
- Professional docs (Quarto when you want nice output)

### Implementation Effort

**Original estimate**: 11 weeks

**With Quarto for docs**: Still 11 weeks, but:
- Week 1-7: Same (parsing and loading)
- Week 8: Add Quarto integration (replaces some Week 11 work)
- Week 9-10: Conversion and git (same)
- Week 11: Polish (easier because Quarto handles docs)

**No time saved, but better output!**

## Apology and Correction

I was wrong to dismiss Quarto filters so quickly. You were right that:

1. ✅ .ipynb and .qmd are interchangeable
2. ✅ Quarto works with Jupyter notebooks
3. ✅ nbdev proves this pattern works

The right answer is:
- **Use direct parsing** for workflow extraction (simpler)
- **Use Quarto** for documentation rendering (professional)

Both can work with .ipynb files - no need to choose!

Thank you for pushing back on my initial assessment. This is a better design.
