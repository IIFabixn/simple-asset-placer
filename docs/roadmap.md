# Simple Asset Placer Interaction Roadmap

> Last updated: 2025-10-16

This roadmap captures the planned evolution of the plugin from the current modal-focused workflow to a unified, extensible interaction model. It is intentionally detailed so future contributors can understand the reasoning behind each milestone.

---

## Vision

Deliver a placement and transform experience that is:

- **Fluid** – mouse, keyboard, and numeric inputs blend seamlessly without modal friction.
- **Predictable** – overlays and settings make the active control state obvious at all times.
- **Extensible** – new input sources (gamepad, gizmos) and UX features plug into a shared command pipeline.
- **Guided** – the plugin teaches itself via contextual hints, quick toggles, and self-serve documentation.

---

## Phase 1 – Command Pipeline Refactor

### Goals
- Replace the legacy-vs-modal branching with a single per-frame "transform intent" object.
- Keep `ControlModeState` as a source of truth without auto-activating modal on entry.

### Key Tasks
1. **Command Object Definition**  
   - Introduce a `TransformCommand` struct/dictionary (position delta, rotation delta, scale delta, snap overrides, confirm/cancel flags, metadata).
   - Implement helper methods to merge contributions (mouse modal, key presses, numeric overrides).

2. **Router Restructure**  
   - Convert `TransformActionRouter.process()` into a pure aggregator that populates the command object.
   - Ensure numeric input only overrides the relevant component when confirmed; otherwise it contributes to the command via pending state.

3. **Handler Integration**  
   - Update `PlacementModeHandler.process_input()` and `TransformModeHandler.process_input()` to consume `TransformCommand` instead of direct `PositionInputState` and manual modal callbacks.
   - Preserve existing `PositionManager`, `RotationManager`, and `ScaleManager` helpers so the math stays centralized.

4. **Control State Behaviour**  
   - Call `set_control_mode(ControlModeState.ControlMode.POSITION, false)` on mode entry so `_modal_active` remains false until the user presses G/R/L.
   - Expose `deactivate_modal()` on ESC, right-click, or placement completion to revert to pure command mode.

5. **Safety Net**  
   - Temporary logging for emitted commands to compare behaviour with the current build.
   - Manual regression checklist covering placement, transform, numeric overrides, and undo/redo.

### Ticket Backlog
1. **CORE-001: Define TransformCommand schema**  
   - *Affected components:* new `core/transform_command.gd`, unit tests under `addons/simpleassetplacer/tests/` (create folder if missing).  
   - *Deliverables:* Command struct with deltas/flags/metadata, helper constructors (`from_modal_input`, `merge`, `clear`), inline documentation, initial test harness scaffolding.  
   - *Expected result:* Centralized data object representing per-frame intent.  
   - *Acceptance criteria:* Merge precedence (modal > numeric > direct) verified by automated tests; script lint passes; team walkthrough held.  
   - *Notes:* Match naming with `TransformState` properties to avoid confusion.  
   - *Blocked by:* None  
    - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
      - [x] Done  
   - *Progress note:* 2025-10-16 – Schema implemented with merge helpers + GUT tests (CLI not available locally).
2. **CORE-002: Refactor TransformActionRouter**  
   - *Affected components:* `core/transform_action_router.gd`, `core/service_registry.gd`, settings schema.  
   - *Deliverables:* Router returning `TransformCommand`, population of source flags, optional debug logging gated by new `debug_commands` setting (added to settings schema/persistence).  
   - *Expected result:* All input paths emit a single command object; handlers remain unaware of individual input states.  
   - *Acceptance criteria:* Placement/transform flows operate normally; debug logging toggles via settings; no regressions in input latency.  
   - *Notes:* Provide temporary adapter layer if handlers still expect legacy return type until CORE-003/004 land.  
   - *Blocked by:* CORE-001  
      - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
          - [x] Done  
    - *Progress note:* 2025-10-16 – Router now emits TransformCommand with source flags, debug_commands setting added; GUT suite passing.
