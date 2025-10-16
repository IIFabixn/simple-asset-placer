# Command Pipeline Smoke Test

> Last updated: 2025-10-17

This checklist documents the manual/visual regression pass required after major changes to the command pipeline (placement + transform). Use it before tagging a release or merging a feature branch that touches input handling, modal state, or mode handlers.

---

## 1. Environment & Tooling

- Godot 4.5.1 (Mono) – use the CLI build configured in `scripts/run_gut_tests.ps1`.
- Simple Asset Placer plugin installed and enabled in the editor.
- Sample scenes available under `sample/` for controlled scenarios.
- Ensure the project opens with the default input map and settings reset (optional but recommended):
  1. `Project > Tools > Simple Asset Placer > Placement Settings > Reset All Settings to Defaults`.
  2. Restart the editor to confirm state.

### 1.1 Automated Sanity Checks

Run the headless test suite first. Any failure blocks the remainder of the checklist.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_gut_tests.ps1
```

Record the summary (scripts, tests, assertions) in the session log below.

---

## 2. Manual Smoke Checklist

Mark each task with `[x]` when completed. Capture short clips (5–10s) where noted and deposit them under `docs/testing/assets/` using the naming convention `YYYY-MM-DD_<test-id>.gif`.

| ID | Area | Steps | Expected | Media |
|----|------|-------|----------|-------|
| CP-01 | Placement – default | Scene: `sample/building_a.tscn`. Activate placement via dock, left-click place asset, `ESC` to exit. | Overlay shows Placement mode, placement occurs at cursor, `ESC` exits without lingering overlay. | optional |
| CP-02 | Placement – modal axis | While placing, press `G` then `X`, drag to constrain, confirm with left-click. | Object slides along world X only, axis badge updates, confirm finalises placement. | optional |
| CP-03 | Placement – numeric override | In placement, press `R`, type `=90`, hit `ENTER`, confirm placement. | Preview rotates exactly 90° before placement; numeric UI flashes and clears after confirm. | optional |
| CP-04 | Transform – group move | Select two nodes in `sample/building_b.tscn`, press `TAB`, drag mouse with `G` active, confirm with `ENTER`. | Both nodes translate together, overlay lists Transform mode, confirm exits mode. | recommended |
| CP-05 | Transform – axis snap reset | In transform, press `R`, tap `X`, rotate, then tap `Y`; verify snap resets for new axis. | Rotation accumulators reset when switching axis, preventing carry-over jitter. | optional |
| CP-06 | Transform – numeric confirm | In transform, press `L`, type `+0.5`, hit `ENTER`. | Scale applies uniformly, numeric confirm exits if `ENTER` pressed again. | optional |
| CP-07 | Undo/Redo | After CP-04 or CP-06, issue `CTRL+Z` then `CTRL+SHIFT+Z`. | Transform reverts and reapplies without desync. | optional |
| CP-08 | Modal exit pathways | With modal active, right-click once, then press `ESC` on a second attempt. | First action drops modal, second exits mode; overlay updates accordingly. | recommended |
| CP-09 | Overlay accuracy | Toggle `auto_modal_activation` in settings, enter both modes, observe overlay. | Overlay reflects modal status only when active; setting persists after restart. | screenshot |
| CP-10 | Placement loop options | Disable continuous placement, place an asset, then re-enable and repeat. | Single-placement mode exits immediately and auto-selects when enabled; continuous mode keeps preview active until ESC. | recommended |
| CP-11 | Cursor warp toggle | In transform mode, ensure cursor warp is enabled, push the cursor toward each viewport edge, then disable the setting and repeat. | With the toggle on, the pointer recenters inside the same viewport instead of jumping across monitors; with it off, the cursor never warps. | optional |
| CP-12 | Wheel increments | In placement mode, scroll the mouse wheel without modifiers, then with CTRL, ALT, and SHIFT held; repeat in transform modal with axis constraint active. | Step size follows default/fine/large values, SHIFT reverses direction, and overlay modifier badges reflect held modifiers. | optional |
| CP-13 | Overlay wheel hints | With placement and transform overlays visible, hold CTRL, ALT, and SHIFT individually while scrolling once. | Keybind line shows the correct modifier labels and stays legible; badges toggle on/off with each modifier. | optional |
| CP-14 | UI focus guard | With placement or transform active, click any numeric SpinBox or LineEdit in the dock, type a value, pause, clear it, and continue typing. | The field keeps keyboard focus the entire time, no unexpected mode exit or viewport focus grab occurs. | optional |

> **Tip:** Use the built-in `Editor > Viewport > Capture to GIF` shortcut or an external tool (ScreenToGif, ShareX) for recordings.

---

## 3. Session Log Template

Append one block per run.

```
## YYYY-MM-DD – Tester Name
- Automated: scripts/run_gut_tests.ps1 (pass/fail, notes)
- Manual Summary: CP-01 ✅, CP-02 ✅, ...
- Media: [list filenames placed in docs/testing/assets/]
- Findings: [new issues or regressions]
- Follow-up Tasks: [links to issues/PRs]
```

### Recorded Sessions

```
## 2025-10-16 – Internal QA Dry Run
- Automated: scripts/run_gut_tests.ps1 (not run – Godot headless CLI unavailable in current workspace)
- Manual Summary: Checklist pending first capture session.
- Media: none yet (prepare baseline GIFs before closing QA-001).
- Findings: n/a
- Follow-up Tasks: Schedule full smoke pass once editor access is available; capture CP-04, CP-08 recordings.
```

---

## 4. Outstanding Improvements

- Automate viewport capture for critical flows.
- Integrate report uploads with project issue tracker.
- Add timed reminders post-merge to re-run the suite.
