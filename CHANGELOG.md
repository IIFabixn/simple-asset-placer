# Changelog

## [Unreleased]

## [1.4.0] - 2025-10-09

### ✨ New Features

#### Quick Action Toolbar Enhancements
- **Transform Mode Button** (🔧): Added dedicated toolbar button for transform mode
  - Toggle button with visual feedback when active
  - Displays configured keyboard shortcut in tooltip (default: TAB)
  - Button state automatically syncs with keyboard shortcut
  - Requires selected Node3D objects to activate
  
- **Reset All Transforms Button** (↺): One-click reset for all transform offsets
  - Clears position, rotation, scale, and height offsets instantly
  - Works in both Placement and Transform modes
  
- **Dynamic Keybind Tooltips**: All toolbar buttons now show actual configured keybinds
  - Automatically updates when settings change
  - Reads directly from settings for immediate consistency
  - Eliminates confusion from hardcoded hints

#### Keyboard Confirmation
- **Configurable Confirmation Key**: Added keyboard shortcut for confirming placements/transformations
  - Default: Enter key (customizable in Settings → Control Keys)
  - Works alongside left mouse click
  - Confirms asset placement and transformations
  - Settings persist across sessions

#### Visual Enhancements
- **Placement Strategy Indicator**: On-screen overlay shows active placement mode
  - 🎯 Collision icon for raycast placement
  - 📐 Plane icon for horizontal plane projection
  - Updates in real-time when switching strategies
  
- **Half-Step Grid Visualization**: Visual feedback for fine increment snapping
  - Red half-step grid appears when fine increment modifier (CTRL) is held
  - Shows grid at 50% of normal spacing
  - Semi-transparent overlay above main grid

### 🎨 UI/UX Improvements

#### Toolbar Integration
- **Quick Actions Moved to Viewport Toolbar**: Buttons relocated from overlay to 3D viewport menu
  - Appears in `CONTAINER_SPATIAL_EDITOR_MENU` next to Transform/View tools
  - Icon-only format (71% space reduction: 440px → 128px)
  - **6 Toolbar Buttons**:
    - 🎯 Placement Mode (cycles Collision ↔ Plane, icon changes)
    - 📏 Grid Snap
    - 🔲 Grid Overlay
    - 🔄 Random Rotation
    - 🔧 Transform Mode
    - ↺ Reset All
  - Matches Godot's native toolbar aesthetic
  - Two-way sync with settings panel

#### Status Overlay Redesign
- **Compact Layout**: Restructured with organized information hierarchy
  - Title Row: Mode label + Node name + Strategy indicator
  - Transform Row: Color-coded Position | Rotation | Scale (with VSeparator dividers)
  - Keybinds Row: Context-sensitive control hints
  - Size reduced: 800×120px → 700×100px (27% smaller)
  - Mouse filter set to `IGNORE` (display-only)

### 🏗️ Architecture Improvements

#### Directory Reorganization
- **Logical Folder Structure**: Organized 33 files into 7 subdirectories
  - `core/` - Transform & state management (7 files)
  - `placement/` - Strategy pattern system (4 files)
  - `ui/` - User interface components (6 files)
  - `settings/` - Settings management (4 files)
  - `managers/` - Supporting managers (5 files)
  - `thumbnails/` - Thumbnail generation (3 files)
  - `utils/` - Utilities & helpers (4 files)
  - Updated 100+ import paths

#### State Management Refactor
- **Stateless Design Pattern**: Eliminated scattered static variables
  - **TransformState**: Unified container for all transform state (237 lines)
  - **TransformApplicator**: Centralized transform application (238 lines)
  - **PositionManager**, **RotationManager**, **ScaleManager**: Refactored to stateless
    - All methods now accept `TransformState` as parameter
    - 48% reduction in state management complexity
    - Single source of truth for transform data
    - Improved testability (pure functions)