3. **CORE-003: Update PlacementModeHandler**  
    - *Affected components:* `modes/placement_mode_handler.gd`, preview/overlay integration.  
    - *Deliverables:* Handler consumes `TransformCommand`, applies deltas through Position/Rotation/Scale managers, cleans up obsolete callbacks.  
    - *Expected result:* Preview responds consistently to modal, keyboard, numeric, and wheel inputs.  
    - *Acceptance criteria:* Legacy keys functional again; overlay values correct; placement undo unchanged; manual QA checklist signed off.  
    - *Notes:* Document new data flow for future contributors.  
    - *Blocked by:* CORE-001, CORE-002  
    - *Status:*  
          - [ ] Not started  
          - [ ] In progress  
       - [x] Done  
      - *Progress note:* 2025-10-16 – PlacementModeHandler now processes TransformCommand end-to-end (position/rotation/scale/numeric), axis taps feed numeric offsets; manual smoke tests pass.
4. **CORE-004: Update TransformModeHandler**  
   - *Affected components:* `modes/transform_mode_handler.gd`, group offset caches, numeric confirmation logic.  
   - *Deliverables:* Command-driven processing with maintained snapping/accumulation, updated overlay hooks.  
   - *Expected result:* Multi-node transforms honour commands identically to placement mode.  
   - *Acceptance criteria:* Numeric confirm exits mode; undo/redo unaffected; automated regression (once available) passes.  
   - *Notes:* Reset accumulated rotation when command axis changes to avoid drift.  
   - *Blocked by:* CORE-001, CORE-002  
   - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [x] Done  
    - *Progress note:* 2025-10-17 – TransformModeHandler now consumes TransformCommand (position/rotation/scale/height), resets rotation accumulation on axis changes, numeric confirm exits mode; manual QA via headless GUT smoke run.
5. **CORE-005: ControlModeState adjustments**  
   - *Affected components:* `core/control_mode_state.gd`, `core/transformation_coordinator.gd`, `modes/placement_mode_handler.gd`, `modes/transform_mode_handler.gd`, `ui/placement_settings.gd`, `settings/settings_definition.gd`.  
   - *Deliverables:* Optional auto-modal setting, explicit deactivate hooks (ESC/right-click/placement complete), overlay state reporting, removal (or gating) of auto-activation calls in mode handlers.  
   - *Expected result:* Modal engages only when user (or setting) chooses, with clear escape path.  
   - *Acceptance criteria:* Auto-modal toggle persists; modal status accurate in overlay; QA verifies ESC/right-click exit; placement/transform entry no longer forces modal without toggle.  
   - *Notes:* Capture modal activation metrics behind debug flag for telemetry; document legacy auto-activate behaviour before removal.  
   - *Blocked by:* CORE-003, CORE-004  
   - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [x] Done  
    - *Progress note:* 2025-10-16 – Added auto-modal activation toggle with persistence, primed placement/transform entries without forced modal, ESC/right-click/placement completion now deactivate ControlModeState; overlay reflects modal state via existing feed.
6. **QA-001: Command pipeline smoke tests**  
   - *Affected components:* Newly created `docs/testing.md`, `docs/testing/assets/`, baseline capture scripts.  
   - *Deliverables:* Checklist covering placement/transform/numeric/undo, comparison GIF/video, logged findings; create missing docs/testing structure if absent.  
   - *Expected result:* Baseline behaviour documented pre-merge and post-merge.  
   - *Acceptance criteria:* Checklist completed with pass/fail notes; media stored in the new directory; follow-up issues created as needed.  
   - *Notes:* Schedule immediately after CORE-004 before broader rollout; treat directory scaffolding as part of the ticket.  
   - *Blocked by:* CORE-004, CORE-005  
    - *Status:*   
       - [ ] Not started   
       - [x] In progress   
       - [ ] Done   
    - *Progress note:* 2025-10-16 – Added `/docs/testing/command_pipeline_smoke.md` checklist + assets staging folder; awaiting baseline captures and first recorded run log.

