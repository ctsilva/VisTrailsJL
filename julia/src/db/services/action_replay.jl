"""
Action Replay System

Reconstructs pipelines by replaying the action history from VisTrails .vt files.
This is the proper way to build a pipeline at any version.
"""

using EzXML

"""
    PipelineBuilder

Mutable state used during action replay to build up a pipeline.
"""
mutable struct PipelineBuilder
    modules::Dict{Int, Dict{String, Any}}  # moduleId -> module data
    connections::Dict{Int, Dict{String, Any}}  # connectionId -> connection data
    functions::Dict{Int, Dict{String, Any}}  # functionId -> function data
    parameters::Dict{Int, Dict{String, Any}}  # parameterId -> parameter data
    locations::Dict{Int, Dict{String, Any}}  # locationId -> location data
end

PipelineBuilder() = PipelineBuilder(
    Dict{Int, Dict{String, Any}}(),
    Dict{Int, Dict{String, Any}}(),
    Dict{Int, Dict{String, Any}}(),
    Dict{Int, Dict{String, Any}}(),
    Dict{Int, Dict{String, Any}}()
)

"""
    replay_actions_to_version(root::EzXML.Node, target_version::Int) -> Pipeline

Replay actions from version 0 to target_version to reconstruct the pipeline.
"""
function replay_actions_to_version(root::EzXML.Node, target_version::Int)
    builder = PipelineBuilder()

    # Find all actions and sort by ID
    actions = findall("//action", root)

    # Build a chain from 0 to target_version
    action_chain = build_action_chain(actions, target_version)

    # Replay each action in order
    for action in action_chain
        replay_action!(builder, action)
    end

    # Convert builder state to Pipeline
    return build_pipeline_from_state(builder)
end

"""
    build_action_chain(actions, target_version::Int) -> Vector{EzXML.Node}

Build the chain of actions from version 0 to target_version.
"""
function build_action_chain(actions, target_version::Int)
    # Create a map of action ID to action element
    action_map = Dict{Int, EzXML.Node}()
    for action in actions
        attrs = attrs_dict(action)
        id = parse(Int, attrs["id"])
        action_map[id] = action
    end

    # Walk backwards from target to build chain
    chain = EzXML.Node[]
    current_id = target_version

    while current_id > 0
        if !haskey(action_map, current_id)
            @warn "Action $current_id not found"
            break
        end

        action = action_map[current_id]
        pushfirst!(chain, action)

        # Get previous action
        attrs = attrs_dict(action)
        current_id = parse(Int, attrs["prevId"])
    end

    return chain
end

"""
    replay_action!(builder::PipelineBuilder, action::EzXML.Node)

Replay a single action, updating the builder state.
"""
function replay_action!(builder::PipelineBuilder, action::EzXML.Node)
    # Process all operations in this action
    for op in elements(action)
        op_name = nodename(op)

        if op_name == "add"
            replay_add!(builder, op)
        elseif op_name == "delete"
            replay_delete!(builder, op)
        elseif op_name == "change"
            replay_change!(builder, op)
        end
    end
end

