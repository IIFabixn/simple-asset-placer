# Simple Asset Placer v2.0.1

## 🐛 Bug Fix Release

This release focuses on fixing critical issues with the collision-based placement system.

### What's Fixed

**Collision-Based Placement System**
- ✅ Objects now properly sit on floors without clipping through
- ✅ Walls placement works correctly on all sides (left, right, front, back)
- ✅ Ceiling attachment now works as expected
- ✅ Fixed clipping issues at different viewing angles
- ✅ Transform Mode now respects surface collision properly

**Camera Navigation**
- ✅ Position no longer jumps when right-clicking to navigate viewport
- ✅ Manual offsets are preserved during camera movement

**Grid Snapping**
- ✅ Removed unpredictable directional snapping
- ✅ Objects now align consistently with grid on all surfaces
- ✅ Snapping respects both surface contact and grid alignment

### Technical Improvements

- Complete rewrite of surface offset calculation with proper pivot point handling
- Enhanced bounds detection for complex PackedScenes with multiple meshes
- Rotation and scale now correctly factored into collision calculations
- Support for both Placement and Transform modes

### Installation

1. Download `simple-asset-placer-v2.0.1.zip`
2. Extract the archive
3. Copy the `addons/simpleassetplacer` folder to your Godot project's `addons/` directory
4. Enable the plugin in Project Settings → Plugins

### Compatibility

- **Godot Version:** 4.2+
- **Platform:** Windows, macOS, Linux

---

**Full Changelog:** https://github.com/IIFabixn/simple-asset-placer/blob/main/CHANGELOG.md
