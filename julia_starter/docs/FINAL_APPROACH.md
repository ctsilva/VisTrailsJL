# Final Approach: Simple Direct Parsing

**Decision**: Parse .ipynb files directly in Julia. Don't complicate with Quarto.

## Clear Assessment

### What We Actually Need

1. **Parse .ipynb files** - Extract directives and code
2. **Register modules** - From package notebooks
3. **Build workflows** - From workflow notebooks
4. **Execute workflows** - Using existing interpreter

### What Quarto Would Add

**For parsing**: Nothing
- .ipynb is JSON → Parse directly
- Directives are comments → Regex extraction
- **Quarto doesn't make this easier**

**For rendering**: Nice documentation
- Professional HTML/PDF output
- But we already have:
  - Notebooks render in Jupyter/VSCode
  - Can export HTML from Jupyter
  - Users can use Quarto if they want

**For nbdev features**: Advanced features we don't need
- Code extraction to modules → We're not building Python packages
- Documentation generation → Not our primary goal
- Testing framework → We have Julia's test framework
- CI/CD integration → Too sophisticated for our needs

## What nbdev Actually Does (That We Don't Need)

Looking at [fastcore.fast.ai](https://fastcore.fast.ai/basics.html):

**nbdev features**:
1. Extract code from notebooks → Python modules
2. Generate documentation site
3. Run tests in notebooks
4. Publish to PyPI
5. CI/CD integration
6. Two-way sync (notebook ↔ .py files)

**VisTrails needs**:
1. ✅ Extract workflow from notebooks → Pipeline objects
2. ❌ Don't need module export (we eval code directly)
3. ❌ Don't need doc site generation (notebooks are the docs)
4. ✅ Can run tests in notebooks (but Julia has better testing)
5. ❌ Don't publish to package registry
6. ❌ Don't need CI/CD (yet)
7. ⚠️ Two-way sync (.ipynb ↔ .vt) but different purpose

**We need ~15% of what nbdev does!**

## Recommended Implementation

### Simple and Direct

```julia
# src/notebook/parser.jl

using JSON

"""
Parse a Jupyter notebook (.ipynb) file
"""
function parse_notebook(path::String)
    # .ipynb is JSON - super simple!
    nb = JSON.parsefile(path)
    return nb
end

"""
Extract directives from cell source
"""
function parse_directives(source::String)
    directives = Dict{String, Any}()

    for line in split(source, '\n')
        # Match #| key: value
        m = match(r"^#\|\s*([^:]+):\s*(.*)$", strip(line))
        if m !== nothing
            key = strip(m.captures[1])
            value = strip(m.captures[2])
            directives[key] = parse_directive_value(value)
        end
    end

    return directives
end

"""
Load package from notebook
"""
function load_package_from_notebook(path::String)
    nb = parse_notebook(path)

    for cell in nb["cells"]
        if cell["cell_type"] != "code"
            continue
        end

        source = join(cell["source"], "")
        directives = parse_directives(source)

        if haskey(directives, "module")
            # Extract code (everything after directives)
            code = extract_code(source)

            # Eval the struct and compute function
            eval(Meta.parse(code))

            # Register module
            register_module_from_directives(directives)
        end
    end
end
```

**That's it! ~100 lines of simple Julia code.**

### No External Dependencies Needed

**Current dependencies**:
- JSON.jl (already have it)
- LightXML.jl (for .vt files)

**Don't need**:
- ❌ Quarto
- ❌ IJulia.jl (for parsing - users need it to run notebooks)
- ❌ YAML.jl (can parse simple directives with regex)
- ❌ Pandoc
- ❌ Any Lua

**Simpler is better!**

## Comparison

### Complex Approach (nbdev-style)
```
.ipynb → Quarto → Lua filter → JSON → Julia → Workflow
```
- Multiple tools
- Multiple languages (Julia + Lua)
- External dependencies

### Simple Approach (direct)
```
.ipynb → Julia parser → Workflow
```
- One tool
- One language
- Minimal dependencies

**Simple wins!**

## What About Documentation?

### Users Can Choose

**Option 1**: Just use the notebook
- Open in Jupyter/VSCode
- Markdown cells are the documentation
- Run cells to see results
- **No rendering needed**

**Option 2**: Export from Jupyter
- File → Export → HTML
- Built-in Jupyter feature
- **No Quarto needed**

**Option 3**: Use Quarto (if they want)
- `quarto render workflow.ipynb`
- Professional output
- **Optional, not required**

**We don't need to build this!**

## Updated Implementation Plan

### Simplified Timeline: 8-9 weeks

| Phase | Duration | What Changed |
|-------|----------|--------------|
| 1. Parser | 1.5 weeks | **Simpler** - No Quarto, just JSON |
| 2. Package Loading | 2 weeks | Same |
| 3. Workflow Parser | 2 weeks | Same |
| 4. Execution | 1 week | Same |
| 5. Conversion | 1.5 weeks | **Simpler** - Direct JSON manipulation |
| 6. Git Integration | 1 week | Same |
| 7. Documentation | 1 week | Same |

**Total: 9 weeks instead of 11**

**Saved 2 weeks by not adding Quarto complexity!**

### Phase 1: Parser (Simplified)

**Week 1**:
1. Parse .ipynb (JSON parsing) - 1 day
2. Extract directives (regex) - 1 day
3. Parse directive values - 1 day
4. Extract code from cells - 1 day
5. Tests - 1 day

**Week 2 (first half)**:
6. Parse package metadata - 1 day
7. Parse module directives - 1 day
8. Integration tests - 0.5 days

**Done in 1.5 weeks instead of 2!**

## Final Decision

### Do This

✅ Parse .ipynb directly (simple JSON)
✅ Extract directives with regex (simple patterns)
✅ Eval Julia code directly (no export needed)
✅ Use existing interpreter (already works)

### Don't Do This

❌ Integrate Quarto (adds complexity, little value)
❌ Use Lua filters (another language to maintain)
❌ Generate documentation (notebooks are self-documenting)
❌ Copy nbdev features we don't need

### Summary

**Keep it simple!**

1. .ipynb files are JSON → Parse with JSON.jl
2. Directives are `#| key: value` → Parse with regex
3. Code is Julia → Eval directly
4. Workflows execute → Use existing interpreter

**Total code: ~300 lines of Julia**

No Quarto. No Lua. No complexity.

## Example Code

### Complete Parser (Sketch)

```julia
# src/notebook/parser.jl

using JSON

# Parse notebook
function parse_notebook(path::String)
    return JSON.parsefile(path)
end

# Get code cells
function get_code_cells(nb)
    return filter(c -> c["cell_type"] == "code", nb["cells"])
end

# Parse directives from source
function parse_directives(source::String)
    directives = Dict{String, Any}()
    lines = split(source, '\n')

    i = 1
    while i <= length(lines)
        line = strip(lines[i])

        # Match #| key: value
        if startswith(line, "#|")
            m = match(r"^#\|\s*([^:]+):\s*(.*)$", line)
            if m !== nothing
                key = strip(m.captures[1])
                value = strip(m.captures[2])

                # Handle multi-line YAML (simple version)
                if isempty(value)
                    # Next lines might be nested
                    nested = parse_nested_directives(lines, i+1)
                    directives[key] = nested[1]
                    i = nested[2]  # Skip processed lines
                else
                    directives[key] = value
                end
            end
        elseif !startswith(line, "#|")
            # End of directives
            break
        end

        i += 1
    end

    return directives
end

# Extract code (everything after directives)
function extract_code(source::String)
    lines = split(source, '\n')
    code_lines = []
    in_code = false

    for line in lines
        if in_code
            push!(code_lines, line)
        elseif !startswith(strip(line), "#|")
            in_code = true
            push!(code_lines, line)
        end
    end

    return join(code_lines, '\n')
end

# Load package from notebook
function load_package_from_notebook(path::String)
    nb = parse_notebook(path)
    cells = get_code_cells(nb)

    for cell in cells
        source = join(cell["source"], "")
        directives = parse_directives(source)

        if haskey(directives, "package-meta")
            # Process package metadata
            pkg_meta = directives
        end

        if haskey(directives, "module")
            # Extract and eval code
            code = extract_code(source)

            # This defines the struct and compute function
            eval(Meta.parse(code))

            # Register the module
            module_name = directives["module"]
            # ... create descriptor and register
        end
    end
end
```

**~100 lines. Simple. Clear. No external tools.**

## Conclusion

You were right to question the Quarto complexity. For our use case:

**Quarto adds**: Documentation rendering (nice but optional)
**Quarto costs**: Extra dependency, complexity, learning curve

**Simple parsing adds**: Everything we need
**Simple parsing costs**: ~100 lines of straightforward Julia code

**Decision: Go simple. Parse directly. Skip Quarto.**

Users who want professional docs can use Quarto themselves. We don't need to integrate it.

---

**Ready to implement the simple approach?** 🚀
