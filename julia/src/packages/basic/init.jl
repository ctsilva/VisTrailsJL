"""
Basic Package Initialization

Registers all basic modules (HTTPFile, File, String, etc.)
"""

include("HTTPFile.jl")
include("PythonSource.jl")
include("constants.jl")
include("datastructures.jl")
include("io.jl")

"""
    initialize_basic_package!()

Register all modules in the basic package.
"""
function initialize_basic_package!()
    println("Initializing basic package...")

    register_httpfile!()
    register_pythonsource!()
    register_constants!()
    register_datastructures!()
    register_io!()

    println("  ✓ Basic package initialized")
end