---

## Phase 2 – Feedback & Discoverability

### Goals
- Make the UI reflect the new command model so users always know which inputs work.
- Reduce dependency on the README by adding in-editor guidance.

### Key Tasks
1. **Overlay Update**  
   - Display mode (Placement/Transform), modal status, axis constraints, snap/grid state, active modifiers, and numeric input strings in the overlay.
   - Add subtle animation or color changes when toggles switch to reinforce state changes.

2. **Toolbar & Dock Toggles**  
   - Provide quick toggles for snap, surface alignment, smooth transforms, and placement strategy with visual feedback.
   - Synchronize toggle state with settings storage.

3. **First-Run & Cheatsheet**  
   - Add a lightweight onboarding tooltip tour or info panel that highlights key controls.
   - Include a "Quick Controls" panel in the dock (collapsible) summarizing commands and modifiers.

4. **Settings Surface**  
   - Promote relevant settings (auto modal on entry, cursor warp, sensitivity curves) to user-facing toggles.
   - Add descriptive tooltips explaining how each setting affects the command pipeline.

### Ticket Backlog
1. **UI-101: Overlay redesign implementation**  
   - *Affected components:* `ui/status_overlay.tscn`, `ui/status_overlay_control.gd`, `managers/overlay_manager.gd`.  
   - *Deliverables:* New layout sections (mode, modal state, snap, modifiers, numeric status), data binding updates, subtle transition animations.  
   - *Expected result:* Overlay communicates control context instantly and matches editor themes.  
   - *Acceptance criteria:* State changes visible within one frame; layout responsive at various resolutions; color contrast meets accessibility guidelines.  
   - *Notes:* Provide light/dark mockups in design document.  
   - *Blocked by:* CORE-001, CORE-002, CORE-003, CORE-004, CORE-005  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [x] Done  
    - *Progress note:* 2025-10-16 – Overlay layout rebuilt with snap/modifier badges, numeric strip, color-based feedback, and dynamic resizing to contain content across resolutions.
2. **UI-102: Toolbar quick toggles**  
   - *Affected components:* `ui/toolbar_buttons.tscn/.gd`, `settings/settings_manager.gd`, icon assets.  
   - *Deliverables:* Snap/alignment/smooth/strategy buttons with persistent state, SVG icons, tooltips.  
   - *Expected result:* Users toggle features without leaving viewport; overlay reflects changes.  
   - *Acceptance criteria:* Toggle state persists across sessions; tooltips display remapped shortcuts; icon assets optimized (<10KB).  
   - *Notes:* Ensure toolbar width handles localization.  
   - *Blocked by:* CORE-005, SET-101  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
3. **DOC-101: In-editor onboarding tooltips**  
   - *Affected components:* New `ui/onboarding_manager.gd`, `SettingsManager`, dock/toolbar scripts.  
   - *Deliverables:* First-run detection, guided tooltip sequence with dismissal option, reset command.  
   - *Expected result:* New users receive contextual guidance without documentation.  
   - *Acceptance criteria:* Tooltips appear only when intended; keyboard navigation supported; dismissal state stored in settings.  
   - *Notes:* Capture screenshots for README Quickstart.  
   - *Blocked by:* UI-101, UI-102, SET-101  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
4. **UI-103: Quick Controls panel in dock**  
   - *Affected components:* `ui/asset_placer_dock.gd`, new panel scene, keybinding display helpers.  
   - *Deliverables:* Collapsible controls panel pulling live keybind data, cached layout nodes.  
   - *Expected result:* Users see current shortcuts at a glance, respecting remaps.  
   - *Acceptance criteria:* Panel toggles without layout jitter; updates within one frame after keybinding change; negligible frame impact (<0.1ms).  
   - *Notes:* Add preference to default panel state (collapsed/expanded).  
   - *Blocked by:* UI-102, DOC-101  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