#### Placement Strategy Pattern
- **Strategy-Based Architecture**: Clean separation of placement modes
  - Base `PlacementStrategy` class with `CollisionPlacementStrategy` and `PlanePlacementStrategy`
  - `PlacementStrategyManager` coordinates strategy selection
  - Reduced `PositionManager.update_position_from_mouse()` from 100+ to ~40 lines
  - 60% reduction in positioning logic complexity

#### Settings System Refactor
- **Data-Driven Architecture**: 86% reduction in settings code
  - **SettingsDefinition**: Single source of truth for metadata (229 lines)
  - **SettingsUIBuilder**: Automated UI generation (234 lines)
  - **SettingsPersistence**: Centralized save/load (109 lines)
  - Reduced from 2,178 to 301 lines in main settings file
  - Adding new settings now requires only 1 line instead of 15+

### 🔧 Improvements

- **Collision Exclusion System**: Preview meshes no longer interfere with placement raycasts
  - Recursively gathers collision RIDs from nodes
  - **Note**: CSG nodes cannot be excluded (Godot 4 engine limitation)
  
- **Placement Mode Switching**: Press `P` to cycle Collision ↔ Plane modes
  - Works in both placement and transform modes
  - Visual feedback via overlay
  
- **Increment Calculator**: Unified step calculations with modifier support
  - Consistent scaling across rotation, scale, position, height
  - Configurable multipliers (default: 5x large, 0.1x fine)

### 🐛 Bug Fixes

- Fixed toolbar buttons not reflecting saved settings on load
- Fixed VSeparator2 parent path typo in status_overlay.tscn
- Fixed tooltip lag when updating keybinds in settings
- Fixed placement mode icon not syncing with keyboard shortcut (P key)
- Fixed overlay collision detection blocking viewport clicks
- Fixed duplicate strategy logging on mode entry
- Fixed position offsets not persisting between placement/transform modes
- Fixed objects jumping when entering transform mode
- Fixed rotation/scale increments not using configured values

### 📁 Technical Changes

**New Files:**
- `core/transform_state.gd` - Unified transform state container
- `core/transform_applicator.gd` - Centralized transform application
- `core/smooth_transform_manager.gd` - Interpolation system
- `placement/placement_strategy.gd` - Base strategy class
- `placement/collision_placement_strategy.gd` - Raycast placement
- `placement/plane_placement_strategy.gd` - Plane projection
- `placement/placement_strategy_manager.gd` - Strategy coordinator
- `settings/settings_definition.gd` - Settings metadata
- `settings/settings_ui_builder.gd` - Automated UI generation
- `settings/settings_persistence.gd` - Save/load operations
- `ui/toolbar_buttons.tscn` - Toolbar button scene
- `ui/toolbar_buttons.gd` - Toolbar controller
- `ui/status_overlay.tscn` - Status overlay scene
- `ui/status_overlay_control.gd` - Status overlay controller
- `utils/increment_calculator.gd` - Increment calculations

**Reorganized Files:**
- Moved all managers to respective folders (core/, managers/, etc.)
- Updated 100+ import paths across codebase

---

## [1.3.2] - 2025-10-05

### 🐛 Fixed
- **Orphaned Tag Data**: Tag system now automatically cleans up data for deleted assets
  - Tags, favorites, and recent assets for deleted files are automatically removed
  - Cleanup runs automatically when plugin loads or when refresh button is clicked
  - Tag usage statistics are recalculated after cleanup
  - Prevents stale references and keeps `.assetcategories` file clean
- **Position Reset on Large Rotation**: Fixed position getting reset unexpectedly after rotating with large increments
  - Increased XZ distance threshold from 0.01 to 0.1 units in position change detection
  - Prevents tiny mouse movements during rotation from triggering false position updates
  - Asset position now remains stable when rotating with 90° or other large increments
