"""
Machine Information

Stores information about the machine where a workflow was executed.
Similar to Python VisTrails' core/log/machine.py
"""

using Dates

"""
    Machine

Information about the machine where workflow execution occurred.
"""
mutable struct Machine
    id::Int
    name::String          # Hostname
    os::String           # Operating system name
    architecture::String # CPU architecture (e.g., "x86_64", "arm64")
    processor::String    # Processor type
    ram::Int            # RAM in MB

    function Machine(;
        id::Int=-1,
        name::String=gethostname(),
        os::String=String(Sys.KERNEL),
        architecture::String=String(Sys.ARCH),
        processor::String=String(Sys.CPU_NAME),
        ram::Int=round(Int, Sys.total_memory() / (1024 * 1024))
    )
        new(id, name, os, architecture, processor, ram)
    end
end

"""
    current_machine(id::Int=1) -> Machine

Get information about the current machine.
"""
function current_machine(id::Int=1)
    return Machine(id=id)
end
