# Next Steps for VisTrailsJL Development

## Current Status (as of 2025-12-27)

### ✅ Completed in This Session
- **Matplotlib package implementation** (v0.1)
  - Core modules: MplFigure, MplFigureOutput, MplLinePlot, MplScatter, MplBar, MplHist
  - Successfully executes real Python VisTrails example: `lineplot_ex3.vt`
  - Generates matplotlib PNG output (16KB)
  - Fixed critical action replay bug for small pipelines
  - Implemented JSON parameter parsing for .vt compatibility
  - Added "self" output port for Python VisTrails compatibility

- **Automated .vt → Notebook conversion**
  - Demonstrated `vistrail_workflow_to_notebook()` function works
  - Created test showing round-trip conversion and execution
  - Generated example: `lineplot_ex3_converted.ipynb`

### 📂 Key Files Modified
- `julia/src/packages/matplotlib/matplotlib.jl` (NEW - 264 lines)
- `julia/src/packages/matplotlib/init.jl` (MODIFIED - 124 lines)
- `julia/src/db/services/io.jl` (FIXED - action replay for small pipelines)
- `julia/test/matplotlib/test_lineplot_ex3.jl` (NEW - end-to-end test)
- `julia/test/matplotlib/test_notebook_conversion.jl` (NEW - conversion test)

## Recommended Next Steps

### Option 1: Expand Matplotlib Package Coverage
Test and implement more matplotlib examples from `examples/matplotlib/`:
- [ ] `bar_ex1.vt` - Bar charts
- [ ] `hist_ex1.vt` - Histograms
- [ ] `scatter.vt` - Scatter plots
- [ ] Property modules (MplLine2DProperties, MplRectangleProperties, etc.)
- [ ] More complex plot types (contour, pie, polar, etc.)

**Effort**: 1-2 days per example
**Benefit**: More complete matplotlib compatibility

### Option 2: Test Other Package Types
Try translating other simpler Python VisTrails packages:
- [ ] **NumPy package** - Array operations (likely easier than VTK)
- [ ] **SciPy package** - Scientific computing functions
- [ ] **URL/HTTP package** - Web data fetching (we have HTTPFile already)

**Effort**: 2-4 days per package
**Benefit**: Validates package system works broadly

### Option 3: Focus on Notebook Workflow System (v0.2)
Continue the v0.2 vision of notebook-based workflows:
- [ ] Implement directive parser for package notebooks
- [ ] Implement directive parser for workflow notebooks (expand existing)
- [ ] Build diff engine (notebook diffs → VisTrails actions)
- [ ] Git history importer (commits → version tree)
- [ ] Quarto integration for publication-ready reports

**Effort**: 6-9 weeks (per PACKAGE_DEFINITIONS_V2.md)
**Benefit**: Complete the git-native workflow vision

### Option 4: Production Hardening
Focus on robustness and edge cases:
- [ ] Error handling in module execution
- [ ] Better error messages for missing packages
- [ ] Validation of notebook directive syntax
- [ ] More comprehensive tests for existing features
- [ ] Documentation improvements

**Effort**: 2-3 weeks
**Benefit**: More stable, user-ready system

## Technical Debt & Known Issues

### Minor Issues
- Some matplotlib modules not yet implemented (contour, pie, polar, etc.)
- No property modules yet (styling/appearance configuration)
- Lightweight rendering still needed for packages we haven't implemented

### Design Questions
- Should we prioritize backward compatibility (.vt files) or notebook-first approach?
- How much of Python VisTrails' package ecosystem do we want to replicate?
- When to switch focus from v0.1 (execution) to v0.2 (notebook workflows)?

## Recommendation

**Suggested path**: Try **Option 2** (test another package type like NumPy) to validate the package system is robust, then move to **Option 3** (notebook workflow system) to complete the v0.2 vision.

This balances:
- ✅ Validation that our architecture works broadly
- ✅ Moving toward the innovative notebook-based approach
- ✅ Not getting stuck replicating all of Python VisTrails

## Session Context for Next Time

### What Just Worked
- Real .vt file execution with matplotlib
- Automated conversion to notebooks
- JSON parameter parsing from .vt files
- Lambda/function output pattern for plot modules

### Key Patterns Established
```julia
# Parse JSON parameters from .vt files
function parse_param_value(val)
    if val isa String && startswith(val, "[")
        return JSON.parse(val)
    end
    return val
end

# Module lifecycle
self.outputs["result"] = computed_value
self.uptodate = true
self.cache_state = :valid
return self.outputs
```

### Commands to Remember
```bash
# Run matplotlib tests
cd julia && julia --project=. test/matplotlib/test_lineplot_ex3.jl
cd julia && julia --project=. test/matplotlib/test_notebook_conversion.jl

# Test other .vt files
cd julia && julia --project=. -e 'include("src/VisTrailsJL.jl"); using .VisTrailsJL; ...'
```