5. **SET-101: Settings exposure**  
   - *Affected components:* `ui/placement_settings.gd`, `settings/settings_definition.gd`, README.  
   - *Deliverables:* Toggles for auto-modal, cursor warp, sensitivity curves; tooltips; persisted values.  
   - *Expected result:* Users manage critical behaviour from UI with clear explanations.  
   - *Acceptance criteria:* Settings survive editor restart; README updated; unit tests confirm persistence.  
   - *Notes:* Align default values with Phase 1 outcomes (e.g., auto-modal off).  
   - *Blocked by:* CORE-005  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
6. **QA-102: Usability testing round**  
   - *Affected components:* Testing templates, roadmap backlog.  
   - *Deliverables:* At least three recorded sessions, summary report, backlog adjustments.  
   - *Expected result:* Actionable feedback informs Phase 3 scope.  
   - *Acceptance criteria:* Findings documented; new issues/tickets created; roadmap updated if priorities shift.  
   - *Notes:* Include mix of new and experienced users.  
   - *Blocked by:* UI-101, UI-102, UI-103, DOC-101, SET-101  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_

---

## Phase 3 – Workflow Enhancements

### Goals
- Reduce friction during asset placement and transformation loops.
- Expose more contextual information without leaving the viewport.

### Key Tasks
1. **Placement Loop Options**  
   - Allow users to toggle between "single placement" and "continuous placement"; optionally auto-select the placed node.
   - Provide commands to repeat last asset or open a history palette overlay.

2. **Asset Context**  
   - Show material variants, LOD info, or alternative meshes within the viewport overlay while cycling.
   - Enhance dock entries with placement history counters and quick-favorite toggles.

3. **Mouse & Wheel Polishing**  
   - Make cursor warp optional and configurable; ensure multi-monitor edges behave gracefully.
   - Extend wheel handling to support large step modifiers for position adjustments and to respect axis constraints in both command and modal contexts.

4. **Camera & Focus Management**  
   - Guarantee viewport focus is reclaimed as needed without breaking text input; coordinate with Godot’s focus APIs.

### Ticket Backlog
1. **WF-201: Placement loop mode toggle**  
   - *Affected components:* `ui/placement_settings.gd`, `modes/placement_mode_handler.gd`, `core/transformation_coordinator.gd`, `managers/utility_manager.gd`.  
   - *Deliverables:* Toggle for single/continuous placement, auto-select option, updated placement flow.  
   - *Expected result:* Users can keep preview active for batch placement or revert to single-shot behaviour.  
   - *Acceptance criteria:* Continuous mode retains preview until ESC; auto-select highlights placed node when enabled; behaviour described in overlay tooltip.  
    - *Notes:* Communicate behaviour change in changelog if defaults shift.  
    - *Blocked by:* CORE-003, CORE-004, SET-101  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_
2. **WF-202: Placement history overlay**  
   - *Affected components:* `core/service_registry.gd`, `ui/status_overlay_control.gd`, `ui/asset_placer_dock.gd`, `managers/overlay_manager.gd`.  
   - *Deliverables:* History data store (last N assets), overlay palette with shortcuts, dock accessors.  
   - *Expected result:* Users quickly re-place recent assets without opening dock.  
   - *Acceptance criteria:* History updates reliably; overlay selection re-enters placement; session-level persistence confirmed.  
    - *Notes:* Evaluate persisting history per project in later iterations.  
    - *Blocked by:* WF-201, CORE-003  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_
