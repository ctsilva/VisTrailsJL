"""
Debug tag parsing
"""

using Pkg
Pkg.activate(@__DIR__)

using EzXML
using ZipFile

vt_file = joinpath(@__DIR__, "..", "examples", "mta-yankees.vt")
println("Opening $vt_file...")

# Read ZIP
reader = ZipFile.Reader(vt_file)
global xml_content = nothing

for file in reader.files
    println("  Found file in ZIP: ", file.name)
    if file.name == "vistrail" || file.name == "vistrail.xml"
        global xml_content = read(file, String)
        break
    elseif endswith(file.name, ".xml")
        global xml_content = read(file, String)
    end
end

close(reader)

if xml_content === nothing
    println("❌ No XML found in ZIP!")
    exit(1)
end

println("\n✓ Loaded XML (", length(xml_content), " bytes)")

# Parse XML
root = parsexml(xml_content).root

println("\nSearching for tags...")
tag_elems = findall("//tag", root)
println("Found ", length(tag_elems), " tag elements")

if !isempty(tag_elems)
    println("\nTag details:")
    for (i, tag_elem) in enumerate(tag_elems)
        attrs = Dict{String, String}()
        for attr in attributes(tag_elem)
            attrs[attr.name] = attr.content
        end
        println("  Tag $i:")
        println("    name: ", get(attrs, "name", "MISSING"))
        println("    value: ", get(attrs, "value", "MISSING"))
        println("    All attrs: ", keys(attrs))
    end
end
