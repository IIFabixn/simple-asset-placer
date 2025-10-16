# Undo/Redo Scenario Checklist

> Last updated: 2025-10-16

Use this checklist during WF-202 (Undo/redo completeness audit) and any future regression passes. Each scenario records the workflow, expected editor history entries, and current status. Update the **Status** column whenever you run the scenario, and add notes if behaviour deviates from the expected result.

| Scenario ID | Workflow | Expected History Entries | Status | Notes |
|-------------|----------|---------------------------|--------|-------|
| U-001 | Single-node placement (click mesh, confirm) then `Ctrl+Z` | `Place <NodeName>` undo removes node, redo restores | ✓ 2025-10-16 | Baseline behaviour verified during placement loop smoke test. |
| U-002 | Continuous placement with auto-select on, place twice, undo twice, redo twice | Two `Place <NodeName>` entries, stack unwinds in order, selection persists | TODO – queue for next placement loop QA pass | Pending scripted coverage once CLI run is available. |
| U-003 | Single-node transform (TAB → G drag → LMB) then `Ctrl+Z`/`Ctrl+Shift+Z` | `Transform <NodeName>` reverts/apply transform without hierarchy changes | ✓ 2025-10-16 | Manual confirmation after routing undo registrations through `UndoRedoHelper`. |
| U-004 | **Multi-node transform (TAB with 2 nodes selected → G drag → LMB)** then `Ctrl+Z` followed by `Ctrl+Shift+Z` | `Transform 2 objects` entry repositions both nodes; undo/redo no longer removes instances | ✓ 2025-10-16 | Previously reproduced deletion bug; fixed by `_register_transform_undo` ensuring multi-node history. |
| U-005 | Transform with numeric override (TAB → G start drag → type value → Enter → LMB → undo/redo) | Numeric entry still produces `Transform <NodeName>` and round-trips to numeric position | TODO – blocked by numeric harness | Awaiting numeric coverage after planned test harness updates. |
| U-006 | Placement cancel (start placement, press ESC) | No history entry added | TODO – capture during next manual run | Confirm behaviour after overlay usability pass. |
| U-007 | Transform cancel (TAB → G drag → ESC) | No history entry, nodes revert immediately | TODO – capture during next manual run | Verify once keyboard automation is in place. |

## Reproduction Steps (U-004 – Multi-node Transform)

1. Select two `Node3D` instances in the scene tree.
2. Press `TAB` to enter transform mode.
3. Press `G` and drag the mouse to reposition the selection.
4. Left-click to confirm the transform.
5. Press `Ctrl+Z` to undo. Both nodes should snap back to their original positions and remain in the scene tree.
6. Press `Ctrl+Shift+Z` to redo. The nodes should return to the dragged location.
7. Open Godot's History panel and confirm a single entry labelled `Transform 2 objects` appears for the operation.

Add additional scenarios as issues are discovered or tickets are resolved. Prefer referencing ticket IDs in the **Notes** column for traceability.

## Pending Work Summary

- U-002 – cover continuous placement/auto-select once the scripted placement loop harness lands.
- U-005 – blocked until numeric input regression harness is ready (tracked under WF-202).
- U-006/U-007 – schedule manual cancel-path verification during the upcoming full smoke pass.
