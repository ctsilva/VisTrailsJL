"""
Module and subpipeline signatures

A signature identifies the computation a module performs, independently of
module ids, so that results can be reused across runs and across versions
of a vistrail. Ported from Python VisTrails:

- `module_signature`: the module's type, implementation, parameters, preset
  inputs and port specs (`vistrails/core/cache/hasher.py`, `module_signature`)
- `subpipeline_signatures`: the module signature combined with the signature
  of every incoming connection and its upstream subpipeline, so a module's
  signature changes whenever anything upstream changes
  (`vistrails/core/vistrail/pipeline.py`, `subpipeline_signature`)

Signatures are SHA-1 hex digests of a canonical encoding of these values.
"""

using SHA

"""
    canonical(io::IO, x)

Write a deterministic encoding of `x`: dictionaries sorted by key, values
tagged with their type (so `5` and `"5"` differ).
"""
function canonical(io::IO, d::AbstractDict)
    print(io, "{")
    for (k, v) in sort(collect(d), by=p -> string(p.first))
        canonical(io, k)
        print(io, "=>")
        canonical(io, v)
        print(io, ",")
    end
    print(io, "}")
end

function canonical(io::IO, xs::Union{AbstractVector, Tuple})
    print(io, typeof(xs) <: Tuple ? "(" : "[")
    for x in xs
        canonical(io, x)
        print(io, ",")
    end
    print(io, typeof(xs) <: Tuple ? ")" : "]")
end

# Functions have no stable textual form; identity is enough for an in-memory cache
canonical(io::IO, f::Function) = print(io, "Function:", objectid(f))

canonical(io::IO, x) = print(io, typeof(x), ":", repr(x))

canonical_string(x) = sprint(canonical, x)

hash_string(s::AbstractString) = bytes2hex(sha1(s))

"""
    implementation_id(mod::ModuleInstance) -> String

Identifies the code that computes a module: the notebook compute function if
one is registered (it changes when the notebook package is re-registered),
otherwise the module's Julia type.
"""
function implementation_id(mod::ModuleInstance)
    notebook_compute = get_notebook_compute(mod.descriptor.package, mod.descriptor.name)
    if notebook_compute !== nothing
        return "notebook:" * string(objectid(notebook_compute))
    end
    return string(mod.descriptor.module_type)
end

"""
    module_signature(mod::ModuleInstance) -> String

Signature of a module on its own: package, name, implementation, parameters,
inputs preset on the module (e.g. by the API's `execute(vt; in_a=2)`), and
port specs. Module ids and layout do not take part.
"""
function module_signature(mod::ModuleInstance)
    port_specs = sort([(ps.port_type, ps.name, ps.signature, ps.optional, ps.sort_key)
                       for ps in mod.port_specs])
    return hash_string(canonical_string((
        mod.descriptor.package,
        mod.descriptor.name,
        implementation_id(mod),
        mod.parameters,
        mod.inputs,
        port_specs,
    )))
end

"""
    subpipeline_signatures(pipeline::Pipeline, order=topological_sort(pipeline))
        -> Dict{Int, String}

Signature of every module together with everything upstream of it.
Incoming connections are combined in connection-id order, since that order
determines list-valued inputs.
"""
function subpipeline_signatures(pipeline::Pipeline, order::Vector{Int}=topological_sort(pipeline))
    signatures = Dict{Int, String}()

    for module_id in order
        mod = pipeline.modules[module_id]
        incoming = sort(get_connections_to(pipeline, module_id), by=c -> c.id)
        upstream = [(c.dest_port, c.source_port, signatures[c.source_module_id]) for c in incoming]
        signatures[module_id] = hash_string(canonical_string((module_signature(mod), upstream)))
    end

    return signatures
end

"""
    is_cacheable(module_type::Type) -> Bool

Whether results of a module type may be reused. Modules with side effects
(printing, writing files) or non-deterministic results should return false.
"""
is_cacheable(::Type) = true
