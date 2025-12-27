# VisTrailsJL Test Suite

Organized test suite for VisTrailsJL with incremental progress reporting.

## Structure

```
test/
├── runtests.jl          # Main test runner
├── notebooks/           # Notebook system tests (7 files)
├── legacy/              # Legacy .vt file tests (4 files)
├── rendering/           # SVG/graph rendering tests (4 files)
├── execution/           # Workflow execution tests (5 files)
└── archive/             # Archived debug/redundant tests (17 files)
```

## Running Tests

### All Tests
```bash
julia --project=. test/runtests.jl
```

### Specific Test Suite
```bash
julia --project=. test/runtests.jl notebooks    # Notebook system tests
julia --project=. test/runtests.jl legacy       # Legacy .vt file tests
julia --project=. test/runtests.jl rendering    # Rendering tests
julia --project=. test/runtests.jl execution    # Execution tests
```

### Individual Test
```bash
julia --project=. test/notebooks/test_branching.jl
julia --project=. test/notebooks/test_vector_ops.jl
# etc.
```

## Test Suites

### Notebook System Tests (`notebooks/`)

Tests for the notebook-based workflow system (v0.2):

- ✅ **test_notebook_system.jl** - Core notebook functionality (package loading, workflow parsing, pipeline building, execution)
- ✅ **test_conversion.jl** - .vt ↔ notebook conversion, package export
- ✅ **test_http.jl** - HTTPFile module and JSON parsing
- ✅ **test_math.jl** - Math modules (Divide, Add, Multiply)
- ✅ **test_branching.jl** - Branching workflows (one → many connections)
- ✅ **test_optional.jl** - Optional input ports with has_input()
- ✅ **test_vector_ops.jl** - Vector operations (Sum, Cross, Dot, ElementwiseProduct)

**Status**: 7/7 passing (100%) ✅

### Legacy .vt File Tests (`legacy/`)

Tests for loading and parsing legacy Python VisTrails .vt XML files:

- **test_vistrail.jl** - General .vt file loading (requires command-line argument)
- **test_action_replay.jl** - Action replay system (requires command-line argument)
- **test_version_tree_structure.jl** - Version tree parsing (requires command-line argument)
- **test_tags.jl** - Tag management (requires command-line argument)

**Status**: 0/4 passing (require .vt file path as argument, not standalone tests)

**Note**: These are development scripts, not automated tests. Run with:
```bash
julia --project=. test/legacy/test_vistrail.jl examples/gcd.vt
```

### Rendering Tests (`rendering/`)

Tests for SVG and graph rendering:

- **test_svg_rendering.jl** - SVG generation (needs path fixes)
- **test_pipeline_rendering.jl** - Pipeline graph rendering (needs path fixes)
- **test_version_tree_rendering.jl** - Version tree visualization (needs path fixes)
- **test_workflow_rendering.jl** - Workflow graph rendering (needs path fixes)

**Status**: 0/4 passing (need to replace old `include()` statements with VisTrailsJL module)

**Note**: These use old development patterns. The underlying rendering functionality works (used by conversion tests).

### Execution Tests (`execution/`)

Tests for workflow and module execution:

- ✅ **test_logging_simple.jl** - Execution logging (provenance tracking)
- **test_python_modules.jl** - Python interop (needs path fixes)
- **test_python_advanced.jl** - Advanced Python features (needs path fixes)
- **test_pythoncalc_params.jl** - PythonCalc parameters (needs path fixes)
- **test_port_specs.jl** - Port specifications (needs path fixes)

**Status**: 1/5 passing (20%)

**Note**: test_logging_simple.jl has been updated to use VisTrailsJL module properly. Other tests need similar fixes.

## Test Output

The test runner provides incremental progress:

```
======================================================================
📦 Notebook System Tests
======================================================================
Found 7 test file(s)

[1/7] Running test_notebook_system... ✅ PASSED
[2/7] Running test_conversion... ✅ PASSED
[3/7] Running test_http... ✅ PASSED
[4/7] Running test_math... ✅ PASSED
[5/7] Running test_branching... ✅ PASSED
[6/7] Running test_optional... ✅ PASSED
[7/7] Running test_vector_ops... ✅ PASSED

----------------------------------------------------------------------
✅ Suite PASSED: 7/7 tests

======================================================================
🎉 ALL TESTS PASSED: 7/7
======================================================================
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

This allows integration with CI/CD systems.

## Adding New Tests

1. Create test file in appropriate directory:
   ```julia
   using Test
   using VisTrailsJL

   @testset "My Feature" begin
       # Your tests here
   end
   ```

2. Add to `runtests.jl` in the appropriate test suite configuration.

3. Run to verify:
   ```bash
   julia --project=. test/runtests.jl <category>
   ```

## Archived Tests

The `archive/` directory contains:
- Debug scripts from early development
- Redundant test files that were consolidated
- Sample output files

These are preserved for reference but not part of the active test suite.

## Notes

- Tests run as independent subprocesses to avoid module conflicts
- Each test file should be runnable standalone
- Use `@testset` to group related tests
- Tests should be deterministic (no random failures)
