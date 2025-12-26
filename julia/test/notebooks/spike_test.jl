"""
Spike Test - End-to-End Notebook Workflow Execution

This script tests the complete flow:
1. Load package from notebook
2. Load workflow from notebook
3. Execute workflow
4. Verify result
"""

# Get the julia root directory
const JULIA_STARTER_ROOT = dirname(dirname(@__DIR__))

# Load VisTrailsJL core first
include(joinpath(JULIA_STARTER_ROOT, "src/VisTrailsJL.jl"))

# Now we work in the VisTrailsJL module context
module NotebookSpike

using JSON
using ..VisTrailsJL

# Include the parser
include(joinpath(Main.JULIA_STARTER_ROOT, "src/notebook/parser.jl"))

# ============================================================================
# Package Loader (inline for spike)
# ============================================================================

struct NotebookPackage
    identifier::String
    version::String
    modules::Vector{Tuple{String, VisTrailsJL.ModuleDescriptor, Function}}
end

function load_package_from_notebook(path::String)
    cells = parse_notebook(path)

    identifier = "unknown"
    version = "1.0.0"

    for cell in cells
        if has_directive(cell, "package-meta")
            identifier = get_directive(cell, "identifier", identifier)
            version = get_directive(cell, "version", version)
            break
        end
    end

    modules = Tuple{String, VisTrailsJL.ModuleDescriptor, Function}[]

    for cell in cells
        if has_directive(cell, "module")
            module_name = get_directive(cell, "module")

            input_ports = parse_input_ports(get_directive(cell, "input_ports", []))
            output_ports = parse_output_ports(get_directive(cell, "output_ports", []))

            # Create a unique struct for this module
            module_type = create_module_type(identifier, module_name)

            descriptor = VisTrailsJL.ModuleDescriptor(
                identifier,
                module_name,
                module_type,
                input_ports,
                output_ports,
                Tuple{String, Type}[]
            )

            # Create compute function from code
            compute_fn = create_compute_function(cell.code)

            push!(modules, (module_name, descriptor, compute_fn))
        end
    end

    return NotebookPackage(identifier, version, modules)
end

function parse_input_ports(specs)
    ports = VisTrailsJL.InputPort[]
    for spec in specs
        if spec isa Dict
            name = get(spec, "name", "unnamed")
            sig = get(spec, "signature", "basic:Any")
            push!(ports, VisTrailsJL.InputPort(name, signature_to_type(sig)))
        end
    end
    return ports
end

function parse_output_ports(specs)
    ports = VisTrailsJL.OutputPort[]
    for spec in specs
        if spec isa Dict
            name = get(spec, "name", "unnamed")
            sig = get(spec, "signature", "basic:Any")
            push!(ports, VisTrailsJL.OutputPort(name, signature_to_type(sig)))
        end
    end
    return ports
end

function signature_to_type(sig::String)
    type_name = occursin(":", sig) ? split(sig, ":")[end] : sig
    type_map = Dict("Integer" => Int, "Float" => Float64, "String" => String, "Any" => Any)
    return get(type_map, type_name, Any)
end

# Counter for unique module types
const MODULE_TYPE_COUNTER = Ref(0)

function create_module_type(package::String, name::String)
    # Use a simple marker type - we'll dispatch on the descriptor instead
    return Nothing  # Placeholder - we'll use a different dispatch mechanism
end

function create_compute_function(code::String)
    # Create a function that takes a module instance and runs the user code
    code = strip(code)
    if isempty(code)
        return function(mod::VisTrailsJL.ModuleInstance)
            return mod.outputs
        end
    end

    # Parse all expressions as a single block
    block_code = "begin\n$code\nend"
    block_expr = Meta.parse(block_code)

    # Return a closure that will be called during execution
    return function(mod::VisTrailsJL.ModuleInstance)
        # Set up helper functions
        get_input = (name) -> mod.inputs[name]
        has_input = (name) -> haskey(mod.inputs, name)
        set_output = (name, value) -> (mod.outputs[name] = value)
        get_parameter = (name) -> mod.parameters[name]
        has_parameter = (name) -> haskey(mod.parameters, name)

        # Wrap the block in a let that provides the helpers
        wrapper = Expr(:let,
            Expr(:block,
                Expr(:(=), :get_input, get_input),
                Expr(:(=), :has_input, has_input),
                Expr(:(=), :set_output, set_output),
                Expr(:(=), :get_parameter, get_parameter),
                Expr(:(=), :has_parameter, has_parameter),
            ),
            block_expr
        )
        eval(wrapper)

        return mod.outputs
    end
