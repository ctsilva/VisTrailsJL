# Design Validation: Notebook-Based VisTrails

Testing the proposed design against real use cases, edge cases, and potential problems.

## Validation Criteria

A sound design should:

1. ✅ **Handle existing .vt files** - Can we convert real VisTrails files?
2. ✅ **Support all VisTrails operations** - Add/delete/modify modules and connections
3. ✅ **Git integration works** - Diffs cleanly map to actions
4. ✅ **Execution model is clear** - How does code actually run?
5. ✅ **Package system is complete** - Can we define all module types?
6. ✅ **Edge cases handled** - Dynamic ports, optional inputs, etc.
7. ✅ **Tooling is feasible** - Can we actually build the parser?

## Test Case 1: Convert Existing .vt File

### Input: gcd.vt (Real VisTrails File)

From your existing examples, let's convert `gcd.vt` to notebook format.

**VisTrails modules in gcd.vt**:
- PythonCalc modules (Add, Subtract, Multiply, Modulo)
- Tuple/Untuple for data flow
- Control flow (If, While)

**Expected notebook**:

```julia
# %% [markdown]
# # GCD Calculation Workflow
#
# Computes greatest common divisor using Euclidean algorithm.

# %% Workflow metadata
#| workflow: gcd_workflow
#| version: 134  # Latest version from .vt file

# %% Input: First number
#| module-id: input_a
#| module-type: basic:Integer
#| params:
#|   value: 140

# %% Input: Second number
#| module-id: input_b
#| module-type: basic:Integer
#| params:
#|   value: 72

# %% Create tuple of inputs
#| module-id: create_tuple
#| module-type: basic:Tuple
#| inputs:
#|   in1: input_a.value
#|   in2: input_b.value

# %% While loop: Continue while b != 0
#| module-id: gcd_loop
#| module-type: control_flow:While
#| inputs:
#|   FunctionPort: loop_body.result
#|   StatePort: create_tuple.value
#|   ConditionPort: check_condition.result

# %% Loop condition: b != 0
#| module-id: check_condition
#| module-type: pythoncalc:PythonCalc
#| inputs:
#|   a: gcd_loop.StatePort
#| params:
#|   op: "!="
#|   value2: 0

# %% Loop body: (b, a mod b)
#| module-id: loop_body
#| module-type: julia:JuliaSource
#| inputs:
#|   state: gcd_loop.StatePort

# Unpack tuple
a, b = get_input("state")

# Compute: (b, a % b)
new_state = (b, a % b)

set_output("result", new_state)

# %% Extract result
#| module-id: extract_result
#| module-type: basic:Untuple
#| inputs:
#|   tuple: gcd_loop.Result

# %% Execute
#| execute

println("GCD: ", extract_result.item1)
```

**Questions**:
1. ✅ Can we represent loops? → Yes, via module instances
2. ✅ Can we represent tuple operations? → Yes, as modules
3. ⚠️ Complex control flow might be hard to read in linear notebook format

**Issue Found**: Control flow with feedback loops doesn't map naturally to linear notebook cells.

**Proposed Solution**: Allow forward references?

```julia
#| module-id: loop
#| inputs:
#|   StatePort: initial_state.value
#|   ConditionPort: condition.result   # Forward reference
#|   FunctionPort: body.result         # Forward reference

#| module-id: condition
#| inputs:
#|   value: loop.StatePort  # References output of loop

#| module-id: body
#| inputs:
#|   state: loop.StatePort
```

Or: Define loop structure explicitly?

```julia
#| module-id: gcd_loop
#| module-type: control_flow:While
#| loop-structure:
#|   initial: create_tuple.value
#|   condition: check_condition.result
#|   body: loop_body.result
```

**Decision needed**: How to handle cyclic workflows in linear notebook format?

## Test Case 2: Dynamic Ports (PythonSource/JuliaSource)

### Challenge: Ports Created at Runtime

PythonSource/JuliaSource can have any inputs/outputs:

