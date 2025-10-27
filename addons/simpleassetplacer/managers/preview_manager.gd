@tool
extends RefCounted

class_name PreviewManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

"""
PREVIEW MESH MANAGEMENT SYSTEM
==============================

PURPOSE: Handles creation, styling, and lifecycle management of preview meshes during placement mode.

RESPONSIBILITIES:  
- Preview mesh creation from various asset types (Mesh, PackedScene, asset paths)
- Preview material application (semi-transparent, no shadows)
- Preview position updates and synchronization (with optional smooth interpolation)
- Asset loading and instantiation for previews
- Preview cleanup and memory management
- Material application to complex node hierarchies

ARCHITECTURE POSITION: Pure preview mesh logic with no dependencies
- Does NOT handle input detection (receives update requests)
- Does NOT handle positioning math (receives positions to apply)
- Does NOT handle UI overlays
- Focused solely on preview mesh lifecycle

USED BY: TransformationManager for placement mode preview operations  
DEPENDS ON: Godot scene system, material system, resource loading, SmoothTransformManager
"""

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === INSTANCE VARIABLES ===

# Preview state
var _preview_mesh: Node3D = null
var _preview_material: StandardMaterial3D = null
var _current_position: Vector3 = Vector3.ZERO
var _current_rotation: Vector3 = Vector3.ZERO
var _current_scale: Vector3 = Vector3.ONE

# Preview configuration
var _preview_opacity: float = 0.6
var _preview_color: Color = Color.WHITE

## Configuration

func configure(settings: Dictionary) -> void:
	"""Configure preview manager with settings"""
	# Handle preview appearance settings
	if settings.has("preview_opacity"):
		set_preview_opacity(settings.preview_opacity)
	
	if settings.has("preview_color"):
		set_preview_color(settings.preview_color)
	
	# Recreate material with new settings if it exists
	if _preview_material and (settings.has("preview_opacity") or settings.has("preview_color")):
		_preview_material.queue_free()
		_preview_material = null

## Preview Creation

func start_preview_mesh(mesh: Mesh, settings: Dictionary = {}) -> void:
	"""Start preview with a mesh"""
	if not mesh or not is_instance_valid(mesh):
		PluginLogger.error("PreviewManager", "Cannot start preview - invalid mesh provided")
		return
	
	cleanup_preview()
	
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if not current_scene or not is_instance_valid(current_scene):
		PluginLogger.error("PreviewManager", "No valid scene available for preview")
		return
	
	# Create preview mesh instance
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.mesh = mesh
	# Don't override materials - preserve original mesh appearance
	# Instead, use transparency property to make it semi-transparent
	# Apply transparency to mesh
	_preview_mesh.transparency = 1.0 - _preview_opacity  # transparency: 0.0 = opaque, 1.0 = fully transparent
	_preview_mesh.name = "AssetPlacerPreview"
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_mesh.layers = 1  # Default render layer
	
	# Disable collision on preview to prevent raycast interference
	_disable_collision_on_preview(_preview_mesh)
	
	# Add to scene first
	current_scene.add_child(_preview_mesh)	# Apply initial transform (after node is in tree)
	_preview_mesh.global_position = _current_position
	_preview_mesh.rotation = _current_rotation
	_preview_mesh.scale = _current_scale
	
	# Register with smooth transform manager for interpolation
	if _services and _services.smooth_transform_manager:
		_services.smooth_transform_manager.register_object(_preview_mesh)
	
	PluginLogger.info("PreviewManager", "Started mesh preview")

