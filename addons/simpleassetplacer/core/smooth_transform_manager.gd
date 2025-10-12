@tool
extends RefCounted

class_name SmoothTransformManager

"""
SMOOTH TRANSFORMATION MANAGER
=============================

PURPOSE: Handles smooth interpolation/lerping of object transformations for a more polished feel.

RESPONSIBILITIES:
- Manages smooth position, rotation, and scale interpolation
- Provides configurable interpolation speed and easing
- Tracks multiple objects with independent smooth transforms
- Handles both preview objects and placed objects in transform mode

ARCHITECTURE POSITION: Pure interpolation logic with no dependencies
- Does NOT handle input detection 
- Does NOT handle positioning math (receives target transforms)
- Focused solely on smooth transformation interpolation

USED BY: PreviewManager and TransformationManager
DEPENDS ON: Godot's Tween system and Transform3D math
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# Smooth transform data for each object
static var _smooth_data: Dictionary = {}

# Settings cache
static var _smooth_enabled: bool = true
static var _smooth_speed: float = 8.0

# Smooth transform data structure
class SmoothTransform:
	var node: Node3D
	var target_position: Vector3
	var target_rotation: Vector3
	var target_scale: Vector3
	var is_lerping: bool = false
	
	func _init(p_node: Node3D):
		node = p_node
		if node and node.is_inside_tree():
			target_position = node.global_position
			target_rotation = node.rotation
			target_scale = node.scale

## CONFIGURATION

static func configure(smooth_enabled_or_settings, smooth_speed: float = 8.0):
	"""Configure smooth transformation settings
	
	Can be called two ways:
	1. configure(settings: Dictionary) - Recommended
	2. configure(enabled: bool, speed: float) - Legacy
	"""
	var enabled: bool
	var speed: float
	
	# Handle Dictionary input (new standardized way)
	if smooth_enabled_or_settings is Dictionary:
		var settings: Dictionary = smooth_enabled_or_settings
		enabled = settings.get("smooth_enabled", _smooth_enabled)
		speed = settings.get("smooth_speed", _smooth_speed)
	# Handle legacy boolean + float input
	else:
		enabled = smooth_enabled_or_settings
		speed = smooth_speed
	
	var was_enabled = _smooth_enabled
	_smooth_enabled = enabled
	_smooth_speed = clamp(speed, 0.1, 50.0)  # Safety clamps
	
	# If smooth transforms were just disabled, snap all objects to their targets
	if was_enabled and not enabled:
		force_update_to_targets()

static func load_from_editor_settings():
	"""Load settings from Godot's EditorSettings"""
	if not Engine.is_editor_hint():
		return
		
	var editor_settings = EditorInterface.get_editor_settings()
	if not editor_settings:
		return
	
	# Load smooth transforms settings
	var smooth_enabled = true  # Default
	var smooth_speed = 8.0     # Default
	
	if editor_settings.has_setting("simple_asset_placer/smooth_transforms"):
		smooth_enabled = editor_settings.get_setting("simple_asset_placer/smooth_transforms")
	
	if editor_settings.has_setting("simple_asset_placer/smooth_transform_speed"):
		smooth_speed = editor_settings.get_setting("simple_asset_placer/smooth_transform_speed")
	
	configure(smooth_enabled, smooth_speed)

## OBJECT REGISTRATION

static func register_object(node: Node3D) -> bool:
	"""Register an object for smooth transformations"""
	if not node or not node.is_inside_tree():
		return false
	
	var node_id = node.get_instance_id()
	if not _smooth_data.has(node_id):
		_smooth_data[node_id] = SmoothTransform.new(node)
		PluginLogger.info("SmoothTransformManager", "Registered object: " + str(node.name))
	
	return true

static func unregister_object(node: Node3D):
	"""Unregister an object from smooth transformations"""
	if not node:
		return
		
	var node_id = node.get_instance_id()
	if _smooth_data.has(node_id):
		_smooth_data.erase(node_id)
		PluginLogger.info("SmoothTransformManager", "Unregistered object: " + str(node.name))

