# Implementation Plan: Notebook-Based VisTrails

Detailed breakdown of implementation steps with time estimates and concrete deliverables.

## Overview

**Total Estimated Time**: 8-10 weeks (2-2.5 months)
**Complexity**: Medium - parsing and code generation, no GUI
**Risk Level**: Low - design validated, clear incremental path

## Phase 1: Directive Parser (Week 1-2)

**Goal**: Parse `#|` directives from notebook cells

### Week 1: Basic Parser

**Tasks**:

1. **Set up notebook parsing infrastructure** (1 day)
   - Add IJulia.jl dependency
   - Add YAML.jl for parsing nested directives
   - Create `src/notebook/` directory structure
   - File: `src/notebook/notebook_io.jl`

2. **Implement directive parser** (2 days)
   - Parse `#| key: value` lines
   - Handle multi-line YAML (e.g., port lists)
   - Extract code vs directives from cell
   - File: `src/notebook/directives.jl`
   ```julia
   function parse_cell_directives(cell_source::String) -> Dict{String, Any}
   function extract_code_without_directives(cell_source::String) -> String
   ```

3. **Parse package metadata** (1 day)
   - Parse `#| package-meta` directive
   - Extract identifier, name, version
   - File: `src/notebook/package_parser.jl`
   ```julia
   struct PackageMetadata
       identifier::String
       name::String
       version::String
       configuration::Dict{String, Any}
   end

   function parse_package_metadata(notebook) -> PackageMetadata
   ```

4. **Parse module directives** (1 day)
   - Parse `#| module:`, `#| input_ports:`, etc.
   - Handle port specifications
   - Handle parameter specifications
   ```julia
   struct ModuleDirectives
       module_name::String
       input_ports::Vector{PortSpec}
       output_ports::Vector{PortSpec}
       parameters::Vector{ParamSpec}
   end

   function parse_module_directives(cell) -> Union{ModuleDirectives, Nothing}
   ```

**Deliverables**:
- `src/notebook/directives.jl` - Core directive parser
- `src/notebook/package_parser.jl` - Package metadata parsing
- Unit tests for directive parsing
- **Test**: Can parse directives from example cells

**Effort**: 5 days (1 week)

### Week 2: Code Extraction

**Tasks**:

1. **Extract struct definitions** (1 day)
   - Find `struct <Name>Module <: Module` in code
   - Validate struct definition
   ```julia
   function extract_struct_definition(code::String, module_name::String) -> Union{Expr, Nothing}
   ```

2. **Extract compute functions** (1 day)
   - Find `function compute(mod, ::Type{<Name>Module})`
   - Validate signature
   - Extract function body
   ```julia
   function extract_compute_function(code::String, module_name::String) -> Union{Expr, Nothing}
   ```

3. **Parse port signatures** (1 day)
   - Convert `basic:String` to Julia types
   - Handle package references
   - Create InputPort/OutputPort objects
   ```julia
   function parse_port_signature(sig::String) -> Type
   function create_port_from_directive(directive::Dict) -> Port
   ```

4. **Integration and testing** (2 days)
   - Put everything together
   - Test with example package notebook
   - Handle edge cases
   - Write comprehensive tests

**Deliverables**:
- `src/notebook/code_extraction.jl` - Extract Julia code elements
- `src/notebook/port_parser.jl` - Parse port specifications
- **Test**: Can extract struct and compute from example cells
- **Example**: `examples/notebooks/test_package.ipynb`

**Effort**: 5 days (1 week)

**Phase 1 Total**: 2 weeks, ~80 hours

## Phase 2: Package Loading (Week 3-4)

**Goal**: Load package notebooks and register modules

### Week 3: Module Registration

**Tasks**:

1. **Create module descriptor from directives** (1 day)
   - Combine directives + extracted code
   - Build ModuleDescriptor
   ```julia
   function create_module_descriptor(
       pkg_id::String,
       directives::ModuleDirectives,
       struct_def::Expr,
       compute_func::Expr
   ) -> ModuleDescriptor
   ```

2. **Evaluate code in runtime** (2 days)
   - Use `eval()` to define struct and function
   - Handle module namespacing
   - Capture any errors with helpful messages
   ```julia
   function eval_module_code(struct_def::Expr, compute_func::Expr)
       eval(struct_def)
       eval(compute_func)
       # Return the module type
   end
   ```

3. **Register modules** (1 day)
   - Call existing `register_module!()` function
   - Integrate with existing module registry
   - Handle duplicate registrations

4. **Package initialization** (1 day)
   - Load package-level setup code
   - Handle dependencies (using statements)
   - Run package initialization

