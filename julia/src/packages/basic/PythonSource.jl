"""
PythonSource Module

Execute Python code within workflows using PyCall.
Compatible with original VisTrails PythonSource modules.
"""

using PyCall
using HTTP

"""
PythonSource module type
"""
struct PythonSourceModule end

"""
Register the PythonSource module in the registry.
"""
function register_pythonsource!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "PythonSource",
        PythonSourceModule,
        InputPort[],  # Dynamic inputs
        [OutputPort("self", Any)],
        [("source", String)]
    )

    register_module!(descriptor)
    @info "Registered module: org.vistrails.vistrails.basic::PythonSource"
end

"""
    compute(mod::ModuleInstance, ::Type{PythonSourceModule})

Execute Python source code with access to input/output ports.

The Python code can use:
- get_input(port_name) - get input from a port
- set_output(port_name, value) - set output to a port
- self - the output value (set via set_output("self", value))
"""
function compute(mod::ModuleInstance, ::Type{PythonSourceModule})
    # Get source parameter (might be URL-encoded)
    if !haskey(mod.parameters, "source")
        @warn "PythonSource: No source parameter found" available_params=keys(mod.parameters)
        mod.outputs["self"] = nothing
        return mod.outputs
    end

    source = mod.parameters["source"]

    # URL-decode if needed
    if occursin("%", source)
        source = HTTP.URIs.unescapeuri(source)
    end

    # Create a new Python namespace for this execution
    py_globals = PyDict()

    # Debug: show inputs
    println("    PythonSource inputs: ", mod.inputs)

    # Add all inputs directly as variables in Python
    for (name, value) in mod.inputs
        if value === nothing
            @warn "PythonSource: Input '$name' is nothing!"
            continue  # Skip nothing values
        end
        # Convert Julia value to Python
        try
            py_globals[name] = PyObject(value)
        catch e
            @warn "Failed to convert input '$name' to Python" value=value exception=e
        end
    end

    # Note: We don't add Julia functions to py_globals as they don't convert well to Python
    # Users should use direct variable access instead

    # Execute the Python code
    try
        py"""
        exec($source, $py_globals)
        """

        # Extract all new variables as outputs
        # (Variables that weren't there initially or were modified)
        for (key, val) in py_globals
            # Skip internal Python stuff and our helper functions
            if !startswith(String(key), "__") && !isa(val, Function)
                mod.outputs[String(key)] = val
            end
        end

        # Get the self value if it was set
        if haskey(py_globals, "self") && py_globals["self"] != pybuiltin("None")
            mod.outputs["self"] = py_globals["self"]
        end

    catch e
        @error "PythonSource execution failed" exception=e source=source
        rethrow(e)
    end

    return mod.outputs
end