static func clear_all_objects():
	"""Clear all registered objects"""
	_smooth_data.clear()
	PluginLogger.info("SmoothTransformManager", "Cleared all smooth transform objects")

static func cleanup():
	"""Cleanup static resources (called on plugin disable)"""
	clear_all_objects()
	PluginLogger.debug("SmoothTransformManager", "Cleanup completed")

## TRANSFORM UPDATES

static func set_target_position(node: Node3D, position: Vector3):
	"""Set target position for smooth interpolation"""
	if not _smooth_enabled or not node or not node.is_inside_tree():
		# Apply directly if smooth transforms disabled or node invalid
		if node and node.is_inside_tree():
			node.global_position = position
		return
	
	var node_id = node.get_instance_id()
	if not _smooth_data.has(node_id):
		register_object(node)
	
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		smooth_data.target_position = position
		smooth_data.is_lerping = true

static func set_target_rotation(node: Node3D, rotation: Vector3):
	"""Set target rotation for smooth interpolation"""
	if not _smooth_enabled or not node or not node.is_inside_tree():
		# Apply directly if smooth transforms disabled or node invalid
		if node and node.is_inside_tree():
			node.rotation = rotation
		return
	
	var node_id = node.get_instance_id()
	if not _smooth_data.has(node_id):
		register_object(node)
	
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		smooth_data.target_rotation = rotation
		smooth_data.is_lerping = true

static func set_target_scale(node: Node3D, scale: Vector3):
	"""Set target scale for smooth interpolation"""
	if not _smooth_enabled or not node or not node.is_inside_tree():
		# Apply directly if smooth transforms disabled or node invalid
		if node and node.is_inside_tree():
			node.scale = scale
		return
	
	var node_id = node.get_instance_id()
	if not _smooth_data.has(node_id):
		register_object(node)
	
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		smooth_data.target_scale = scale
		smooth_data.is_lerping = true

static func set_target_transform(node: Node3D, position: Vector3, rotation: Vector3, scale: Vector3):
	"""Set all target transform components at once"""
	if not _smooth_enabled or not node or not node.is_inside_tree():
		# Apply directly if smooth transforms disabled or node invalid
		if node and node.is_inside_tree():
			node.global_position = position
			node.rotation = rotation
			node.scale = scale
		return
	
	var node_id = node.get_instance_id()
	if not _smooth_data.has(node_id):
		register_object(node)
	
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		smooth_data.target_position = position
		smooth_data.target_rotation = rotation
		smooth_data.target_scale = scale
		smooth_data.is_lerping = true

static func apply_transform_immediately(node: Node3D, position: Vector3, rotation: Vector3, scale: Vector3):
	"""Apply transform immediately without smoothing (for initialization)"""
	if not node or not node.is_inside_tree():
		return
	
	node.global_position = position
	node.rotation = rotation
	node.scale = scale
	
	# Update smooth data if registered
	var node_id = node.get_instance_id()
	if _smooth_data.has(node_id):
		var smooth_data = _smooth_data.get(node_id)
		smooth_data.target_position = position
		smooth_data.target_rotation = rotation
		smooth_data.target_scale = scale
		smooth_data.is_lerping = false

static func force_update_to_targets():
	"""Force all objects to immediately snap to their target transforms (useful when disabling smoothing)"""
	for node_id in _smooth_data.keys():
		var smooth_data = _smooth_data[node_id]
		
		# Check if node is still valid
		if not smooth_data.node or not is_instance_valid(smooth_data.node) or not smooth_data.node.is_inside_tree():
			continue
		
		# Snap to target
		smooth_data.node.global_position = smooth_data.target_position
		smooth_data.node.rotation = smooth_data.target_rotation
		smooth_data.node.scale = smooth_data.target_scale
		smooth_data.is_lerping = false

