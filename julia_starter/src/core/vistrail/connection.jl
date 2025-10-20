"""
Connection between modules in a workflow.

Connections represent data flow edges in the workflow DAG.
"""

"""
Connection

Represents a connection from one module's output port to another module's input port.
"""
struct Connection
    id::Int
    source_module_id::Int
    source_port::String
    dest_module_id::Int
    dest_port::String
end

function Connection(source_module_id::Int, source_port::String,
                   dest_module_id::Int, dest_port::String)
    Connection(0, source_module_id, source_port, dest_module_id, dest_port)
end

function Base.show(io::IO, conn::Connection)
    print(io, "Connection($(conn.source_module_id):$(conn.source_port) -> " *
              "$(conn.dest_module_id):$(conn.dest_port))")
end