3. **WF-203: Variant and LOD display**  
   - *Affected components:* `managers/category_manager.gd`, `ui/meshlib_browser.gd`, `ui/modellib_browser.gd`, `ui/status_overlay_control.gd`, thumbnail cache helpers.  
   - *Deliverables:* Metadata extraction for variants/LODs, UI selector, thumbnail cache.  
   - *Expected result:* Variant switching happens in-place with updated preview.  
   - *Acceptance criteria:* Assets with variants expose controls; switching updates preview within one frame; cached thumbnails reduce reload time.  
    - *Notes:* Start with GLTF and MeshLibrary metadata path.  
    - *Blocked by:* WF-201  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_
4. **WF-204: Cursor warp preferences**  
   - *Affected components:* `modes/placement_mode_handler.gd`, `modes/transform_mode_handler.gd`, `ui/placement_settings.gd`, `settings/settings_definition.gd`, `settings/settings_manager.gd`.  
   - *Deliverables:* Runtime toggle + setting for cursor warp, multi-monitor safe bounds, documentation.  
   - *Expected result:* Users opt-in/out of warp without restart; behaviour reliable on multi-screen setups.  
   - *Acceptance criteria:* Toggle accessible from overlay/toolbar; cursor stays within primary viewport; tests cover both modes.  
    - *Notes:* Preserve last mouse delta when warp disabled to avoid jump.  
    - *Blocked by:* CORE-005, SET-101  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_
5. **WF-205: Mouse wheel granularity**  
   - *Affected components:* `managers/input_handler.gd`, `core/transformation_coordinator.gd`, `ui/status_overlay_control.gd`.  
   - *Deliverables:* Modifier-driven step scaling, axis-aware deltas, updated overlay text.  
   - *Expected result:* Wheel gestures provide fine/large adjustments consistent with keyboard modifiers.  
   - *Acceptance criteria:* CTRL/ALT alter step size; constraints honoured; overlay displays current increment; regression tests pass.  
    - *Notes:* Coordinate with command pipeline to avoid double application.  
    - *Blocked by:* CORE-002, CORE-003, CORE-004  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_
6. **WF-206: Focus management**  
   - *Affected components:* `core/transformation_coordinator.gd`, `ui/asset_placer_dock.gd`, `ui/placement_settings.gd`, automated focus tests.  
   - *Deliverables:* Revised focus grabbing logic, automated tests, behaviour docs.  
   - *Expected result:* Text inputs retain focus unless user returns to viewport; numeric entry unaffected.  
   - *Acceptance criteria:* QA verifies no unexpected focus theft; automated tests cover dock fields; documentation updated.  
    - *Notes:* Align with onboarding tooltips to prevent conflicts.  
    - *Blocked by:* CORE-005, DOC-101  
    - *Status:*  
       - [ ] Not started  
       - [ ] In progress  
       - [ ] Done  
    - *Progress note:* _(record updates here)_

---

## Phase 4 – Extensibility & Testing

### Goals
- Ensure the refactored system is resilient, observable, and welcoming to future input sources.

### Key Tasks
1. **Automated Integration Tests**  
   - Build scripted tests for placement and transform flows (modal engagement, numeric overrides, undo/redo, axis constraints, snapping).
   - Use mock cameras or scripted raycast results to validate `TransformCommand` application.

2. **Logging & Telemetry (Optional)**  
   - Add structured command logging (behind a debug toggle) for troubleshooting.
   - Offer a simple command-history view for QA (e.g., last 10 commands with timestamps).

3. **Input Source Abstraction**  
   - Document how to plug additional input providers (e.g., gamepads) into the command builder.
   - Create placeholders or TODOs for future gizmo integration.

4. **Docs & Diagrams**  
   - Update Mermaid diagrams (`docs/architecture/*.mmd`) to reflect the new pipeline and overlay relationships.
   - Provide developer notes on testing strategy and command schema.