## INTERPOLATION UPDATE

static func update_smooth_transforms(delta: float):
	"""Update all smooth transformations - call this every frame"""
	if not _smooth_enabled:
		return
	
	var nodes_to_remove = []
	
	for node_id in _smooth_data.keys():
		var smooth_data = _smooth_data[node_id]
		
		# Check if node is still valid
		if not smooth_data.node or not is_instance_valid(smooth_data.node) or not smooth_data.node.is_inside_tree():
			nodes_to_remove.append(node_id)
			continue
		
		if not smooth_data.is_lerping:
			continue
		
		var node = smooth_data.node
		var lerp_speed = _smooth_speed * delta
		
		# Smooth position
		var current_pos = node.global_position
		var new_pos = current_pos.lerp(smooth_data.target_position, lerp_speed)
		node.global_position = new_pos
		
		# Smooth rotation (using lerp_angle for each component to handle wrapping)
		var current_rot = node.rotation
		var new_rot = Vector3(
			lerp_angle(current_rot.x, smooth_data.target_rotation.x, lerp_speed),
			lerp_angle(current_rot.y, smooth_data.target_rotation.y, lerp_speed),
			lerp_angle(current_rot.z, smooth_data.target_rotation.z, lerp_speed)
		)
		node.rotation = new_rot
		
		# Smooth scale
		var current_scale = node.scale
		var new_scale = current_scale.lerp(smooth_data.target_scale, lerp_speed)
		node.scale = new_scale
		
		# Check if we're close enough to target (stop lerping to prevent infinite micro-adjustments)
		var pos_diff = new_pos.distance_to(smooth_data.target_position)
		var rot_diff = new_rot.distance_to(smooth_data.target_rotation)
		var scale_diff = new_scale.distance_to(smooth_data.target_scale)
		
		if pos_diff < 0.001 and rot_diff < 0.001 and scale_diff < 0.001:
			# Snap to exact target and stop lerping
			node.global_position = smooth_data.target_position
			node.rotation = smooth_data.target_rotation
			node.scale = smooth_data.target_scale
			smooth_data.is_lerping = false
	
	# Remove invalid nodes
	for node_id in nodes_to_remove:
		_smooth_data.erase(node_id)

## UTILITY FUNCTIONS

static func is_smooth_transforms_enabled() -> bool:
	"""Check if smooth transforms are currently enabled"""
	return _smooth_enabled

static func is_object_lerping(node: Node3D) -> bool:
	"""Check if an object is currently lerping"""
	if not node:
		return false
	
	var node_id = node.get_instance_id()
	var smooth_data = _smooth_data.get(node_id)
	return smooth_data != null and smooth_data.is_lerping

static func get_target_position(node: Node3D) -> Vector3:
	"""Get the target position for an object"""
	if not node:
		return Vector3.ZERO
	
	var node_id = node.get_instance_id()
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		return smooth_data.target_position
	return node.global_position if node.is_inside_tree() else Vector3.ZERO

static func get_target_rotation(node: Node3D) -> Vector3:
	"""Get the target rotation for an object"""
	if not node:
		return Vector3.ZERO
	
	var node_id = node.get_instance_id()
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		return smooth_data.target_rotation
	return node.rotation if node.is_inside_tree() else Vector3.ZERO

static func get_target_scale(node: Node3D) -> Vector3:
	"""Get the target scale for an object"""
	if not node:
		return Vector3.ONE
	
	var node_id = node.get_instance_id()
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		return smooth_data.target_scale
	return node.scale if node.is_inside_tree() else Vector3.ONE

static func stop_lerping(node: Node3D):
	"""Stop lerping for a specific object"""
	if not node:
		return
	
	var node_id = node.get_instance_id()
	var smooth_data = _smooth_data.get(node_id)
	if smooth_data:
		smooth_data.is_lerping = false






