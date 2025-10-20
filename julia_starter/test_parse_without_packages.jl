"""
Test parsing .vt files without loading any packages

This demonstrates that the XML parsing and pipeline reconstruction
work independently of module implementations.
"""

using Pkg
Pkg.activate(@__DIR__)

# Use only the core XML parsing - don't load VisTrailsJL which initializes packages
using EzXML

# Import just the I/O functions we need
include("src/db/services/io.jl")

println("=" ^ 60)
println("Parsing .vt File WITHOUT Package Implementations")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")

println("\nLoading XML from $vt_file...")

# Load the XML directly
doc = open(vt_file, "r") do io
    # .vt files are ZIP archives
    using ZipFile
    archive = ZipFile.Reader(io)

    # Find the vistrail file
    for file in archive.files
        if endswith(file.name, ".xml") || file.name == "vistrail"
            xml_content = read(file, String)
            return parsexml(xml_content)
        end
    end
end

root = doc.root

println("✓ XML loaded successfully")

# Extract basic information without needing package details
println("\n" * "=" ^ 60)
println("Basic Information (no packages needed)")
println("=" ^ 60)

# Count actions (versions)
actions = findall("//action", root)
println("Total versions: ", length(actions))

# Get latest version ID
latest_id = 0
for action in actions
    id = parse(Int, action["id"])
    if id > latest_id
        latest_id = id
    end
end
println("Latest version: ", latest_id)

# Count tags
tags = findall("//tag", root)
println("Tags: ", length(tags))

# Look at workflow element
workflow = findfirst("//workflow", root)
if workflow !== nothing
    modules = findall(".//module", workflow)
    connections = findall(".//connection", workflow)

    println("\n" * "=" ^ 60)
    println("Workflow Element (no packages needed)")
    println("=" ^ 60)
    println("Modules: ", length(modules))
    println("Connections: ", length(connections))

    println("\nModule Types:")
    module_types = Dict{String, Int}()
    for mod in modules
        name = mod["name"]
        package = get(mod, "package", "unknown")
        key = "$package::$name"
        module_types[key] = get(module_types, key, 0) + 1
    end

    for (mod_type, count) in sort(collect(module_types), by=x->x[2], rev=true)
        println("  $mod_type: $count")
    end
end

# Parse action history without needing modules
println("\n" * "=" ^ 60)
println("Action History (no packages needed)")
println("=" ^ 60)

action_types = Dict{String, Int}()
for action in actions
    # Count what types of operations are in each action
    for op in ["add", "delete", "change"]
        ops = findall(".//$op", action)
        for op_elem in ops
            what = get(op_elem, "what", "unknown")
            key = "$op($what)"
            action_types[key] = get(action_types, key, 0) + 1
        end
    end
end

println("\nOperation types:")
for (op_type, count) in sort(collect(action_types), by=x->x[2], rev=true)
    println("  $op_type: $count")
end

# Show action timeline
println("\nAction Timeline (first 10):")
sorted_actions = sort(collect(actions), by=a->parse(Int, a["id"]))
for action in sorted_actions[1:min(10, length(sorted_actions))]
    id = action["id"]
    date = get(action, "date", "unknown")
    user = get(action, "user", "unknown")

    # Count operations
    adds = length(findall(".//add", action))
    deletes = length(findall(".//delete", action))
    changes = length(findall(".//change", action))

    println("  Version $id ($date, $user): +$adds -$deletes ~$changes")
end

println("\n✓ Successfully parsed .vt file without any package implementations!")
