<div align="center">
  <img src="branding/github-banner.svg" alt="Simple Asset Placer Banner" width="100%"/>
</div>

---

# 🎯 Simple Asset Placer

**A comprehensive asset placement plugin for Godot 4.x that revolutionizes level design workflows!**

Simple Asset Placer brings professional-grade asset placement capabilities to Godot Engine, featuring a dual-mode system that combines traditional placement workflows with an innovative Transform Mode for modifying existing objects.

## ✨ Core Features

- 🚀 **Dual Placement Modes**: Traditional placement mode for new asset placement, plus innovative **Transform Mode** for modifying existing Node3D objects with a customizable key (TAB by default). Full undo/redo support for all operations.
- 🔢 **Direct Numeric Input**: Type exact values for transformations - press rotation keys and type `45` for precise 45° rotation. Works for rotation, scale, height, and position adjustments in both modes.
- 🔄 **Asset Cycling System**: Browse and switch between assets directly in the viewport with `[` and `]` keys - stay in your creative flow without returning to the dock. Supports tap or hold to rapidly cycle, with context-aware filtering and auto-scroll.
- � **Multi-Object Transformation**: Select multiple Node3D objects and transform them simultaneously with full group coordination and atomic undo/redo tracking.
- �🌍 **Universal Keyboard Support**: ALL keybinds work with international keyboards! Configure any key with modifier combinations (CTRL+ALT+key) for perfect compatibility with German, French, and other keyboard layouts.
- 🏷️ **Advanced Category System**: Intelligent asset organization with automatic folder-based categories, custom tags, favorites, and recent assets tracking.
- 🎮 **Professional Input Handling**: Advanced conflict prevention system ensures plugin shortcuts never interfere with Godot's built-in commands. Full modifier key support (CTRL, ALT, SHIFT, META) for every keybind.
- 🔧 **Complete Customization**: Every aspect is configurable - from key bindings and reset behaviors to placement settings and visual feedback.
- 🔁 **Placement Loop Control**: Switch between continuous placement and single-drop workflows, and auto-select placed nodes directly from the settings dock.
- ⚡ **Performance Optimized**: Frame-based settings caching, double-buffered AABB calculations, fast thumbnail generation with isolated rendering, and smooth real-time placement with instant visual feedback.
- 🎨 **Clean Architecture**: Modern instance-based design with service registry pattern, dedicated mode handlers, and specialized utility classes for maintainability and extensibility.

## 🚀 Quick Start

### **Installation**
1. Download or clone this repository.
2. Copy the `addons/simpleassetplacer/` folder to your project's `addons/` directory.
3. Enable "SimpleAssetPlacer" in **Project → Project Settings → Plugins**.
4. The "Asset Placer" dock appears automatically in the right panel of the editor.

### **Basic Usage - Placement Mode**
```
1. Open the Asset Placer dock (right panel).
2. Switch to the "3D Models" or "MeshLibraries" tab.
3. Click any asset thumbnail to start placement mode.
4. Move your mouse in the 3D viewport to position the preview.
5. Use Q/E keys (or mouse wheel) to rotate the object.
6. Use [ and ] keys to cycle through different assets without leaving the viewport.
7. Left-click to place the asset in your scene.
8. ESC to exit placement mode.
```

> **Tip:** Tweak the **Continuous Placement** and **Auto-select Placed Node** toggles in the Settings dock to swap between single-drop bursts and hands-free placement runs.

<div align="center">
  <img src="branding/gifs/placement_mode.gif" alt="Placement Mode Demo" width="80%"/>
  <p><i>Placement Mode in action - selecting, positioning, and placing assets</i></p>
</div>

### **Advanced Usage - Transform Mode**
``` 
1. Select any Node3D object(s) in the scene tree (single or multiple).
2. Press TAB (or your configured key) to enter Transform Mode.
3. Use mouse movement to reposition the object(s).
4. Use Q/E for rotation, W/A/S/D for precise positioning.
5. Type numbers after pressing transform keys for exact values (e.g., Q → 45 → Enter).
6. All placement controls work in Transform Mode.
7. Left-click or Enter to confirm changes, ESC to cancel and restore original state.
8. All changes are tracked in undo/redo history (Ctrl+Z/Ctrl+Shift+Z).
```

<div align="center">
  <img src="branding/gifs/transform_mode.gif" alt="Transform Mode Demo" width="80%"/>
  <p><i>Transform Mode - modifying existing objects in the scene</i></p>
</div>

### **Asset Browser Interface**

<div align="center">
  <img src="branding/screnshoots/asset_browser.png" alt="3D Models Asset Browser" width="80%"/>
  <p><i>3D Models Browser - Browse, search, and organize your 3D assets</i></p>
</div>

<div align="center">
  <img src="branding/screnshoots/meshlib_browser.png" alt="MeshLibrary Browser" width="80%"/>
  <p><i>MeshLibrary Browser - Access GridMap mesh items</i></p>
</div>

### **Essential Controls**

**🎮 Modal Transform Controls (Blender-style):**
- **G**: Position control mode - Move object with mouse, type numbers for exact offsets
- **R**: Rotation control mode - Rotate with mouse, type numbers for exact angles
- **L**: Scale control mode - Scale with mouse wheel, type numbers for exact scale
- **X / Y / Z**: Axis constraint toggle (double-tap to disable) - Works in any control mode
- **Mouse Wheel**: Context-aware adjustment based on current control mode (G=height, R=rotation, L=scale)

**⌨️ Quick Actions:**
- **Q / E**: Quick height adjustment (works in any control mode)
- **W/A/S/D**: Alternative position controls in G mode (camera-relative)
- **Left-Click**: Place asset (Placement Mode) / Confirm changes (Transform Mode)
- **Enter**: Confirm numeric input or placement/transformation
- **ESC**: Cancel numeric input / Cancel and exit current mode

**🔄 Mode Management:**
- **TAB**: Enter/exit Transform Mode (when Node3D selected)
- **[ / ]**: Cycle to previous/next asset during placement

**🎯 Modifiers:**
- **CTRL**: Fine adjustment mode (smaller increments)
- **ALT**: Large adjustment mode (bigger increments)
- **SHIFT**: Reverse direction for certain adjustments
- **Ctrl+Z / Ctrl+Shift+Z**: Undo / Redo transformations and placements

**💡 Example Workflows:**
- Position → **G** → Move mouse → **Enter**
- Rotate 90° on Y → **R** → **Y** → Type `90` → **Enter**
- Scale to 2x → **L** → Type `2` → **Enter**
- Height adjust → **Q/E** or **G** + **Mouse Wheel**
- Constrained move on Z → **G** → **Z** → Move mouse → **Enter**

## 🔄 Asset Cycling - Stay in Your Flow

**New in v1.2.0!** Browse and switch between assets without ever leaving the 3D viewport.

