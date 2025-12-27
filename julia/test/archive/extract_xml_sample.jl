using Pkg
Pkg.activate(@__DIR__)
using ZipFile

r = ZipFile.Reader(joinpath(@__DIR__, "..", "examples", "mta-yankees.vt"))
xml = read(r.files[findfirst(f->f.name=="vistrail", r.files)], String)
close(r)

# Save first 50KB to inspect
open("mta_sample.xml", "w") do f
    write(f, xml[1:min(50000, length(xml))])
end

println("Saved sample to mta_sample.xml")
