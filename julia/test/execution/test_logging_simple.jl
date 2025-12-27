"""
Simple test of execution logging functionality
"""

# Load VisTrailsJL module
include(joinpath(@__DIR__, "..", "..", "src", "VisTrailsJL.jl"))
using .VisTrailsJL
using Dates

println("=" ^ 60)
println("Testing Execution Logging Data Structures")
println("=" ^ 60)

# Test Machine
println("\n1. Creating Machine info...")
machine = VisTrailsJL.current_machine(1)
println("   ✓ Machine: $(machine.name)")
println("     OS: $(machine.os)")
println("     Architecture: $(machine.architecture)")
println("     RAM: $(machine.ram) MB")

# Test WorkflowExec
println("\n2. Creating Workflow Execution...")
wf_exec = VisTrailsJL.WorkflowExec(
    parent_version=5,
    name="Test Workflow"
)
push!(wf_exec.machines, machine)
println("   ✓ WorkflowExec created")
println("     User: $(wf_exec.user)")
println("     IP: $(wf_exec.ip)")
println("     Start: $(wf_exec.ts_start)")

# Test ModuleExec
println("\n3. Simulating module executions...")

# Module 1 - successful
mod_exec1 = VisTrailsJL.ModuleExec(
    module_id=1,
    module_name="ReadFile",
    machine_id=machine.id
)
sleep(0.05)  # Simulate work
VisTrailsJL.mark_completed!(mod_exec1)
VisTrailsJL.add_module_exec!(wf_exec, mod_exec1)
println("   ✓ Module 1 (ReadFile) - completed")

# Module 2 - cached
mod_exec2 = VisTrailsJL.ModuleExec(
    module_id=2,
    module_name="ProcessData",
    machine_id=machine.id
)
VisTrailsJL.mark_cached!(mod_exec2)
VisTrailsJL.add_module_exec!(wf_exec, mod_exec2)
println("   ✓ Module 2 (ProcessData) - cached")

# Module 3 - failed
mod_exec3 = VisTrailsJL.ModuleExec(
    module_id=3,
    module_name="WriteFile",
    machine_id=machine.id
)
sleep(0.03)  # Simulate work
VisTrailsJL.mark_failed!(mod_exec3, "Permission denied")
VisTrailsJL.add_module_exec!(wf_exec, mod_exec3)
println("   ✓ Module 3 (WriteFile) - failed")

# Complete workflow
sleep(0.01)
VisTrailsJL.mark_completed!(wf_exec)

println("\n" * "=" ^ 60)
println("Execution Log Summary")
println("=" ^ 60)

println("\nWorkflow Execution:")
println("  ID: ", wf_exec.id)
println("  User: ", wf_exec.user)
println("  Version: ", wf_exec.parent_version)
println("  Name: ", wf_exec.name)
println("  Start: ", wf_exec.ts_start)
println("  End: ", wf_exec.ts_end)
println("  Status: ", wf_exec.completed == 1 ? "✓ Success" : "✗ Failed")

dur = VisTrailsJL.duration(wf_exec)
if dur !== nothing
    println("  Duration: ", Dates.value(dur), "ms")
end

println("\nMachines:")
for machine in wf_exec.machines
    println("  - $(machine.name) ($(machine.os) $(machine.architecture))")
    println("    RAM: $(machine.ram) MB")
end

println("\nModule Executions:")
for mod_exec in wf_exec.module_execs
    status = mod_exec.completed == 1 ? "✓" : (mod_exec.completed == -1 ? "✗" : "?")
    cached = mod_exec.cached ? " [CACHED]" : ""
    dur = VisTrailsJL.duration(mod_exec)
    dur_str = dur !== nothing ? " ($(Dates.value(dur))ms)" : ""

    println("  $status Module $(mod_exec.module_id): $(mod_exec.module_name)$cached$dur_str")

    if mod_exec.completed == -1
        println("      Error: $(mod_exec.error)")
    end
end

# Statistics
println("\nStatistics:")
println("  Total modules: $(length(wf_exec.module_execs))")
println("  Cached: $(length(VisTrailsJL.cached_modules(wf_exec)))")
println("  Failed: $(length(VisTrailsJL.failed_modules(wf_exec)))")

# Test Log container
println("\n" * "=" ^ 60)
println("Testing Log Container")
println("=" ^ 60)

log = VisTrailsJL.Log(vistrail_id="test_vistrail")
VisTrailsJL.add_workflow_exec!(log, wf_exec)

println("\nLog Summary:")
println("  Vistrail ID: $(log.vistrail_id)")
println("  Total executions: $(length(log.workflow_execs))")

VisTrailsJL.print_summary(log)

println("\n" * "=" ^ 60)
println("✓ All logging tests passed!")
println("=" ^ 60)
