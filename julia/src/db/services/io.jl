"""
Database Services - I/O

XML reading and writing for .vt files.
Similar to Python VisTrails' db/services/io.py
"""

using EzXML
using ZipFile

# Include action replay system
include("action_replay.jl")

"""
    attrs_dict(elem::EzXML.Node) -> Dict{String, String}

Convert XML element attributes to a dictionary.
"""
function attrs_dict(elem::EzXML.Node)
    attrs = Dict{String, String}()
    for attr in attributes(elem)
        attrs[attr.name] = attr.content
    end
    return attrs
end

"""
    load_vt_xml(filename::String) -> EzXML.Node

Load a .vt file and return the XML root.
.vt files are ZIP archives containing an XML file.
"""
function load_vt_xml(filename::String)
    # Try to read as ZIP file
    try
        reader = ZipFile.Reader(filename)

        # Look for vistrail XML
        xml_content = nothing
        for file in reader.files
            if file.name == "vistrail" || file.name == "vistrail.xml"
                xml_content = read(file, String)
                break
            elseif endswith(file.name, ".xml")
                xml_content = read(file, String)
            end
        end

        close(reader)

        if xml_content === nothing
            error("No XML file found in .vt archive")
        end

        return parsexml(xml_content).root

    catch e
        # Try as plain XML
        if isfile(filename)
            return readxml(filename).root
        else
            rethrow(e)
        end
    end
end

"""
    load_vistrail_internal(filename::String) -> Vistrail

Load a complete vistrail from a .vt file (internal function).
"""
function load_vistrail_internal(filename::String; version::Union{Int,Nothing}=nothing)
    root = load_vt_xml(filename)

    # Create vistrail object
    attrs = attrs_dict(root)
    vt_name = get(attrs, "name", basename(filename))
    vt = Vistrail(vt_name)

    # Load actions (versions)
    for action_elem in findall("//action", root)
        action = parse_action(action_elem)
        vt.actions[action.id] = action
    end

    # Load tags
    for tag_elem in findall("//tag", root)
        tag = parse_tag(tag_elem)
        push!(vt.tags, tag)
    end

    # Don't load all pipelines - reconstruct on demand instead
    # Store the XML root for later pipeline reconstruction
    # (In a real implementation, we'd store this differently)

    # Determine which version to load
    if !isempty(vt.actions)
        if version === nothing
            vt.current_version = maximum(keys(vt.actions))
        else
            vt.current_version = version
        end

        # Only reconstruct the specified version pipeline
        println("  Reconstructing version $(vt.current_version)...")
        pipeline = reconstruct_pipeline(root, vt.current_version)
        if pipeline !== nothing
            vt.pipelines[vt.current_version] = pipeline
        end
    end

    return vt
end

"""
    parse_action(elem::EzXML.Node) -> Action

Parse an action element from XML.
"""
function parse_action(elem::EzXML.Node)
    attrs = attrs_dict(elem)

    id = parse(Int, attrs["id"])
    prev_id = parse(Int, get(attrs, "prevId", "0"))
    timestamp = get(attrs, "timestamp", "")
    user = get(attrs, "user", "unknown")
    notes = get(attrs, "notes", "")

    # Parse timestamp if available
    dt = if timestamp != ""
        try
            DateTime(timestamp)
        catch
            now()
        end
    else
        now()
    end

    return Action(id, prev_id, dt, user, notes, [])
end

"""
    parse_tag(elem::EzXML.Node) -> Tag

Parse a tag element from XML.
"""
function parse_tag(elem::EzXML.Node)
    attrs = attrs_dict(elem)

    name = attrs["name"]
    # Tags can use either "value" or "id" for version ID (different VisTrails versions)
    version_id = if haskey(attrs, "value")
        parse(Int, attrs["value"])
    elseif haskey(attrs, "id")
        parse(Int, attrs["id"])
    else
        error("Tag element missing both 'value' and 'id' attributes")
    end

    return Tag(name, version_id)
end