**Deliverables**:
- `src/notebook/module_loader.jl` - Load and register modules
- Integration with existing module registry
- **Test**: Can load example package and register modules

**Effort**: 5 days (1 week)

### Week 4: Full Package Loading

**Tasks**:

1. **Main package loading function** (1 day)
   ```julia
   function load_package_from_notebook(notebook_path::String)
       # 1. Read notebook
       # 2. Parse metadata
       # 3. Parse each module cell
       # 4. Eval and register each module
   end
   ```

2. **Error handling and validation** (1 day)
   - Validate notebook structure
   - Check for missing required directives
   - Helpful error messages
   - Validate port/parameter specifications

3. **Test with real packages** (2 days)
   - Convert existing `basic` package to notebook
   - Convert existing `julia` package to notebook
   - Test loading and execution
   - Compare behavior with .jl versions

4. **Documentation** (1 day)
   - How to write package notebooks
   - Directive reference
   - Examples

**Deliverables**:
- `load_package_from_notebook()` function
- Error handling and validation
- `examples/notebooks/basic_package.ipynb` - Example package
- `docs/PACKAGE_NOTEBOOK_GUIDE.md` - User guide

**Effort**: 5 days (1 week)

**Phase 2 Total**: 2 weeks, ~80 hours

## Phase 3: Workflow Parser (Week 5-6)

**Goal**: Parse workflow notebooks and build pipelines

### Week 5: Workflow Directives

**Tasks**:

1. **Parse workflow metadata** (1 day)
   - Parse `#| workflow:` directive
   - Extract version, description, tags
   ```julia
   struct WorkflowMetadata
       name::String
       version::Int
       description::String
       tags::Vector{String}
   end
   ```

2. **Parse module instance directives** (2 days)
   - Parse `#| module-id:`, `#| module-type:`
   - Parse `#| params:` (parameter values)
   - Parse `#| inputs:` (connections)
   ```julia
   struct ModuleInstanceDirective
       id::String
       module_type::String  # "basic:HTTPFile"
       params::Dict{String, Any}
       inputs::Dict{String, String}  # port => source.port
       position::Union{Tuple{Float64, Float64}, Nothing}
   end
   ```

3. **Parse connection syntax** (1 day)
   - Parse `data: fetch_data.file` format
   - Extract source module, source port
   - Validate connection specs
   ```julia
   function parse_connection(input_spec::String) -> Connection
       # "fetch_data.file" -> Connection(source="fetch_data", port="file")
   end
   ```

4. **Handle code cells (JuliaSource)** (1 day)
   - For JuliaSource modules, code is parameter
   - Extract cell code as `source` parameter
   - Preserve syntax highlighting

**Deliverables**:
- `src/notebook/workflow_parser.jl` - Parse workflow directives
- Connection parsing logic
- **Test**: Can parse workflow directive cells

**Effort**: 5 days (1 week)

### Week 6: Pipeline Building

**Tasks**:

1. **Create ModuleInstance from directives** (1 day)
   - Lookup module descriptor from registry
   - Create instance with ID
   - Set parameters from directives
   ```julia
   function create_module_instance(directive::ModuleInstanceDirective) -> ModuleInstance
   ```

2. **Build connections** (1 day)
   - Resolve source/dest modules by ID
   - Create Connection objects
   - Add to pipeline
   ```julia
   function build_connections(
       instances::Dict{String, ModuleInstance},
       directives::Vector{ModuleInstanceDirective}
   ) -> Vector{Connection}
   ```

3. **Assemble pipeline** (1 day)
   - Create Pipeline object
   - Add all modules
   - Add all connections
   - Validate (no cycles, etc.)
   ```julia
   function build_pipeline_from_notebook(notebook_path::String) -> Pipeline
   ```

4. **Test with real workflows** (2 days)
   - Create example workflow notebooks
   - Test loading and execution
   - Compare with .vt file workflows

**Deliverables**:
- `build_pipeline_from_notebook()` function
- `examples/notebooks/covid_workflow.ipynb` - Example
- `examples/notebooks/simple_workflow.ipynb` - Simple example
- Pipeline validation

**Effort**: 5 days (1 week)

**Phase 3 Total**: 2 weeks, ~80 hours

## Phase 4: Execution (Week 7)

**Goal**: Execute workflows from notebooks

### Week 7: Execution Engine

**Tasks**:

1. **Parse execute directive** (0.5 day)
   - Recognize `#| execute` cells
   - Handle `#| execute-from:` for partial execution
   - Handle `#| cache: true/false`

