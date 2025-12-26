# Compute Function Naming Strategy

**Issue**: How to handle multiple `compute` functions in package notebooks without name clashes?

## The Problem

### Current Julia Implementation (Works)

Uses **multiple dispatch on module type**:

```julia
# In HTTPFile.jl
struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # HTTPFile-specific logic
end

# In JuliaSource.jl
struct JuliaSourceModule <: Module end

function compute(mod::ModuleInstance, ::Type{JuliaSourceModule})
    # JuliaSource-specific logic
end

# Dispatcher calls the right one
compute(mod, HTTPFileModule)  # → HTTPFile version
compute(mod, JuliaSourceModule)  # → JuliaSource version
```

**Works perfectly** - no name clashes because Julia dispatches on the `Type{T}` parameter.

### Proposed Notebook Design (BROKEN)

In `PACKAGE_DEFINITIONS_V2.md`, I suggested:

```julia
#| module: HTTPFile

function compute(self::ModuleInstance)  # ❌ NAME CLASH
    # HTTPFile logic
end

#| module: JuliaSource

function compute(self::ModuleInstance)  # ❌ REDEFINES compute!
    # JuliaSource logic
end
```

**Problem**: Both functions have the same signature! Second definition overwrites the first.

## Solution Options

### Option 1: Module-Specific Names (Simplest)

Name functions uniquely per module:

```julia
#| module: HTTPFile

function compute_httpfile(self::ModuleInstance)
    url = get_parameter(self, "url")
    response = HTTP.get(url)
    set_output(self, "file", String(response.body))
end

#| module: JuliaSource

function compute_juliasource(self::ModuleInstance)
    source = get_parameter(self, "source")
    # Execute source code
    set_output(self, "self", result)
end
```

**Pros**:
- ✅ No name clashes
- ✅ Clear which module each function belongs to
- ✅ Simple to implement
- ✅ Easy to debug (stack traces show function names)

**Cons**:
- ⚠️ Less elegant than generic `compute`
- ⚠️ Need to follow naming convention (compute_modulename)

**Parser Implementation**:
```julia
# Extract module name from directive
module_name = directives["module"]  # "HTTPFile"

# Find function compute_httpfile
func_name = "compute_" * lowercase(module_name)

# Register with type-dispatched wrapper
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    return compute_httpfile(mod)
end
```

### Option 2: Keep Multiple Dispatch (Best for Julia)

Use the same pattern as current implementation:

```julia
#| module: HTTPFile
#| struct: HTTPFileModule  # Define the type

# Parser creates the struct automatically:
# struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = get_parameter(mod, "url")
    response = HTTP.get(url)
    set_output(mod, "file", String(response.body))
end

#| module: JuliaSource
#| struct: JuliaSourceModule

function compute(mod::ModuleInstance, ::Type{JuliaSourceModule})
    source = get_parameter(mod, "source")
    # Execute source code
end
```

**Pros**:
- ✅ **Best Julia idiom** (uses multiple dispatch)
- ✅ Matches current implementation exactly
- ✅ No name clashes (dispatch on type)
- ✅ Type-safe

**Cons**:
- ⚠️ More complex syntax (need type annotation)
- ⚠️ Parser must create struct types

**Parser Implementation**:
```julia
# From directives
module_name = "HTTPFile"
struct_name = get(directives, "struct", "$(module_name)Module")

# Create struct type
eval(quote
    struct $(Symbol(struct_name)) <: Module end
end)

# Function is already defined with correct signature in cell
```

### Option 3: Anonymous Functions / Closures

Store compute functions as closures:

```julia
#| module: HTTPFile

# Define compute as a closure stored in directive metadata
compute_func = function(self::ModuleInstance)
    url = get_parameter(self, "url")
    response = HTTP.get(url)
    set_output(self, "file", String(response.body))
end

#| module: JuliaSource

compute_func = function(self::ModuleInstance)
    source = get_parameter(self, "source")
    # Execute source code
end
```

**Parser stores the function**:
```julia
# Extract compute_func from cell
compute_func = extract_function(cell)

# Store in descriptor
descriptor = ModuleDescriptor(
    ...,
    compute_function = compute_func
)

# Call it later
descriptor.compute_function(mod)
```

**Pros**:
- ✅ No name clashes
- ✅ Clean cell syntax

**Cons**:
- ❌ Can't use multiple dispatch
- ❌ Need to store functions in descriptors (not typical Julia pattern)
- ❌ Harder to debug (anonymous functions)

### Option 4: Module Namespaces

Put each module's compute in its own Julia module:

```julia
#| module: HTTPFile

module HTTPFile_Impl
    function compute(self::ModuleInstance)
        url = get_parameter(self, "url")
        response = HTTP.get(url)
        set_output(self, "file", String(response.body))
    end
end

#| module: JuliaSource

module JuliaSource_Impl
    function compute(self::ModuleInstance)
        source = get_parameter(self, "source")
        # Execute source code
    end
end
```

**Call via**:
```julia
HTTPFile_Impl.compute(mod)
JuliaSource_Impl.compute(mod)
```

**Pros**:
- ✅ No name clashes (namespaced)
- ✅ Can use simple `compute` name

**Cons**:
- ⚠️ Creates many modules (pollution)
- ⚠️ More complex for users
- ⚠️ Harder to debug