end

# Global storage for notebook compute functions
const NOTEBOOK_COMPUTE_FUNCTIONS = Dict{Tuple{String, String}, Function}()

function register_notebook_package!(pkg::NotebookPackage)
    println("Registering package: $(pkg.identifier) v$(pkg.version)")

    for (name, descriptor, compute_fn) in pkg.modules
        # Store the compute function
        NOTEBOOK_COMPUTE_FUNCTIONS[(pkg.identifier, name)] = compute_fn

        # Register the module
        VisTrailsJL.register_module!(descriptor)

        println("  ✓ Registered module: $name")
    end

    println("Package $(pkg.identifier) registered with $(length(pkg.modules)) modules")
end

# ============================================================================
# Workflow Parser (inline for spike)
# ============================================================================

struct NotebookModule
    id::String
    module_type::String
    params::Dict{String, Any}
    inputs::Dict{String, String}
end

struct NotebookWorkflow
    name::String
    modules::Vector{NotebookModule}
end

function parse_workflow_notebook(path::String)
    cells = parse_notebook(path)

    workflow_name = "unnamed"
    modules = NotebookModule[]

    for cell in cells
        if has_directive(cell, "workflow")
            workflow_name = get_directive(cell, "workflow")
        end

        if has_directive(cell, "module-id")
            id = get_directive(cell, "module-id")
            module_type = get_directive(cell, "module-type", "unknown:Unknown")

            # Parse params
            params = Dict{String, Any}()
            params_raw = get_directive(cell, "params", nothing)
            if params_raw !== nothing
                if params_raw isa Vector
                    for item in params_raw
                        if item isa Dict
                            merge!(params, item)
                        end
                    end
                elseif params_raw isa Dict
                    params = params_raw
                end
            end

            # Parse inputs
            inputs = Dict{String, String}()
            inputs_raw = get_directive(cell, "inputs", nothing)
            if inputs_raw !== nothing
                if inputs_raw isa Vector
                    for item in inputs_raw
                        if item isa Dict
                            for (k, v) in item
                                inputs[string(k)] = string(v)
                            end
                        end
                    end
                elseif inputs_raw isa Dict
                    for (k, v) in inputs_raw
                        inputs[string(k)] = string(v)
                    end
                end
            end

            push!(modules, NotebookModule(id, module_type, params, inputs))
        end
    end

    return NotebookWorkflow(workflow_name, modules)
end

function parse_module_type(type_str::AbstractString)
    type_str = String(type_str)
    if occursin(":", type_str)
        parts = split(type_str, ":")
        package_short = String(parts[1])
        name = String(parts[2])

        package_map = Dict(
            "basic" => "org.vistrails.vistrails.basic",
            "julia" => "org.vistrails.vistrails.julia",
        )

        package = get(package_map, package_short, package_short)
        return (package, name)
    end
    return ("unknown", type_str)
end

function build_pipeline(workflow::NotebookWorkflow)
    pipeline = VisTrailsJL.Pipeline()
    id_to_module = Dict{String, VisTrailsJL.ModuleInstance}()

    # Create modules
    for nb_mod in workflow.modules
        package, name = parse_module_type(nb_mod.module_type)

        mod = VisTrailsJL.add_module!(pipeline, package, name)

        # Set parameters
        for (param_name, param_value) in nb_mod.params
            VisTrailsJL.set_parameter!(mod, param_name, param_value)
        end

        id_to_module[nb_mod.id] = mod
    end

    # Create connections
    for nb_mod in workflow.modules
        dest_mod = id_to_module[nb_mod.id]

        for (dest_port, source_ref) in nb_mod.inputs
            parts = split(source_ref, ".")
            source_id = parts[1]
            source_port = join(parts[2:end], ".")

            source_mod = id_to_module[source_id]
            VisTrailsJL.add_connection!(pipeline, source_mod, source_port, dest_mod, dest_port)
        end
    end

    return pipeline
