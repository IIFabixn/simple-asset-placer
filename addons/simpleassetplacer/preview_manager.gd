@tool
extends RefCounted

class_name PreviewManager

"""
PREVIEW MESH MANAGEMENT SYSTEM
==============================

PURPOSE: Handles creation, styling, and lifecycle management of preview meshes during placement mode.

RESPONSIBILITIES:  
- Preview mesh creation from various asset types (Mesh, PackedScene, asset paths)
- Preview material application (semi-transparent, no shadows)
- Preview position updates and synchronization
- Asset loading and instantiation for previews
- Preview cleanup and memory management
- Material application to complex node hierarchies

ARCHITECTURE POSITION: Pure preview mesh logic with no dependencies
- Does NOT handle input detection (receives update requests)
- Does NOT handle positioning math (receives positions to apply)
- Does NOT handle UI overlays
- Focused solely on preview mesh lifecycle

USED BY: TransformationManager for placement mode preview operations  
DEPENDS ON: Godot scene system, material system, resource loading
"""

# Preview state
static var preview_mesh: Node3D = null
static var preview_material: StandardMaterial3D = null
static var current_position: Vector3 = Vector3.ZERO
static var current_rotation: Vector3 = Vector3.ZERO
static var current_scale: Vector3 = Vector3.ONE

# Preview configuration
static var preview_opacity: float = 0.6
static var preview_color: Color = Color.WHITE

## Preview Creation

static func start_preview_mesh(mesh: Mesh, settings: Dictionary = {}):
	"""Start preview with a mesh"""
	if not mesh:
		PluginLogger.error("PreviewManager", "Cannot start preview - no mesh provided")
		return
	
	cleanup_preview()
	
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		PluginLogger.error("PreviewManager", "No scene available for preview")
		return
	
	# Create preview mesh instance
	preview_mesh = MeshInstance3D.new()
	preview_mesh.mesh = mesh
	# Don't override materials - preserve original mesh appearance
	# Instead, use transparency property to make it semi-transparent
	preview_mesh.transparency = 1.0 - preview_opacity  # transparency: 0.0 = opaque, 1.0 = fully transparent
	preview_mesh.name = "AssetPlacerPreview"
	preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview_mesh.layers = 1  # Default render layer
	
	# Add to scene first
	current_scene.add_child(preview_mesh)
	
	# Apply initial transform (after node is in tree)
	preview_mesh.global_position = current_position
	preview_mesh.rotation = current_rotation
	preview_mesh.scale = current_scale
	
	PluginLogger.info("PreviewManager", "Started mesh preview")

static func start_preview_asset(asset_path: String, settings: Dictionary = {}):
	"""Start preview with an asset file"""
	if asset_path == "":
		PluginLogger.error("PreviewManager", "Cannot start preview - no asset path provided")
		return
	
	var asset = load(asset_path)
	if not asset:
		PluginLogger.error("PreviewManager", "Failed to load asset: " + asset_path)
		return
	
	cleanup_preview()
	
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		PluginLogger.error("PreviewManager", "No scene available for preview")
		return
	
	var preview_node = null
	
	# Handle different asset types
	if asset is PackedScene:
		preview_node = asset.instantiate()
		if preview_node:
			_apply_preview_transparency_to_children(preview_node)
	elif asset is Mesh:
		preview_node = MeshInstance3D.new()
		preview_node.mesh = asset
		# Use transparency instead of material override
		preview_node.transparency = 1.0 - preview_opacity
	else:
		PluginLogger.error("PreviewManager", "Unsupported asset type for: " + asset_path)
		return
	
	if not preview_node:
		PluginLogger.error("PreviewManager", "Failed to create preview node from: " + asset_path)
		return
	
	preview_mesh = preview_node
	preview_mesh.name = "AssetPlacerPreview"
	
	# Apply transparency to all mesh instances
	_apply_preview_transparency_to_children(preview_mesh)
	
	# Add to scene first
	current_scene.add_child(preview_mesh)
	
	# Apply initial transform (after node is in tree)
	preview_mesh.global_position = current_position
	preview_mesh.rotation = current_rotation
	preview_mesh.scale = current_scale
	
	PluginLogger.info("PreviewManager", "Started asset preview for: " + asset_path)

static func _apply_preview_transparency_to_children(node: Node):
	"""Apply transparency to all GeometryInstance3D children (preserves original materials)"""
	if node is GeometryInstance3D:
		# Use transparency property to make it semi-transparent while preserving materials
		node.transparency = 1.0 - preview_opacity  # 0.0 = opaque, 1.0 = fully transparent
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	for child in node.get_children():
		_apply_preview_transparency_to_children(child)

## Preview Updates

static func update_preview_position(position: Vector3):
	"""Update preview position"""
	current_position = position
	if preview_mesh and is_instance_valid(preview_mesh) and preview_mesh.is_inside_tree():
		preview_mesh.global_position = position

