# 🎯 Simple Asset Placer# 🎯 Simple Asset Placer



**A comprehensive asset placement plugin for Godot 4.x that revolutionizes level design workflows!****A comprehensive asset placement plugin for Godot 4.x that revolutionizes level design workflows!**



Simple Asset Placer brings professional-grade asset placement capabilities to Godot, featuring a dual-mode system that combines traditional placement workflows with an innovative Transform Mode. Whether you're rapidly prototyping or crafting detailed levels, this plugin delivers the speed, precision, and flexibility that modern game development demands.Simple Asset Placer brings professional-grade asset placement capabilities to Godot, featuring a dual-mode system that combines traditional placement workflows with an innovative Transform Mode. Whether you're rapidly prototyping or crafting detailed levels, this plugin delivers the speed, precision, and flexibility that modern game development demands.



## ✨ Core Features## ✨ Core Features



🚀 **Dual Placement Modes**: Traditional placement mode for new asset placement, plus innovative **Transform Mode** for modifying existing Node3D objects with a customizable key (TAB by default)**Key Features**: Dual placement modes, transform mode, complete customization, conflict prevention



🎮 **Professional Input Handling**: Advanced conflict prevention system ensures plugin shortcuts never interfere with Godot's built-in commands### **Acknowledgments**

- Godot community for inspiring robust level design tools

🔧 **Complete Customization**: Every aspect is configurable - from key bindings and reset behaviors to placement settings and visual feedback- Asset placement workflow research and best practices

- Modern game development efficiency requirements

⚡ **Performance Optimized**: Fast thumbnail generation with isolated rendering, efficient asset loading, and smooth real-time placement with instant visual feedback

---

🎨 **Clean Architecture**: Modular, decoupled design built for reliability and extensibility

## 🚀 **Ready to Enhance Your Workflow?**

## 🎯 Key Features

*Simple Asset Placer brings professional-grade asset placement to Godot 4.x. With dual modes, complete customization, and conflict-free operation, it's designed to handle everything from rapid prototyping to detailed level design.*

### **🔄 Dual Placement System**

- **Placement Mode**: Traditional asset placement with mouse-based positioning**Download and experience efficient asset placement today! 🎯**

- **Transform Mode**: Activate on selected Node3D objects using configurable key (TAB default)

- **Seamless Switching**: Move between modes without losing context or settings🎮 **Professional Input Handling**: Advanced conflict prevention system ensures plugin shortcuts never interfere with Godot's built-in commands



### **🎮 Advanced Input System**🔧 **Complete Customization**: Every aspect is configurable - from key bindings and reset behaviors to placement settings and visual feedback

- **Conflict Prevention**: Plugin keys never interfere with Godot shortcuts

- **Flexible Key Bindings**: Support for standalone keys and modifier combinations (CTRL+X, ALT+Y, etc.)⚡ **Performance Optimized**: Fast thumbnail generation with isolated rendering, efficient asset loading, and smooth real-time placement with instant visual feedback

- **Multi-Layer Interception**: Comprehensive input handling across all Godot input systems

- **Smart Detection**: Only intercepts relevant keys during active plugin usage🎨 **Clean Architecture**: Modular, decoupled design built for reliability and extensibility


### **🔧 Complete Transform Control**
- **Position, Rotation, Scale**: Full 6DOF manipulation with visual feedback
- **Grid Snapping**: Configurable snap-to-grid for precise alignment
- **Surface Alignment**: Automatic surface normal alignment for natural placement
- **Preview System**: Real-time visual feedback before committing changes

### **⚙️ Comprehensive Settings**
- **Reset Behaviors**: Choose what resets when switching between assets/modes
- **Key Customization**: Remap any function to preferred key combinations
- **Visual Preferences**: Customize overlay appearance and feedback systems
- **Performance Tuning**: Adjust thumbnail generation and preview settings

## 🚀 Quick Start

### **Installation**
1. Download the plugin files
2. Copy `addons/simpleassetplacer/` to your project's `addons/` folder
3. Enable "Simple Asset Placer" in Project Settings > Plugins
4. The dock appears automatically in your editor interface

### **Basic Usage - Placement Mode**
```
1. Open the Simple Asset Placer dock
2. Browse and select an asset from the thumbnails
3. Move your mouse in the 3D viewport to position
4. Left-click to place the asset
5. Use scroll wheel or Q/E to rotate during placement
```

### **Advanced Usage - Transform Mode**
```
1. Select any Node3D object in the scene tree
2. Press TAB (or your configured key) to enter Transform Mode
3. Use the same controls as Placement Mode to modify the object
4. Press TAB again or ESC to exit Transform Mode
```

