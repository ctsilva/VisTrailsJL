"""
Test that routes load successfully
"""

println("Testing route loading...")

# Get absolute path to routes file
routes_file = joinpath(@__DIR__, "../../backend/routes.jl")
println("Loading routes from: $routes_file")

# Include routes
include(routes_file)

println("✅ Routes loaded successfully!")
println("   - Read-only routes (Genie.jl)")
println("   - Workflow editing routes (integrated)")