- **Grid Offset Snapping**: Fixed grid offset not being applied to snapping calculations
  - Grid offset spinbox controls are now properly stored as class member variables (`grid_offset_x_spin`, `grid_offset_z_spin`)
  - Fixed `_on_grid_setting_changed()` callback to access spinbox values using member variables instead of failing node path lookups
  - Grid offset values now correctly update the `snap_offset` variable when changed in the UI
  - Snapping now properly offsets from world origin (e.g., 0.5 offset results in snapping to -6.5, -1.5 instead of -6.0, -1.0)
- **Grid Offset Settings Persistence**: Fixed grid offset values not loading on plugin startup
  - Added `update_ui_from_settings()` call in `_ready()` to apply loaded settings to UI controls
  - Updated `update_ui_from_settings()` to use member variable references for grid offset spinboxes
  - Grid offset values now persist correctly across Godot sessions
- **Settings System**: Fixed critical issues with settings not being saved or loaded correctly
  - Connected all missing signal handlers for grid controls (8 controls)
  - Connected all missing signal handlers for position increment controls (3 controls)
  - Added `_on_grid_setting_changed()` handler for grid extent, Y-axis snapping, center snapping, and grid offset controls
  - Added `_on_position_increment_changed()` handler for position increment spinboxes
  - Updated `save_settings()` to save all grid settings (grid_extent, snap_center_x/y/z, position increments)
  - Updated `load_settings()` to load all grid settings with proper defaults
  - Enhanced `_disconnect_ui_signals()` and `_connect_ui_signals()` to properly handle grid and position controls
  - Fixed initial values for grid controls to use actual settings instead of hardcoded defaults
  - All 11 previously unconnected controls now properly save/load their values

### 🔧 Improved
- **Settings Persistence**: All placement settings now correctly persist across Godot sessions
  - Grid display size setting now saves/loads properly
  - Y-axis snapping settings (enabled and step size) now persist
  - Grid center snapping options (X/Y/Z) now save/load correctly
  - Grid offset values (X/Z) now persist properly and update UI on load
  - Position increment values (normal/fine/large) now save/load correctly
  - UI controls now display loaded values on startup

## [1.3.1] - 2025-10-05

### 🐛 Fixed
- **Critical Runtime Error**: Fixed missing `fine_increment_modifier_held` key in rotation and scale input dictionaries
  - Added `fine_increment_modifier_held` to `get_rotation_input()` function
  - Added `fine_increment_modifier_held` to `get_scale_input()` function
  - Eliminated hundreds of runtime errors when using rotation or scale transformations
  - Ensures consistent modifier key structure across all input query functions

### 🏗️ Technical Improvements
- **Code Cleanup**: Removed deprecated helper functions (`is_shift_held()`, `is_ctrl_held()`, `is_alt_held()`) from input dictionaries
  - All input now uses configurable modifier system (`reverse_modifier_held`, `large_increment_modifier_held`, `fine_increment_modifier_held`)

## [1.3.0] - 2025-10-05

### ✨ New Features

#### Hold-to-Repeat System
- **Continuous Actions While Holding Keys**: Hold transformation keys to repeatedly apply actions
  - **Grace Period**: 150ms delay before repeat starts (preserves tap behavior for mouse wheel combos)
  - **Smart Repeat Intervals**: Optimized for each action type
    - Rotation: 100ms (responsive rotation)
    - Scale: 80ms (smooth scaling)
    - Height: 80ms (smooth vertical adjustment)
    - Position: 50ms (smooth WASD movement)
  - **Supported Keys**: Works with all transformation keys (X/Y/Z rotation, Q/E height, WASD position, PageUp/Down scale)
  - **Single Action Priority**: Only one action repeats at a time (pressing new key cancels previous)
  - **Modifier Change Detection**: Pressing/releasing SHIFT or ALT during repeat cancels it
  - **Wheel Interruption**: Using mouse wheel interrupts repeat and requires key re-press
  - **Tap Behavior Preserved**: Quick press (< 150ms) still performs single action for wheel combos

