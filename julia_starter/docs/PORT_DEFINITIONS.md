# VisTrails Module Port Definitions

This document catalogs the static port definitions for VisTrails modules, copied from the Python source code.

## Purpose

When rendering workflows, we need to know the exact number and names of input/output ports for each module. This information comes from two sources:

1. **Static ports** - Defined in the Python module class (covered in this document)
2. **Dynamic ports** - Defined per-instance in workflow XML `<portSpec>` elements (e.g., Tuple, Untuple)

## Static Port Definitions

### Basic Package (org.vistrails.vistrails.basic)

#### InputPort
**Source:** `vistrails/core/modules/sub_module.py:74-92`

**Input Ports (5):**
- `name` (String, optional): Name of the input port
- `optional` (Boolean, optional): Whether the input is optional
- `spec` (String): Port specification
- `ExternalPipe` (Variant, optional): External value piped in
- `Default` (Variant): Default value if no input provided

**Output Ports (1):**
- `InternalPipe` (Variant): Value passed to workflow modules

**Julia Implementation:** `src/packages/basic/io.jl`

---

#### OutputPort
**Source:** `vistrails/core/modules/sub_module.py:96-105`

**Input Ports (4):**
- `name` (String, optional): Name of the output port
- `optional` (Boolean, optional): Whether the output is optional
- `spec` (String): Port specification
- `InternalPipe` (Variant): Value from workflow modules

**Output Ports (1):**
- `ExternalPipe` (Variant, optional): Value exported from workflow

**Julia Implementation:** `src/packages/basic/io.jl`

---

#### Round
**Source:** `vistrails/core/modules/basic_modules.py` (class Round)

**Input Ports (2):**
- `in_value` (Float): Input floating-point value
- `floor` (Boolean, optional, default=True): Use floor rounding if true

**Output Ports (1):**
- `out_value` (Integer): Rounded integer value

**Julia Implementation:** `src/packages/basic/datastructures.jl`

---

#### Integer, Float, String, Boolean
**Source:** `vistrails/core/modules/basic_modules.py`

**Input Ports:** 0

**Output Ports (1):**
- `value` (respective type): The constant value

**Julia Implementation:** `src/packages/basic/constants.jl`

---

### PythonCalc Package (org.vistrails.vistrails.pythoncalc)

#### PythonCalc
**Source:** `vistrails/packages/pythonCalc/init.py:54-77`

**Input Ports (3):**
- `value1` (Float): First operand
- `value2` (Float): Second operand
- `op` (String, enum): Operation (+, -, *, /)

**Output Ports (1):**
- `value` (Float): Result of calculation

**Julia Implementation:** `src/packages/pythoncalc/PythonCalc.jl`

---

### Control Flow Package (org.vistrails.vistrails.control_flow)

#### If
**Source:** `vistrails/packages/controlflow/init.py`

**Input Ports (1):**
- `Condition` (Boolean): Condition to evaluate

**Output Ports (1):**
- `Result` (Variant): Result from TruePort or FalsePort branch

---

#### And
**Source:** `vistrails/packages/controlflow/init.py`

**Input Ports (1):**
- `InputList` (List): List of boolean values to AND together

**Output Ports (1):**
- `Result` (Boolean): Logical AND of all inputs

---

## Dynamic Port Modules

These modules have ports defined per-instance in the workflow XML via `<portSpec>` elements:

### Tuple
**Source:** `vistrails/core/modules/basic_modules.py` (class Tuple)

**Input Ports:** **DYNAMIC** - Defined per workflow instance (e.g., "a", "b", "c")
**Output Ports (1):**
- `value` (Tuple): Tuple containing all input values

The input port names and count are specified in the workflow XML.

---

### Untuple
**Source:** `vistrails/core/modules/basic_modules.py` (class Untuple)

**Input Ports (1):**
- `value` (Tuple): Input tuple to unpack

**Output Ports:** **DYNAMIC** - Defined per workflow instance (e.g., "a", "b", "c")

The output port names and count match the tuple structure, specified in workflow XML.

---

### PythonSource
**Source:** `vistrails/core/modules/basic_modules.py`

**Input Ports:** **DYNAMIC** - Can be defined per workflow instance
**Output Ports:** **DYNAMIC** - Defined by the Python source code execution

---

## Workflow XML Port Specifications

For dynamic modules, the workflow XML contains `<portSpec>` elements that define ports:

```xml
<portSpec id="3" maxConns="-1" minConns="0" name="a" optional="0" sortKey="0" type="output">
  <portSpecItem default="" entryType="" id="3" label=""
                module="Integer" namespace=""
                package="org.vistrails.vistrails.basic" pos="0" values="" />
</portSpec>
```

Key attributes:
- `name`: Port name (e.g., "a", "b", "value")
- `type`: "input" or "output"
- `sortKey`: Order for rendering (important for port positioning!)
- `optional`: Whether the port is optional

## Rendering Implications

When rendering workflows in SVG:

1. **Use static port counts** from module descriptors for modules with fixed ports
2. **Parse `<portSpec>` elements** from workflow XML for dynamic port modules
3. **Use `sortKey`** to order ports correctly (left to right on edges)
4. **Position ports horizontally** along top edge (inputs) and bottom edge (outputs)
5. **Space ports evenly** using: `x = module_left + (port_index * spacing)` where `spacing = module_width / (num_ports + 1)`

## References

- VisTrails Python source: `/Users/csilva/src/VisTrails/vistrails/`
- Julia implementations: `/Users/csilva/src/VisTrails/julia_starter/src/packages/`
