"""
Vistrail - Version Control for Workflows

Represents a vistrail file with complete version history.
Similar to Python VisTrails' vistrail.py
"""

"""
Action

Represents a single change in the version tree (like a git commit).
"""
struct Action
    id::Int
    prev_id::Int  # Parent version
    timestamp::DateTime
    user::String
    notes::String
    operations::Vector{Any}  # List of operations (add module, delete connection, etc.)
end

"""
Tag

A named pointer to a specific version.
"""
struct Tag
    name::String
    version_id::Int
end

"""
Vistrail

Container for a complete vistrail with version history.
"""
mutable struct Vistrail
    # Version control
    actions::Dict{Int, Action}
    tags::Vector{Tag}
    current_version::Int

    # Workflows (one per version)
    pipelines::Dict{Int, Pipeline}

    # Metadata
    name::String
    created::DateTime
    modified::DateTime

    Vistrail(name::String="Untitled") = new(
        Dict{Int, Action}(),
        Tag[],
        0,
        Dict{Int, Pipeline}(),
        name,
        now(),
        now()
    )
end

# Vistrail operations

"""
    add_version!(vt::Vistrail, pipeline::Pipeline, parent_id::Int=0) -> Int

Add a new version to the vistrail.
"""
function add_version!(vt::Vistrail, pipeline::Pipeline, parent_id::Int=0;
                     notes::String="", user::String="user")
    # Generate new version ID
    new_id = length(vt.actions) + 1

    # Create action
    action = Action(
        new_id,
        parent_id,
        now(),
        user,
        notes,
        []  # Operations would be computed by diffing pipelines
    )

    # Store
    vt.actions[new_id] = action
    vt.pipelines[new_id] = pipeline
    vt.current_version = new_id
    vt.modified = now()

    return new_id
end

"""
    add_tag!(vt::Vistrail, name::String, version_id::Int=-1)

Add a named tag to a version (default: current version).
"""
function add_tag!(vt::Vistrail, name::String, version_id::Int=-1)
    if version_id == -1
        version_id = vt.current_version
    end

    tag = Tag(name, version_id)
    push!(vt.tags, tag)
end

"""
    get_pipeline(vt::Vistrail, version_id::Int=-1) -> Pipeline

Get the pipeline for a specific version (default: current).
"""
function get_pipeline(vt::Vistrail, version_id::Int=-1)
    if version_id == -1
        version_id = vt.current_version
    end

    if !haskey(vt.pipelines, version_id)
        error("Version $version_id not found")
    end

    return vt.pipelines[version_id]
end

"""
    get_latest_version(vt::Vistrail) -> Int

Get the ID of the latest version.
"""
function get_latest_version(vt::Vistrail)
    if isempty(vt.actions)
        return 0
    end
    return maximum(keys(vt.actions))
end

"""
    get_tag(vt::Vistrail, tag_name::String) -> Union{Int, Nothing}

Get the version ID for a tag name.
"""
function get_tag(vt::Vistrail, tag_name::String)
    for tag in vt.tags
        if tag.name == tag_name
            return tag.version_id
        end
    end
    return nothing
end

# Display
function Base.show(io::IO, vt::Vistrail)
    print(io, "Vistrail(\"$(vt.name)\", $(length(vt.actions)) versions, $(length(vt.tags)) tags)")
end
