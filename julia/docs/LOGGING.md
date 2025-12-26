# Execution Logging

The Julia VisTrails implementation includes comprehensive execution logging that tracks workflow and module executions, similar to the Python VisTrails logging system.

## Overview

The logging system captures:
- **Machine information**: Hardware and OS details
- **Module executions**: Individual module timing, caching, and errors
- **Workflow executions**: Complete workflow runs with all module executions
- **Execution logs**: Historical record of all workflow runs

## Components

### Machine

Stores information about the machine where execution occurred:

```julia
Machine(
    id=1,
    name="hostname",          # Automatically detected
    os="Darwin",             # Automatically detected
    architecture="aarch64",  # Automatically detected
    processor="Apple M3",    # Automatically detected
    ram=131072              # MB, automatically detected
)
```

### ModuleExec

Records a single module execution:

```julia
ModuleExec(
    id=-1,                    # Auto-assigned when added to workflow
    module_id=42,            # Module ID in pipeline
    module_name="ReadFile",  # Module type name
    ts_start=now(),          # Start timestamp
    ts_end=nothing,          # End timestamp (set on completion)
    cached=false,            # Was result from cache?
    completed=0,             # 1=success, -1=error, 0=incomplete
    error="",                # Error message if failed
    machine_id=1,            # Which machine executed this
    annotations=Dict()       # Additional metadata
)
```

**Status codes:**
- `1` = Success
- `-1` = Failed
- `0` = Incomplete/Running

**Helper functions:**
```julia
mark_completed!(mod_exec)                    # Mark as successful
mark_failed!(mod_exec, "error message")      # Mark as failed
mark_cached!(mod_exec)                       # Mark as cached
duration(mod_exec)                           # Get execution time
```

### WorkflowExec

Records a complete workflow execution:

```julia
WorkflowExec(
    id=-1,
    user="username",              # Automatically detected from ENV["USER"]
    ip="127.0.0.1",              # Automatically detected
    session=1,
    vt_version="0.1.0-julia",
    ts_start=now(),
    ts_end=nothing,
    parent_type="vistrail",
    parent_id="",
    parent_version=-1,            # Version number executed
    name="",
    completed=0,                  # 1=success, -1=error, 0=incomplete
    machines=Machine[],
    module_execs=ModuleExec[],
    annotations=Dict()
)
```

**Helper functions:**
```julia
add_machine!(wf_exec, machine)               # Add machine info
add_module_exec!(wf_exec, mod_exec)         # Add module execution
add_annotation!(wf_exec, "key", "value")    # Add metadata
mark_completed!(wf_exec)                     # Mark as successful
mark_failed!(wf_exec, "error")              # Mark as failed
duration(wf_exec)                            # Get total time
is_successful(wf_exec)                       # Check if completed
failed_modules(wf_exec)                      # Get failed modules
cached_modules(wf_exec)                      # Get cached modules
```

### Log

Container for multiple workflow executions:

```julia
Log(
    id=-1,
    vistrail_id="",
    workflow_execs=WorkflowExec[]
)
```

**Helper functions:**
```julia
add_workflow_exec!(log, wf_exec)            # Add workflow execution
get_last_exec_id(log)                        # Get latest execution ID
get_execs_for_version(log, version)         # Get executions for version
successful_execs(log)                        # Get successful executions
failed_execs(log)                           # Get failed executions
print_summary(log)                           # Print formatted summary
```

## Usage

### Basic Logging

```julia
include("src/core/log/machine.jl")
include("src/core/log/module_exec.jl")
include("src/core/log/workflow_exec.jl")
include("src/core/log/log.jl")

# Create workflow execution record
wf_exec = WorkflowExec(parent_version=5, name="My Workflow")

# Add machine info
machine = current_machine(1)
add_machine!(wf_exec, machine)

# Record module execution
mod_exec = ModuleExec(module_id=1, module_name="ReadFile", machine_id=1)
# ... execute module ...
mark_completed!(mod_exec)
add_module_exec!(wf_exec, mod_exec)

# Complete workflow
mark_completed!(wf_exec)
```

### With Interpreter

The interpreter automatically creates execution logs when `enable_logging=true`:

```julia
include("src/core/interpreter/default.jl")

# Execute with logging (default)
cache, workflow_exec = execute_pipeline(pipeline)

# Execute without logging
cache, workflow_exec = execute_pipeline(pipeline, enable_logging=false)
```

The interpreter automatically:
- Creates `WorkflowExec` when execution starts
- Creates `ModuleExec` for each module
- Tracks cached vs computed modules
- Records execution timing
- Captures errors with stack traces
- Marks completion status

### Viewing Logs

```julia
# Print summary
if workflow_exec !== nothing
    println("Workflow completed: ", is_successful(workflow_exec))
    println("Duration: ", duration(workflow_exec))
    println("Failed modules: ", length(failed_modules(workflow_exec)))
    println("Cached modules: ", length(cached_modules(workflow_exec)))

    for mod_exec in workflow_exec.module_execs
        status = mod_exec.completed == 1 ? "✓" : "✗"
        println("$status $(mod_exec.module_name): $(duration(mod_exec))")
    end
end

# Use Log container for multiple executions
log = Log(vistrail_id="my_vistrail")
add_workflow_exec!(log, workflow_exec)
print_summary(log)  # Formatted summary
```

## Example Output

```
============================================================
Execution Log Summary
============================================================

Total executions: 1
  Successful: 1
  Failed: 0

Executions by version:
  Version 5: 1 executions

Recent executions:
  ✓ Version 5 - 2025-10-21T01:27:37.476 (319ms)

Workflow Execution:
  User: csilva
  Version: 5
  Duration: 319ms

Machines:
  - hostname (Darwin aarch64)
    RAM: 131072 MB

Module Executions:
  ✓ Module 1: ReadFile (59ms)
  ✓ Module 2: ProcessData [CACHED] (3ms)
  ✗ Module 3: WriteFile (35ms)
      Error: Permission denied

Statistics:
  Total modules: 3
  Cached: 1
  Failed: 1
```

## Architecture Comparison

### Python VisTrails

The Python implementation stores logs in:
- `.vtl` files (XML format) for standalone executions
- Log files within `.vt` bundles (ZIP)
- Database tables when using DB backend

Key files:
- `vistrails/core/log/log.py` - Log container
- `vistrails/core/log/workflow_exec.py` - Workflow execution
- `vistrails/core/log/module_exec.py` - Module execution
- `vistrails/core/log/machine.py` - Machine info

### Julia Implementation

The Julia implementation follows the same structure:
- `src/core/log/log.jl` - Log container
- `src/core/log/workflow_exec.jl` - Workflow execution
- `src/core/log/module_exec.jl` - Module execution
- `src/core/log/machine.jl` - Machine info

Currently logs are in-memory only. Future work:
- XML serialization (for .vtl files)
- Integration with .vt bundle loading/saving
- Database backend support

## Testing

Run the logging test:

```bash
cd julia
julia --project=. test_logging_simple.jl
```

This tests:
- Machine information detection
- Module execution tracking (success, cached, failed)
- Workflow execution tracking
- Duration calculation
- Log container and queries
- Summary formatting

## Future Work

- [ ] XML serialization for .vtl files
- [ ] Load logs from .vt bundles
- [ ] Save logs to .vt bundles
- [ ] Database backend support
- [ ] Log querying and filtering
- [ ] Log visualization
- [ ] Group execution support (for loops/map)
- [ ] Streaming execution logs
