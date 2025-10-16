@tool
extends RefCounted

class_name TransformState

"""
UNIFIED TRANSFORM STATE DATA CLASS
==================================

PURPOSE: Single source of truth for all transform-related state data.

RESPONSIBILITIES:
- Store position, rotation, scale state
- Store transform offsets (manual adjustments)
- Store surface alignment data
- Store grid/snap configuration
- Provide reset operations
- Serialize/deserialize state

ARCHITECTURE POSITION: Pure data container with no business logic
- Does NOT handle calculations (delegates to calculators)
- Does NOT handle application (delegates to TransformApplicator)
- Does NOT handle input (delegates to InputHandler)

REPLACES: Scattered static variables from PositionManager, RotationManager, ScaleManager

USED BY: TransformationManager, all transform systems
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

## POSITION STATE

var position: Vector3 = Vector3.ZERO  # Current calculated position
var target_position: Vector3 = Vector3.ZERO  # Target for smooth interpolation
var base_height: float = 0.0  # Base height from raycast (before offset)
var height_offset: float = 0.0  # Manual height adjustment
var manual_position_offset: Vector3 = Vector3.ZERO  # WASD position adjustments
var is_initial_position: bool = true  # First position update flag
var last_raycast_xz: Vector2 = Vector2.ZERO  # Track XZ position changes

## ROTATION STATE

var manual_rotation_offset: Vector3 = Vector3.ZERO  # Manual rotation in radians
var surface_alignment_rotation: Vector3 = Vector3.ZERO  # Base rotation from surface normal
var surface_normal: Vector3 = Vector3.UP  # Current surface normal

## SCALE STATE

var scale_multiplier: float = 1.0  # Uniform scale multiplier
var non_uniform_multiplier: Vector3 = Vector3.ONE  # Non-uniform scale per axis

## GRID/SNAP CONFIGURATION

var snap_enabled: bool = false
var snap_step: float = 1.0
var snap_offset: Vector3 = Vector3.ZERO
var snap_y_enabled: bool = false
var snap_y_step: float = 1.0
var snap_center_x: bool = false
var snap_center_y: bool = false
var snap_center_z: bool = false
var use_half_step: bool = false

# Rotation snap configuration
var snap_rotation_enabled: bool = false
var snap_rotation_step: float = 15.0  # Degrees

# Scale snap configuration
var snap_scale_enabled: bool = false
var snap_scale_step: float = 0.1

## PLACEMENT CONFIGURATION

var align_with_normal: bool = false  # Align rotation with surface
var collision_mask: int = 1  # Physics collision layer
var height_step_size: float = 0.1  # Height adjustment step

## CONSTRUCTOR

func _init():
	"""Initialize with default values"""
	reset_all()

## RESET OPERATIONS

func reset_position():
	"""Reset position and position offsets"""
	manual_position_offset = Vector3.ZERO
	height_offset = 0.0
	is_initial_position = true
	last_raycast_xz = Vector2.ZERO
	# Debug logging removed to reduce spam (called frequently during reset cycles)

func reset_rotation():
	"""Reset manual rotation offset (keeps surface alignment)"""
	manual_rotation_offset = Vector3.ZERO
	# Debug logging removed to reduce spam (called frequently during reset cycles)

func reset_surface_alignment():
	"""Reset surface alignment rotation"""
	surface_alignment_rotation = Vector3.ZERO
	surface_normal = Vector3.UP

func reset_all_rotation():
	"""Reset both manual and surface alignment rotation"""
	manual_rotation_offset = Vector3.ZERO
	surface_alignment_rotation = Vector3.ZERO
	surface_normal = Vector3.UP
	# Debug logging removed to reduce spam (called frequently during reset cycles)

func reset_scale():
	"""Reset scale multiplier to 1.0"""
	scale_multiplier = 1.0
	non_uniform_multiplier = Vector3.ONE
	# Debug logging removed to reduce spam (called frequently during reset cycles)

func reset_all():
	"""Reset all transform state to defaults"""
	position = Vector3.ZERO
	target_position = Vector3.ZERO
	base_height = 0.0
	reset_position()
	reset_all_rotation()
	reset_scale()
	# Debug logging removed - this is called from _init() and frequently during normal operation

## GETTERS

func get_final_position() -> Vector3:
	"""Get final position including all offsets"""
	return position + manual_position_offset

func get_final_rotation() -> Vector3:
	"""Get final rotation combining surface alignment and manual offset"""
	return surface_alignment_rotation + manual_rotation_offset

func get_final_rotation_degrees() -> Vector3:
	"""Get final rotation in degrees"""
	var rot = get_final_rotation()
	return Vector3(
		rad_to_deg(rot.x),
		rad_to_deg(rot.y),
		rad_to_deg(rot.z)
	)

func get_scale_vector() -> Vector3:
	"""Get scale as Vector3"""
	return non_uniform_multiplier

## SETTERS WITH VALIDATION

func set_scale_multiplier(multiplier: float):
	"""Set uniform scale multiplier with validation"""
	scale_multiplier = max(0.01, multiplier)  # Prevent zero/negative
	non_uniform_multiplier = Vector3(scale_multiplier, scale_multiplier, scale_multiplier)

func set_non_uniform_scale(scale_vec: Vector3):
	"""Set non-uniform scale with validation"""
	non_uniform_multiplier = Vector3(
		max(0.01, scale_vec.x),
		max(0.01, scale_vec.y),
		max(0.01, scale_vec.z)
	)
	# Update uniform multiplier to average
	scale_multiplier = (non_uniform_multiplier.x + non_uniform_multiplier.y + non_uniform_multiplier.z) / 3.0

func set_rotation_radians(rotation: Vector3):
	"""Set manual rotation in radians"""
	manual_rotation_offset = rotation
	_normalize_rotation()

func set_rotation_degrees(rotation_degrees: Vector3):
	"""Set manual rotation in degrees"""
	manual_rotation_offset = Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)
	_normalize_rotation()

## CONFIGURATION

func configure_from_settings(settings: Dictionary):
	"""Configure state from settings dictionary.

	IMPORTANT: Keys must match SettingMeta ids from settings_definition.gd.
	Older aliases (snap_to_grid, grid_size) are still supported for backward compatibility.
	"""
	# Position snap
	snap_enabled = settings.get("snap_enabled", settings.get("snap_to_grid", false))
	snap_step = settings.get("snap_step", settings.get("grid_size", 1.0))
	snap_offset = settings.get("snap_offset", Vector3.ZERO)
	snap_y_enabled = settings.get("snap_y_enabled", false)
	snap_y_step = settings.get("snap_y_step", 1.0)
	snap_center_x = settings.get("snap_center_x", false)
	snap_center_y = settings.get("snap_center_y", false)
	snap_center_z = settings.get("snap_center_z", false)
	
	# Rotation and scale snap settings
	snap_rotation_enabled = settings.get("snap_rotation_enabled", false)
	snap_rotation_step = settings.get("snap_rotation_step", 15.0)
	snap_scale_enabled = settings.get("snap_scale_enabled", false)
	snap_scale_step = settings.get("snap_scale_step", 0.1)
	
	# Debug logging for snap settings
	if snap_rotation_enabled or snap_scale_enabled or snap_enabled:
		PluginLogger.debug("TransformState", "Snap settings | Pos:%s step:%s Rot:%s step:%s Scale:%s step:%s half_step:%s" % [snap_enabled, snap_step, snap_rotation_enabled, snap_rotation_step, snap_scale_enabled, snap_scale_step, use_half_step])
	
	var align_normal_setting = settings.get("align_with_normal")
	if align_normal_setting == null:
		align_normal_setting = settings.get("use_surface_normal", false)
	align_with_normal = bool(align_normal_setting)
	collision_mask = settings.get("collision_mask", 1)
	height_step_size = settings.get("height_step_size", 0.1)

func reset_for_new_placement(reset_height: bool = false, reset_position_offset: bool = false):
	"""Reset state for new placement with optional selective resets"""
	is_initial_position = true
	last_raycast_xz = Vector2.ZERO
	position = Vector3.ZERO
	target_position = Vector3.ZERO
	
	if reset_height:
		height_offset = 0.0
		base_height = 0.0
	
	if reset_position_offset:
		manual_position_offset = Vector3.ZERO

## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize state to dictionary"""
	return {
		"position": position,
		"height_offset": height_offset,
		"manual_position_offset": manual_position_offset,
		"manual_rotation_offset": manual_rotation_offset,
		"surface_alignment_rotation": surface_alignment_rotation,
		"scale_multiplier": scale_multiplier,
		"non_uniform_multiplier": non_uniform_multiplier,
	}

func from_dictionary(data: Dictionary):
	"""Deserialize state from dictionary"""
	position = data.get("position", Vector3.ZERO)
	height_offset = data.get("height_offset", 0.0)
	manual_position_offset = data.get("manual_position_offset", Vector3.ZERO)
	manual_rotation_offset = data.get("manual_rotation_offset", Vector3.ZERO)
	surface_alignment_rotation = data.get("surface_alignment_rotation", Vector3.ZERO)
	scale_multiplier = data.get("scale_multiplier", 1.0)
	non_uniform_multiplier = data.get("non_uniform_multiplier", Vector3.ONE)

## INTERNAL HELPERS

func _normalize_rotation():
	"""Normalize rotation angles to valid range"""
	manual_rotation_offset.x = fposmod(manual_rotation_offset.x, TAU)
	manual_rotation_offset.y = fposmod(manual_rotation_offset.y, TAU)
	manual_rotation_offset.z = fposmod(manual_rotation_offset.z, TAU)







