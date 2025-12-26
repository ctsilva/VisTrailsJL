"""
Pipeline (Workflow) management.

A Pipeline represents a workflow - a DAG of modules and connections.
"""

"""
Pipeline

Represents a complete workflow (directed acyclic graph of modules).
"""
mutable struct Pipeline
    id::Int
    modules::Dict{Int, ModuleInstance}
    connections::Vector{Connection}
    next_module_id::Int
    next_connection_id::Int

    Pipeline() = new(0, Dict{Int, ModuleInstance}(), Connection[], 1, 1)
end

# Pipeline operations

"""
    add_module!(pipeline::Pipeline, package::String, name::String) -> ModuleInstance

Add a module to the pipeline.
"""
function add_module!(pipeline::Pipeline, package::String, name::String)
    # Look up module descriptor in registry
    descriptor = get_module_descriptor(package, name)

    # Create module instance
    mod = ModuleInstance(pipeline.next_module_id, descriptor)
    pipeline.next_module_id += 1

    # Add to pipeline
    pipeline.modules[mod.id] = mod

    return mod
end

"""
    add_connection!(pipeline::Pipeline,
                   source::ModuleInstance, source_port::String,
                   dest::ModuleInstance, dest_port::String)

Add a connection between two modules.
"""
function add_connection!(pipeline::Pipeline,
                        source::ModuleInstance, source_port::String,
                        dest::ModuleInstance, dest_port::String)
    conn = Connection(
        pipeline.next_connection_id,
        source.id, source_port,
        dest.id, dest_port
    )
    pipeline.next_connection_id += 1

    push!(pipeline.connections, conn)

    return conn
end

"""
    get_module(pipeline::Pipeline, id::Int) -> ModuleInstance

Get a module by ID.
"""
function get_module(pipeline::Pipeline, id::Int)
    return pipeline.modules[id]
end

"""
    get_connections_to(pipeline::Pipeline, module_id::Int) -> Vector{Connection}

Get all connections where the given module is the destination.
"""
function get_connections_to(pipeline::Pipeline, module_id::Int)
    return filter(c -> c.dest_module_id == module_id, pipeline.connections)
end

"""
    get_connections_from(pipeline::Pipeline, module_id::Int) -> Vector{Connection}

Get all connections where the given module is the source.
"""
function get_connections_from(pipeline::Pipeline, module_id::Int)
    return filter(c -> c.source_module_id == module_id, pipeline.connections)
end

"""
    topological_sort(pipeline::Pipeline) -> Vector{Int}

Return module IDs in topological order for execution.
Uses Kahn's algorithm.
"""
function topological_sort(pipeline::Pipeline)
    # Calculate in-degree for each module
    in_degree = Dict{Int, Int}()
    for (id, _) in pipeline.modules
        in_degree[id] = 0
    end

    for conn in pipeline.connections
        in_degree[conn.dest_module_id] += 1
    end

    # Queue of modules with no dependencies
    queue = Int[]
    for (id, degree) in in_degree
        if degree == 0
            push!(queue, id)
        end
    end

    # Process queue
    sorted = Int[]
    while !isempty(queue)
        current = popfirst!(queue)
        push!(sorted, current)

        # Reduce in-degree of downstream modules
        for conn in get_connections_from(pipeline, current)
            dest_id = conn.dest_module_id
            in_degree[dest_id] -= 1

            if in_degree[dest_id] == 0
                push!(queue, dest_id)
            end
        end
    end

    # Check for cycles
    if length(sorted) != length(pipeline.modules)
        error("Pipeline contains cycles!")
    end

    return sorted
end

# Display
function Base.show(io::IO, pipeline::Pipeline)
    print(io, "Pipeline($(length(pipeline.modules)) modules, $(length(pipeline.connections)) connections)")
end
