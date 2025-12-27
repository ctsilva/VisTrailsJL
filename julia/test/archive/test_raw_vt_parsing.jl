"""
Test parsing .vt files at the XML level without ANY package knowledge

This shows that .vt files are self-describing XML that can be parsed
without knowing anything about the module implementations.
"""

using Pkg
Pkg.activate(@__DIR__)

using EzXML
using ZipFile

println("=" ^ 60)
println("Raw .vt XML Parsing (Zero Package Knowledge)")
println("=" ^ 60)

vt_file = joinpath(@__DIR__, "..", "examples", "gcd.vt")

println("\nStep 1: Extract XML from .vt ZIP archive...")

# .vt files are ZIP archives containing XML
xml_content = open(vt_file, "r") do io
    archive = ZipFile.Reader(io)

    for file in archive.files
        if endswith(file.name, ".xml") || file.name == "vistrail"
            return read(file, String)
        end
    end
end

println("✓ Extracted $(length(xml_content)) bytes of XML")

println("\nStep 2: Parse XML structure...")

doc = parsexml(xml_content)
root = doc.root

println("✓ Root element: <$(root.name)>")

# Helper function to get attributes
function attrs_dict(node)
    Dict(attr.name => attr.content for attr in EzXML.attributes(node))
end

println("\n" * "=" ^ 60)
println("Version History (from <action> elements)")
println("=" ^ 60)

actions = findall("//action", root)
println("Total versions: ", length(actions))

# Parse first few actions to show structure
println("\nFirst 5 actions:")
for action in actions[1:min(5, length(actions))]
    attrs = attrs_dict(action)
    id = attrs["id"]
    date = get(attrs, "date", "unknown")
    user = get(attrs, "user", "unknown")

    # Count operations
    adds = findall(".//add", action)
    deletes = findall(".//delete", action)
    changes = findall(".//change", action)

    println("\n  Version $id:")
    println("    Date: $date")
    println("    User: $user")
    println("    Operations: $(length(adds)) adds, $(length(deletes)) deletes, $(length(changes)) changes")

    # Show what was added
    if !isempty(adds)
        println("    Added:")
        for add in adds[1:min(3, length(adds))]
            what = add["what"]
            println("      - $what")
        end
    end
end

println("\n" * "=" ^ 60)
println("Workflow Snapshot (from <workflow> element)")
println("=" ^ 60)

workflow = findfirst("//workflow", root)
if workflow !== nothing
    modules = findall(".//module", workflow)
    connections = findall(".//connection", workflow)

    println("Modules: ", length(modules))
    println("Connections: ", length(connections))

    println("\nModule details (first 5):")
    for mod in modules[1:min(5, length(modules))]
        attrs = attrs_dict(mod)
        id = attrs["id"]
        name = attrs["name"]
        package = get(attrs, "package", "unknown")

        println("\n  Module $id:")
        println("    Name: $name")
        println("    Package: $package")

        # Check for functions (parameters)
        functions = findall(".//function", mod)
        if !isempty(functions)
            println("    Functions:")
            for func in functions
                fname = func["name"]
                params = findall(".//parameter", func)
                println("      - $fname ($(length(params)) parameters)")

                for param in params[1:min(2, length(params))]
                    pattrs = attrs_dict(param)
                    ptype = get(pattrs, "type", "")
                    pval = get(pattrs, "val", "")
                    println("        * $ptype = $pval")
                end
            end
        end
    end

    println("\nConnections (first 5):")
    for conn in connections[1:min(5, length(connections))]
        ports = findall(".//port", conn)

        if length(ports) >= 2
            src_attrs = attrs_dict(ports[1])
            dst_attrs = attrs_dict(ports[2])

            src_mod = src_attrs["moduleName"]
            src_port = src_attrs["name"]
            dst_mod = dst_attrs["moduleName"]
            dst_port = dst_attrs["name"]

            println("  $src_mod:$src_port -> $dst_mod:$dst_port")
        end
    end
end

println("\n" * "=" ^ 60)
println("Summary")
println("=" ^ 60)

println("""
Key Points:
1. .vt files are ZIP archives containing XML
2. XML structure is self-describing with:
   - <action> elements tracking version history
   - <module> elements with package, name, functions, parameters
   - <connection> elements with source/dest ports
   - <workflow> element as a snapshot

3. NO package implementation needed for parsing!
   - Package names are just strings in XML
   - Module types are just names
   - Parameters are stored as type + value strings

4. To EXECUTE workflows, you need implementations
   - But to READ, ANALYZE, DIFF, or CONVERT, you don't!

✓ Parsed complete .vt file with zero package knowledge
""")
