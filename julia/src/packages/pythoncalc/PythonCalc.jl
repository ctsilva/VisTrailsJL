"""
PythonCalc Module

Execute Python expressions/calculations.
Similar to PythonSource but optimized for calculations.

# Port Definitions (from Python source):

## PythonCalc (vistrails/packages/pythonCalc/init.py:54-77)
- **Input Ports** (3):
  - value1 (Float): First operand
  - value2 (Float): Second operand
  - op (String, enum): Operation (+, -, *, /)
- **Output Ports** (1):
  - value (Float): Result of calculation
"""

using PyCall

"""
PythonCalc module type
"""
struct PythonCalcModule end

"""
Register the PythonCalc module in the registry.
Python source: vistrails/packages/pythonCalc/init.py:54-77
"""
function register_pythoncalc!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.pythoncalc",
        "PythonCalc",
        PythonCalcModule,
        [
            InputPort("value1", Float64),
            InputPort("value2", Float64),
            InputPort("op", String)  # enum: +, -, *, /
        ],
        [OutputPort("value", Float64)],
        [("expression", String), ("op", String)]
    )

    register_module!(descriptor)
    @info "Registered module: org.vistrails.vistrails.pythoncalc::PythonCalc"
end

"""
    compute(mod::ModuleInstance, ::Type{PythonCalcModule})

Execute a Python expression and return the result.

The expression can reference inputs by name.
"""
function compute(mod::ModuleInstance, ::Type{PythonCalcModule})
    # Check for 'op' parameter (operator like "+", "-", "*", "/")
    if haskey(mod.parameters, "op")
        op = mod.parameters["op"]
        # Build expression from inputs and operator
        # Expect inputs like value1, value2 or input1, input2
        input_names = sort(collect(keys(mod.inputs)))

        if length(input_names) >= 2
            # Binary operation
            val1_name = input_names[1]
            val2_name = input_names[2]
            expression = "$val1_name $op $val2_name"
        else
            @warn "PythonCalc: Not enough inputs for operator '$op'"
            mod.outputs["value"] = nothing
            return mod.outputs
        end
    else
        # Check for 'expression' parameter
        expression = get(mod.parameters, "expression", "")

        if expression == ""
            @warn "PythonCalc: No expression or operator provided"
            mod.outputs["value"] = nothing
            return mod.outputs
        end
    end

    # Create Python namespace with inputs
    py_globals = PyDict()

    # Add all inputs to Python namespace
    for (name, value) in mod.inputs
        py_globals[name] = PyObject(value)
    end

    # Evaluate the expression
    try
        result = py"""eval($expression, $py_globals)"""
        mod.outputs["value"] = result
    catch e
        @error "PythonCalc execution failed" expression=expression exception=e
        rethrow(e)
    end

    return mod.outputs
end
