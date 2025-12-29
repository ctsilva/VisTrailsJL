"""
Test Workflow Editing Operations

Tests the core workflow editing functionality without HTTP layer.
"""

include("../../backend/workflow_editing.jl")

println("\n" * "="^70)
println("Testing Workflow Editing Operations")
println("="^70)

# ============================================================================
# Test 1: Create New Workflow
# ============================================================================

println("\n1. Testing workflow creation")
println("-"^70)

session = create_new_workflow("test_workflow", "Test Workflow")
println("✓ Created workflow session: ", session.workflow_id)
@assert session.workflow_id == "test_workflow"
@assert session.vistrail.name == "Test Workflow"
@assert !session.modified
println("✓ Initial state correct")

# ============================================================================
# Test 2: Add Modules
# ============================================================================

println("\n2. Testing module addition")
println("-"^70)

# Add an Integer module
mod1_id, mod1 = add_module!(session, "basic:Integer", (100.0, 100.0),
                           Dict("value" => 42))
println("✓ Added Integer module: ID = $mod1_id")
@assert mod1_id == 1
@assert mod1.descriptor.name == "Integer"
@assert mod1.parameters["value"] == 42
@assert mod1.layout_position == (100.0, 100.0)
@assert session.modified == true

# Add another Integer module
mod2_id, mod2 = add_module!(session, "basic:Integer", (300.0, 100.0),
                           Dict("value" => 10))
println("✓ Added second Integer module: ID = $mod2_id")
@assert mod2_id == 2

# Add a PythonCalc module
mod3_id, mod3 = add_module!(session, "pythoncalc:PythonCalc", (200.0, 200.0),
                           Dict("op" => "+"))
println("✓ Added PythonCalc module: ID = $mod3_id")
@assert mod3_id == 3
@assert mod3.descriptor.name == "PythonCalc"

println("✓ All modules added successfully")

# ============================================================================
# Test 3: Update Module Position
# ============================================================================

println("\n3. Testing module position update")
println("-"^70)

update_module_position!(session, mod1_id, (150.0, 120.0))
updated_mod = session.current_pipeline.modules[mod1_id]
@assert updated_mod.layout_position == (150.0, 120.0)
println("✓ Module position updated")

# ============================================================================
# Test 4: Update Module Parameters
# ============================================================================

println("\n4. Testing module parameter update")
println("-"^70)

update_module_parameters!(session, mod1_id, Dict("value" => 100))
updated_mod = session.current_pipeline.modules[mod1_id]
@assert updated_mod.parameters["value"] == 100
println("✓ Module parameters updated")

# ============================================================================
# Test 5: Add Connections
# ============================================================================

println("\n5. Testing connection addition")
println("-"^70)

# Connect Integer (mod1) to PythonCalc (mod3)
conn1_id, conn1 = add_connection!(session, mod1_id, "value", mod3_id, "value1")
println("✓ Added connection: $mod1_id.value → $mod3_id.value1 (ID=$conn1_id)")
@assert conn1_id == 1
@assert conn1.source_module_id == mod1_id
@assert conn1.dest_module_id == mod3_id

# Connect second Integer to PythonCalc
conn2_id, conn2 = add_connection!(session, mod2_id, "value", mod3_id, "value2")
println("✓ Added connection: $mod2_id.value → $mod3_id.value2 (ID=$conn2_id)")
@assert conn2_id == 2

@assert length(session.current_pipeline.connections) == 2
println("✓ All connections added successfully")

# ============================================================================
# Test 6: Type Validation
# ============================================================================

println("\n6. Testing type validation")
println("-"^70)

# Try to connect Integer to String output port (should fail - wrong port type)
try
    # First add a String module
    mod4_id, mod4 = add_module!(session, "basic:String", (400.0, 100.0),
                               Dict("value" => "hello"))

    # Try invalid connection - String only has output port "value", not input port
    add_connection!(session, mod1_id, "value", mod4_id, "value")
    println("❌ Should have failed - connected to output port!")
    @assert false
catch e
    error_msg = string(e)
    if occursin("Port 'value' not found in input ports", error_msg)
        println("✓ Port validation working: String module has no input port 'value'")
    elseif occursin("Type mismatch", error_msg)
        println("✓ Type validation working: ", error_msg)
    else
        println("❌ Unexpected error: ", error_msg)
        rethrow(e)
    end
end

# ============================================================================
# Test 7: Delete Connection
# ============================================================================

println("\n7. Testing connection deletion")
println("-"^70)

delete_connection!(session, conn1_id)
@assert length(session.current_pipeline.connections) == 1
println("✓ Connection deleted")

# ============================================================================
# Test 8: Delete Module
# ============================================================================

println("\n8. Testing module deletion")
println("-"^70)

# Delete module 2 (should also remove its connection)
removed_conns = delete_module!(session, mod2_id)
println("✓ Deleted module $mod2_id")
println("  Removed connections: ", removed_conns)
@assert length(removed_conns) == 1  # conn2 should be removed
@assert !haskey(session.current_pipeline.modules, mod2_id)
@assert length(session.current_pipeline.connections) == 0
println("✓ Module and connections removed")

# ============================================================================
# Test 9: Workflow State
# ============================================================================

println("\n9. Testing workflow state")
println("-"^70)

state = get_workflow_state(session)
println("Workflow state:")
println("  ID: ", state["workflow_id"])
println("  Modified: ", state["modified"])
println("  Modules: ", state["module_count"])
println("  Connections: ", state["connection_count"])

@assert state["workflow_id"] == "test_workflow"
@assert state["modified"] == true
@assert state["module_count"] == 3  # mod1, mod3, mod4
@assert state["connection_count"] == 0
println("✓ Workflow state correct")

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^70)
println("✅ All workflow editing tests passed!")
println("="^70)
println("\nTested operations:")
println("  ✓ Create workflow")
println("  ✓ Add modules")
println("  ✓ Update module position")
println("  ✓ Update module parameters")
println("  ✓ Add connections")
println("  ✓ Type validation")
println("  ✓ Delete connection")
println("  ✓ Delete module")
println("  ✓ Get workflow state")
println("\nWorkflow editing backend is ready for HTTP API integration!")
println("="^70)
