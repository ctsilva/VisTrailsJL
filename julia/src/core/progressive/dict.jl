"""
ProgressiveDict and ProgressiveValue

`ProgressiveDict` is the `PDict` of ProgressiVis: a small keyed result
(min/max per column, query bounds, a variable's current value) that reports
created / updated / deleted keys. Changes are recorded on write, and writing
a value equal (`isequal`) to the current one is not a change. (`PDict` finds
changes by diffing against a copy and compares values by identity, so it
misses in-place mutation and reports equal new objects as updates.)

`ProgressiveValue` wraps any value; its only change is "replaced". It is how
ordinary (one-shot) values take part in a progressive pipeline.
"""

"""
    DictSubscription{K}

A consumer's unread key changes of a `ProgressiveDict`.
"""
mutable struct DictSubscription{K} <: AbstractSubscription
    dict::Any  # ProgressiveDict{K}
    created::Set{K}
    updated::Set{K}
    deleted::Set{K}
end

"""
    ProgressiveDict{K,V}()
    ProgressiveDict(pairs...)

A dictionary that reports key changes to its subscribers. Read it like a
`Dict`; iterate a `snapshot` if another thread may write concurrently.
"""
struct ProgressiveDict{K, V} <: AbstractDict{K, V}
    data::Dict{K, V}
    subscriptions::Vector{DictSubscription{K}}
    lock::ReentrantLock
end

ProgressiveDict{K, V}() where {K, V} = ProgressiveDict{K, V}(Dict{K, V}(), DictSubscription{K}[], ReentrantLock())
ProgressiveDict{K, V}(ps::Pair...) where {K, V} = ProgressiveDict{K, V}(Dict{K, V}(ps...), DictSubscription{K}[], ReentrantLock())

function ProgressiveDict(ps::Pair...)
    d = Dict(ps...)
    return ProgressiveDict{keytype(d), valtype(d)}(d, DictSubscription{keytype(d)}[], ReentrantLock())
end

Base.length(d::ProgressiveDict) = @lock d.lock length(d.data)
Base.getindex(d::ProgressiveDict, k) = @lock d.lock d.data[k]
Base.get(d::ProgressiveDict, k, default) = @lock d.lock get(d.data, k, default)
Base.haskey(d::ProgressiveDict, k) = @lock d.lock haskey(d.data, k)
Base.iterate(d::ProgressiveDict, state...) = iterate(d.data, state...)

"""
    snapshot(d::ProgressiveDict) -> Dict

A copy of the current contents.
"""
snapshot(d::ProgressiveDict) = @lock d.lock copy(d.data)

function Base.setindex!(d::ProgressiveDict{K, V}, v, k) where {K, V}
    key = convert(K, k)
    value = convert(V, v)
    @lock d.lock begin
        if haskey(d.data, key)
            isequal(d.data[key], value) && return d
            d.data[key] = value
            for sub in d.subscriptions
                key in sub.created || push!(sub.updated, key)
            end
        else
            d.data[key] = value
            for sub in d.subscriptions
                push!(sub.created, key)
            end
        end
    end
    return d
end

function Base.delete!(d::ProgressiveDict, k)
    @lock d.lock begin
        haskey(d.data, k) || return d
        delete!(d.data, k)
        for sub in d.subscriptions
            if k in sub.created
                delete!(sub.created, k)
            else
                delete!(sub.updated, k)
                push!(sub.deleted, k)
            end
        end
    end
    return d
end

function subscribe!(d::ProgressiveDict{K}) where {K}
    @lock d.lock begin
        sub = DictSubscription{K}(d, Set{K}(keys(d.data)), Set{K}(), Set{K}())
        push!(d.subscriptions, sub)
        return sub
    end
end

function unsubscribe!(sub::DictSubscription)
    d = sub.dict
    @lock d.lock filter!(s -> s !== sub, d.subscriptions)
    return sub
end

has_changes(sub::DictSubscription) =
    @lock sub.dict.lock !(isempty(sub.created) && isempty(sub.updated) && isempty(sub.deleted))

"""
    take_changes!(sub::DictSubscription) -> (created, updated, deleted)

All unread key changes, as sets of keys; the buffers are then empty.
"""
function take_changes!(sub::DictSubscription{K}) where {K}
    @lock sub.dict.lock begin
        changes = (created=sub.created, updated=sub.updated, deleted=sub.deleted)
        sub.created, sub.updated, sub.deleted = Set{K}(), Set{K}(), Set{K}()
        return changes
    end
end

function reset!(sub::DictSubscription{K}) where {K}
    d = sub.dict
    @lock d.lock begin
        sub.created = Set{K}(keys(d.data))
        empty!(sub.updated)
        empty!(sub.deleted)
    end
    return sub
end

# ProgressiveValue

"""
    ProgressiveValue{T}()
    ProgressiveValue(value)

A value that can be replaced; subscribers see whether it changed since they
last took it.
"""
mutable struct ProgressiveValue{T}
    value::Union{Nothing, Some{T}}
    version::Int
    lock::ReentrantLock
end

ProgressiveValue{T}() where {T} = ProgressiveValue{T}(nothing, 0, ReentrantLock())
ProgressiveValue{T}(v) where {T} = ProgressiveValue{T}(Some{T}(v), 1, ReentrantLock())
ProgressiveValue(v::T) where {T} = ProgressiveValue{T}(v)

"""
    set!(pv::ProgressiveValue, v)

Replace the value (always a change, even if equal).
"""
function set!(pv::ProgressiveValue{T}, v) where {T}
    @lock pv.lock begin
        pv.value = Some{T}(v)
        pv.version += 1
    end
    return pv
end

has_value(pv::ProgressiveValue) = @lock pv.lock pv.value !== nothing

"""
    current_value(pv::ProgressiveValue)

The current value (an error if none was set yet).
"""
function current_value(pv::ProgressiveValue)
    v = @lock pv.lock pv.value
    v === nothing && error("ProgressiveValue has no value yet")
    return something(v)
end

mutable struct ValueSubscription{T} <: AbstractSubscription
    source::ProgressiveValue{T}
    seen_version::Int
end

subscribe!(pv::ProgressiveValue{T}) where {T} = ValueSubscription{T}(pv, 0)
unsubscribe!(sub::ValueSubscription) = sub
has_changes(sub::ValueSubscription) = @lock sub.source.lock sub.seen_version < sub.source.version
reset!(sub::ValueSubscription) = (sub.seen_version = 0; sub)

"""
    take_value!(sub::ValueSubscription)

The current value, marking it as read.
"""
function take_value!(sub::ValueSubscription)
    pv = sub.source
    @lock pv.lock begin
        pv.value === nothing && error("ProgressiveValue has no value yet")
        sub.seen_version = pv.version
        return something(pv.value)
    end
end