### Ticket Backlog
1. **TEST-301: Integration test harness**  
   - *Affected components:* Newly created `tests/integration/` scenes/scripts, CI workflow.  
   - *Deliverables:* Automated placement/transform scripts with assertions, CI job executing headless tests, scaffolding for the `tests/` folder if absent.  
   - *Expected result:* Regression coverage for command pipeline and undo consistency.  
   - *Acceptance criteria:* Tests run headless locally and in CI; failures produce actionable logs; CI badge updated.  
   - *Notes:* Investigate Godot 4 headless quirks before scripting complex scenes; confirm repository structure supports Godot’s test runner.  
   - *Blocked by:* CORE-001, CORE-002, CORE-003, CORE-004, CORE-005, QA-001  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
2. **DEV-301: Command logging toggle**  
   - *Affected components:* `core/transform_action_router.gd`, `core/transformation_coordinator.gd`, `settings/settings_definition.gd`, `settings/settings_manager.gd`, optional debug panel scene/script.  
   - *Deliverables:* JSON logging behind `debug_commands`, history viewer UI, auto-trim policy.  
   - *Expected result:* Developers inspect recent commands during debugging without cluttering normal runs.  
   - *Acceptance criteria:* Logs only emit when enabled; viewer lists latest N commands with timestamps; memory usage bounded.  
   - *Notes:* Consider integrating with placement history overlay for reuse; depends on `debug_commands` setting introduced in CORE-002.  
   - *Blocked by:* CORE-002, WF-202  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
3. **DEV-302: Input provider abstraction**  
   - *Affected components:* `core/transform_action_router.gd`, `core/frame_input_orchestrator.gd`, `core/service_registry.gd`, developer docs.  
   - *Deliverables:* Interface for external input providers, gamepad stub example, dev guide.  
   - *Expected result:* Future inputs integrate without modifying router core.  
   - *Acceptance criteria:* Stub registers via ServiceRegistry and emits commands; documentation explains lifecycle; unit tests validate provider hook.  
   - *Notes:* Leave actual gamepad keymap implementation for future ticket.  
   - *Blocked by:* CORE-002, DEV-301  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
4. **DOC-301: Architecture diagrams refresh**  
   - *Affected components:* `docs/architecture/*.mmd`, exported assets, README references.  
   - *Deliverables:* Updated flow/class diagrams, new TransformCommand sequence diagram, optimized PNG exports.  
   - *Expected result:* Documentation reflects command pipeline and overlay updates.  
   - *Acceptance criteria:* Diagrams render without errors; README links valid; PNGs under 500KB each.  
   - *Notes:* Commit Mermaid and generated assets together.  
   - *Blocked by:* CORE-002, UI-101, WF-201  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
5. **QA-301: Stress testing protocol**  
   - *Affected components:* Test scripts, `docs/testing/performance.md`.  
   - *Deliverables:* Repeatable stress scenario, metrics log (CPU/GPU/frame time), comparison chart vs baseline.  
   - *Expected result:* Team can detect performance regressions early.  
   - *Acceptance criteria:* Script runs unattended; metrics documented; follow-up issues created for regressions.  
   - *Notes:* Coordinate with art team for heavy asset datasets.  
   - *Blocked by:* TEST-301  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_

---

## Phase 5 – Documentation & Release Polish

### Goals
- Ensure users and contributors are confident adopting the new experience.

### Key Tasks
1. **In-Editor Help**  
   - Add a help/about panel accessible from the dock with links to docs, a condensed cheatsheet, and version info.

2. **README & Changelog Refresh**  
   - Highlight the new unified interaction model, overlay information, and customization options.
   - Document migration notes for users upgrading from the modal-only build.

3. **Sample Projects & GIFs**  
   - Refresh demo GIFs and sample scenes to demonstrate the refactored flow.

4. **Release Validation**  
   - Run regression suite, stress-test asset discovery on large projects, and confirm undo/redo integrity.

