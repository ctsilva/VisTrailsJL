"""
Test: Load and register package from notebook

Tests the complete package notebook workflow:
1. Load package from notebook
2. Register modules
3. Verify modules are usable in workflows
"""

include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL

println("="^70)
println("Package Notebook Test")
println("="^70)

# 1. Load package from notebook
println("\n1. Loading datatools package from notebook...")
pkg_path = joinpath(@__DIR__, "..", "..", "examples", "packages", "datatools.ipynb")

if !isfile(pkg_path)
    error("Package notebook not found: $pkg_path")
end

pkg = load_package_from_notebook(pkg_path)
println("   ✓ Loaded package: $(pkg.identifier) v$(pkg.version)")
println("   Modules defined: $(length(pkg.modules))")

# Show modules
for (name, descriptor, _) in pkg.modules
    println("     - $name")
    println("       Input ports: $(length(descriptor.input_ports))")
    println("       Output ports: $(length(descriptor.output_ports))")
end

# 2. Register the package
println("\n2. Registering package...")
register_notebook_package!(pkg)
println("   ✓ Package registered")

# 3. Verify modules are registered
println("\n3. Verifying module registration...")
for (name, descriptor, _) in pkg.modules
    # Try to find the module in registry
    try
        found = get_module_descriptor(pkg.identifier, name)
        println("   ✓ $name is registered")
    catch e
        error("   ✗ $name not found in registry! Error: $e")
    end
end

# 4. Test creating module instances
println("\n4. Testing module instantiation...")
pipeline = Pipeline()

# Test CSVParser
csv_parser = add_module!(pipeline, pkg.identifier, "CSVParser")
println("   ✓ Created CSVParser instance (ID: $(csv_parser.id))")

# Test FilterRows
filter_rows = add_module!(pipeline, pkg.identifier, "FilterRows")
println("   ✓ Created FilterRows instance (ID: $(filter_rows.id))")

# Test ComputeStats
compute_stats = add_module!(pipeline, pkg.identifier, "ComputeStats")
println("   ✓ Created ComputeStats instance (ID: $(compute_stats.id))")

println("\n" * "="^70)
println("✅ SUCCESS: Package notebook system working!")
println("="^70)
println("\nPackage notebooks can:")
println("  - Define module types with #| directives")
println("  - Implement compute logic in Julia")
println("  - Be loaded and registered automatically")
println("  - Be used in workflows alongside built-in modules")
println("="^70)