2. **Integrate with existing interpreter** (1 day)
   - Build pipeline from notebook
   - Call existing `execute_pipeline()` function
   - Capture results
   ```julia
   function execute_notebook(notebook_path::String; cache=true)
       pipeline = build_pipeline_from_notebook(notebook_path)
       cache, log = execute_pipeline(pipeline, cache_enabled=cache)
       return cache, log
   end
   ```

3. **Make results available** (1 day)
   - Store results in cache
   - Make available as variables (optional)
   - Display results in notebook

4. **Error handling** (1 day)
   - Catch execution errors
   - Display helpful error messages
   - Show which module failed

5. **CLI tool** (0.5 day)
   - Create `vt-notebook` command
   - `vt-notebook execute workflow.ipynb`
   - `vt-notebook validate workflow.ipynb`

6. **Testing and examples** (1 day)
   - Test execution with various workflows
   - Performance testing
   - Documentation

**Deliverables**:
- `src/notebook/executor.jl` - Execute workflows
- `vt-notebook` CLI tool
- Execution tests
- Example executable workflows

**Effort**: 5 days (1 week)

**Phase 4 Total**: 1 week, ~40 hours

## Phase 5: Conversion Tools (Week 8-9)

**Goal**: Bidirectional .vt ↔ notebook conversion

### Week 8: Notebook → .vt

**Tasks**:

1. **Generate actions from notebook** (2 days)
   - Build pipeline from notebook
   - Create Action with operations
   - Generate operation list (add module, add connection, etc.)
   ```julia
   function notebook_to_action(notebook_path::String) -> Action
   ```

2. **Create Vistrail structure** (1 day)
   - Create Vistrail with single version
   - Set current_version
   - Add metadata

3. **Serialize to XML** (1 day)
   - Use existing XML serialization
   - Generate .vt file structure
   - Test with Python VisTrails

4. **Round-trip testing** (1 day)
   - Load .vt → convert to notebook → convert back to .vt
   - Verify equivalence
   - Test with example .vt files

**Deliverables**:
- `notebook_to_vistrail()` function
- XML generation
- Round-trip tests

**Effort**: 5 days (1 week)

### Week 9: .vt → Notebook

**Tasks**:

1. **Convert modules to cells** (2 days)
   - For each module in pipeline, create cell
   - Generate directives from module descriptor
   - For JuliaSource, extract code
   - Handle layout positions

2. **Generate package notebooks** (1 day)
   - Extract unique module types
   - Generate package definition cells
   - Create struct and compute from descriptors

3. **CLI tools** (1 day)
   - `vt-notebook export workflow.vt -o workflow.ipynb`
   - `vt-notebook import workflow.ipynb -o workflow.vt`

4. **Testing and documentation** (1 day)
   - Convert example .vt files
   - Verify notebooks are readable
   - User guide

**Deliverables**:
- `vistrail_to_notebook()` function
- Conversion CLI tools
- Converted example notebooks
- Conversion guide

**Effort**: 5 days (1 week)

**Phase 5 Total**: 2 weeks, ~80 hours

## Phase 6: Git Integration (Week 10)

**Goal**: Import git history as version tree

### Week 10: Git History Import

**Tasks**:

1. **Git log parsing** (1 day)
   - Use LibGit2.jl
   - Get commit history for notebook file
   - Extract commit metadata (author, date, message)
   ```julia
   function get_git_history(notebook_path::String) -> Vector{GitCommit}
   ```

2. **Diff generation** (2 days)
   - For each commit, get notebook content
   - Diff consecutive versions
   - Generate VisTrails operations from diffs
   ```julia
   function git_diff_to_operations(
       old_notebook::Notebook,
       new_notebook::Notebook
   ) -> Vector{Operation}
   ```

3. **Build version tree** (1 day)
   - Create Vistrail
   - Add action for each commit
   - Handle branches and merges
   - Import git tags as VisTrails tags

4. **Testing** (1 day)
   - Test with real git repos
   - Verify version tree structure
   - Test branch handling

**Deliverables**:
- `import_git_history()` function
- Git integration
- Version tree from git commits
- Git integration guide

**Effort**: 5 days (1 week)

**Phase 6 Total**: 1 week, ~40 hours

## Phase 7: Documentation and Examples (Week 11)

**Goal**: Make system usable for end users

### Week 11: Documentation

**Tasks**:

1. **User guide** (2 days)
   - Getting started
   - Writing package notebooks
   - Writing workflow notebooks
   - Best practices

2. **API documentation** (1 day)
   - Document all public functions
   - Directive reference
   - Examples for each function