"""
    replay_add!(builder::PipelineBuilder, add_op::EzXML.Node)

Process an <add> operation.
"""
function replay_add!(builder::PipelineBuilder, add_op::EzXML.Node)
    attrs = attrs_dict(add_op)

    # Some operations might not have all attributes
    if !haskey(attrs, "what") || !haskey(attrs, "objectId")
        return
    end

    what = attrs["what"]
    obj_id = parse(Int, attrs["objectId"])

    # Get the actual element being added (child of <add>)
    elem = findfirst("*", add_op)
    if elem === nothing
        return
    end

    if what == "module"
        # Add a module
        mod_attrs = attrs_dict(elem)
        builder.modules[obj_id] = Dict{String, Any}(
            "id" => obj_id,
            "name" => get(mod_attrs, "name", ""),
            "package" => get(mod_attrs, "package", ""),
            "namespace" => get(mod_attrs, "namespace", ""),
            "functions" => Int[],
            "location" => nothing
        )

    elseif what == "connection"
        # Add a connection
        builder.connections[obj_id] = Dict{String, Any}(
            "id" => obj_id,
            "ports" => Dict{String, Any}()
        )

    elseif what == "function"
        # Add a function (parameter group) to a module
        parent_id = parse(Int, attrs["parentObjId"])
        func_attrs = attrs_dict(elem)

        builder.functions[obj_id] = Dict{String, Any}(
            "id" => obj_id,
            "name" => get(func_attrs, "name", ""),
            "parameters" => Int[]
        )

        # Link to parent module
        if haskey(builder.modules, parent_id)
            push!(builder.modules[parent_id]["functions"], obj_id)
        end

    elseif what == "parameter"
        # Add a parameter to a function
        parent_id = parse(Int, attrs["parentObjId"])
        param_attrs = attrs_dict(elem)

        builder.parameters[obj_id] = Dict{String, Any}(
            "id" => obj_id,
            "name" => get(param_attrs, "name", ""),
            "type" => get(param_attrs, "type", ""),
            "val" => get(param_attrs, "val", "")
        )

        # Link to parent function
        if haskey(builder.functions, parent_id)
            push!(builder.functions[parent_id]["parameters"], obj_id)
        end

    elseif what == "location"
        # Add location to a module
        parent_id = parse(Int, attrs["parentObjId"])
        loc_attrs = attrs_dict(elem)

        builder.locations[obj_id] = Dict{String, Any}(
            "id" => obj_id,
            "x" => get(loc_attrs, "x", "0"),
            "y" => get(loc_attrs, "y", "0")
        )

        # Link to parent module
        if haskey(builder.modules, parent_id)
            builder.modules[parent_id]["location"] = obj_id
        end

    elseif what == "port"
        # Add a port to a connection
        parent_id = parse(Int, attrs["parentObjId"])
        port_attrs = attrs_dict(elem)

        port_type = get(port_attrs, "type", "")

        if haskey(builder.connections, parent_id)
            builder.connections[parent_id]["ports"][port_type] = Dict{String, Any}(
                "moduleId" => parse(Int, get(port_attrs, "moduleId", "0")),
                "moduleName" => get(port_attrs, "moduleName", ""),
                "name" => get(port_attrs, "name", ""),
                "signature" => get(port_attrs, "signature", "")
            )
        end
    end
end

"""
    replay_delete!(builder::PipelineBuilder, delete_op::EzXML.Node)

Process a <delete> operation.
"""
function replay_delete!(builder::PipelineBuilder, delete_op::EzXML.Node)
    attrs = attrs_dict(delete_op)
    what = attrs["what"]
    obj_id = parse(Int, attrs["objectId"])

    if what == "module"
        delete!(builder.modules, obj_id)
    elseif what == "connection"
        delete!(builder.connections, obj_id)
    elseif what == "function"
        delete!(builder.functions, obj_id)
    elseif what == "parameter"
        delete!(builder.parameters, obj_id)
    elseif what == "location"
        delete!(builder.locations, obj_id)
    elseif what == "port"
        parent_id = parse(Int, attrs["parentObjId"])
        if haskey(builder.connections, parent_id)
            # Remove port by type
            # This is simplified - would need to match exact port
            # For now, just note that the connection may be invalid
        end
    end
end

