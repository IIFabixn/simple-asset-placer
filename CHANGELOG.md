# Changelog

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

### 📚 Documentation
- Added `ASSET_CYCLING_IMPLEMENTATION.md` - Complete technical documentation
- Added `KEYBOARD_LAYOUT_SUPPORT.md` - Guide for international keyboard users
- Updated README with asset cycling feature description
- Added usage examples for different keyboard layouts

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

## [1.1.1] - 2025-10-04

### 🔧 Architecture & Bug Fixes

#### Offset-Based Architecture Refactor
- **RotationManager**: Complete refactor to use offset-based system instead of absolute rotations
  - Renamed `current_rotation` → `manual_rotation_offset` (breaking change for internal API)
  - Renamed `set_rotation()` → `set_rotation_offset()`
  - Renamed `get_rotation()` → `get_rotation_offset()`
  - Renamed `get_rotation_degrees()` → `get_rotation_offset_degrees()`
  - Now preserves original node rotations when entering transform mode
  - Updated `apply_rotation_to_node()` to accept `original_rotation` parameter
  - Rotation formula: `final_rotation = original_rotation + surface_alignment + manual_offset`
  - All rotation operations (rotate_x, rotate_y, rotate_z) now modify offset instead of absolute rotation
  
- **ScaleManager**: Complete refactor to use multiplier-based system instead of absolute scales
  - Renamed `current_scale` → `scale_multiplier` (breaking change for internal API)
  - Renamed `non_uniform_scale` → `non_uniform_multiplier`
  - Renamed `set_scale()` → `set_scale_multiplier()`
  - Renamed `get_scale()` → `get_scale_multiplier()`
  - Now preserves original node scales when entering transform mode
  - Updated `apply_scale_to_node()` and `apply_uniform_scale_to_node()` to accept `original_scale` parameter
  - Scale formula: `final_scale = original_scale * scale_multiplier`

#### Transform Mode Improvements
- **Fixed critical bug**: Node rotations no longer reset to zero when entering transform mode with multiple nodes
- **Group rotation**: Implemented rotation around collective center while preserving individual node rotations
  - Each node orbits the group center while maintaining its own rotation offset
  - Uses rotation basis calculation: `rotation_basis * original_offset` for proper orbital motion
- **Position updates**: Eliminated `initial_frame` workaround for cleaner logic
  - `snap_offset` now calculated once at mode start for consistent positioning
  - Simplified flow: `new_center = mouse_center + snap_offset + accumulated_delta`
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

This update is a major enhancement release focusing on:
1. **Better positioning control** with grid snapping and surface alignment
2. **Enhanced transformation tools** supporting multiple objects
3. **Improved asset management** with filtering and better thumbnails
4. **Persistent settings** that remember your preferences
5. **Cleaner codebase** with better error handling and logging

### Breaking Changes
None - all changes are backward compatible.

### Known Issues
- Terrain3D plugin files included for testing purposes (will be removed in future release)

---

**Total Changes**: 42 commits, affecting 27 core files with 3000+ lines of improvements
