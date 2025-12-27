# Test Organization Plan

## Current Situation

Found **24 test files** in the `julia/` directory root that were created during early development. Analysis shows:

### By Category:
- **VT Loading** (20 files): Tests for loading legacy .vt XML files
- **Execution** (3 files): Tests for workflow/module execution
- **Other** (1 file): Miscellaneous tests

### Issues:
- ⚠️ **Location**: All tests in root directory, should be in `test/`
- ⚠️ **Old patterns**: Many use `Pkg.activate(".")` and direct `include()` instead of `using VisTrailsJL`
- ⚠️ **No structure**: No clear organization or test suite runner
- ⚠️ **Overlap**: Some functionality may already be tested in `test/notebooks/`

## Recommended Organization

### Structure:
```
julia/
├── test/
│   ├── legacy/              # Legacy .vt file loading/parsing
│   │   ├── test_vt_loading.jl
│   │   ├── test_action_replay.jl
│   │   ├── test_version_tree.jl
│   │   └── test_tags.jl
│   ├── rendering/           # SVG/graph rendering
│   │   ├── test_pipeline_rendering.jl
│   │   ├── test_version_tree_rendering.jl
│   │   └── test_svg_generation.jl
│   ├── execution/           # Workflow execution (non-notebook)
│   │   ├── test_python_modules.jl
│   │   └── test_execution_logging.jl
│   ├── notebooks/           # Notebook-based system (CURRENT)
│   │   ├── test_branching.jl
│   │   ├── test_optional.jl
│   │   ├── test_vector_ops.jl
│   │   ├── test_math.jl
│   │   ├── test_http.jl
│   │   └── ...
│   └── runtests.jl          # Main test runner
```

## Test File Analysis

### VT Loading Tests (20 files)

These test the legacy .vt XML file loading system:

**Keep & Consolidate:**
1. `test_action_replay.jl` - ✅ Core feature: action replay system
2. `test_version_tree_structure.jl` - ✅ Core feature: version tree
3. `test_tags.jl` - ✅ Core feature: tag management
4. `test_vistrail.jl` - ✅ General .vt loading

**Consolidate into test_vt_examples.jl:**
- `test_gcd_v100.jl` - GCD workflow version 100
- `test_gcd_workflow.jl` - GCD workflow (fallback)
- `test_lung.jl` - Lung dataset
- `test_lung_all.jl` - Lung all versions
- `test_lung_workflow.jl` - Lung workflow specific
- `test_multiple_vistrails.jl` - Multiple files

**Rendering - Move to test/rendering/:**
- `test_pipeline_rendering.jl`
- `test_version_tree_rendering.jl`
- `test_workflow_rendering.jl`
- `test_svg_rendering.jl`

**Debug/One-off - Archive or Remove:**
- `test_tag_debug.jl` - Debug script
- `test_terse_graph_debug.jl` - Debug script
- `test_manual_tags.jl` - Manual testing
- `test_parse_without_packages.jl` - Edge case test
- `test_raw_vt_parsing.jl` - Low-level parsing test

**Python-specific:**
- `test_python_modules.jl` - Keep in test/execution/
- `test_python_advanced.jl` - Keep in test/execution/
- `test_pythoncalc_params.jl` - Consolidate with above
- `test_port_specs.jl` - Consolidate with above

**Logging:**
- `test_logging_simple.jl` - Move to test/execution/

### Execution Tests (3 files)

**Keep:**
1. `test_python_modules.jl` - ✅ Python interop testing
2. `test_python_advanced.jl` - ✅ Advanced Python features
3. `test_logging_simple.jl` - ✅ Execution logging

**Action:** Move to `test/execution/`, update to use `using VisTrailsJL`

## Implementation Plan

### Phase 1: Create Directory Structure ✅
```bash
mkdir -p test/legacy
mkdir -p test/rendering
mkdir -p test/execution
# test/notebooks/ already exists
```

### Phase 2: Move & Consolidate Tests

**A. Legacy Tests** (test/legacy/)
```bash
# Core functionality
mv test_action_replay.jl test/legacy/
mv test_version_tree_structure.jl test/legacy/
mv test_tags.jl test/legacy/
mv test_vistrail.jl test/legacy/

# Create consolidated test
cat > test/legacy/test_vt_examples.jl <<EOF
# Consolidates: gcd_v100, gcd_workflow, lung, lung_all, lung_workflow, multiple_vistrails
...
EOF
```