"""
    replay_change!(builder::PipelineBuilder, change_op::EzXML.Node)

Process a <change> operation.
"""
function replay_change!(builder::PipelineBuilder, change_op::EzXML.Node)
    attrs = attrs_dict(change_op)
    what = attrs["what"]
    old_id = parse(Int, attrs["oldObjId"])
    new_id = parse(Int, attrs["newObjId"])

    # Get the new element
    elem = findfirst("*", change_op)
    if elem === nothing
        return
    end

    # Delete old object directly (don't call replay_delete! as it expects different attributes)
    if what == "module"
        delete!(builder.modules, old_id)
    elseif what == "connection"
        delete!(builder.connections, old_id)
    elseif what == "function"
        delete!(builder.functions, old_id)
    elseif what == "parameter"
        delete!(builder.parameters, old_id)
    elseif what == "location"
        delete!(builder.locations, old_id)
    end

    # Create/update new object
    if what == "location"
        parent_id = parse(Int, attrs["parentObjId"])
        loc_attrs = attrs_dict(elem)

        builder.locations[new_id] = Dict{String, Any}(
            "id" => new_id,
            "x" => get(loc_attrs, "x", "0"),
            "y" => get(loc_attrs, "y", "0")
        )

        if haskey(builder.modules, parent_id)
            builder.modules[parent_id]["location"] = new_id
        end
    end
end

"""
    build_pipeline_from_state_lightweight(builder::PipelineBuilder) -> Pipeline

Convert the builder state into a Pipeline for rendering purposes only.
Creates placeholder modules without requiring module descriptors.
This allows rendering workflows even when packages (like VTK) aren't loaded.
"""
function build_pipeline_from_state_lightweight(builder::PipelineBuilder)
    pipeline = Pipeline()
    module_id_map = Dict{Int, Int}()  # XML ID -> Pipeline ID
    next_id = 1

    # Create placeholder modules with layout positions
    for (xml_id, mod_data) in builder.modules
        package = mod_data["package"]
        namespace = mod_data["namespace"]
        name = mod_data["name"]

        # Create a minimal placeholder descriptor
        full_package = if namespace != ""
            "$package.$namespace"
        else
            package
        end

        # Create placeholder descriptor (doesn't need to be registered)
        descriptor = ModuleDescriptor(
            full_package,
            name,
            Nothing,  # No compute function
            InputPort[],  # Ports will be inferred from connections
            OutputPort[],
            Tuple{String, Type}[]
        )

        # Create module instance using the constructor
        mod = ModuleInstance(next_id, descriptor)

        # Add parameters from functions (same logic as standard mode)
        for func_id in mod_data["functions"]
            if haskey(builder.functions, func_id)
                func = builder.functions[func_id]
                func_name = func["name"]

                for param_id in func["parameters"]
                    if haskey(builder.parameters, param_id)
                        param = builder.parameters[param_id]
                        param_name = param["name"]
                        param_val = param["val"]

                        if param_val != ""
                            # Use function name as key if parameter name is empty or "<no description>"
                            key = if param_name == "" || param_name == "<no description>"
                                func_name
                            else
                                param_name
                            end

                            # Store parameter directly in mod.parameters dict
                            mod.parameters[key] = param_val
                        end
                    end
                end
            end
        end

        # Add annotations from annotation data
        if haskey(mod_data, "annotations")
            for ann_id in mod_data["annotations"]
                if haskey(builder.annotations, ann_id)
                    ann = builder.annotations[ann_id]
                    ann_key = ann["key"]
                    ann_value = ann["value"]
                    mod.annotations[ann_key] = ann_value
                end
            end
        end

        # Add location (layout position) if available
        if haskey(mod_data, "location")
            loc_id = mod_data["location"]
            if haskey(builder.locations, loc_id)
                loc = builder.locations[loc_id]
                x = parse(Float64, loc["x"])
                y = parse(Float64, loc["y"])
                mod.layout_position = (x, y)
            end
        end

        pipeline.modules[next_id] = mod
        module_id_map[xml_id] = next_id
        next_id += 1
    end

    # Add connections and infer port specs
    for (conn_id, conn_data) in builder.connections
        ports = conn_data["ports"]

        if haskey(ports, "source") && haskey(ports, "destination")
            src = ports["source"]
            dst = ports["destination"]

            src_xml_id = src["moduleId"]
            dst_xml_id = dst["moduleId"]

            if haskey(module_id_map, src_xml_id) && haskey(module_id_map, dst_xml_id)
                src_mod_id = module_id_map[src_xml_id]
                dst_mod_id = module_id_map[dst_xml_id]

                src_mod = pipeline.modules[src_mod_id]
                dst_mod = pipeline.modules[dst_mod_id]

                src_port = src["name"]
                dst_port = dst["name"]

                # Add connection
                conn = Connection(src_mod_id, src_port, dst_mod_id, dst_port)
                push!(pipeline.connections, conn)

                # Infer port specs from connections
                # Check if this output port already exists
                if !any(ps -> ps.name == src_port && ps.port_type == :output, src_mod.port_specs)
                    push!(src_mod.port_specs, PortSpec(src_port, :output, length(src_mod.port_specs) + 1, false, ""))
                end

                # Check if this input port already exists
                if !any(ps -> ps.name == dst_port && ps.port_type == :input, dst_mod.port_specs)
                    push!(dst_mod.port_specs, PortSpec(dst_port, :input, length(dst_mod.port_specs) + 1, false, ""))
                end
            end
        end
    end

    return pipeline