### 🐛 Fixed
- **Grid Overlay Coordinate System**: Fixed grid overlay moving in opposite direction when transforming nodes
  - Root cause: Grid was inheriting flipped coordinate system from scene root nodes with 180° Y-axis rotation
  - Solution: Set `top_level = true` on grid overlay to make it independent of parent transform
  - Grid now works correctly regardless of scene root rotation or transform
  - Both XZ plane movement and Y-axis height adjustments now follow object correctly
- **Random Y-Rotation Now Works**: Fixed broken random rotation feature - settings were being passed but never applied during placement
  - Added random rotation application in `utility_manager.gd` for all three placement functions (place_asset_in_scene, place_meshlib_item_in_scene, place_mesh_in_scene)
  - Random rotation now applies AFTER manual rotation offsets, giving full 0-360 degree randomization on Y-axis
- **Hardcoded Modifier Keys**: Fixed all remaining hardcoded CTRL/SHIFT/ALT key references
  - Added new configurable `fine_increment_modifier_key` setting (default: CTRL)
  - Removed all hardcoded `ctrl_held` checks throughout codebase
  - TransformationManager now uses `fine_increment_modifier_held` for grid snapping half-step mode
  - Updated fine increment detection for height adjustments (placement and transform modes)
  - Updated fine increment detection for WASD position adjustments (placement and transform modes)
  - Updated rotation increment logic to use `fine_increment_modifier_held` instead of hardcoded CTRL
  - All modifier keys now fully configurable: Reverse Direction, Large Increment, and Fine Increment
  - Users can now bind all modifiers to any key combination

### 🏗️ Technical Improvements
- **InputHandler Enhancements**:
  - Added `is_action_key_held_with_repeat()` function with comprehensive state tracking
  - New tracking variables: `active_repeat_key`, `active_repeat_modifiers`, `wheel_interrupted_keys`, `repeat_intervals`
  - Modifier tracking now uses all three configured modifier keys (`reverse_modifier_key`, `large_increment_modifier_key`, `fine_increment_modifier_key`)
  - Added `is_fine_increment_modifier_held()` helper function for half-step detection
  - Wheel interruption detection automatically flags held keys when wheel is used
  - Automatic cleanup on key release (clears interruption flags and repeat state)
- **Input Query Functions Updated**:
  - `get_rotation_input()`: X/Y/Z keys support hold-to-repeat
  - `get_scale_input()`: PageUp/Down keys support hold-to-repeat
  - `get_position_input()`: Q/E (height) and WASD (position) keys support hold-to-repeat, added `fine_increment_modifier_held` field
- **Settings System**:
  - Added "Fine Increment" modifier key configuration in Settings → Modifier Keys
  - All three modifier keys now fully configurable: Reverse Direction (SHIFT), Large Increment (ALT), Fine Increment (CTRL)
  - UI controls for fine increment modifier key binding with key capture support
  - Settings persist across sessions via EditorSettings

---

## [1.2.1] - 2025-10-04

### 🐛 Fixed
- **Pure Modifier Key Bindings**: Fixed support for binding pure modifiers (ALT, CTRL, SHIFT, META) to modifier keys (Large Increment, Reverse Direction)
- **Modifier-Only Combinations**: Fixed capturing modifier-only combinations like CTRL+ALT without requiring a base key
- **Key Chord Recording**: Improved key binding capture to record all pressed keys and capture complete combinations on release
- **Modifier Key Recognition**: Fixed issue where modifier keys were not being recognized during gameplay (rotation, scale, height adjustments)
- **Configurable Modifiers in Transformation Manager**: Updated all transformation logic to use configurable modifier keys instead of hardcoded SHIFT/ALT
- **Input Dictionary Completeness**: Added missing `reverse_modifier_held` field to scale input dictionary

