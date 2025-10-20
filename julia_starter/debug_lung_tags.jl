"""
Debug lung.vt tag structure
"""

using Pkg
Pkg.activate(@__DIR__)

using EzXML
using ZipFile

vt_file = joinpath(@__DIR__, "..", "examples", "lung.vt")
println("Opening $vt_file...")

# Read ZIP
reader = ZipFile.Reader(vt_file)
global xml_content = nothing

for file in reader.files
    if file.name == "vistrail" || file.name == "vistrail.xml"
        global xml_content = read(file, String)
        break
    elseif endswith(file.name, ".xml")
        global xml_content = read(file, String)
    end
end

close(reader)

if xml_content === nothing
    println("❌ No XML found!")
    exit(1)
end

# Parse XML
root = parsexml(xml_content).root

println("\nSearching for tag elements...")
tag_elems = findall("//tag", root)
println("Found ", length(tag_elems), " tag elements")

if !isempty(tag_elems)
    println("\nTag element attributes:")
    for (i, tag_elem) in enumerate(tag_elems[1:min(5, length(tag_elems))])
        println("\nTag $i:")
        println("  Element name: ", tag_elem.name)

        # Get all attributes
        attrs = Dict{String, String}()
        for attr in attributes(tag_elem)
            attrs[attr.name] = attr.content
            println("    $(attr.name) = \"$(attr.content)\"")
        end

        # Check for common attribute names
        println("  Has 'value': ", haskey(attrs, "value"))
        println("  Has 'id': ", haskey(attrs, "id"))
        println("  Has 'version': ", haskey(attrs, "version"))
        println("  Has 'versionId': ", haskey(attrs, "versionId"))
        println("  Has 'actionId': ", haskey(attrs, "actionId"))
    end
end