static func update_preview_rotation(rotation: Vector3):
	"""Update preview rotation"""
	current_rotation = rotation
	if preview_mesh and is_instance_valid(preview_mesh) and preview_mesh.is_inside_tree():
		preview_mesh.rotation = rotation

static func update_preview_scale(scale: Vector3):
	"""Update preview scale"""
	current_scale = scale
	if preview_mesh and is_instance_valid(preview_mesh) and preview_mesh.is_inside_tree():
		preview_mesh.scale = scale

static func update_preview_transform(position: Vector3, rotation: Vector3, scale: Vector3):
	"""Update all preview transform components at once"""
	current_position = position
	current_rotation = rotation
	current_scale = scale
	
	if preview_mesh and is_instance_valid(preview_mesh) and preview_mesh.is_inside_tree():
		preview_mesh.global_position = position
		preview_mesh.rotation = rotation
		preview_mesh.scale = scale

## Preview State Queries

static func has_preview() -> bool:
	"""Check if there's an active preview"""
	return preview_mesh != null and is_instance_valid(preview_mesh) and preview_mesh.is_inside_tree()

static func get_preview_position() -> Vector3:
	"""Get current preview position"""
	if has_preview() and preview_mesh.is_inside_tree():
		return preview_mesh.global_position
	return current_position

static func get_preview_rotation() -> Vector3:
	"""Get current preview rotation"""
	if has_preview():
		return preview_mesh.rotation
	return current_rotation

static func get_preview_scale() -> Vector3:
	"""Get current preview scale"""
	if has_preview():
		return preview_mesh.scale
	return current_scale

static func get_preview_transform() -> Transform3D:
	"""Get current preview transform"""
	if has_preview():
		return preview_mesh.transform
	return Transform3D()

## Preview Visibility and Appearance

static func set_preview_visibility(visible: bool):
	"""Set preview visibility"""
	if preview_mesh and is_instance_valid(preview_mesh):
		preview_mesh.visible = visible

static func set_preview_opacity(opacity: float):
	"""Set preview opacity"""
	preview_opacity = clampf(opacity, 0.0, 1.0)
	
	if preview_material:
		preview_material.albedo_color.a = preview_opacity
	
	PluginLogger.debug("PreviewManager", "Set preview opacity to " + str(preview_opacity))

static func set_preview_color(color: Color):
	"""Set preview color tint"""
	preview_color = color
	
	if preview_material:
		preview_material.albedo_color = Color(color.r, color.g, color.b, preview_opacity)
	
	PluginLogger.debug("PreviewManager", "Set preview color to " + str(color))

## Preview Cleanup

static func cleanup_preview():
	"""Clean up the current preview"""
	if preview_mesh and is_instance_valid(preview_mesh):
		preview_mesh.queue_free()
		preview_mesh = null
		PluginLogger.debug("PreviewManager", "Cleaned up preview")

## Configuration

static func configure(settings: Dictionary):
	"""Configure preview manager with settings"""
	if settings.has("preview_opacity"):
		set_preview_opacity(settings.preview_opacity)
	
	if settings.has("preview_color"):
		set_preview_color(settings.preview_color)
	
	# Recreate material with new settings
	if preview_material:
		preview_material.queue_free()
		preview_material = null

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"preview_opacity": preview_opacity,
		"preview_color": preview_color,
		"has_preview": has_preview()
	}

## Utility Functions

static func get_preview_bounds() -> AABB:
	"""Get preview bounding box"""
	if has_preview() and preview_mesh.mesh:
		var aabb = preview_mesh.mesh.get_aabb()
		# Transform AABB by the preview's transform
		return aabb.transformed(preview_mesh.transform)
	return AABB()

static func is_preview_in_camera_view(camera: Camera3D) -> bool:
	"""Check if preview is visible in camera view"""
	if not has_preview() or not camera:
		return false
	
	var bounds = get_preview_bounds()
	# Simple distance check (could be enhanced with proper frustum testing)
	var distance = camera.global_position.distance_to(bounds.get_center())
	return distance < 1000.0  # Reasonable view distance

## Debug and Information

static func debug_print_preview_state():
	"""Print current preview state for debugging"""
	PluginLogger.debug("PreviewManager", "PreviewManager State:")
	PluginLogger.debug("PreviewManager", "  Has Preview: " + str(has_preview()))
	PluginLogger.debug("PreviewManager", "  Position: " + str(current_position))
	PluginLogger.debug("PreviewManager", "  Rotation: " + str(current_rotation))
	PluginLogger.debug("PreviewManager", "  Scale: " + str(current_scale))
	PluginLogger.debug("PreviewManager", "  Opacity: " + str(preview_opacity))
	PluginLogger.debug("PreviewManager", "  Color: " + str(preview_color))

static func get_preview_info() -> Dictionary:
	"""Get comprehensive preview information"""
	return {
		"has_preview": has_preview(),
		"position": get_preview_position(),
		"rotation": get_preview_rotation(),
		"scale": get_preview_scale(),
		"opacity": preview_opacity,
		"color": preview_color,
		"bounds": get_preview_bounds() if has_preview() else AABB()
	}