### **Essential Controls**
- **TAB**: Enter/exit Transform Mode (configurable)
- **Mouse**: Position assets in 3D space
- **Q/E**: Rotate around Y-axis during placement
- **Scroll**: Fine rotation control
- **Shift**: Hold for faster rotation/scaling
- **ESC**: Cancel current operation

## ⌨️ Controls & Key Bindings

### **Default Bindings**
| Action | Default Key | Customizable |
|--------|-------------|--------------|
| Transform Mode | TAB | ✅ |
| Rotate Left | Q | ✅ |
| Rotate Right | E | ✅ |
| Scale Up | R | ✅ |
| Scale Down | F | ✅ |
| Cancel | ESC | ✅ |

### **Advanced Key Binding Features**
- **Modifier Support**: Use CTRL, SHIFT, ALT alone or in combinations
- **Conflict Prevention**: Plugin automatically avoids Godot shortcut conflicts
- **Per-Action Customization**: Every action can be remapped independently
- **Visual Feedback**: Settings panel shows current bindings and conflicts

### **Input Examples**
```
✅ Valid Bindings:
- TAB (standalone key)
- CTRL (standalone modifier)  
- CTRL+X (modifier + key)
- SHIFT+R (modifier + key)
- ALT+SPACE (modifier + key)

❌ Conflicting Bindings:
- CTRL+S (conflicts with Save)
- CTRL+Z (conflicts with Undo)
- F5 (conflicts with Play Scene)
```

## ⚙️ Settings & Customization

### **Reset Behavior Options**
- **None**: Keep all transforms when switching assets
- **Position**: Reset position only, maintain rotation/scale
- **Rotation**: Reset rotation only, maintain position/scale  
- **Scale**: Reset scale only, maintain position/rotation
- **Position + Rotation**: Reset position and rotation, keep scale
- **All**: Complete reset to default state

### **Key Binding Customization**
- **Individual Remapping**: Change any action's key binding
- **Modifier Combinations**: Support for CTRL, SHIFT, ALT modifiers
- **Conflict Detection**: Automatic warning for Godot shortcut conflicts
- **Reset to Defaults**: Restore original key bindings anytime

### **Visual & Performance Settings**
- **Overlay Display**: Customize transform feedback appearance
- **Thumbnail Quality**: Adjust generation speed vs. quality
- **Preview Sensitivity**: Fine-tune real-time placement feedback
- **Grid Snap Settings**: Configure snap-to-grid precision

### **Persistence**
All settings automatically save to your project and persist between sessions.

## 🏗️ Architecture

Simple Asset Placer uses a clean, modular architecture designed for maintainability and extension:

### **Core Managers**
- **TransformationManager**: Central coordinator for all transform operations
- **InputHandler**: Advanced input detection and conflict prevention
- **PositionManager**: 3D math and spatial calculations
- **OverlayManager**: Visual feedback and UI overlay system

### **Specialized Components**
- **RotationManager**: Handles all rotation logic and constraints
- **ScaleManager**: Manages scaling operations and limits
- **PreviewManager**: Real-time visual feedback system
- **UtilityManager**: Scene manipulation and validation utilities

### **Support Systems**
- **Settings Management**: Configuration persistence and UI binding
- **Thumbnail Generation**: Isolated rendering with dedicated World3D
- **Asset Browser**: File system integration and asset discovery

## 📁 Project Structure

```
addons/simpleassetplacer/
├── simpleassetplacer.gd          # Main plugin coordinator
├── plugin.cfg                   # Plugin configuration
├── asset_placer_dock.gd          # Main dock interface
├── placement_settings.gd         # Settings UI and management
├── transformation_manager.gd     # Core transform coordinator
├── input_handler.gd              # Input detection system
├── position_manager.gd           # 3D spatial calculations
├── overlay_manager.gd            # Visual feedback system
├── rotation_manager.gd           # Rotation logic
├── scale_manager.gd              # Scale operations
├── preview_manager.gd            # Real-time previews
├── utility_manager.gd            # Scene utilities
├── thumbnail_generator.gd        # Asset thumbnail creation
├── asset_thumbnail_item.gd       # Individual thumbnail items
├── meshlib_browser.gd            # MeshLibrary browser
└── controls/                     # UI control components
```

## 🎮 Supported Asset Formats

### **3D Model Formats**
- **FBX**: Full support with materials and animations
- **OBJ**: Complete geometry with MTL material files  
- **GLTF/GLB**: Modern format with full feature support
- **DAE (Collada)**: Legacy format support
- **Blend**: Direct Blender file import