"""
    reconstruct_pipeline(root::EzXML.Node, version_id::Int) -> Union{Pipeline, Nothing}

Reconstruct a pipeline for a specific version by replaying actions.
Falls back to <workflow> element if action replay fails.
"""
function reconstruct_pipeline(root::EzXML.Node, version_id::Int)
    # Try action replay first (the proper VisTrails way)
    try
        println("  Using action replay to reconstruct version $version_id...")
        pipeline = replay_actions_to_version(root, version_id)
        println("  ✓ Action replay successful: $(length(pipeline.modules)) modules, $(length(pipeline.connections)) connections")

        # Return the pipeline if we got any modules with proper types
        # (small pipelines are valid - matplotlib examples have only 3 modules!)
        if !isempty(pipeline.modules)
            # Check if modules have real types (not Nothing)
            has_real_types = any(m -> m.descriptor.module_type !== Nothing, values(pipeline.modules))
            if has_real_types || isempty(pipeline.modules)
                return pipeline
            else
                println("  Action replay produced placeholder modules, trying workflow element...")
                throw(ErrorException("Modules have no types, using workflow element"))
            end
        end

        throw(ErrorException("Pipeline empty"))
    catch e
        # Try lightweight action replay (for rendering when modules aren't loaded)
        println("  Standard action replay failed, trying lightweight mode for rendering...")
        try
            builder = PipelineBuilder()
            actions = findall("//action", root)
            action_chain = build_action_chain(actions, version_id)
            for action in action_chain
                replay_action!(builder, action)
            end
            pipeline = build_pipeline_from_state_lightweight(builder)

            if !isempty(pipeline.modules)
                println("  ✓ Lightweight action replay successful: $(length(pipeline.modules)) modules, $(length(pipeline.connections)) connections")
                return pipeline
            end
        catch e2
            @warn "Lightweight action replay also failed" exception=e2
        end

        @warn "Action replay failed, falling back to workflow element" exception=e
    end

    # Fallback: use the workflow element (if present)
    workflow_elem = findfirst("//workflow", root)

    if workflow_elem === nothing
        @warn "No workflow element found and all action replay methods failed"
        return nothing
    end

    println("  Using <workflow> element as fallback...")

    # Find modules within the workflow element only
    modules_elems = findall(".//module", workflow_elem)

    if isempty(modules_elems)
        @warn "No modules found in workflow"
        return nothing
    end

    pipeline = Pipeline()
    module_id_map = Dict{String, Int}()  # XML id -> Pipeline id

    # Parse modules
    for mod_elem in modules_elems
        try
            mod = parse_module(mod_elem, pipeline)
            xml_id = attrs_dict(mod_elem)["id"]
            module_id_map[xml_id] = mod.id
        catch e
            @warn "Failed to parse module" exception=e
        end
    end

    # Parse connections within the workflow element
    for conn_elem in findall(".//connection", workflow_elem)
        try
            parse_connection!(conn_elem, pipeline, module_id_map)
        catch e
            @warn "Failed to parse connection" exception=e
        end
    end

    return pipeline
end

"""
    parse_module(elem::EzXML.Node, pipeline::Pipeline) -> ModuleInstance

Parse a module element and add to pipeline.
"""
function parse_module(elem::EzXML.Node, pipeline::Pipeline)
    attrs = attrs_dict(elem)

    name = get(attrs, "name", "Unknown")
    package = get(attrs, "package", "org.vistrails.vistrails.basic")
    namespace = get(attrs, "namespace", "")

    # Construct full package name
    full_package = if namespace != ""
        "$package.$namespace"
    else
        package
    end

    # Add module to pipeline
    mod = try
        add_module!(pipeline, full_package, name)
    catch e
        # If module not registered, skip it
        @warn "Module not registered: $full_package::$name"
        rethrow(e)
    end

    # Parse parameters (functions)
    for func_elem in findall(".//function", elem)
        func_attrs = attrs_dict(func_elem)
        param_name = get(func_attrs, "name", "")

        # Find parameter values
        for param_elem in findall(".//parameter", func_elem)
            param_attrs = attrs_dict(param_elem)
            val = get(param_attrs, "val", "")

            if val == ""
                # Try to find in nested elements
                val_elem = findfirst(".//value", param_elem)
                if val_elem !== nothing && nodecontent(val_elem) != ""
                    val = nodecontent(val_elem)
                end
            end

            if val != "" && param_name != ""
                set_parameter!(mod, param_name, val)
            end
        end
    end

    # Parse location (layout position) if present
    loc_elem = findfirst(".//location", elem)
    if loc_elem !== nothing
        loc_attrs = attrs_dict(loc_elem)
        x = parse(Float64, get(loc_attrs, "x", "0.0"))
        y = parse(Float64, get(loc_attrs, "y", "0.0"))
        mod.layout_position = (x, y)
    end

    # Parse annotations (like "__desc__" for module labels)
    for ann_elem in findall(".//annotation", elem)
        ann_attrs = attrs_dict(ann_elem)
        key = get(ann_attrs, "key", "")
        value = get(ann_attrs, "value", "")
        if key != ""
            mod.annotations[key] = value
        end
    end

    # Parse port specifications (instance-specific ports from workflow XML)
    for portspec_elem in findall(".//portSpec", elem)
        portspec_attrs = attrs_dict(portspec_elem)

        name = get(portspec_attrs, "name", "")
        port_type_str = get(portspec_attrs, "type", "input")
        port_type = port_type_str == "output" ? :output : :input
        sort_key = parse(Int, get(portspec_attrs, "sortKey", "0"))
        optional = get(portspec_attrs, "optional", "0") == "1"

        # Get signature from first portSpecItem
        signature = ""
        portspec_item = findfirst(".//portSpecItem", portspec_elem)
        if portspec_item !== nothing
            item_attrs = attrs_dict(portspec_item)
            module_name = get(item_attrs, "module", "")
            signature = module_name  # e.g., "Integer", "Float"
        end

        if name != ""
            port_spec = PortSpec(name, port_type, sort_key, optional, signature)
            push!(mod.port_specs, port_spec)
        end
    end

    return mod