**B. Rendering Tests** (test/rendering/)
```bash
mv test_pipeline_rendering.jl test/rendering/
mv test_version_tree_rendering.jl test/rendering/
mv test_workflow_rendering.jl test/rendering/
mv test_svg_rendering.jl test/rendering/
```

**C. Execution Tests** (test/execution/)
```bash
mv test_python_modules.jl test/execution/
mv test_python_advanced.jl test/execution/
mv test_logging_simple.jl test/execution/
mv test_pythoncalc_params.jl test/execution/
mv test_port_specs.jl test/execution/
```

**D. Archive/Remove Debug Tests**
```bash
mkdir -p test/archive
mv test_tag_debug.jl test/archive/
mv test_terse_graph_debug.jl test/archive/
mv test_manual_tags.jl test/archive/
mv test_parse_without_packages.jl test/archive/
mv test_raw_vt_parsing.jl test/archive/
```

### Phase 3: Create Main Test Runner

Create `test/runtests.jl`:
```julia
using Test
using VisTrailsJL

@testset "VisTrailsJL Test Suite" begin

    @testset "Legacy .vt Loading" begin
        include("legacy/test_action_replay.jl")
        include("legacy/test_version_tree_structure.jl")
        include("legacy/test_tags.jl")
        include("legacy/test_vistrail.jl")
        include("legacy/test_vt_examples.jl")
    end

    @testset "Rendering" begin
        include("rendering/test_pipeline_rendering.jl")
        include("rendering/test_version_tree_rendering.jl")
        include("rendering/test_workflow_rendering.jl")
        include("rendering/test_svg_rendering.jl")
    end

    @testset "Execution" begin
        include("execution/test_python_modules.jl")
        include("execution/test_python_advanced.jl")
        include("execution/test_logging_simple.jl")
    end

    @testset "Notebook System" begin
        include("notebooks/test_branching.jl")
        include("notebooks/test_optional.jl")
        include("notebooks/test_vector_ops.jl")
        include("notebooks/test_math.jl")
        include("notebooks/test_http.jl")
    end
end
```

### Phase 4: Update All Tests

For each test file:
1. ✅ Remove `Pkg.activate(".")` (use `Pkg.activate(@__DIR__)` or rely on --project)
2. ✅ Replace `include("src/...")` with `using VisTrailsJL`
3. ✅ Add proper `@testset` structure
4. ✅ Fix hardcoded paths (use `@__DIR__` and `joinpath()`)
5. ✅ Add docstrings explaining what the test does

## Benefits

1. **Better Organization**: Clear separation by functionality
2. **Easier Maintenance**: Know where to find tests
3. **CI/CD Ready**: Can run all tests with `julia --project=test test/runtests.jl`
4. **Less Clutter**: Root directory only has source code
5. **Consolidation**: Reduce 24 files to ~15 well-organized tests

## Migration Commands

```bash
# From julia/ directory

# Create structure
mkdir -p test/legacy test/rendering test/execution test/archive

# Move legacy tests
for f in test_action_replay.jl test_version_tree_structure.jl test_tags.jl test_vistrail.jl; do
    git mv $f test/legacy/
done

# Move rendering tests
for f in test_pipeline_rendering.jl test_version_tree_rendering.jl test_workflow_rendering.jl test_svg_rendering.jl; do
    git mv $f test/rendering/
done

# Move execution tests
for f in test_python_modules.jl test_python_advanced.jl test_logging_simple.jl test_pythoncalc_params.jl test_port_specs.jl; do
    git mv $f test/execution/
done

# Archive debug tests
for f in test_tag_debug.jl test_terse_graph_debug.jl test_manual_tags.jl test_parse_without_packages.jl test_raw_vt_parsing.jl; do
    git mv $f test/archive/
done

# Archive redundant GCD/lung tests (consolidate later)
for f in test_gcd_v100.jl test_gcd_workflow.jl test_lung.jl test_lung_all.jl test_lung_workflow.jl test_multiple_vistrails.jl; do
    git mv $f test/archive/
done
```

## Next Steps

1. Execute migration commands
2. Update each test file to use modern patterns
3. Create consolidated test files
4. Create main test runner
5. Run full test suite and fix any issues
6. Update CI/CD to use new structure
7. Document test organization in README.md
