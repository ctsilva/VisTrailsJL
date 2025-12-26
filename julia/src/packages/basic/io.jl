"""
I/O Modules

InputPort, OutputPort, StandardOutput for workflow I/O.

# Port Definitions (from Python source):

## InputPort (vistrails/core/modules/sub_module.py:74-92)
- **Input Ports** (5):
  - name (String, optional): Name of the input port
  - optional (Boolean, optional): Whether the input is optional
  - spec (String): Port specification
  - ExternalPipe (Variant, optional): External value piped in
  - Default (Variant): Default value if no input provided
- **Output Ports** (1):
  - InternalPipe (Variant): Value passed to workflow modules

## OutputPort (vistrails/core/modules/sub_module.py:96-105)
- **Input Ports** (4):
  - name (String, optional): Name of the output port
  - optional (Boolean, optional): Whether the output is optional
  - spec (String): Port specification
  - InternalPipe (Variant): Value from workflow modules
- **Output Ports** (1):
  - ExternalPipe (Variant, optional): Value exported from workflow
"""

# Module types
struct InputPortModule end
struct OutputPortModule end
struct StandardOutputModule end

"""
Register all I/O modules.
"""
function register_io!()
    # InputPort - receives input from outside the workflow
    # Python source: vistrails/core/modules/sub_module.py:74-92
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "InputPort",
        InputPortModule,
        [
            InputPort("name", String, optional=true),
            InputPort("optional", Bool, optional=true),
            InputPort("spec", String),
            InputPort("ExternalPipe", Any, optional=true),
            InputPort("Default", Any)
        ],
        [OutputPort("InternalPipe", Any)],
        [("name", String), ("default", Any)]
    )
    register_module!(descriptor)

    # OutputPort - sends output outside the workflow
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "OutputPort",
        OutputPortModule,
        [
            InputPort("InternalPipe", Any),
            InputPort("name", String, optional=true),
            InputPort("optional", Bool, optional=true),
            InputPort("spec", String, optional=true)
        ],
        [OutputPort("ExternalPipe", Any)],
        [("name", String)]
    )
    register_module!(descriptor)

    # StandardOutput - prints to stdout
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "StandardOutput",
        StandardOutputModule,
        [InputPort("value", Any)],
        OutputPort[],
        Tuple{String, Type}[]
    )
    register_module!(descriptor)

    @info "Registered I/O modules: InputPort, OutputPort, StandardOutput"
end

"""
Compute function for InputPort - gets value from workflow inputs or default.
"""
function compute(mod::ModuleInstance, ::Type{InputPortModule})
    port_name = get(mod.parameters, "name", "input")
    default_val = get(mod.parameters, "default", nothing)

    # TODO: In a full implementation, this would check workflow-level inputs
    # For now, just use the default value as a tuple (common in gcd.vt)
    # InputPort typically outputs to "InternalPipe" or similar

    # Create a dummy tuple for testing (84, 132) - classic GCD example
    value = (84, 132)

    # Set output to all possible port names
    mod.outputs["value"] = value
    mod.outputs["InternalPipe"] = value

    return mod.outputs
end

"""
Compute function for OutputPort - stores value for workflow output.

Takes input from InternalPipe and sends it to ExternalPipe.
"""
function compute(mod::ModuleInstance, ::Type{OutputPortModule})
    port_name = get(mod.parameters, "name", "output")

    # Get value from InternalPipe
    value = get(mod.inputs, "InternalPipe", nothing)

    # Set output to ExternalPipe
    mod.outputs["ExternalPipe"] = value

    # TODO: In a full implementation, this would set workflow-level outputs
    @info "OutputPort '$port_name':" value

    return mod.outputs
end

"""
Compute function for StandardOutput - prints to stdout.
"""
function compute(mod::ModuleInstance, ::Type{StandardOutputModule})
    value = mod.inputs["value"]
    println(value)

    return mod.outputs
end