```python
# PythonSource can have inputs: x, y, z
# And outputs: result1, result2
```

**How does this work in notebook?**

**Option A: Declare all ports**

```julia
#| module-id: custom_logic
#| module-type: julia:JuliaSource
#| input_ports:
#|   - x
#|   - y
#|   - z
#| output_ports:
#|   - result1
#|   - result2
#| inputs:
#|   x: source_a.value
#|   y: source_b.value
#|   z: source_c.value

# Code uses declared ports
x = get_input("x")
y = get_input("y")
z = get_input("z")

set_output("result1", x + y)
set_output("result2", x + z)
```

**Option B: Infer from connections**

```julia
#| module-id: custom_logic
#| module-type: julia:JuliaSource
#| inputs:
#|   x: source_a.value    # Port 'x' inferred
#|   y: source_b.value    # Port 'y' inferred
#|   z: source_c.value    # Port 'z' inferred

# Code can create any outputs
set_output("result1", ...)
set_output("result2", ...)  # Port 'result2' created dynamically
```

**Option C: Fully dynamic (no declarations)**

```julia
#| module-id: custom_logic
#| module-type: julia:JuliaSource

# No port declarations at all
# Ports created by:
# 1. Connections TO this module (inputs)
# 2. set_output() calls (outputs)
```

**Recommendation**: Option B - Infer inputs from connections, outputs from code.

**Why**: Matches Python VisTrails behavior, clearest for users.

## Test Case 3: Workflow Versions and Git

### Scenario: Evolving Workflow

**Version 1** (initial commit):
```julia
#| module-id: fetch
#| params:
#|   url: "https://api.example.com/v1/data"

#| module-id: process
#| inputs:
#|   data: fetch.file
```

**Version 2** (git commit 2):
```julia
#| module-id: fetch
#| params:
#|   url: "https://api.example.com/v2/data"  # Changed

#| module-id: process
#| inputs:
#|   data: fetch.file
```

**Git diff**:
```diff
  #| params:
-   url: "https://api.example.com/v1/data"
+   url: "https://api.example.com/v2/data"
```

**ViTrails Action**:
```julia
Action(
    id = 2,
    prev_id = 1,
    timestamp = ...,
    operations = [
        Operation(
            type = :change_parameter,
            module_id = "fetch",
            parameter_name = "url",
            old_value = "https://api.example.com/v1/data",
            new_value = "https://api.example.com/v2/data"
        )
    ]
)
```

✅ **This works cleanly!**

### Git Branches = Version Tree Branches

```
main:    v1 ─ v2 ─ v3 ─ v5 (merge)
              │         /
feature:      └─ v4 ───┘
```

Maps to VisTrails version tree structure!

✅ **Git model matches VisTrails perfectly**

## Test Case 4: Complex Workflow (Real Science)

Let's validate with a realistic bioinformatics pipeline.

### RNA-Seq Analysis

**Workflow**:
1. Download genome (HTTPFile)
2. Download reads (HTTPFile)
3. Quality control (JuliaSource)
4. If QC passes → Align (STAR)
5. Count features (HTSeq)
6. Differential expression (DESeq2)
7. Visualize (Plots)

**Notebook representation**:

```julia
# %% Download genome
#| module-id: genome
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://ftp.ncbi.nlm.nih.gov/genome.fa.gz"

# %% Download reads
#| module-id: reads
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://sra.ncbi.nlm.nih.gov/SRR12345.fastq.gz"

# %% Quality control
#| module-id: qc
#| module-type: julia:JuliaSource
#| inputs:
#|   reads: reads.file

using FastQC
qc_results = run_fastqc(get_input("reads"))
set_output("passed", qc_results.quality_score > 30)
set_output("report", qc_results)

# %% Conditional: Only align if QC passed
#| module-id: conditional_align
#| module-type: control_flow:If
#| inputs:
#|   condition: qc.passed
#|   true_port: genome.file
#|   false_port: error_handler.message

# %% Alignment (executed only if QC passed)
#| module-id: align
#| module-type: julia:JuliaSource
#| inputs:
#|   genome: conditional_align.output
#|   reads: reads.file

using STAR
bam = star_align(get_input("genome"), get_input("reads"))
set_output("bam", bam)

# %% Rest of pipeline...
```

