# Changelog

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