## Recommendation: Option 1 or 2

### For MVP: **Option 1 (Module-Specific Names)**

**Syntax**:
```julia
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

function compute_httpfile(self::ModuleInstance)
    url = get_parameter(self, "url")
    response = HTTP.get(url)
    set_output(self, "file", String(response.body))
end
```

**Why**:
- Simplest to implement
- Clear and explicit
- No magic
- Easy to debug

**Naming convention**: `compute_<modulename>` where `<modulename>` is lowercase module name.

### For Polish: **Option 2 (Multiple Dispatch)**

**Syntax**:
```julia
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = get_parameter(mod, "url")
    response = HTTP.get(url)
    set_output(mod, "file", String(response.body))
end
```

**Why**:
- **Most idiomatic Julia**
- Uses type system properly
- Matches current implementation
- Type-safe

**Parser creates struct**:
```julia
# Parser automatically generates:
struct HTTPFileModule <: Module end
```

## Hybrid Approach (Best of Both)

Allow **both** styles:

### Style A: Named Functions (Simpler)

```julia
#| module: HTTPFile

function compute_httpfile(self::ModuleInstance)
    # Implementation
end
```

Parser wraps it:
```julia
struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    return compute_httpfile(mod)
end
```

### Style B: Type-Dispatched (Advanced)

```julia
#| module: HTTPFile

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # Implementation
end
```

Parser uses it directly.

**Benefits**:
- Beginners use simple named functions
- Advanced users can use multiple dispatch
- Both export to same .jl code

## Updated Design

### Package Notebook Syntax (Revised)

**Simple style** (recommended for most users):

```julia
# %% Package metadata
#| package-meta
#| identifier: org.vistrails.vistrails.basic
#| version: 2.2.0

# %% HTTPFile module
#| module: HTTPFile
#| output_ports:
#|   - name: file
#|     signature: basic:String
#| parameters:
#|   - name: url
#|     signature: basic:String

function compute_httpfile(mod::ModuleInstance)
    url = get_parameter(mod, "url")
    response = HTTP.get(url)
    set_output(mod, "file", String(response.body))
end

# %% JuliaSource module
#| module: JuliaSource
#| output_ports:
#|   - name: self
#|     signature: basic:Any
#| parameters:
#|   - name: source
#|     signature: basic:String

function compute_juliasource(mod::ModuleInstance)
    source = get_parameter(mod, "source")
    # Create execution module
    code_module = Core.Module(Symbol("JuliaSourceExec_", mod.id))
    # ... implementation
    set_output(mod, "self", result)
end
```

**Advanced style** (for Julia experts):

```julia
# %% HTTPFile module
#| module: HTTPFile
#| struct: HTTPFileModule  # Optional: specify struct name
#| output_ports:
#|   - name: file
#|     signature: basic:String

struct HTTPFileModule <: Module end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = get_parameter(mod, "url")
    response = HTTP.get(url)
    set_output(mod, "file", String(response.body))
end
```

## Export to .jl Files

Both styles export to the same canonical form:

```julia
# Generated: src/packages/basic/HTTPFile.jl

"""
HTTPFile Module

Fetches content from an HTTP/HTTPS URL.
"""

using HTTP

struct HTTPFileModule <: Module
end

function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    url = get_parameter(mod, "url")
    response = HTTP.get(url)
    set_output(mod, "file", String(response.body))
    mod.uptodate = true
    mod.cache_state = :valid
    return mod.outputs
end

function register_httpfile!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",
        "HTTPFile",
        HTTPFileModule,
        InputPort[],
        [OutputPort("file", String)],
        [("url", String)]
    )
    register_module!(descriptor)
end
```

## Implementation in Parser

```julia
function parse_module_cell(cell)
    directives = parse_cell_directives(cell.source)
    module_name = directives["module"]

    # Check which style is used
    if has_function_named("compute_$(lowercase(module_name))", cell.source)
        # Style A: Named function
        func_name = "compute_$(lowercase(module_name))"
        func_body = extract_function(cell.source, func_name)

        # Generate wrapper
        struct_name = Symbol("$(module_name)Module")
        return quote
            struct $struct_name <: Module end

            # Original function
            $func_body

            # Type-dispatched wrapper
            function compute(mod::ModuleInstance, ::Type{$struct_name})
                return $(Symbol(func_name))(mod)
            end
        end

    elseif has_function_named("compute", cell.source)
        # Style B: Type-dispatched function
        # User already defined struct and compute properly
        return parse_cell_code(cell.source)

    else
        error("Module $(module_name) must define either compute_$(lowercase(module_name)) or compute")
    end
end
```

## Decision

**Use Option 1 (Named Functions) for v0.2**:

Reasons:
1. **Simpler for users** - Just name your function `compute_modulename`
2. **No magic** - Clear what happens
3. **Easy to implement** - Parser just wraps it
4. **Clear errors** - If you forget the function, error message is clear

**Can add Option 2 (Multiple Dispatch) later** if users want more idiomatic Julia.

## Updated Documentation

Need to update:
- `PACKAGE_DEFINITIONS_V2.md` - Change examples to use named functions
- `DESIGN_VALIDATION.md` - Update examples

**Examples become**:

```julia
#| module: HTTPFile

function compute_httpfile(mod::ModuleInstance)
    # Implementation
end
```

Much clearer and no name clashes!