### **Godot Native Formats**  
- **TSCN**: Godot scene files with full node hierarchy
- **MeshLibrary**: Optimized mesh collections for GridMap
- **PackedScene**: Pre-configured scene instances

### **Performance Features**
- **Asynchronous Loading**: Non-blocking asset import
- **Thumbnail Caching**: Fast preview generation with persistent cache
- **LOD Support**: Automatic level-of-detail handling for complex assets
- **Memory Management**: Efficient resource cleanup and reuse

## 💡 Tips & Workflow Optimization

### **Efficient Asset Organization**
- 📁 **Folder Structure**: Organize assets by category (buildings, props, nature)
- 🏷️ **Naming Convention**: Use descriptive names for easy thumbnail identification  
- 📊 **Asset Sizes**: Keep reasonable polygon counts for smooth placement
- 🔄 **Batch Operations**: Use Transform Mode for modifying multiple similar objects

### **Placement Best Practices**  
- 🎯 **Surface Alignment**: Enable surface snapping for natural object placement
- 📏 **Grid Snapping**: Use grid alignment for architectural precision
- 🔍 **Camera Positioning**: Position camera for optimal placement angles
- ⌨️ **Hotkey Efficiency**: Customize keys for your most common operations

### **Performance Optimization**
- 🖼️ **Thumbnail Management**: Clear cache periodically for large asset libraries
- 🎨 **Preview Quality**: Adjust settings based on your hardware capabilities
- 💾 **Memory Usage**: Monitor resource usage with large scenes
- 🔧 **Settings Tuning**: Optimize based on your specific workflow needs

### **Collaborative Workflows**
- 📋 **Shared Settings**: Settings persist per-project for team consistency  
- 🔑 **Key Standardization**: Establish team conventions for key bindings
- 📖 **Documentation**: Document custom asset organization for team members
- 🔄 **Version Control**: Plugin settings integrate cleanly with Git workflows

## 🔧 Troubleshooting

### **Assets Not Appearing**
- ✅ Ensure assets are within your project folder
- ✅ Verify file formats are supported (FBX, OBJ, GLTF, etc.)
- ✅ Use the Refresh button to rescan for new assets
- ✅ Check Godot's import tab for asset import errors

### **Thumbnails Not Generating**
- ✅ Clear thumbnail cache in Settings tab
- ✅ Check Output panel for error messages
- ✅ Ensure assets import correctly in Godot
- ✅ Try restarting Godot if thumbnails appear corrupted

### **Transform/Placement Issues**
- ✅ Verify you're working in a 3D scene with a camera
- ✅ Check that selected objects are Node3D types (for TAB mode)
- ✅ Ensure 3D viewport has focus during operations
- ✅ Try different camera angles if raycasting fails

### **Key Binding Problems**  
- ✅ Check Settings to see current key assignments
- ✅ Verify keys aren't conflicting with Godot shortcuts
- ✅ Try reassigning problematic keys to different combinations
- ✅ Remember: plugin only intercepts keys during active modes

### **Performance Issues**
- ✅ Clear thumbnail cache if using many large assets
- ✅ Reduce thumbnail generation for better responsiveness  
- ✅ Check for asset import issues causing slowdowns
- ✅ Consider organizing assets into smaller folders

## 🤝 Contributing

Contributions are welcome! The plugin uses a clean, modular architecture that makes adding features straightforward.

### **How to Contribute**
- 🐛 **Bug Reports**: Use GitHub issues with detailed reproduction steps
- 💡 **Feature Requests**: Describe use cases and expected behavior
- 🔧 **Code Contributions**: Follow the existing architectural patterns
- 📚 **Documentation**: Help improve README, code comments, and examples

### **Development Setup**
1. Fork the repository
2. Create feature branch from `main`
3. Test thoroughly in Godot 4.x
4. Submit pull request with clear description

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🏆 Credits

**Author**: IIFabixn aka. LuckyTeapot
**Version**: 1.0  
**Godot Version**: 4.x  
**Architecture**: Modern decoupled design with specialized managers  
**Key Features**: Dual placement modes, transform mode, complete customization, conflict prevention

### **Acknowledgments**
- Godot community for inspiring robust level design tools
- Asset placement workflow research and best practices
- Modern game development efficiency requirements

---

## 🚀 **Ready to Enhance Your Workflow?**

*Simple Asset Placer brings professional-grade asset placement to Godot 4.x. With dual modes, complete customization, and conflict-free operation, it's designed to handle everything from rapid prototyping to detailed level design.*

**Download and experience efficient asset placement today! 🎯**