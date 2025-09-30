# Simple Asset Placer

A comprehensive asset placement tool for Godot 4 that provides thumbnail previews, drag-and-drop functionality, MeshLibrary support, and customizable placement settings.

![Plugin Version](https://img.shields.io/badge/version-1.0-blue)
![Godot Version](https://img.shields.io/badge/godot-4.x-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 🎯 **Asset Browsing & Management**
- **Thumbnail Preview System**: Auto-generated thumbnails for all supported 3D assets
- **Tabbed Interface**: Organized browsing with separate tabs for Models and MeshLibraries
- **Search & Filter**: Quickly find assets with real-time search functionality
- **Supported Formats**: FBX, OBJ, GLTF/GLB, DAE, TRES, RES, and MeshLibrary files

### 🎮 **Interactive Placement**
- **Real-time Preview**: See exactly where your asset will be placed before confirming
- **Mouse-based Positioning**: Click to place assets with visual feedback
- **Height Adjustment**: Use Q/E keys to raise/lower assets during placement
- **Escape to Cancel**: Press ESC to exit placement mode anytime

### 🔄 **Advanced Rotation System**
- **Multi-axis Rotation**: Rotate around X (pitch), Y (yaw), and Z (roll) axes
- **Customizable Key Bindings**: Set your preferred keys for each rotation axis
- **Keyboard Rotation**: Use R/X/Z keys for precise rotation control
- **Multiple Increment Modes**: 
  - Base increment for keyboard (default 15°)
  - Large increment for Ctrl+Key (default 90°)
- **Visual Feedback**: On-screen rotation display with current values
- **Reset Function**: Quickly reset all rotations to 0°

### 📏 **Scale Management**
- **Dynamic Scaling**: Adjust asset scale during placement
- **Keyboard Controls**: Dedicated keys for scale up/down/reset
- **Real-time Preview**: See scale changes immediately in the preview
- **Increment Settings**: Configurable scale step sizes

### ⚡ **Smart Placement Options**
- **Surface Snapping**: Automatically place objects on ground/surfaces
- **Grid Snapping**: Align objects to a customizable grid
- **Random Rotation**: Apply random Y-axis rotation for natural variation
- **Auto Collision**: Automatically add collision shapes to placed objects
- **Instance Grouping**: Group multiple instances of the same asset

### 📚 **MeshLibrary Support**
- **Full Integration**: Browse and place MeshLibrary items with thumbnails
- **Seamless Workflow**: Same placement controls work for both individual assets and MeshLibrary items
- **Preview Generation**: Auto-generated thumbnails for MeshLibrary items

## Installation

1. Download or clone this repository
2. Copy the `addons/simpleassetplacer` folder to your project's `addons/` directory
3. Enable the plugin in Project Settings → Plugins
4. The Asset Placer dock will appear in the right panel

## Usage

### Basic Placement

1. **Open the Asset Placer dock** in the right panel
2. **Browse assets** using the Models tab or MeshLibraries tab
3. **Click on an asset thumbnail** to start placement mode
4. **Move your mouse** in the 3D viewport to position the preview
5. **Click to place** the asset at the preview location
6. **Press ESC** to cancel placement mode

### Rotation Controls

During placement mode, you can rotate assets using:

#### 🎯 **Simple Rotation Controls**

**Key Press Rotation**
- **Press X/Y/Z keys** for instant 15° rotation increments
- **Shift + Key**: Rotate in opposite direction (-15°)
- **Ctrl + Key**: Large rotation (90°) 
- **T Key**: Reset all rotations to 0°

**Modifier Combinations**
- **X + Shift**: -15° X-axis rotation (pitch backward)
- **Y + Shift**: -15° Y-axis rotation (turn left)
- **Z + Shift**: -15° Z-axis rotation (roll left)
- **X + Ctrl**: 90° X-axis rotation (quarter turn)
- **Any Key + Ctrl + Shift**: Large reverse rotation (-90°)

#### 🎮 **Rotation Keys (Customizable)**
- **Y Key** (default): Y-axis rotation (yaw/turning)
- **X Key** (default): X-axis rotation (pitch/nodding)  
- **Z Key** (default): Z-axis rotation (roll/banking)
- **T Key** (default): Reset all rotations to 0°

> **Pro Tip**: The overlay shows current rotation mode - hold a rotation key and move your mouse for precise control, or just tap keys for quick increments!

### Scale Controls

Adjust scale during placement:

- **Page Up** (default): Increase scale
- **Page Down** (default): Decrease scale
- **Home** (default): Reset scale to 1.0

### Settings Configuration

Access the Settings tab to customize:

#### Placement Options
- **Snap to Ground**: Place objects on surfaces below
- **Enable Grid Snapping**: Snap to grid with configurable size
- **Random Y Rotation**: Add natural variation
- **Auto Collision**: Automatically add collision shapes
- **Group Instances**: Organize multiple instances

#### Key Bindings
- Customize all rotation and scale keys
- Click any key button and press your preferred key
- Press ESC to cancel key binding

#### Rotation Settings
- **Base Increment**: Standard rotation step (default: 15°)
- **Large Increment**: Ctrl+Key rotation step (default: 90°)

#### Scale Settings
- **Scale Increment**: Standard scale step (default: 0.1)
- **Large Scale Increment**: Alternative scale step (default: 0.5)

## File Structure

```
addons/simpleassetplacer/
├── plugin.cfg                 # Plugin configuration
├── simpleassetplacer.gd      # Main plugin class
├── asset_placer_dock.gd      # Main UI dock
├── placement_core.gd         # Core placement logic
├── preview_manager.gd        # Preview system
├── rotation_manager.gd       # Rotation handling
├── scale_manager.gd          # Scale management
├── placement_settings.gd     # Settings UI and persistence
├── meshlib_browser.gd        # MeshLibrary browser
└── thumbnail_generator.gd    # Thumbnail generation system
```

## Configuration

All settings are automatically saved to Godot's editor settings and persist between sessions. The plugin creates settings under the `simple_asset_placer/` namespace.

## Supported Asset Types

- **FBX**: Complete scene instantiation with materials
- **OBJ**: Mesh-only geometry
- **GLTF/GLB**: Full scene support with animations and materials
- **DAE (Collada)**: Complete scene support
- **TRES/RES**: Native Godot resources
- **MeshLibrary**: GridMap-compatible mesh libraries

## Performance Features

- **Thumbnail Caching**: Generated thumbnails are cached for faster loading
- **Asynchronous Generation**: Thumbnails generate in the background
- **Memory Management**: Automatic cleanup of resources
- **Queue System**: Prevents thumbnail generation conflicts

## Tips & Tricks

### Workflow Optimization
- Use the search bar to quickly find specific assets
- Organize assets in folders for better discovery
- Create MeshLibraries for frequently used asset sets
- Use grid snapping for precise architectural placement

### Keyboard Shortcuts
- **Q/E**: Adjust height during placement
- **R/X/Z**: Rotate around Y/X/Z axes (customizable)
- **Ctrl + R/X/Z**: Large rotation increments (90°)
- **T**: Reset rotation
- **Page Up/Down**: Scale up/down
- **Home**: Reset scale
- **ESC**: Cancel placement mode

### Performance Tips
- Clear thumbnail cache periodically if you have many assets
- Use smaller thumbnail sizes for better performance with large asset collections
- Group similar objects to reduce scene complexity

## Troubleshooting

### Assets Not Showing
- Ensure assets are in your project folder
- Check that file extensions are supported
- Use the Refresh button to rescan for assets

### Thumbnails Not Generating
- Clear the thumbnail cache in Settings
- Check console for error messages
- Ensure assets are valid Godot resources

### Placement Issues
- Verify you're in a 3D scene
- Check that the camera has a clear view
- Try adjusting placement settings

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Credits

**Author**: LuckyTeapot  
**Version**: 1.0  
**Godot Version**: 4.x

---

*For more information and updates, visit the project repository.*
