"""
JuliaSource Module

Executes arbitrary Julia code within a workflow.
Similar to Python VisTrails' PythonSource but for Julia.
"""

"""
JuliaSourceModule <: Module

Executes Julia source code with access to inputs and outputs.

Parameters:
- source::String - Julia code to execute

The code has access to:
- `get_input(name::String)` - Get value from input port
- `set_output(name::String, value)` - Set value to output port
- All input port values are available as variables

Outputs:
- self::Any - The result of executing the code
- Any ports defined dynamically in the code
"""
struct JuliaSourceModule <: Module
end

"""
    compute(mod::ModuleInstance, ::Type{JuliaSourceModule})

Execute the JuliaSource module - run user-provided Julia code.
"""
function compute(mod::ModuleInstance, ::Type{JuliaSourceModule})
    # Get source code
    source = mod.parameters["source"]

    # Create a module for code execution
    code_module = Core.Module(Symbol("JuliaSourceExec_", mod.id))

    # Make inputs available as variables in the execution context
    for (name, value) in mod.inputs
        Core.eval(code_module, :($(Symbol(name)) = $value))
    end

    # Define helper functions
    Core.eval(code_module, quote
        # Get input by name
        function get_input(name::String)
            return $(mod.inputs)[name]
        end

        # Set output by name
        local outputs = $(mod.outputs)
        function set_output(name::String, value)
            outputs[name] = value
        end
    end)

    # Execute the user code
    try
        # Parse all expressions (handles multi-line code)
        parsed = Meta.parseall(source)
        result = Core.eval(code_module, parsed)

        # Set default output
        mod.outputs["self"] = result

        mod.uptodate = true
        mod.cache_state = :valid

        return mod.outputs
    catch e
        println("Error executing Julia code: ", e)
        println("Code was: ", source)
        rethrow(e)
    end
end

"""
    register_juliasource!()

Register JuliaSource module in the module registry.
"""
function register_juliasource!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.julia",   # package
        "JuliaSource",                      # name
        JuliaSourceModule,                  # type
        InputPort[],                        # inputs (dynamic)
        [OutputPort("self", Any)],          # outputs
        [("source", String)]                # parameters
    )

    register_module!(descriptor)
end