### 🔧 Improved
- **Key Binding Capture Logic**: Redesigned to use a recording approach that tracks all pressed keys and captures on complete release
- **Action Key Detection**: Action keys (Y, X, Z, Q, E, etc.) now properly detected even when modifiers are held
- **Modifier Separation**: Modifier state checks are now independent from action key detection, allowing proper combinations like SHIFT+Y for reverse rotation

---

## [1.2.0] - 2025-10-04

### ✨ New Features

#### Asset Cycling System
- **Cycle Through Assets During Placement**: Press `]` or `[` to browse assets without leaving the viewport
  - **Next Asset**: Press `]` (BRACKETRIGHT) to cycle forward through visible assets
  - **Previous Asset**: Press `[` (BRACKETLEFT) to cycle backward through visible assets
  - **Tap to Cycle Once**: Quick press cycles to next/previous asset
  - **Hold to Rapid Cycle**: Hold key to quickly browse through multiple assets (150ms repeat rate)
  - **Context-Aware**: Cycles through currently filtered view (category, favorites, search results, tags)
  - **Auto-Scroll**: Browser automatically scrolls to keep selected asset visible
  - **Visual Feedback**: Thumbnail highlights and preview updates instantly
  - **Works with Both Tabs**: Supports 3D Models and MeshLibrary browsers
  - **Wrap-Around**: Seamlessly loops from last asset back to first

#### Cycling Configuration
- Added "Cycle Next Asset" keybind in Settings → Control Keys
- Added "Cycle Previous Asset" keybind in Settings → Control Keys
- Fully customizable key assignments
- Settings persist across Godot sessions

### 🌍 Enhanced - Universal Keyboard Layout Support

#### International Keyboard Compatibility
- **ALL keybinds now support modifier combinations** (CTRL+ALT+8, SHIFT+X, etc.)
  - Rotation keys (X, Y, Z, Reset)
  - Scale keys (Page Up, Page Down, Home)
  - Height adjustment keys (Q, E, R)
  - Position keys (W, A, S, D, G)
  - Control keys (TAB, ESC)
  - Asset cycling keys (], [)

#### Modifier Combination Support
- **Full chord detection**: Press CTRL+ALT+8 to configure keybinds requiring modifiers
- **Conflict prevention**: Simple key bindings won't trigger when modifiers are held
- **Exact matching**: Each keybind checks for precise modifier state
- **Number key fallback**: Automatic conversion for keyboards requiring modifiers for numbers
- **Works with all modifiers**: CTRL, ALT, SHIFT, META (Windows/Command key)

#### Keybind Capture Improvements
- Settings UI now properly captures modifier combinations
- Ignores standalone modifier key presses (waits for actual key)
- Displays full key combination in settings (e.g., "CTRL+ALT+9")
- Visual feedback during key capture
- ESC to cancel key binding

### 🐛 Fixed
- **Keybind capture bug**: Settings now correctly captures full modifier combinations instead of first key pressed
- **Modifier isolation**: Modifiers no longer interfere with simple key bindings
- **International layouts**: Keyboards requiring modifiers for brackets/special chars now work properly

### 🏗️ Technical Improvements
- New `InputHandler._check_key_with_modifiers()` - Universal modifier detection
- Enhanced input state tracking for tap vs hold detection
- `ModelLibraryBrowser.cycle_to_next_asset()` - Cycles through 3D models
- `ModelLibraryBrowser.cycle_to_previous_asset()` - Reverse cycling for models
- `MeshLibraryBrowser.cycle_to_next_item()` - Cycles through meshlib items
- `MeshLibraryBrowser.cycle_to_previous_item()` - Reverse cycling for meshlib
- `AssetPlacerDock.cycle_next_asset()` - Tab-aware cycling coordinator
- `AssetPlacerDock.cycle_previous_asset()` - Reverse coordinator
- `TransformationManager._process_asset_cycling_input()` - Placement mode integration
- Auto-scroll implementation for browser visibility management