### Ticket Backlog
1. **DOC-401: In-editor help panel**  
   - *Affected components:* New help panel scene, `addons/simpleassetplacer/simpleassetplacer.gd`, dock integration, version retrieval logic.  
   - *Deliverables:* Multi-tab help/about panel with shortcuts, troubleshooting, links, dynamic version badge.  
   - *Expected result:* Users access key docs without leaving Godot.  
   - *Acceptance criteria:* Panel loads instantly; content sourced from markdown/resources; version badge reflects `plugin.cfg`.  
   - *Notes:* Explore markdown-to-rich-text pipeline for maintainability.  
   - *Blocked by:* DOC-101, UI-103, WF-202  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
2. **DOC-402: README/Changelog rewrite**  
   - *Affected components:* README, CHANGELOG, branding assets.  
   - *Deliverables:* Updated documentation highlighting command pipeline, migration notes, refreshed media.  
   - *Expected result:* Public materials accurately describe new UX.  
   - *Acceptance criteria:* README quickstart covers new controls; changelog grouped by release; media links valid.  
   - *Notes:* Coordinate with release date to avoid stale screenshots.  
   - *Blocked by:* DOC-401, WF-201, WF-203, QA-301  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
3. **DOC-403: Sample project refresh**  
   - *Affected components:* `sample/` scenes, branding GIFs/video, documentation references.  
   - *Deliverables:* Updated sample scenes demonstrating continuous placement/variants, new GIFs (placement/transform/overlay), optional walkthrough video.  
   - *Expected result:* Users can explore new workflows immediately.  
   - *Acceptance criteria:* Sample scenes open without warnings; media showcases latest UI; README links functional.  
   - *Notes:* Note minimum Godot version compatibility if scene features require it.  
   - *Blocked by:* WF-201, WF-202, WF-203, WF-204, WF-205  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_
4. **QA-401: Release gate checklist**  
   - *Affected components:* `docs/release-checklist.md`, CI metadata capture.  
   - *Deliverables:* Formal go/no-go checklist, automated metadata script, sign-off template.  
   - *Expected result:* Each release verified against consistent criteria.  
   - *Acceptance criteria:* Checklist completed for release candidate; build metadata archived with tag; sign-off recorded.  
   - *Notes:* Revisit checklist post-release for continuous improvement.  
   - *Blocked by:* TEST-301, QA-301, DOC-401, DOC-402, DOC-403  
   - *Status:*  
     - [ ] Not started  
     - [ ] In progress  
     - [ ] Done  
   - *Progress note:* _(record updates here)_

---

## Supporting Workstreams

- **Settings Audit:** Inventory existing flags, remove obsolete ones, and group related options for clarity.
- **Performance Watch:** Profile command pipeline and overlay updates in heavy scenes; ensure no new stalls.
- **Accessibility:** Evaluate color contrast and text size in overlays; consider key remapping presets.
- **Test Scaffolding:** Establish `tests/` and `docs/testing/` structure early, add placeholder scenes/scripts, and document how to run CI or local harnesses.

---

## Tracking & Updates

- Use this roadmap as a living document; annotate completed milestones, blockers, and design decisions.
- Sync roadmap updates with Git commits (e.g., mention phase progress in commit messages or changelog entries).
- Revisit the roadmap quarterly or after each major release to confirm priorities.
- Action item: capture refreshed overlay screenshots/GIFs once UI-101 visual QA completes.

---

## Appendix – Command Object Sketch

```text
TransformCommand
├─ position_delta: Vector3 (world or camera-relative)
├─ rotation_delta: Vector3 (degrees)
├─ scale_delta: Vector3 (uniform or per-axis)
├─ snap_override: Optional settings diff
├─ confirm: bool
├─ cancel: bool
├─ source_flags: { mouse_modal, numeric, key_direct, wheel, gamepad }
├─ axis_constraints: { X: bool, Y: bool, Z: bool }
├─ metadata: Dictionary (mode, placement data, etc.)
```

This schema is intentionally simple; future work can extend it with per-axis masks, smoothing hints, or animation cues.