func start_preview_asset(asset_path: String, settings: Dictionary = {}) -> void:
	"""Start preview with an asset file"""
	if asset_path == "" or not FileAccess.file_exists(asset_path):
		PluginLogger.error("PreviewManager", "Cannot start preview - invalid asset path: " + asset_path)
		return
	
	if not asset_path.begins_with("res://"):
		PluginLogger.warning("PreviewManager", "Asset path should start with res://: " + asset_path)
	
	var asset = load(asset_path)
	if not asset or not is_instance_valid(asset):
		PluginLogger.error("PreviewManager", "Failed to load asset: " + asset_path)
		return
	
	cleanup_preview()
	
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if not current_scene or not is_instance_valid(current_scene):
		PluginLogger.error("PreviewManager", "No valid scene available for preview")
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
		preview_node.transparency = 1.0 - _preview_opacity
	else:
		PluginLogger.error("PreviewManager", "Unsupported asset type for: " + asset_path)
		return
	
	if not preview_node:
		PluginLogger.error("PreviewManager", "Failed to create preview node from: " + asset_path)
		return
	
	_preview_mesh = preview_node
	_preview_mesh.name = "AssetPlacerPreview"
	
	# Apply transparency to all mesh instances
	_apply_preview_transparency_to_children(_preview_mesh)
	
	# Disable collision on preview to prevent raycast interference
	_disable_collision_on_preview(_preview_mesh)
	
	# Add to scene first
	current_scene.add_child(_preview_mesh)
	
	# Apply initial transform (after node is in tree)
	_preview_mesh.global_position = _current_position
	_preview_mesh.rotation = _current_rotation
	_preview_mesh.scale = _current_scale
	
	# Register with smooth transform manager for interpolation
	if _services and _services.smooth_transform_manager:
		_services.smooth_transform_manager.register_object(_preview_mesh)
	
	PluginLogger.info("PreviewManager", "Started asset preview for: " + asset_path)

func _apply_preview_transparency_to_children(node: Node) -> void:
	"""Apply transparency to all GeometryInstance3D children (preserves original materials)"""
	if node is GeometryInstance3D:
		# Use transparency property to make it semi-transparent while preserving materials
		node.transparency = 1.0 - _preview_opacity  # 0.0 = opaque, 1.0 = fully transparent
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	for child in node.get_children():
		_apply_preview_transparency_to_children(child)

func _disable_collision_on_preview(node: Node) -> void:
	"""Disable collision on all CollisionObject3D nodes in the preview hierarchy"""
	if node is CollisionObject3D:
		# Disable collision detection by setting collision layer and mask to 0
		node.collision_layer = 0
		node.collision_mask = 0
		PluginLogger.debug("PreviewManager", "Disabled collision on preview node: %s" % node.name)
	
	for child in node.get_children():
		_disable_collision_on_preview(child)

## Preview Updates

func update_preview_position(position: Vector3) -> void:
	"""Update preview position"""
	_current_position = position
	if NodeUtils.is_valid_and_in_tree(_preview_mesh):
		_preview_mesh.global_position = position

func update_preview_rotation(rotation: Vector3) -> void:
	"""Update preview rotation"""
	_current_rotation = rotation
	if NodeUtils.is_valid_and_in_tree(_preview_mesh):
		_preview_mesh.rotation = rotation

func update_preview_scale(scale: Vector3) -> void:
	"""Update preview scale"""
	_current_scale = scale
	if NodeUtils.is_valid_and_in_tree(_preview_mesh):
		_preview_mesh.scale = scale

func update_preview_transform(position: Vector3, rotation: Vector3, scale: Vector3) -> void:
	"""Update all preview transform components at once"""
	_current_position = position
	_current_rotation = rotation
	_current_scale = scale
	
	if NodeUtils.is_valid_and_in_tree(_preview_mesh):
		_preview_mesh.global_position = position
		_preview_mesh.rotation = rotation
		_preview_mesh.scale = scale

## Preview State Queries

func has_preview() -> bool:
	"""Check if there's an active preview"""
	return _preview_mesh != null and is_instance_valid(_preview_mesh) and _preview_mesh.is_inside_tree()

func get_preview_mesh() -> Node3D:
	"""Get the preview mesh node"""
	return _preview_mesh

func get_preview_position() -> Vector3:
	"""Get current preview position"""
	if has_preview():
		return _preview_mesh.global_position
	return _current_position

func get_preview_rotation() -> Vector3:
	"""Get current preview rotation"""
	if has_preview():
		return _preview_mesh.rotation
	return _current_rotation

func get_preview_scale() -> Vector3:
	"""Get current preview scale"""
	if has_preview():
		return _preview_mesh.scale
	return _current_scale