### **How Asset Cycling Works**
While in Placement Mode with a preview visible:
- **Press `]`** to cycle to the next asset
- **Press `[`** to cycle to the previous asset  
- **Tap once** to switch to the next/previous asset
- **Hold the key** to rapidly browse through all assets
- Preview updates **instantly** - no interruption to your workflow!

### **Smart Context-Aware Cycling**
Cycling respects your current view and filters:
- ✅ **Filtered Categories**: Cycle only through "Trees", "Rocks", etc.
- ✅ **Search Results**: Cycle through search matches
- ✅ **Favorites**: Cycle through favorited assets only
- ✅ **Custom Tags**: Cycle through tagged asset groups
- ✅ **Auto-scroll**: Browser automatically scrolls to show current asset
- ✅ **Wrap-around**: Last asset → first asset seamlessly

### **Perfect Workflow for Level Design**
```
Example: Placing trees in a forest scene
1. Filter to "Trees" category
2. Click any tree to start placing
3. Position first tree location
4. Press ] to browse other tree types
5. Found the perfect one? Click to place!
6. Move to next location, press ] again
7. Never touch the dock - stay focused on your scene
```

### **Works Everywhere**
- ✅ **3D Models Tab**: Cycle through .fbx, .obj, .gltf, etc.
- ✅ **MeshLibrary Tab**: Cycle through GridMap mesh items
- ✅ **Both Tap and Hold**: Flexible input for your workflow

### **International Keyboard Support**
If your keyboard requires modifier keys for brackets:
1. Go to **Settings → Control Keys**
2. Click **"Cycle Next Asset"** button
3. Press your bracket combination (e.g., `CTRL+ALT+9`)
4. Click **"Cycle Previous Asset"** button  
5. Press your other bracket (e.g., `CTRL+ALT+8`)
6. Done! Cycling now works perfectly with your layout

## 🔢 Numeric Input System

**New in v1.5.0!** Type exact values for precise transformations instead of repeatedly tapping keys.

### **How Numeric Input Works**
1. **Press any transform key** (Q, E, W, A, S, D, Page Up/Down, etc.)
2. **Type the desired number** (e.g., `45` for 45 degrees, `1.5` for 1.5 scale)
3. **Press Enter** to apply the exact value, or **ESC** to cancel
4. **Visual feedback** appears in the overlay showing your input

### **Supported Operations**
- **Rotation**: Press Q/E/X/Z and type angle in degrees (e.g., `90`, `45.5`, `-30`)
- **Scale**: Press Page Up/Down and type scale value (e.g., `2.0`, `0.5`, `1.25`)
- **Height**: Press height adjustment keys and type distance (e.g., `5.0`, `-2.5`)
- **Position**: Press W/A/S/D and type distance to move (e.g., `3.0`, `0.5`)

### **Examples**
```
Rotate exactly 45 degrees clockwise:
  Q → 4 → 5 → Enter

Scale to exactly 2.5x:
  Page Up → 2 → . → 5 → Enter

Move 3 units forward:
  W → 3 → Enter

Adjust height by -1.5 units:
  Height Down → 1 → . → 5 → Enter (or type: - → 1 → . → 5)
```

### **Features**
- ✅ Works in both **Placement Mode** and **Transform Mode**
- ✅ Supports **positive and negative values**
- ✅ Supports **decimal numbers** (e.g., 1.5, 0.25)
- ✅ Visual overlay shows current input
- ✅ ESC to cancel without applying
- ✅ Invalid input rejected with feedback

## ⌨️ Controls & Key Bindings

