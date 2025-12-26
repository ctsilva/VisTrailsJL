"""
Conditional Control Flow Modules

If, While, And, Or, Not for control flow.
"""

# Module types
struct IfModule end
struct WhileModule end
struct AndModule end
struct OrModule end
struct NotModule end

"""
Register all conditional modules.
"""
function register_conditionals!()
    # If - conditional execution
    # Like While, If uses ports to connect subpipelines (TruePort/FalsePort)
    # and parameters to specify which output ports to use
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "If",
        IfModule,
        [InputPort("Condition", Bool)],  # Note: capital C to match Python
        [OutputPort("Result", Any)],
        [
            ("TrueOutputPorts", Vector{String}),
            ("FalseOutputPorts", Vector{String})
        ]
    )
    register_module!(descriptor)

    # While - looping construct
    # The While module doesn't have regular input ports - it uses parameters
    # to configure port names and the FunctionPort for the subpipeline
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "While",
        WhileModule,
        InputPort[],  # No regular input ports
        [OutputPort("Result", Any)],
        [
            ("OutputPort", String),
            ("ConditionPort", String),
            ("StateInputPorts", Vector{String}),
            ("StateOutputPorts", Vector{String}),
            ("MaxIterations", Int),
            ("Delay", Float64)
        ]
    )
    register_module!(descriptor)

    # And - logical AND over a list (Fold operation)
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "And",
        AndModule,
        [InputPort("InputList", Vector)],
        [OutputPort("Result", Bool)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Or - logical OR over a list (Fold operation)
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "Or",
        OrModule,
        [InputPort("InputList", Vector)],
        [OutputPort("Result", Bool)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    # Not - logical NOT
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.control_flow",
        "Not",
        NotModule,
        [InputPort("input", Bool)],
        [OutputPort("value", Bool)],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    @info "Registered control flow modules: If, While, And, Or, Not"
end

"""
Compute function for If - conditionally executes TruePort or FalsePort subpipeline.

The If module is a control flow construct that:
- Takes a Condition input (boolean)
- Executes either TruePort or FalsePort module based on condition
- Returns the output from the executed module (specified by TrueOutputPorts/FalseOutputPorts)

Full implementation requires:
- Access to modules connected on TruePort/FalsePort
- Ability to execute those modules
- Extracting outputs based on output port parameters

For now, this is simplified.
"""
function compute(mod::ModuleInstance, ::Type{IfModule})
    condition = mod.inputs["Condition"]

    # Get parameters
    true_output_ports = get(mod.parameters, "TrueOutputPorts", String[])
    false_output_ports = get(mod.parameters, "FalseOutputPorts", String[])

    # Full If implementation requires:
    # 1. Access to the modules connected on TruePort/FalsePort
    # 2. Ability to execute the chosen module
    # 3. Extract outputs from the executed module
    # This requires interpreter integration

    @warn "If module is simplified - actual conditional execution not yet implemented" maxlog=1

    # For now, just output a placeholder based on condition
    mod.outputs["Result"] = condition ? true : false

    return mod.outputs
end

"""
Compute function for While - executes a subpipeline in a loop.

The While module is a control flow construct that repeatedly executes
a connected module (FunctionPort) until a condition is false or max iterations reached.

Full implementation requires:
- Re-executing the module connected to FunctionPort
- Passing state between iterations via StateInputPorts/StateOutputPorts
- Checking the condition on ConditionPort after each iteration
- Returning the final value from OutputPort

For now, this is simplified to just set a placeholder result.
"""
function compute(mod::ModuleInstance, ::Type{WhileModule})
    # Get parameters
    output_port = get(mod.parameters, "OutputPort", "result")
    condition_port = get(mod.parameters, "ConditionPort", nothing)
    state_input_ports = get(mod.parameters, "StateInputPorts", String[])
    state_output_ports = get(mod.parameters, "StateOutputPorts", String[])
    max_iterations = get(mod.parameters, "MaxIterations", 100)
    delay = get(mod.parameters, "Delay", 0.0)

    # Full While loop implementation requires:
    # 1. Access to the module connected on FunctionPort
    # 2. Ability to re-execute that module with modified inputs
    # 3. State management between iterations
    # This is complex and requires interpreter integration

    @warn "While module is simplified - actual loop execution not yet implemented" maxlog=1

    # For now, just output a placeholder
    # In a real implementation, this would be the result of the final iteration
    mod.outputs["Result"] = nothing

    return mod.outputs
end

"""
Compute function for And - logical AND over a list (Fold operation).

Treats non-zero/non-nothing/non-false values as true.
"""
function compute(mod::ModuleInstance, ::Type{AndModule})
    input_list = mod.inputs["InputList"]

    # Convert to boolean: treat non-zero, non-nothing, non-false as true
    result = true
    for item in input_list
        # Convert item to boolean (non-zero is true)
        item_bool = if item isa Bool
            item
        elseif item === nothing
            false
        elseif item isa Number
            item != 0
        else
            true  # Non-empty objects are truthy
        end

        result = result && item_bool
        if !result
            break  # Short-circuit
        end
    end

    mod.outputs["Result"] = result
    return mod.outputs
end

"""
Compute function for Or - logical OR over a list (Fold operation).

Treats non-zero/non-nothing/non-false values as true.
"""
function compute(mod::ModuleInstance, ::Type{OrModule})
    input_list = mod.inputs["InputList"]

    # Convert to boolean: treat non-zero, non-nothing, non-false as true
    result = false
    for item in input_list
        # Convert item to boolean (non-zero is true)
        item_bool = if item isa Bool
            item
        elseif item === nothing
            false
        elseif item isa Number
            item != 0
        else
            true  # Non-empty objects are truthy
        end

        result = result || item_bool
        if result
            break  # Short-circuit
        end
    end

    mod.outputs["Result"] = result
    return mod.outputs
end

"""
Compute function for Not - logical NOT.
"""
function compute(mod::ModuleInstance, ::Type{NotModule})
    input = mod.inputs["input"]

    mod.outputs["value"] = !input
    return mod.outputs
end