func get_preview_transform() -> Transform3D:
	"""Get current preview transform"""
	if has_preview():
		return _preview_mesh.transform
	return Transform3D()

## Preview Visibility and Appearance

func set_preview_visibility(visible: bool) -> void:
	"""Set preview visibility"""
	NodeUtils.safe_set_visible(_preview_mesh, visible)

func set_preview_opacity(opacity: float) -> void:
	"""Set preview opacity"""
	_preview_opacity = clampf(opacity, 0.0, 1.0)
	
	if _preview_material:
		_preview_material.albedo_color.a = _preview_opacity
	
	PluginLogger.debug("PreviewManager", "Set preview opacity to " + str(_preview_opacity))

func set_preview_color(color: Color) -> void:
	"""Set preview color tint"""
	_preview_color = color
	
	if _preview_material:
		_preview_material.albedo_color = Color(color.r, color.g, color.b, _preview_opacity)
	
	PluginLogger.debug("PreviewManager", "Set preview color to " + str(color))

## Preview Cleanup

func cleanup_preview() -> void:
	"""Clean up the current preview"""
	if NodeUtils.is_valid(_preview_mesh):
		# Unregister from smooth transform manager
		if _services and _services.smooth_transform_manager:
			_services.smooth_transform_manager.unregister_object(_preview_mesh)
		_preview_mesh = NodeUtils.cleanup_and_null(_preview_mesh)
		PluginLogger.debug("PreviewManager", "Cleaned up preview")

func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"_preview_opacity": _preview_opacity,
		"_preview_color": _preview_color,
		"has_preview": has_preview()
	}

## Utility Functions

func get_preview_bounds() -> AABB:
	"""Get preview bounding box"""
	if has_preview() and _preview_mesh.mesh:
		var aabb = _preview_mesh.mesh.get_aabb()
		# Transform AABB by the preview's transform
		# In Godot 4.x, we need to manually transform all corners
		if _preview_mesh.transform != Transform3D.IDENTITY:
			# Get all 8 corners
			var corners = [
				aabb.position,
				aabb.position + Vector3(aabb.size.x, 0, 0),
				aabb.position + Vector3(0, aabb.size.y, 0),
				aabb.position + Vector3(0, 0, aabb.size.z),
				aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
				aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
				aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
				aabb.position + aabb.size
			]
			
			# Transform all corners
			var transformed_corners = []
			for corner in corners:
				transformed_corners.append(_preview_mesh.transform * corner)
			
			# Create new AABB from transformed corners
			var result = AABB(transformed_corners[0], Vector3.ZERO)
			for i in range(1, transformed_corners.size()):
				result = result.expand(transformed_corners[i])
			
			return result
		return aabb
	return AABB()

func is_preview_in_camera_view(camera: Camera3D) -> bool:
	"""Check if preview is visible in camera view"""
	if not has_preview() or not camera:
		return false
	
	var bounds = get_preview_bounds()
	# Simple distance check (could be enhanced with proper frustum testing)
	var distance = camera.global_position.distance_to(bounds.get_center())
	return distance < 1000.0  # Reasonable view distance

## Debug and Information

func debug_print_preview_state() -> void:
	"""Print current preview state for debugging"""
	PluginLogger.debug("PreviewManager", "PreviewManager State:")
	PluginLogger.debug("PreviewManager", "  Has Preview: " + str(has_preview()))
	PluginLogger.debug("PreviewManager", "  Position: " + str(_current_position))
	PluginLogger.debug("PreviewManager", "  Rotation: " + str(_current_rotation))
	PluginLogger.debug("PreviewManager", "  Scale: " + str(_current_scale))
	PluginLogger.debug("PreviewManager", "  Opacity: " + str(_preview_opacity))
	PluginLogger.debug("PreviewManager", "  Color: " + str(_preview_color))

func get_preview_info() -> Dictionary:
	"""Get comprehensive preview information"""
	return {
		"has_preview": has_preview(),
		"position": get_preview_position(),
		"rotation": get_preview_rotation(),
		"scale": get_preview_scale(),
		"opacity": _preview_opacity,
		"color": _preview_color,
		"bounds": get_preview_bounds() if has_preview() else AABB()
	}