### 🎯 Workflow Enhancements
- Stay in creative flow - no need to return to dock during placement
- Quick asset iteration for level design
- Visual comparison by rapidly cycling between options
- One-handed operation (place with mouse, cycle with keyboard)
- Works seamlessly with existing filtering and search features

---

## [1.1.1] - 2025-10-04

### 🔧 Architecture & Bug Fixes

#### Offset-Based Architecture Refactor
- **RotationManager**: Complete refactor to use offset-based system instead of absolute rotations
  - Renamed `current_rotation` → `manual_rotation_offset` (breaking change for internal API)
  - Renamed `set_rotation()` → `set_rotation_offset()`
  - Now preserves original node rotations when entering transform mode
  - Rotation formula: `final_rotation = original_rotation + surface_alignment + manual_offset`
  
- **ScaleManager**: Complete refactor to use multiplier-based system instead of absolute scales
  - Renamed `current_scale` → `scale_multiplier` (breaking change for internal API)
  - Renamed `non_uniform_scale` → `non_uniform_multiplier`
  - Now preserves original node scales when entering transform mode
  - Scale formula: `final_scale = original_scale * scale_multiplier`

#### Transform Mode Improvements
- **Fixed critical bug**: Node rotations no longer reset to zero when entering transform mode with multiple nodes
- **Group rotation**: Implemented rotation around collective center while preserving individual node rotations
- **Position updates**: Eliminated `initial_frame` workaround for cleaner logic
- **Original transforms**: All original transforms (position, rotation, scale) now stored in `original_transforms` dictionary at mode start
- Unified transform application flow with consistent offset-based approach

#### Visual Improvements
- **Thumbnail camera angle**: Adjusted from `Vector3(1, 0.7, 1)` to `Vector3(1, 1, -1)` (frontal-diagonal view)
- Increased camera padding from 1.5x to 2x for better framing
- Thumbnails now show frontal view of assets for better preview quality and identification

#### Stability & Compatibility
- **Removed Terrain3D plugin**: Completely removed Terrain3D addon to prevent conflicts
  - Deleted 169 files including binaries, brushes, icons, tools, and utilities
  - Cleaned up sample scenes and terrain data
  - Updated `project.godot` to disable terrain_3d plugin
- Added Terrain3D usage tip in README for users who want to use it separately

### 🏗️ Technical Improvements
- **Unified architecture**: All transformation managers now use consistent offset-based calculations
- **Better encapsulation**: Original node values preserved and never directly modified
- **Cleaner code**: Removed workarounds and simplified logic flows
- **Improved maintainability**: Consistent naming conventions across all managers
- **Better separation of concerns**: Clear distinction between original values, offsets, and final transforms

---

## [1.1.0] - 2025-10-04

### 🎉 Major Features

#### Grid Snapping System
- Added comprehensive grid snapping functionality to position management
- Implemented center snapping options for X, Y, and Z axes independently
- Added grid overlay visualization with dynamic updates based on object movement
- Grid overlay now tracks height changes and responds to vertical movements
- Enhanced snapping features with improved position adjustment logic

#### Surface Normal Alignment
- Added alignment with surface normal feature for object rotation
- Implemented Y position handling with surface normal alignment
- Enhanced clipping prevention with improved surface alignment
- Added surface alignment reset functionality in rotation management

#### Position Management Overhaul
- Complete refactor of position management system
- Added initial position tracking and Y-axis locking functionality
- Implemented base position retrieval for ground-level placement
- Enhanced collision detection based on snap_to_ground setting
- Improved Y position adjustment logic with transformation enhancements
- Added manual position offset with proper state handling
- Height offset now properly saved when switching assets

#### Transform Mode Enhancement
- Multi-node transformation support - apply adjustments to all target nodes
- Enhanced height, scale, and rotation adjustments for multiple objects
- Improved height adjustment handling with fine increments in placement mode
- Added incremental adjustments based on modifier keys (Shift for fine control)
- Refactored to use unified TransformationManager.Mode for mode handling