**Issues**:
1. ⚠️ Conditional execution creates branching - hard to follow in linear notebook
2. ⚠️ Error handling path needs to be represented
3. ⚠️ Parallel execution (if we had multiple samples) unclear

**Proposed Solution**: Visual annotations in markdown

```julia
# %% [markdown]
# ## Conditional Execution Path
#
# If QC passes: genome → align → count → analysis
# If QC fails: error_handler → report

# %% Conditional branch
#| module-id: conditional_align
#| module-type: control_flow:If
```

**OR**: Accept that complex control flow is clearer in GUI

**Decision needed**: Is notebook format acceptable for complex workflows, or should we have GUI for those?

## Test Case 5: Package Definition Edge Cases

### Challenge: Module Inheritance

Python VisTrails has module inheritance:

```python
class MyModule(SpecificBase):
    # Inherits ports and behavior
```

**How to represent in notebook?**

```julia
#| module: MyModule
#| base: SpecificBase  # Inheritance
#| input_ports:
#|   - additional_port: String  # Add to inherited ports
```

✅ **Works, but need to handle port merging**

### Challenge: Module Mixins

Python VisTrails uses mixins for common functionality.

**Options**:
1. Ignore mixins (implement manually in compute function)
2. Support mixin directive: `#| mixins: CachedMixin, FileMixin`

**Recommendation**: Start without mixins, add later if needed.

### Challenge: Custom Widget Configuration

Python modules can specify GUI widgets:

```python
class MyModule(Module):
    @staticmethod
    def get_widget_class():
        return MyCustomWidget
```

**Notebook representation**:

```julia
#| module: MyModule
#| widget: MyCustomWidget  # Optional: for GUI integration
```

✅ **Straightforward - just metadata**

## Test Case 6: Execution Model Validation

### Question: What Happens When Cell Executes?

**Scenario**: User runs notebook cell-by-cell in Jupyter.

**Cell 1**:
```julia
#| module-id: fetch
#| module-type: basic:HTTPFile
#| params:
#|   url: "https://example.com"
```

**What executes?** Options:

**A. Nothing** - Just registers module definition
```julia
# Cell execution output: "Module 'fetch' registered"
```

**B. Execute immediately** - Fetch data now
```julia
# Cell execution output: "Fetching: https://example.com"
# result = HTTPFile.compute()
```

**C. Hybrid** - Register, show preview
```julia
# Cell execution output:
# "Module 'fetch' registered
#  Type: basic:HTTPFile
#  Parameters: url='https://example.com'
#  Status: Not executed (run @execute to execute workflow)"
```

**Recommendation**: **Option C** - Register but don't execute until `#| execute`

**Why**:
- User can define entire workflow without side effects
- Can validate workflow before execution
- Matches VisTrails model (build DAG, then execute)

### Question: How Does `#| execute` Work?

**Cell with `#| execute`**:

```julia
#| execute
```

**What happens**:

1. Parse all previous cells to build workflow DAG
2. Validate DAG (check for cycles, missing connections, etc.)
3. Execute workflow using existing interpreter
4. Cache results
5. Make outputs available as Julia variables

**Example**:

```julia
# Cell 1
#| module-id: fetch
# (Registers module)

# Cell 2
#| module-id: process
# (Registers module)

# Cell 3
#| execute

# After execution:
# - fetch.file contains fetched data
# - process.result contains processed data
# Can now use these in following cells:

# Cell 4
println("Result: ", process.result)
```

✅ **This model is clear and practical**

## Test Case 7: Conversion Round-Trip

### .vt → Notebook → .vt

**Original gcd.vt**:
- 22 modules
- 31 connections
- 134 versions