end

"""
    build_pipeline_from_state(builder::PipelineBuilder) -> Pipeline

Convert the builder state into an actual Pipeline object.
"""
function build_pipeline_from_state(builder::PipelineBuilder)
    pipeline = Pipeline()
    module_id_map = Dict{Int, Int}()  # XML ID -> Pipeline ID

    # Add modules
    for (xml_id, mod_data) in builder.modules
        package = mod_data["package"]
        namespace = mod_data["namespace"]
        name = mod_data["name"]

        # Construct full package name
        full_package = if namespace != ""
            "$package.$namespace"
        else
            package
        end

        # Add module to pipeline
        try
            mod = add_module!(pipeline, full_package, name)
            module_id_map[xml_id] = mod.id

            # Add parameters from functions
            for func_id in mod_data["functions"]
                if haskey(builder.functions, func_id)
                    func = builder.functions[func_id]
                    func_name = func["name"]

                    @debug "Processing function" func_name func_id num_params=length(func["parameters"])

                    for param_id in func["parameters"]
                        if haskey(builder.parameters, param_id)
                            param = builder.parameters[param_id]
                            param_name = param["name"]
                            param_val = param["val"]

                            @debug "Found parameter" param_name param_val func_name

                            if param_val != ""
                                @info "Setting parameter: $func_name.$param_name = $param_val (module $(mod.descriptor.name) #$(mod.id))"
                                set_parameter!(mod, func_name, param_val)
                            else
                                @debug "Skipping empty parameter" param_name func_name
                            end
                        end
                    end
                end
            end

            # Add location (layout position) if available
            if haskey(mod_data, "location")
                loc_id = mod_data["location"]
                if haskey(builder.locations, loc_id)
                    loc = builder.locations[loc_id]
                    x = parse(Float64, loc["x"])
                    y = parse(Float64, loc["y"])
                    mod.layout_position = (x, y)
                end
            end

            # Debug: show final parameter state
            @info "Module $(mod.descriptor.name) #$(mod.id) final parameters: $(mod.parameters)"
        catch e
            @warn "Failed to add module" package=full_package name=name exception=e
        end
    end

    # Add connections
    for (conn_id, conn_data) in builder.connections
        ports = conn_data["ports"]

        if haskey(ports, "source") && haskey(ports, "destination")
            src = ports["source"]
            dst = ports["destination"]

            src_xml_id = src["moduleId"]
            dst_xml_id = dst["moduleId"]

            if haskey(module_id_map, src_xml_id) && haskey(module_id_map, dst_xml_id)
                src_mod_id = module_id_map[src_xml_id]
                dst_mod_id = module_id_map[dst_xml_id]

                src_mod = pipeline.modules[src_mod_id]
                dst_mod = pipeline.modules[dst_mod_id]

                src_port = src["name"]
                dst_port = dst["name"]

                try
                    add_connection!(pipeline, src_mod, src_port, dst_mod, dst_port)
                catch e
                    @warn "Failed to add connection" exception=e
                end
            end
        end
    end

    return pipeline
end
