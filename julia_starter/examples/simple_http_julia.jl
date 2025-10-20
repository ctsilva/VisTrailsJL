"""
Simple Example: HTTP Fetch + Julia Processing

This demonstrates:
1. Fetching data from a URL (HTTPFile)
2. Processing it with Julia code (JuliaSource)
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using VisTrailsJL

println("=" ^ 60)
println("Example: HTTP Fetch + Julia Processing")
println("=" ^ 60)

# Create a new pipeline
pipeline = Pipeline()

# Add HTTPFile module to fetch JSON data
println("\nAdding HTTPFile module...")
http_mod = add_module!(pipeline, "org.vistrails.vistrails.basic", "HTTPFile")
set_parameter!(http_mod, "url", "https://api.github.com/repos/JuliaLang/julia")

# Add JuliaSource module to process the data
println("Adding JuliaSource module...")
julia_mod = add_module!(pipeline, "org.vistrails.vistrails.julia", "JuliaSource")
set_parameter!(julia_mod, "source", """
    using JSON

    # Get the fetched JSON
    json_str = get_input("file")

    # Parse it
    data = JSON.parse(json_str)

    # Extract interesting info
    result = Dict(
        "name" => data["name"],
        "description" => data["description"],
        "stars" => data["stargazers_count"],
        "language" => data["language"],
        "forks" => data["forks_count"]
    )

    # Output
    set_output("info", result)

    # Also return as main output
    result
""")

# Connect HTTPFile output to JuliaSource input
println("Connecting modules...")
add_connection!(pipeline, http_mod, "file", julia_mod, "file")

# Execute the pipeline
println("\n" * "=" ^ 60)
println("Executing Pipeline")
println("=" ^ 60)

results = execute_pipeline(pipeline)

# Display results
println("\n" ^ 60)
println("Results")
println("=" ^ 60)

julia_results = results[julia_mod.id]
info = julia_results["info"]

println("\nJulia Repository Information:")
println("  Name: ", info["name"])
println("  Description: ", info["description"])
println("  Language: ", info["language"])
println("  Stars: ", info["stars"])
println("  Forks: ", info["forks"])

println("\n✓ Example complete!")