### **Core Controls**
| Action               | Default Key      | Customizable | Description                                    |
|----------------------|------------------|--------------|------------------------------------------------|
| Transform Mode       | TAB              | ✅           | Enter/exit transform mode for selected objects |
| Place/Confirm        | Left-Click       | ❌           | Place asset or confirm transform changes       |
| Confirm Action       | Enter            | ✅           | Confirm numeric input or placement             |
| Cancel               | ESC              | ✅           | Cancel numeric input / Exit mode               |
| Cycle Next Asset     | ]                | ✅           | Switch to next asset in filtered view          |
| Cycle Previous Asset | [                | ✅           | Switch to previous asset in filtered view      |
| Undo                 | Ctrl+Z           | ❌           | Undo last placement or transformation          |
| Redo                 | Ctrl+Shift+Z     | ❌           | Redo previously undone action                  |

### **Rotation Controls**
| Action               | Default Key      | Customizable | Description                                    |
|----------------------|------------------|--------------|------------------------------------------------|
| Rotate Y-Axis        | Q / E            | ✅           | Rotate around Y-axis (type number for exact)   |
| Rotate X-Axis        | X                | ✅           | Rotate around X-axis (type number for exact)   |
| Rotate Z-Axis        | Z                | ✅           | Rotate around Z-axis (type number for exact)   |
| Fine Rotation        | Mouse Wheel      | ❌           | Precise rotation control                       |
| Reset Rotation       | T                | ✅           | Reset all rotation offsets to zero             |

### **Position Controls**
| Action               | Default Key      | Customizable | Description                                    |
|----------------------|------------------|--------------|------------------------------------------------|
| Move Forward         | W                | ✅           | Move along camera forward (type for exact)     |
| Move Backward        | S                | ✅           | Move along camera back (type for exact)        |
| Move Left            | A                | ✅           | Move along camera left (type for exact)        |
| Move Right           | D                | ✅           | Move along camera right (type for exact)       |
| Height Up            | Q (when rotated) | ✅           | Increase height offset (type for exact)        |
| Height Down          | E (when rotated) | ✅           | Decrease height offset (type for exact)        |
| Reset Height         | R                | ✅           | Reset height offset to zero                    |
| Reset Position       | G                | ✅           | Reset position offsets to zero                 |

### **Scale Controls**
| Action               | Default Key      | Customizable | Description                                    |
|----------------------|------------------|--------------|------------------------------------------------|
| Scale Up             | Page Up          | ✅           | Increase scale (type number for exact value)   |
| Scale Down           | Page Down        | ✅           | Decrease scale (type number for exact value)   |
| Reset Scale          | Home             | ✅           | Reset scale multiplier to 1.0                  |

### **Modifier Keys**
| Modifier             | Effect                                                                                    |
|----------------------|-------------------------------------------------------------------------------------------|
| **CTRL**             | Fine adjustment mode (10% of base increment for rotation/scale/position)                  |
| **ALT**              | Large adjustment mode (10x base increment for rotation/scale/position)                    |
| **SHIFT**            | Reverse direction for height adjustments (Q/E become E/Q)                                 |

### **Controls in Action**

<div align="center">
  <img src="branding/gifs/position.gif" alt="Position Controls Demo" width="32%"/>
  <img src="branding/gifs/rotation.gif" alt="Rotation Controls Demo" width="32%"/>
  <img src="branding/gifs/scale.gif" alt="Scale Controls Demo" width="32%"/>
  <p><i>Position, Rotation, and Scale controls demonstrated</i></p>
</div>

### **Advanced Key Binding Features**
- **Universal Modifier Support**: Use CTRL, ALT, SHIFT, META (Windows/Command key) alone or in combinations with ANY keybind.
- **International Keyboard Layouts**: Configure keys like `CTRL+ALT+8` for brackets on German keyboards, `ALT+5` on French keyboards, etc.
- **Conflict Prevention**: Plugin intercepts input at the highest priority to avoid conflicts with Godot's built-in shortcuts.
- **Per-Action Customization**: Every action can be remapped independently via the Settings tab.
- **Visual Feedback**: Settings panel shows current bindings and captures full key combinations including modifiers during key assignment.

## 🏷️ Category & Organization System

Simple Asset Placer includes a powerful category system that helps you organize and quickly find assets in large projects.

### **Automatic Folder-Based Categories**
The plugin automatically detects categories based on your folder structure:
```
res://assets/
├── props/          → "Props" category
│   ├── outdoor/    → "Props > Outdoor" 
│   └── indoor/     → "Props > Indoor"
├── vegetation/     → "Vegetation" category
└── buildings/      → "Buildings" category
```
**Features:**
- ✅ **Zero Configuration**: Works automatically with your existing folder structure
- ✅ **Hierarchical Display**: Shows nested folder relationships
- ✅ **Instant Filtering**: Select any folder category to see matching assets

### **Custom Tags System**
Add custom tags to assets for flexible organization:

**Creating Tags:**
1. Right-click any asset thumbnail
2. Select a recent tag or choose "+ New Tag..."
3. Tags are saved in `.assetcategories` file

**Tag File Format (`.assetcategories`):**
```json
{
  "tags": {
    "barrel_01": ["props", "outdoor", "medieval"],
    "tree_pine": ["vegetation", "forest", "nature"],
    "wall_stone": ["buildings", "medieval", "outdoor"]
  },
  "tag_usage": {
    "props": 3,
    "outdoor": 2,
    "medieval": 2
  },
  "recently_used": ["props", "outdoor"]
}
```

**Tag Features:**
- 🏷️ **Multiple Tags per Asset**: Assign unlimited tags to each asset
- 🔍 **Quick Access**: Recently used tags appear first in context menu
- 📊 **Usage Tracking**: Most-used tags prioritized automatically
- 💾 **Persistent Storage**: Tags saved in JSON format, easy to edit/version control

### **Favorites & Recent Assets**
**Favorites:**
- ⭐ Right-click any asset → "Add to Favorites"
- Quick access filter at top of category dropdown
- Persists across sessions in EditorSettings
- Perfect for frequently used assets

**Recent Assets:**
- 🕐 Automatically tracks last 20 used assets
- Shows in dedicated "Recent" filter
- Updates when you place assets
- Great for iterative level design

### **Visual Category Indicators**
Assets display color-coded badges on thumbnails:
- 🟡 **Gold Star**: Favorited asset
- 🟢 **Green Badge**: Custom tag
- 🔵 **Blue Badge**: Folder category

**Enhanced Tooltips:**
Hover over any asset to see:
- Asset name and path
- Favorite/Recent status
- All folder categories
- All custom tags

### **Category Filtering**
**Multi-Criteria Filtering:**
Combine filters for precise asset discovery:
1. **Text Search**: Filter by asset name
2. **Category**: Filter by folder or custom tag
3. **File Type**: Filter by format (FBX, OBJ, etc.)

**Filter Workflow:**
```
1. Select category from dropdown (e.g., "Props")
2. Narrow with file type filter (e.g., "FBX Files")
3. Use search box for specific names
→ Results show only matching assets
```

### **Context Menu Actions**
Right-click any asset for quick actions:
- 📁 **View Folder Categories**: See auto-detected categories
- 🕐 **Recent Tags**: Quick access to last 5 used tags
- 🏷️ **All Tags**: Browse all available tags
- ➕ **New Tag**: Create new custom tag
- ⭐ **Add to Favorites**: Mark as favorite

### **Advanced Tag Management Dialog**
Click the "Manage Tags..." button next to the category filter for powerful bulk operations:

<div align="center">
  <img src="branding/screnshoots/afvance_tag_management_dialog.png" alt="Advanced Tag Management Dialog" width="80%"/>
  <p><i>Advanced Tag Management Dialog - Bulk tag operations and organization</i></p>
</div>

**Features:**
- 📋 **Asset Table**: See all assets with their current tags
- 🔍 **Dual Search**: Filter assets and tags independently
- ✅ **Multi-Select**: Ctrl+Click or Shift+Click to select multiple assets
- ➕ **Bulk Add Tags**: Add selected tags to multiple assets at once
- ➖ **Bulk Remove Tags**: Remove tags from multiple assets
- 📊 **Live Statistics**: Real-time overview of tagged/untagged assets and tag usage
- ✏️ **Rename Tags**: Rename tags across all assets
- 🔀 **Merge Tags**: Combine multiple tags into one
- 🗑️ **Delete Tags**: Remove unused tags from the system

**Tag Management Workflow:**
```
1. Click "Manage Tags..." button
2. Select multiple assets (Ctrl+Click)
3. Select tag(s) from the right panel
4. Click "Add to Selected" or "Remove from Selected"
5. Use Rename/Merge/Delete for tag maintenance
→ Changes auto-save and refresh the asset grid
```

**Use Cases:**
- 🎯 **Batch Tagging**: Import 50 assets → Select all → Add "medieval" tag
- 🧹 **Tag Cleanup**: Merge "outdoor" and "exterior" into one tag
- 📊 **Audit Tags**: See which tags are most used, clean up duplicates
- 🔄 **Reorganize**: Rename tags to match new naming conventions

### **Best Practices**

**Folder Organization:**
```
✅ Good Structure:
res://assets/
├── environment/
│   ├── nature/
│   └── urban/
├── characters/
└── props/

❌ Avoid Flat Structure:
res://assets/
├── barrel1.fbx
├── tree1.fbx
└── (100+ files)
```

**Tag Naming Conventions:**
- Use lowercase for consistency
- Keep tags concise (1-2 words)
- Use descriptive names: "medieval", "outdoor", "destructible"
- Avoid overly specific tags

**Workflow Tips:**
- 🏷️ Tag assets as you import them
- ⭐ Favorite assets you use most often
- 🔍 Use text search + category filter together
- 📊 Review tag usage to identify common patterns

## ⚙️ Settings & Customization

Access all settings via the **Settings** tab in the Asset Placer dock.

### **Placement Settings**

#### **Snap & Alignment Options**
- **Placement Strategy**: Choose between Auto (collision), Collision (raycast to surfaces), or Plane (fixed height)
- **Align with Surface Normal**: Automatically align object rotation to match surface angle
- **Grid Snap Enabled**: Snap positions to a customizable grid
- **Snap Step**: Grid size for X/Z axis snapping (default: 1.0)
- **Snap Y Enabled**: Enable height (Y-axis) snapping to a grid
- **Snap Y Step**: Grid size for Y-axis snapping (default: 1.0)
- **Snap Offset**: Global grid offset from world origin (Vector3)
- **Show Grid**: Display visual grid overlay during placement/transform
- **Grid Extent**: Size of grid visualization in world units (default: 20.0)

#### **Snap Center Options**
Control which part of the object is used for snapping:
- **Snap Center X**: Use object center for X-axis snapping
- **Snap Center Y**: Use object center for Y-axis snapping
- **Snap Center Z**: Use object center for Z-axis snapping

#### **Other Options**
- **Random Rotation**: Apply random Y-axis rotation on placement
- **Scale Multiplier**: Base scale applied to all placed objects
- **Smooth Transforms**: Interpolate preview updates for less jittery motion
- **Auto-Activate Modal Controls**: Enter G/R/L automatically when modes begin (off by default)
- **Cursor Warp**: Keep the mouse centered during modal drags to avoid screen edge stalls
- **Sensitivity Curve**: Choose how mouse movement ramps (Linear, Ease In, Ease Out, Ease In-Out)

### **Reset Behavior**
Control what gets reset when exiting modes:
- **Reset Height on Exit**: Return height offset to zero
- **Reset Scale on Exit**: Return scale multiplier to 1.0
- **Reset Rotation on Exit**: Clear all rotation offsets
- **Reset Position on Exit**: Clear manual position offsets

### **Adjustment Increments**
Fine-tune the step sizes for all transformations:

**Rotation:**
- Base Increment: 15° (default)
- Fine Increment (CTRL): 5°
- Large Increment (ALT): 90°

**Scale:**
- Base Increment: 0.1
- Fine Increment (CTRL): 0.01
- Large Increment (ALT): 0.5

**Height:**
- Base Step: 0.1
- Fine Step (CTRL): 0.01
- Large Step (ALT): 1.0

**Position:**
- Base Step: 0.1
- Fine Step (CTRL): 0.01
- Large Step (ALT): 1.0

### **Key Binding Customization**
Every key can be remapped via the Settings tab:
1. Click the key button you want to change
2. Press the desired key combination (with or without modifiers)
3. Settings save automatically to EditorSettings

### **Cache Management**
- **Clear Thumbnail Cache**: Remove all cached thumbnails to free memory or regenerate corrupted previews

### **Persistence**
- Settings persist per-project in EditorSettings
- `.assetcategories` file stores custom tags (JSON format)
- Favorites and recent assets stored in EditorSettings for each project

## 🏗️ Architecture

Simple Asset Placer uses a modern, instance-based architecture with clear separation of concerns for maintainability and extensibility:

### **Main Plugin**
- **simpleassetplacer.gd** (extends `EditorPlugin`): Main entry point
  - Handles plugin lifecycle (`_enter_tree`, `_exit_tree`)
  - Sets up the dock interface and service registry
  - Forwards input events to mode handlers
  - Provides high-priority input interception to prevent conflicts with Godot shortcuts
  - Manages asset selection callbacks from the dock
  - Reduced from 2000+ to ~500 lines through mode handler pattern

### **Core Architecture Patterns**

#### **Service Registry Pattern**
- **ServiceRegistry**: Centralized service locator for dependency management
  - Single source of truth for all manager instances
  - Eliminates circular dependencies
  - Simplifies initialization and cleanup
  - Makes testing and mocking easier
  - All managers registered and accessed through registry

#### **Mode Handler Pattern**
- **PlacementModeHandler**: Dedicated controller for asset placement
  - Manages placement mode state and lifecycle
  - Processes placement-specific input
  - Handles asset cycling during placement
  - Creates undo/redo entries for placements
  
- **TransformModeHandler**: Dedicated controller for object transformation
  - Manages transform mode state for single/multiple objects
  - Processes transformation input (position, rotation, scale)
  - Group-based AABB calculation for multi-object transforms
  - Confirmation/cancellation with original state restoration
  - Creates undo/redo entries for transformations

- **ModeStateMachine**: Coordinates mode transitions
  - Manages mode lifecycle (enter/exit/process)
  - Ensures clean state transitions
  - Prevents mode conflicts

#### **Instance-Based Managers**
- **InstanceManagerBase**: Base class for all singleton managers
  - Unified instance lifecycle management
  - Automatic cleanup on plugin disable
  - Better encapsulation than static classes
  - Improved resource management

### **Core Managers**
- **TransformationCoordinator**: Central coordinator for transform operations
  - Coordinates between specialist managers
  - Delegates to appropriate mode handler
  - Manages smooth transform interpolation
  - Provides unified interface for transformations

- **InputHandler**: Advanced input detection (extends InstanceManagerBase)
  - Single source of truth for all input state
  - Provides tap vs. hold detection for cycling
  - Handles modifier key combinations (CTRL, ALT, SHIFT, META)
  - Universal keyboard layout support
  - Frame-based input polling for consistency

- **NumericInputManager**: Numeric input processing
  - Tracks input context (rotation, scale, height, position)
  - Validates and parses numeric input
  - Provides visual feedback through overlay
  - Supports positive/negative and decimal numbers

- **PositionManager**: 3D spatial calculations and positioning
  - Raycast-based mouse-to-world position conversion
  - Grid snapping with customizable offsets
  - Height offset management
  - Manual position offsets (WASD adjustments)
  - Surface normal detection for alignment
  - Snap center options for flexible snapping

- **GridManager**: Grid functionality
  - Centralized grid snapping logic
  - Grid visualization management
  - Offset and spacing calculations

- **OverlayManager**: Visual feedback system (extends InstanceManagerBase)
  - Real-time transform information display
  - Grid visualization with dynamic updates
  - Numeric input feedback display
  - Status messages and notifications

- **CategoryManager**: Asset organization and metadata
  - Automatic folder-based category detection
  - Custom tag management via JSON (`.assetcategories`)
  - Favorites and recent assets tracking
  - Tag usage statistics for sorting

### **Specialized Transformation Managers**
- **RotationManager**: Offset-based rotation system
  - Manual rotation offsets (user input)
  - Surface normal alignment (automatic)
  - Combined rotation calculation: `original + surface_alignment + manual_offset`
  - Multi-axis rotation (X, Y, Z)
  - Rotation around group center for multi-object transforms
  - Dictionary-based configuration

- **ScaleManager**: Multiplier-based scaling system
  - Uniform and non-uniform scale multipliers
  - Preserves original object scales
  - Final scale calculation: `original_scale * multiplier`
  - Shows actual scale values instead of percentages
  - Dictionary-based configuration

- **PreviewManager**: Real-time visual feedback (extends InstanceManagerBase)
  - Preview mesh instance management
  - Position, rotation, and scale updates
  - Asset loading and cleanup
  - Isolated preview rendering
  - Target transform tracking for smooth interpolation

- **SmoothTransformManager**: Transform interpolation (extends InstanceManagerBase)
  - Smooth position, rotation, and scale transitions
  - Configurable lerp speeds
  - Target transform management
  - Prevents jarring transform updates

### **UI Components**
- **AssetPlacerDock**: Main dock interface
  - Tab container (3D Models, MeshLibraries, Settings)
  - Search and filtering
  - Asset selection and cycling coordination
  - Settings UI integration

- **ModelLibraryBrowser**: 3D model asset browser
  - Asset discovery and scanning
  - Thumbnail grid with category filtering
  - Asset cycling support
  - Context menu for tags/favorites

- **MeshLibraryBrowser**: MeshLibrary resource browser
  - MeshLibrary item display
  - Item cycling support
  - Category and tag filtering

- **PlacementSettings**: Settings UI and management
  - Key binding capture with full modifier support
  - Placement options configuration
  - Cache management
  - Settings persistence to EditorSettings

### **Support Systems**
- **EditorFacade**: Unified Godot editor API interface
  - Wraps `EditorInterface` for consistent access
  - Provides scene root, selection, undo manager access
  - Simplifies testing with mockable interface
  - Reduces coupling to Godot's editor API

- **SettingsManager**: Centralized configuration management
  - Plugin settings (key bindings, etc.)
  - Dock settings (snap, grid, etc.)
  - Frame-based settings caching for performance
  - Combined settings dictionary for managers
  - File-based and EditorSettings persistence

- **ThumbnailGenerator**: Asset preview generation
  - Isolated World3D for clean rendering
  - Async thumbnail generation
  - Cache management
  - Neutral material override for better visibility

- **ThumbnailQueueManager**: Thumbnail generation queue
  - Request queuing and deduplication
  - Priority-based generation
  - Progress tracking

- **UtilityManager**: Scene manipulation utilities
  - Node creation and parenting
  - Transform application helpers
  - Scene validation

### **Utility Classes**
- **UndoRedoHelper** (326 lines): Centralized undo/redo management
  - Validates nodes and scene state before creating actions
  - Handles single and multi-object transform undo
  - Placement action tracking
  - Consistent action naming for History panel

- **NodeUtils** (378 lines): Node validation and operations
  - Safe node validation (`is_valid`, `is_valid_and_in_tree`)
  - Safe method calling with validation
  - Query helpers for finding children by class
  - Replaces repetitive `if node and is_instance_valid(node)` patterns
  - Debug helpers for node tree inspection

- **LayoutCalculator** (300+ lines): Responsive UI layout calculations
  - Dynamic column calculation for thumbnails
  - Responsive thumbnail sizing based on dock width
  - Grid layout positioning and sizing
  - Breakpoint system for different screen sizes

- **ErrorHandler**: Error reporting integration
  - EditorInterface integration for proper error display
  - Formatted error messages

- **PluginLogger**: Structured logging system
  - Component-based logging
  - Debug, info, warning, error levels
  - Initialization and cleanup tracking

- **PluginConstants**: Shared constants
  - Component identifiers
  - Default values
  - Configuration constants

## 📁 Project Structure

```
addons/simpleassetplacer/
├── plugin.cfg                      # Plugin metadata and configuration
├── simpleassetplacer.gd            # Main plugin (extends EditorPlugin)
│
├── core/                           # Core architecture components
│   ├── editor_facade.gd            # Editor API wrapper
│   ├── instance_manager_base.gd    # Base class for instance managers
│   ├── mode_state_machine.gd       # Mode state management
│   ├── service_registry.gd         # Service locator pattern
│   ├── transform_applicator.gd     # Transform application logic
│   ├── transform_state.gd          # Transform state container
│   └── transformation_coordinator.gd # Transform coordination
│
├── modes/                          # Mode handler implementations
│   ├── placement_mode_handler.gd   # Placement mode logic
│   └── transform_mode_handler.gd   # Transform mode logic
│
├── managers/                       # Specialized manager classes
│   ├── category_manager.gd         # Categories, tags, favorites
│   ├── grid_manager.gd             # Grid snapping and visualization
│   ├── input_handler.gd            # Input detection and edge detection
│   ├── numeric_input_manager.gd    # Numeric input processing
│   ├── overlay_manager.gd          # Visual feedback overlays
│   ├── position_manager.gd         # 3D positioning and raycasting
│   ├── preview_manager.gd          # Preview mesh management
│   ├── rotation_manager.gd         # Rotation offset calculations
│   ├── scale_manager.gd            # Scale multiplier calculations
│   ├── smooth_transform_manager.gd # Transform interpolation
│   └── utility_manager.gd          # Scene manipulation helpers
│
├── placement/                      # Placement strategy pattern
│   ├── placement_strategy.gd       # Base strategy class
│   ├── collision_placement_strategy.gd # Raycast placement
│   ├── plane_placement_strategy.gd # Plane projection
│   └── placement_strategy_manager.gd # Strategy coordinator
│
├── ui/                             # User interface components
│   ├── asset_placer_dock.gd        # Main dock interface
│   ├── asset_thumbnail_item.gd     # Thumbnail item widget
│   ├── meshlib_browser.gd          # MeshLibrary browser
│   ├── modellib_browser.gd         # 3D model asset browser
│   ├── placement_settings.gd       # Settings UI
│   ├── status_overlay.tscn         # Status overlay scene
│   ├── status_overlay_control.gd   # Status overlay controller
│   ├── tag_management_dialog.gd    # Bulk tag operations dialog
│   ├── toolbar_buttons.tscn        # Toolbar button scene
│   └── toolbar_buttons.gd          # Toolbar controller
│
├── settings/                       # Settings management system
│   ├── settings_definition.gd      # Settings metadata
│   ├── settings_manager.gd         # Settings persistence
│   ├── settings_persistence.gd     # Save/load operations
│   └── settings_ui_builder.gd      # Automated UI generation
│
├── thumbnails/                     # Thumbnail generation system
│   ├── asset_scanner.gd            # Asset discovery
│   ├── thumbnail_generator.gd      # Thumbnail rendering
│   └── thumbnail_queue_manager.gd  # Thumbnail queue
│
└── utils/                          # Utility classes and helpers
    ├── error_handler.gd            # Error reporting
    ├── increment_calculator.gd     # Increment calculations
    ├── layout_calculator.gd        # UI layout calculations
    ├── node_utils.gd               # Node validation and utilities
    ├── plugin_constants.gd         # Shared constants
    ├── plugin_logger.gd            # Structured logging
    └── undo_redo_helper.gd         # Undo/redo action creation
```

### **Optional Project Files**
```
project_root/
└── .assetcategories                # Custom tags configuration (JSON)
```

## 🎮 Supported Asset Formats

### **3D Model Formats**
The plugin automatically discovers and displays models in these formats:

- **FBX** (.fbx): Autodesk Filmbox format with materials and animations
- **OBJ** (.obj): Wavefront object files with optional MTL materials
- **GLTF/GLB** (.gltf, .glb): Modern 3D transmission format with full PBR support
- **DAE** (.dae): Collada interchange format
- **Blend** (.blend): Direct Blender file import (requires Blender)

### **Godot Native Formats**
- **TSCN** (.tscn): Godot text-based scene files with full node hierarchy
- **SCN** (.scn): Godot binary scene files
- **TRES** (.tres): Text-based resource files (checked for mesh content)
- **RES** (.res): Binary resource files (checked for mesh content)
- **MeshLibrary** (.meshlib, .tres, .res): Optimized mesh collections for GridMap

### **Asset Detection**
- The plugin scans your entire `res://` directory recursively
- Automatically skips `.godot` and hidden directories
- Filters MeshLibraries from the 3D Models tab (shown only in MeshLibraries tab)
- Only displays assets containing actual mesh data
- Ignored assets can be filtered via context menu

### **Performance Features**
- **Asynchronous Asset Scanning**: Non-blocking asset discovery
- **Thumbnail Caching**: Generated thumbnails persist across sessions
- **Isolated Rendering**: Thumbnails generated in dedicated World3D to avoid scene pollution
- **Efficient Resource Management**: Automatic cleanup and memory management
- **Deferred Loading**: Assets loaded only when selected for placement

## 💡 Tips & Workflow Optimization

### **Efficient Asset Organization**
- 📁 **Folder Structure**: Organize assets by category (buildings, props, nature) for automatic folder-based categorization
  ```
  res://assets/
  ├── environment/nature/     → Auto-detected as "environment > nature"
  ├── environment/urban/      → Auto-detected as "environment > urban"
  ├── characters/             → Auto-detected as "characters"
  └── props/                  → Auto-detected as "props"
  ```
- 🏷️ **Naming Convention**: Use descriptive names for easy identification in thumbnails
- 🏷️ **Tag Early**: Add custom tags via right-click context menu as you import assets
- ⭐ **Favorite Frequently Used**: Mark commonly used assets as favorites for instant filtering
- 📊 **Asset Sizes**: Keep reasonable polygon counts for smooth real-time placement
- 🔄 **Batch Operations**: Use Transform Mode to adjust multiple objects simultaneously

### **Placement Best Practices**
- 🎯 **Surface Placement**: Use "Collision" placement strategy (now default) for natural object placement on terrain
- 🔄 **Surface Normal Alignment**: Enable "Align with Surface Normal" for objects that should match terrain slope
- 📏 **Grid Snapping**: Enable grid snap for architectural precision and consistent spacing
- 🌐 **Grid Visualization**: Enable "Show Grid" to see the snap grid during placement
- 🔍 **Camera Positioning**: Position your 3D viewport camera at optimal angles for placement
- 🛠️ **Terrain3D Collision**: When using Terrain3D plugin separately, enable its Collision option (set to "Dynamic / Editor") so raycasts detect the terrain surface
- ⌨️ **Hotkey Efficiency**: Customize keys in Settings tab for your most common operations
- 🔄 **Asset Cycling**: Use `[` and `]` keys to quickly browse asset variations without leaving the viewport
- 🔢 **Numeric Precision**: Type exact values for perfect alignment (e.g., R → 45 → Enter for 45° rotation)
- ↩️ **Experiment Freely**: Full undo/redo support means you can try different placements without worry

### **Transform Mode Workflow**
- 🎯 **Multi-Object Selection**: Select multiple Node3D objects to transform them as a group
- 📐 **Group Center**: Objects rotate around their collective center while maintaining relative positions
- 🔄 **Non-Destructive**: Original transforms preserved - ESC to cancel and restore
- ✅ **Confirm Changes**: Left-click or Enter to apply transforms, ESC to cancel
- 🎮 **Same Controls**: All placement controls work identically in Transform Mode
- 🔢 **Precise Values**: Use numeric input for exact transformations (Q → 90 → Enter)
- ↩️ **Full Undo Support**: All transformations tracked in undo history (Ctrl+Z/Ctrl+Shift+Z)

### **Performance Optimization**
- 🖼️ **Thumbnail Cache**: Clear cache in Settings if thumbnails become corrupted or to free memory
- 🎨 **Thumbnail Size**: Plugin uses 64x64 thumbnails by default for fast rendering
- 💾 **Memory Usage**: Thumbnails cached in memory - clear cache for very large asset libraries
- 🔧 **Grid Extent**: Reduce grid extent value if grid overlay impacts performance
- 📦 **Asset Discovery**: Plugin scans on startup - large projects may take a moment

### **Collaborative Workflows**
- 📋 **Per-Project Settings**: Settings stored in EditorSettings, unique per project
- 🏷️ **Shared Tags**: Commit `.assetcategories` to version control for team tag sharing
- 🔑 **Key Standardization**: Document team key binding conventions in project wiki
- 📖 **Documentation**: Share folder organization structure with team members
- 🔄 **Version Control**: `.assetcategories` is a simple JSON file, merges cleanly in Git
- 🌍 **International Teams**: Universal keyboard support accommodates different layouts

## 🔧 Troubleshooting

### **Assets Not Appearing in the Dock**
- ✅ Ensure assets are located within your project's `res://` directory
- ✅ Verify file formats are supported (see "Supported Asset Formats" section)
- ✅ Check if assets contain actual mesh data (empty scenes won't appear)
- ✅ Click the **Refresh** button (🔄) in the dock header to rescan
- ✅ Check Godot's **Import** tab for asset import errors
- ✅ Ensure assets aren't in the "Ignored Assets" list (check EditorSettings)
- ✅ For MeshLibraries, make sure they're visible in the "MeshLibraries" tab, not "3D Models"

### **Thumbnails Not Generating or Appearing Blank**
- ✅ Clear thumbnail cache via **Settings → Clear Thumbnail Cache** button
- ✅ Check **Output** panel (bottom) for ThumbnailGenerator error messages
- ✅ Verify assets import correctly in Godot by opening them manually
- ✅ Ensure your GPU drivers are up-to-date (thumbnails use OpenGL rendering)
- ✅ Try restarting Godot if thumbnails appear corrupted
- ✅ For scenes (.tscn), ensure they contain visible MeshInstance3D nodes

### **Transform Mode Not Activating**
- ✅ Ensure you have at least one Node3D object selected in the Scene Tree
- ✅ Verify you're pressing the correct key (default: TAB, check Settings tab)
- ✅ Make sure you're in the 3D viewport (not Scene Tree or other panels)
- ✅ Plugin must be enabled in Project Settings → Plugins
- ✅ Check if TAB key is bound to another shortcut in Godot's Editor Settings
- ✅ Verify selected nodes are valid Node3D objects (not Node2D or other types)

### **Placement Mode Issues**
- ✅ Verify you're working in a 3D scene with objects that have collision
- ✅ Ensure the 3D viewport camera is active and properly positioned
- ✅ Check that "Placement Strategy" is set to "Collision" if you want surface raycasting
- ✅ Try different camera angles if raycasting fails to hit surfaces
- ✅ Use "Plane" placement strategy for free-space placement at fixed height
- ✅ For Terrain3D users: Enable Collision in Terrain3D settings

### **Object Not Appearing Where Expected**
- ✅ Check if grid snapping is enabled - disable to place freely
- ✅ Verify snap offset settings aren't moving objects unexpectedly
- ✅ Check height offset - press R to reset height to zero
- ✅ Press G to reset manual position offsets
- ✅ Disable "Align with Surface Normal" if objects are rotated oddly

### **Key Binding Problems**
- ✅ Open **Settings** tab to see current key assignments
- ✅ Verify keys aren't conflicting with Godot's built-in shortcuts
- ✅ Try reassigning problematic keys using modifier combinations (CTRL+ALT+key)
- ✅ For international keyboards: Use modifier combinations for special characters
- ✅ Remember: Plugin intercepts input ONLY during active Placement/Transform modes
- ✅ Press ESC to exit modes if keys seem unresponsive

### **Asset Cycling Not Working**
- ✅ Ensure you're in Placement Mode with a preview visible
- ✅ Check that `[` and `]` keys are properly configured in Settings
- ✅ For international keyboards, configure with modifiers (e.g., CTRL+ALT+8)
- ✅ Verify there are multiple assets visible in the current filtered view
- ✅ Try filtering by category to narrow down assets for cycling

### **Numeric Input Not Working**
- ✅ Ensure you're in Placement Mode or Transform Mode (not idle)
- ✅ Press a transform key first (Q, E, W, A, S, D, Page Up/Down, etc.)
- ✅ Check overlay for numeric input feedback
- ✅ Only digits, decimal point (.), and minus (-) are accepted
- ✅ Press Enter to confirm, ESC to cancel
- ✅ Some keys may conflict with Godot shortcuts - try in Transform Mode

### **Undo/Redo Not Working**
- ✅ Verify you're using Godot's standard undo/redo shortcuts (Ctrl+Z / Ctrl+Shift+Z)
- ✅ Check Godot's History panel to see tracked actions
- ✅ Ensure you confirmed the action (left-click or Enter), not canceled (ESC)
- ✅ Only completed placements and transformations create undo entries
- ✅ Check Output panel for any error messages about undo system

### **Performance Issues**
- ✅ Clear thumbnail cache if using many large assets (Settings tab)
- ✅ Reduce grid extent value if grid overlay causes lag
- ✅ Check for asset import issues in Godot's import system
- ✅ Consider organizing assets into subdirectories for better management
- ✅ Monitor Godot's profiler if placement feels sluggish
- ✅ Disable grid overlay if not needed ("Show Grid" option)

### **Settings Not Persisting**
- ✅ Settings are stored in EditorSettings per-project automatically
- ✅ Custom tags stored in `.assetcategories` file at project root
- ✅ Ensure Godot has write permissions to your project directory
- ✅ Check if `.assetcategories` file exists for tag persistence
- ✅ Favorites/recent assets stored in EditorSettings, not in project files

### **Plugin Not Loading**
- ✅ Verify plugin is enabled: **Project → Project Settings → Plugins**
- ✅ Check for error messages in Godot's Output panel on startup
- ✅ Ensure all plugin files are present in `addons/simpleassetplacer/`
- ✅ Verify `plugin.cfg` file exists and is properly formatted
- ✅ Try disabling and re-enabling the plugin
- ✅ Restart Godot if the dock doesn't appear after enabling

## 🔬 Technical Implementation Notes

For developers interested in understanding or extending the plugin:

### **Instance-Based Architecture**
The plugin uses a modern instance-based design with singleton pattern:
- **InstanceManagerBase**: Base class for all managers providing lifecycle management
- **ServiceRegistry**: Central registry for all manager instances
- Eliminates static variables in favor of instance variables
- Better encapsulation and resource management
- Automatic cleanup when plugin disabled

### **Mode Handler Pattern**
The plugin uses dedicated mode handlers instead of a monolithic manager:
- **PlacementModeHandler**: Handles all placement mode logic
- **TransformModeHandler**: Handles all transform mode logic
- **ModeStateMachine**: Coordinates mode transitions
- Each handler is self-contained and testable
- Main plugin delegates to appropriate handler based on current mode

**Placement Mode Flow:**
1. User selects asset from dock → `_on_asset_selected()` callback
2. `PlacementModeHandler.enter_mode()` activates placement
3. `PreviewManager` creates a preview mesh instance
4. Each frame: `process_input()` updates preview position via raycasting
5. User clicks or Enter → `confirm_placement()` instantiates asset and creates undo entry

**Transform Mode Flow:**
1. User selects Node3D(s) and presses TAB
2. `TransformModeHandler.enter_mode()` stores original transforms
3. Group AABB calculated for multi-object center point
4. Each frame: mouse position updates all target nodes' positions
5. User clicks/Enter → `confirm_transform()` creates undo entry; ESC → restores originals

### **Undo/Redo System**
Full integration with Godot's EditorUndoRedoManager:
- **UndoRedoHelper**: Validates nodes and creates undo actions
- **Placement Undo**: Tracks node addition/removal
- **Transform Undo**: Single and multi-object transform tracking
- **Atomic Operations**: Multi-object transforms treated as single undo action
- **Node Ownership**: Placed nodes correctly assigned scene root as owner

### **Input Priority Chain**
The plugin uses multiple input interception points to ensure keys are captured before Godot:
1. `_input()` - Highest priority, catches TAB and mouse wheel
2. `_shortcut_input()` - Catches plugin keys to prevent editor shortcuts
3. `_forward_3d_gui_input()` - Viewport-specific input handling
4. Returns `AFTER_GUI_INPUT_STOP` to consume events

### **Offset-Based Transform System**
Unlike absolute transforms, the plugin uses **additive offsets**:

**Rotation:** `final = original_rotation + surface_alignment + manual_offset`
**Scale:** `final = original_scale * scale_multiplier`
**Position:** `final = raycast_position + height_offset + manual_position_offset`

This preserves the original object state and allows non-destructive editing.

### **Grid Snapping Implementation**
Grid snapping happens in `PositionManager._apply_grid_snap()`:
1. Calculate snapped position: `snapped = floor((pos - offset) / step) * step + offset`
2. Optionally use object center instead of pivot for snapping
3. Apply per-axis (X, Y, Z independently controlled)
4. Grid overlay updates when object moves beyond threshold distance

### **Numeric Input System**
Direct numeric input for precise transformations:
1. `InputHandler` detects transform key press (Q, E, W, etc.)
2. `NumericInputManager` activates and tracks input context
3. User types digits, decimal point, minus sign
4. `OverlayManager` displays current input value
5. Enter key confirms → value applied to transformation
6. ESC cancels → input cleared without applying

**Supported Contexts:**
- Rotation (degrees)
- Scale (multiplier value)
- Height (world units)
- Position (world units per direction)

### **Asset Cycling Mechanism**
Cycling leverages the existing filtering system:
1. `InputHandler` detects `[` or `]` key press (with tap/hold detection)
2. `PlacementModeHandler` calls dock's cycle methods
3. Dock determines current filtered view (category, search, favorites, etc.)
4. Browser finds current asset index in filtered list
5. Cycles to next/previous index (with wrap-around)
6. Emits selection signal to update preview
7. Auto-scrolls to make new selection visible

### **Category & Tag System**
Categories are multi-source:
- **Folder Categories**: Extracted from file path (automatic)
- **Custom Tags**: Loaded from `.assetcategories` JSON file
- **Special Categories**: Favorites, Recent (stored in EditorSettings)

Filter dropdown combines all sources, showing:
1. Special categories (Favorites, Recent)
2. Folder-based categories (hierarchical)
3. Custom tags (alphabetically sorted)

### **Thumbnail Generation**
Thumbnails use an isolated rendering system:
1. `ThumbnailGenerator` creates a dedicated `World3D` and `SubViewport`
2. Assets loaded into isolated world (no scene pollution)
3. Camera positioned based on mesh bounds
4. Neutral material applied for consistent lighting
5. Viewport rendered to `Image`, converted to `ImageTexture`
6. Cached in memory for reuse

### **Settings Persistence**
Two storage mechanisms:
- **EditorSettings**: User preferences (key bindings, favorites, recent assets)
- **Project File** (`.assetcategories`): Custom tags (shared via version control)

Settings auto-save on change via signal connections.

**Performance Optimization:**
- Frame-based settings caching reduces queries by 60x at 60 FPS
- Cache invalidates automatically on settings changes
- Significant performance boost during rapid input

### **Conflict Prevention Strategy**
1. Plugin checks `SettingsManager.is_plugin_key()` for every input
2. Known plugin keys consumed via `get_viewport().set_input_as_handled()`
3. `_forward_3d_gui_input()` returns `AFTER_GUI_INPUT_STOP` for plugin keys
4. Non-plugin keys pass through via `AFTER_GUI_INPUT_PASS`
5. TAB key always consumed to prevent focus changes

## 🤝 Contributing

Contributions are welcome! The plugin uses a clean, modular architecture with clear separation of concerns that makes adding features straightforward.

### **How to Contribute**
- 🐛 **Bug Reports**: Open GitHub issues with:
  - Godot version and OS
  - Detailed reproduction steps
  - Expected vs. actual behavior
  - Error messages from Output panel
  
- 💡 **Feature Requests**: Describe:
  - Use case and workflow context
  - Expected behavior
  - How it fits with existing features
  
- 🔧 **Code Contributions**: 
  - Follow the existing architectural patterns
  - Keep managers focused and single-purpose
  - Add logging via PluginLogger
  - Update CHANGELOG.md with your changes
  - Test thoroughly in Godot 4.x
  
- 📚 **Documentation**: 
  - Improve README clarity
  - Add code comments for complex logic
  - Create usage examples or tutorials

### **Development Guidelines**
- **Architecture**: Maintain separation between managers (no business logic in main plugin)
- **Input Handling**: All input detection goes through InputHandler
- **Settings**: Use SettingsManager for configuration
- **Logging**: Use PluginLogger with appropriate component tags
- **Error Handling**: Use ErrorHandler for user-facing errors

### **Development Setup**
1. Fork the repository on GitHub
2. Create a feature branch from `dev` (or `main` if no dev branch)
3. Make your changes following the guidelines above
4. Test thoroughly in Godot 4.x (ideally multiple versions)
5. Update CHANGELOG.md with your changes
6. Submit pull request with clear description

### **Code Style**
- Use GDScript type hints (`: Type`) for all parameters and variables
- Follow GDScript naming conventions (snake_case for functions/variables)
- Add docstrings for classes and complex functions
- Keep functions focused and under 50 lines when possible
- Use meaningful variable names

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**TL;DR**: You can use, modify, and distribute this plugin freely, including in commercial projects. Attribution appreciated but not required.

## 🏆 Credits & Acknowledgments

**Author**: IIFabixn (aka LuckyTeapot)  
**Repository**: [github.com/IIFabixn/simple-asset-placer](https://github.com/IIFabixn/simple-asset-placer)  
**Version**: 1.5.0  
**Godot Version**: 4.x (tested on 4.3+)  
**License**: MIT

### **Technical Highlights**
- **Architecture**: Modern instance-based design with service registry pattern and mode handlers
- **Input System**: Universal keyboard support with full modifier combinations and numeric input
- **Dual Modes**: Placement mode for new assets + Transform mode for existing objects with undo/redo
- **Asset Management**: Automatic categories, custom tags, favorites, recent assets
- **Performance**: Frame-based caching, double-buffered AABB, isolated thumbnail rendering, efficient asset loading
- **Multi-Object Support**: Group transformations with unified AABB and atomic undo tracking

### **Key Features**
✨ Dual placement modes (Placement + Transform)  
🔢 Direct numeric input for precise transformations  
🎯 Multi-object transformation with group coordination  
↩️ Full undo/redo integration  
🔄 Asset cycling in viewport (tap or hold)  
🌍 Universal keyboard layout support  
🏷️ Advanced category system with tags  
📐 Grid snapping with visual overlay  
🎯 Surface alignment and normal detection  
⌨️ Complete key binding customization  
🛡️ Input conflict prevention  
🎨 Real-time visual feedback with numeric input overlay  
⚡ High performance with frame-based caching  
🏗️ Clean instance-based architecture with 50+ specialized classes  

### **Acknowledgments**
- The **Godot Engine** team and community for creating an amazing open-source game engine
- Contributors and users who have provided feedback, bug reports, and feature suggestions
- The game development community for establishing best practices in level design workflows
- Open-source projects that inspired the modular architecture approach

### **Special Thanks**
- Everyone who has starred, forked, or used this plugin in their projects
- Beta testers who helped identify edge cases and improve stability
- Users who contributed to documentation and examples