#### Height Adjustment System
- Comprehensive height adjustment system with reset functionality
- Added reset height button and UI controls
- Implemented "Reset All Settings" button with confirmation dialog
- Enhanced height offset management with simplified logic
- Improved signal connections for height adjustment controls
- Height offset properly persists when switching between assets

#### Asset Management Improvements
- Added "Ignore Asset" functionality to filter unwanted assets
- Improved thumbnail generation with async request handling
- Enhanced thumbnail generation for scene files (.tscn)
- Thumbnail generator now retains cached thumbnails across panel visibility changes
- Added neutral material override for better visibility while preserving asset materials
- Async asset filtering and processing

#### Settings & Preferences
- Implemented last selected mesh library and category restoration
- Settings now persist between sessions
- Added reset position offset option on exit
- Enhanced settings management for placement mode
- New SettingsManager for centralized configuration handling

### 🔧 Major Refactoring

#### Plugin Architecture Refactor
- Created modular plugin architecture with specialized managers:
  - **AssetScanner**: Handles asset discovery and scanning
  - **ErrorHandler**: Centralized error handling and reporting
  - **PluginConstants**: Shared constants and configuration
  - **PluginLogger**: Structured logging system
  - **SettingsManager**: User preferences and settings persistence
- Reduced asset_placer_dock.gd complexity by 250+ lines
- Improved code maintainability and separation of concerns

#### Manager Enhancements
- **TransformationManager**: 885+ lines of improvements
  - Unified mode handling (placement/transform)
  - Better state management
  - Improved input processing configuration
- **PositionManager**: 350+ lines added
  - Enhanced collision detection
  - Improved ground snapping
  - Better height offset handling
- **OverlayManager**: 152+ lines added
  - Grid visualization
  - Dynamic overlay updates
  - Mode-aware rendering
- **RotationManager**: 114+ lines added
  - Surface normal alignment
  - Reset functionality
  - Offset adjustment support

#### Preview Management Refactor
- Preserve original materials by applying transparency instead of material overrides
- Improved preview visibility without affecting asset materials
- Better handling of preview state transitions

### 🐛 Bug Fixes
- Fixed export-ignore rules for addons in .gitattributes
- Removed debug print statements from production code
- Fixed viewport bounds checking for mouse position
- Improved state handling to prevent position reset issues
- Fixed height offset not saving when switching assets

### 🎨 UI/UX Improvements
- Added shift key detection for scaling operations
- Improved rotation display logic with better visual feedback
- Enhanced placement settings UI with more controls
- Added confirmation dialogs for destructive operations
- Better visual feedback for grid overlay
- Improved control responsiveness

### 📦 Asset Categories
- Updated asset categories with improved tagging
- Added new terrain asset support (Terrain3D integration for testing)
- Enhanced input handling for category management

### 🏗️ Sample/Demo Updates
- Added building_b scene to sample project
- Updated building scene configurations with improved transformations
- Enhanced wall and roof node transformations
- Improved demo scene references and examples

### 📝 Technical Improvements
- Better input coordinate conversion with viewport support
- Enhanced modifier key handling (Shift, Ctrl, Alt)
- Improved signal connections throughout the plugin
- Better synchronization between managers
- More robust error handling and validation
- Improved performance with optimized update logic

### 🔄 Internal Changes
- Added 611+ lines to placement_settings.gd for enhanced controls
- Enhanced thumbnail_generator.gd with 400+ lines of improvements
- Improved category_manager.gd with better tag management
- Enhanced modellib_browser.gd with 125+ lines of new features
- Better asset filtering and search capabilities

---

## Installation & Usage

This plugin helps you quickly place assets in your Godot 3D scenes with powerful transform controls, grid snapping, and asset management features.

### Breaking Changes
- v1.1.1: Internal API changes in RotationManager and ScaleManager (offset-based architecture)

### Known Issues
None currently reported

---

**Full Changelog**: https://github.com/IIFabixn/simple-asset-placer/commits/main