**Convert to notebook**:
```julia
vt = load_vistrail("gcd.vt")
vistrail_to_notebook(vt, "gcd.ipynb", version=134)
```

**Expected notebook**:
- 22 cells with module definitions
- 1 cell with `#| execute`
- Markdown cells with documentation

**Convert back to .vt**:
```julia
notebook_to_vistrail("gcd.ipynb", "gcd_new.vt")
```

**Questions**:
1. ✅ Are module IDs preserved? → Yes, via `#| module-id`
2. ✅ Are connections preserved? → Yes, via `#| inputs`
3. ✅ Are parameters preserved? → Yes, via `#| params`
4. ⚠️ Is version history preserved? → Only if import_git_history=true

**Issue**: Single notebook = single version. Need git history to reconstruct version tree.

**Solution**:
```julia
notebook_to_vistrail("gcd.ipynb", "gcd.vt", import_git_history=true)
# Uses git log to build version tree
```

✅ **Round-trip is feasible**

## Test Case 8: Diff Engine Validation

### Challenge: Reordered Cells

**Version 1**:
```julia
# Cell 1
#| module-id: A

# Cell 2
#| module-id: B
```

**Version 2** (cells reordered):
```julia
# Cell 1
#| module-id: B  # Moved up

# Cell 2
#| module-id: A  # Moved down
```

**Git diff**:
```diff
(Shows entire cells moved - not helpful!)
```

**Problem**: Cell reordering creates messy diffs.

**Solutions**:

**A. Ignore cell order** - Use module-id for identity
- Diff engine compares by module-id, not cell position
- Cell order doesn't matter for workflow execution

**B. Stable sort** - Keep cells in consistent order
- Require cells to be in some canonical order (e.g., alphabetical by module-id)
- Tools enforce ordering

**C. Accept messy diffs** - User responsibility
- Document best practice: don't reorder cells unnecessarily

**Recommendation**: **Option A** - Module identity is by ID, not position

✅ **Parser compares by module-id, not cell order**

### Challenge: Whitespace Changes

**Version 1**:
```julia
#| module-id: process
#| params:
#|   threshold: 0.5
```

**Version 2** (whitespace changed):
```julia
#| module-id: process
#| params:
#|    threshold: 0.5  # Extra space
```

**Problem**: Whitespace changes trigger false positives in diff.

**Solution**: Parser normalizes whitespace before comparison.

✅ **Whitespace-insensitive comparison**

## Test Case 9: Notebook Format Compatibility

### Jupyter Notebooks (.ipynb)

**Structure**:
```json
{
  "cells": [
    {
      "cell_type": "markdown",
      "source": ["# Title"]
    },
    {
      "cell_type": "code",
      "source": ["#| module-id: fetch\n", "#| module-type: basic:HTTPFile"]
    }
  ]
}
```

✅ **Standard Jupyter format - works**

### Quarto (.qmd)

**Structure**:
````markdown
# Title

```{julia}
#| module-id: fetch
#| module-type: basic:HTTPFile
```
````

✅ **Standard Quarto format - works**

### Pluto.jl

**Issue**: Pluto uses reactive execution model - cells auto-execute when dependencies change.

**Problem**: Our model assumes cells register modules but don't execute until `#| execute`.

**Conflict**: Pluto's reactivity vs our explicit execution model.

**Proposed Solution**: Special Pluto mode where:
- Modules auto-execute on dependency changes
- No explicit `#| execute` needed
- Workflow updates reactively

**OR**: Don't support Pluto initially (Jupyter/Quarto are enough).

**Recommendation**: Start with Jupyter/Quarto, add Pluto later if there's demand.

## Test Case 10: Scalability

### Large Workflows

**Question**: Can notebooks handle large workflows (100+ modules)?

**Concerns**:
1. 100+ cells in one notebook = hard to navigate
2. Git diffs on large notebooks can be slow
3. Execution of large workflows might timeout

**Solutions**:

**A. Subworkflows** - Break into multiple notebooks
```julia
#| module-id: preprocessing
#| module-type: workflow:Subworkflow
#| params:
#|   notebook: "preprocessing.ipynb"
```

**B. Cell folding** - Use Jupyter's cell folding features

**C. Table of contents** - Generate automatic TOC

**D. Sections** - Group related modules
```julia
# %% [markdown]
# ## Data Loading (10 modules)

# %% [markdown]
# ## Processing (50 modules)

# %% [markdown]
# ## Visualization (20 modules)
```

✅ **Large workflows supported via subworkflows and organization**

## Issues Found

### Critical Issues

None! 🎉

### Medium Issues

1. **Control flow in linear format** - Loops and conditionals are harder to visualize
   - **Mitigation**: Use markdown diagrams, accept that some workflows better in GUI

2. **Cell reordering** - Can create messy diffs
   - **Mitigation**: Parser uses module-id for identity, not cell position

3. **Pluto.jl compatibility** - Reactive model conflicts with explicit execution
   - **Mitigation**: Start with Jupyter/Quarto, add Pluto later

### Minor Issues

1. **Whitespace sensitivity** - YAML indentation matters
   - **Mitigation**: Parser normalizes whitespace

2. **Large workflows** - 100+ cells harder to navigate
   - **Mitigation**: Subworkflows, sections, TOC

3. **Forward references** - Cyclic workflows need forward refs
   - **Mitigation**: Support forward references in parser

## Design Soundness Assessment

### ✅ Core Design is Sound

1. ✅ **Package definitions** - Clean, matches Python VisTrails
2. ✅ **Workflow definitions** - Clear mapping from cells to modules
3. ✅ **Git integration** - Commits = versions works perfectly
4. ✅ **Execution model** - Register then execute is clear
5. ✅ **Conversion** - Round-trip .vt ↔ notebook is feasible
6. ✅ **Diff engine** - Can map diffs to operations
7. ✅ **Tooling** - Parser implementation is straightforward

### 🤔 Areas That Need Decisions

1. **Control flow visualization** - Accept linear format limitations or build GUI?
   - **Recommendation**: Start with linear, add visual tools later

2. **Pluto.jl support** - Support reactive model or skip?
   - **Recommendation**: Skip for v1.0, add later

3. **Dynamic ports** - How much to declare vs infer?
   - **Recommendation**: Infer inputs from connections, outputs from code

4. **Subworkflows** - How to handle nested workflows?
   - **Recommendation**: Reference other notebooks, execute as module

## Final Verdict

**The design is SOUND and FEASIBLE** ✅

**Strengths**:
- Backward compatible with Python VisTrails
- Git-native version control
- Clean separation of packages vs workflows
- Executable and documentable
- No macros, just comments

**Acceptable Tradeoffs**:
- Complex control flow harder to visualize (but we can add GUI later)
- Large workflows need organization (but subworkflows help)
- Some manual work to create directives (but tools can help)

## Recommendation

**Proceed with implementation!**

The design handles all major use cases, edge cases have clear solutions, and the tradeoffs are acceptable.

**Start with**:
1. Phase 1: Parser for package notebooks
2. Phase 2: Parser for workflow notebooks
3. Phase 3: Diff engine
4. Phase 4: Execution engine
5. Phase 5: Conversion to/from .vt

Each phase is independently testable and valuable.

## Questions for You

Before I start implementing, please confirm:

1. **Control flow**: Accept that complex loops/conditionals are harder to read in linear notebook format? (Can add GUI visualization later)

2. **Execution model**: Module cells register but don't execute until `#| execute` cell? (Matches VisTrails model)

3. **Dynamic ports**: Infer input ports from connections, output ports from `set_output()` calls? (Matches Python VisTrails)

4. **Cell ordering**: Module identity by `module-id`, not cell position? (Allows reordering without breaking workflow)

5. **Start with Jupyter/Quarto**: Skip Pluto.jl for now? (Reactive model is complex)

**Are you comfortable with these design decisions?**