3. **Example notebooks** (1.5 days)
   - 3 example package notebooks
   - 5 example workflow notebooks
   - Cover different use cases

4. **Tutorial** (0.5 day)
   - Step-by-step tutorial
   - Convert existing .vt to notebook
   - Create new workflow

**Deliverables**:
- `docs/USER_GUIDE.md`
- `docs/API_REFERENCE.md`
- `docs/DIRECTIVE_REFERENCE.md`
- 3 package notebook examples
- 5 workflow notebook examples
- Tutorial

**Effort**: 5 days (1 week)

**Phase 7 Total**: 1 week, ~40 hours

## Summary

### Total Effort

| Phase | Duration | Hours | Complexity |
|-------|----------|-------|------------|
| 1. Directive Parser | 2 weeks | 80 | Medium |
| 2. Package Loading | 2 weeks | 80 | Medium |
| 3. Workflow Parser | 2 weeks | 80 | Medium |
| 4. Execution | 1 week | 40 | Low |
| 5. Conversion | 2 weeks | 80 | Medium |
| 6. Git Integration | 1 week | 40 | Medium |
| 7. Documentation | 1 week | 40 | Low |
| **Total** | **11 weeks** | **440 hours** | **Medium** |

### Adjusted for Reality

**Best case**: 8 weeks (if everything goes smoothly)
**Realistic**: 10 weeks (accounting for bugs, edge cases)
**Conservative**: 12 weeks (with buffer for unexpected issues)

**Recommended commitment**: **10 weeks** (2.5 months)

## Implementation Strategy

### Incremental Approach

Each phase builds on previous:

**Week 1-2**: ✅ Can parse package notebooks
**Week 3-4**: ✅ Can load packages and register modules
**Week 5-6**: ✅ Can parse workflow notebooks
**Week 7**: ✅ Can execute workflows
**Week 8-9**: ✅ Can convert to/from .vt files
**Week 10**: ✅ Can import git history
**Week 11**: ✅ Complete documentation

**At each milestone, you have something working!**

### Testing Strategy

1. **Unit tests** for each component
2. **Integration tests** at end of each phase
3. **Example notebooks** that demonstrate features
4. **Round-trip tests** (.vt → notebook → .vt)

### Risk Mitigation

**Low risk areas**:
- Directive parsing (straightforward regex/YAML)
- Package loading (eval existing code)
- Execution (reuse existing interpreter)

**Medium risk areas**:
- Code extraction (parsing Julia code)
- Git diff → operations (mapping logic)
- .vt → notebook (generating readable notebooks)

**Mitigation**:
- Start with simple cases
- Add complexity incrementally
- Comprehensive testing

### Dependencies

**New Julia packages needed**:
- `IJulia.jl` - Jupyter notebook interface
- `YAML.jl` - Parse directive metadata
- `LibGit2.jl` - Git integration (already in stdlib)

**Existing packages**:
- Everything else already implemented!

## Minimal Viable Product (MVP)

If you want to ship faster, here's a **6-week MVP**:

### MVP Scope

**Include**:
- ✅ Directive parser (Week 1-2)
- ✅ Package loading (Week 3-4)
- ✅ Basic workflow parsing (Week 5)
- ✅ Execution (Week 6)

**Defer**:
- ⏸️ .vt → notebook conversion (can do manually)
- ⏸️ Git integration (can implement later)
- ⏸️ Full documentation (minimal docs)

### MVP Timeline

**6 weeks** to working system:
- Week 1-2: Parse packages
- Week 3-4: Load packages
- Week 5: Parse workflows
- Week 6: Execute + basic docs

**Then iterate**:
- Week 7-8: Add conversion
- Week 9: Add git integration
- Week 10: Polish documentation

## Next Steps

### To Start Implementation

1. **Set up development environment**
   ```bash
   cd julia_starter
   julia --project=.
   ```

2. **Add dependencies**
   ```julia
   using Pkg
   Pkg.add("IJulia")
   Pkg.add("YAML")
   ```

3. **Create directory structure**
   ```bash
   mkdir -p src/notebook
   mkdir -p examples/notebooks
   ```

4. **Start with Phase 1, Week 1, Task 1**
   - Create `src/notebook/notebook_io.jl`
   - Implement basic notebook reading

5. **Write first test**
   - Create example notebook cell
   - Parse directives from it

### Questions?

Before starting:
- Comfortable with 10-week timeline?
- Want to do 6-week MVP first?
- Any phases to prioritize/defer?
- Need help setting up development environment?

**Ready to begin?** 🚀