end

"""
    parse_connection!(elem::EzXML.Node, pipeline::Pipeline, module_id_map::Dict)

Parse a connection element and add to pipeline.
"""
function parse_connection!(elem::EzXML.Node, pipeline::Pipeline, module_id_map::Dict)
    # Find source and destination ports
    source_elem = findfirst(".//port[@type='source']", elem)
    dest_elem = findfirst(".//port[@type='destination']", elem)

    if source_elem === nothing || dest_elem === nothing
        return
    end

    src_attrs = attrs_dict(source_elem)
    dst_attrs = attrs_dict(dest_elem)

    src_module_xml_id = src_attrs["moduleId"]
    src_port = get(src_attrs, "name", "self")

    dst_module_xml_id = dst_attrs["moduleId"]
    dst_port = get(dst_attrs, "name", "input")

    # Map XML IDs to pipeline IDs
    if !haskey(module_id_map, src_module_xml_id) || !haskey(module_id_map, dst_module_xml_id)
        return
    end

    src_module_id = module_id_map[src_module_xml_id]
    dst_module_id = module_id_map[dst_module_xml_id]

    src_module = get_module(pipeline, src_module_id)
    dst_module = get_module(pipeline, dst_module_id)

    add_connection!(pipeline, src_module, src_port, dst_module, dst_port)
end

"""
    save_vistrail(vistrail::Vistrail, filename::String)

Save a vistrail to a .vt file.
"""
function save_vistrail(vistrail::Vistrail, filename::String)
    error("Not yet implemented: save_vistrail()")
    # TODO: Generate XML and write to ZIP archive
end

"""
    print_vistrail_info(vt::Vistrail)

Print basic information about a vistrail.
"""
function print_vistrail_info(vt::Vistrail)
    println("=" ^ 60)
    println("VisTrails File Information")
    println("=" ^ 60)

    println("\nTotal versions: ", length(vt.actions))

    if !isempty(vt.tags)
        println("\nTagged versions (", length(vt.tags), "):")
        for tag in vt.tags
            println("  - ", tag.name, ": version ", tag.version_id)
        end
    end

    if !isempty(vt.actions)
        println("\nLatest version: ", maximum(keys(vt.actions)))
    end
end

"""
    print_pipeline_info(pipeline::Pipeline)

Print information about a pipeline.
"""
function print_pipeline_info(pipeline::Pipeline)
    println("\n" * "=" ^ 60)
    println("Pipeline Information")
    println("=" ^ 60)

    println("\nModules (", length(pipeline.modules), "):")
    # Sort by ID only
    for (id, mod) in sort(collect(pipeline.modules), by=first)
        println("  - ", mod.descriptor.name, " (", mod.descriptor.package, ")")
        println("    ID: ", id)

        if !isempty(mod.parameters)
            println("    Parameters:")
            for (name, val) in mod.parameters
                println("      ", name, " = ", val)
            end
        end
    end

    println("\nConnections (", length(pipeline.connections), "):")
    for conn in pipeline.connections
        src_mod = get_module(pipeline, conn.source_module_id)
        dst_mod = get_module(pipeline, conn.dest_module_id)

        println("  - ", src_mod.descriptor.name, ":", conn.source_port,
                " -> ", dst_mod.descriptor.name, ":", conn.dest_port)
    end
end