end

# ============================================================================
# Custom execution for notebook modules
# ============================================================================

function execute_with_notebook_modules(pipeline::VisTrailsJL.Pipeline)
    # Simple interpreter that uses our notebook compute functions
    cache = Dict{Int, Dict{String, Any}}()

    # Get execution order
    execution_order = VisTrailsJL.topological_sort(pipeline)

    println("Executing pipeline with $(length(pipeline.modules)) modules...")
    println("Execution order: ", execution_order)

    for module_id in execution_order
        mod = VisTrailsJL.get_module(pipeline, module_id)

        println("  Module $module_id ($(mod.descriptor.name)): computing...")

        # Collect inputs from upstream
        incoming = VisTrailsJL.get_connections_to(pipeline, module_id)
        for conn in incoming
            if haskey(cache, conn.source_module_id)
                source_outputs = cache[conn.source_module_id]
                if haskey(source_outputs, conn.source_port)
                    VisTrailsJL.set_input!(mod, conn.dest_port, source_outputs[conn.source_port])
                end
            end
        end

        # Execute
        key = (mod.descriptor.package, mod.descriptor.name)
        if haskey(NOTEBOOK_COMPUTE_FUNCTIONS, key)
            # Notebook module - use our stored function
            compute_fn = NOTEBOOK_COMPUTE_FUNCTIONS[key]
            outputs = compute_fn(mod)
        else
            # Built-in module - use standard compute
            outputs = VisTrailsJL.compute(mod, mod.descriptor.module_type)
        end

        cache[module_id] = outputs
        println("    Outputs: $outputs")
        println("    ✓ Complete")
    end

    return cache
end

# ============================================================================
# Main test
# ============================================================================

function run_spike_test()
    println("=" ^ 60)
    println("SPIKE TEST: Notebook-Based Workflow System")
    println("=" ^ 60)

    # Step 1: Load and register the test package
    println("\n[Step 1] Loading package from notebook...")
    package_path = joinpath(@__DIR__, "test_package.ipynb")
    pkg = load_package_from_notebook(package_path)
    register_notebook_package!(pkg)

    println("\nPackage loaded:")
    println("  Identifier: $(pkg.identifier)")
    println("  Version: $(pkg.version)")
    println("  Modules: $(length(pkg.modules))")

    # Step 2: Parse the workflow
    println("\n[Step 2] Parsing workflow notebook...")
    workflow_path = joinpath(@__DIR__, "test_workflow.ipynb")
    workflow = parse_workflow_notebook(workflow_path)

    println("\nWorkflow parsed:")
    println("  Name: $(workflow.name)")
    println("  Modules: $(length(workflow.modules))")
    for m in workflow.modules
        println("    - $(m.id): $(m.module_type)")
    end

    # Step 3: Build pipeline
    println("\n[Step 3] Building pipeline...")
    pipeline = build_pipeline(workflow)
    println(pipeline)

    # Step 4: Execute
    println("\n[Step 4] Executing pipeline...")
    results = execute_with_notebook_modules(pipeline)

    # Step 5: Verify results
    println("\n[Step 5] Results:")
    for (module_id, outputs) in results
        mod = VisTrailsJL.get_module(pipeline, module_id)
        println("  Module $(module_id) ($(mod.descriptor.name)): $outputs")
    end

    # Find the final result
    double_module_id = nothing
    for (id, mod) in pipeline.modules
        if mod.descriptor.name == "Double"
            double_module_id = id
            break
        end
    end

    println("\n" * "=" ^ 60)
    if double_module_id !== nothing
        final_result = results[double_module_id]["result"]
        expected = 12  # (5 + 1) * 2 = 12

        if final_result == expected
            println("✓ SUCCESS! Final result: $final_result (expected: $expected)")
        else
            println("✗ FAILED! Final result: $final_result (expected: $expected)")
        end
    else
        println("✗ FAILED! Could not find Double module")
    end
    println("=" ^ 60)
end

end  # module NotebookSpike

# Run the test
NotebookSpike.run_spike_test()
