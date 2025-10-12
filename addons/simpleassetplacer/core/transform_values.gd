@tool
extends RefCounted

class_name TransformValues

"""
TRANSFORM VALUES
================

PURPOSE: Pure transform data container - position, rotation, scale.

RESPONSIBILITIES:
- Store position components (base, target, current, offsets)
- Store rotation components (manual, surface alignment)
- Store scale values (uniform and non-uniform)
- Provide computed final values
- Reset operations for individual components

ARCHITECTURE POSITION: Pure data class with no business logic
- No calculations (delegates to managers)
- No application (delegates to TransformApplicator)
- No configuration (delegates to PlacementConfig)

USED BY: TransformState (composition), all transform managers
"""

## POSITION COMPONENTS

var position: Vector3 = Vector3.ZERO  # Current calculated position
var target_position: Vector3 = Vector3.ZERO  # Target for smooth interpolation
var base_position: Vector3 = Vector3.ZERO  # Base position from raycast (before offset)
var manual_position_offset: Vector3 = Vector3.ZERO  # General position offset (WASD/QE/XYZ adjustments)

## ROTATION COMPONENTS

var manual_rotation_offset: Vector3 = Vector3.ZERO  # Manual rotation in radians
var surface_alignment_rotation: Vector3 = Vector3.ZERO  # Base rotation from surface normal
var surface_normal: Vector3 = Vector3.UP  # Current surface normal

## SCALE COMPONENTS

var scale_multiplier: float = 1.0  # Uniform scale multiplier
var non_uniform_multiplier: Vector3 = Vector3.ONE  # Non-uniform scale per axis

## COMPUTED VALUES

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


## RESET OPERATIONS

func reset_position() -> void:
	"""Reset position and position offsets"""
	manual_position_offset = Vector3.ZERO


func reset_rotation() -> void:
	"""Reset manual rotation offset (keeps surface alignment)"""
	manual_rotation_offset = Vector3.ZERO


func reset_surface_alignment() -> void:
	"""Reset surface alignment rotation"""
	surface_alignment_rotation = Vector3.ZERO
	surface_normal = Vector3.UP


func reset_all_rotation() -> void:
	"""Reset both manual and surface alignment rotation"""
	manual_rotation_offset = Vector3.ZERO
	surface_alignment_rotation = Vector3.ZERO
	surface_normal = Vector3.UP


func reset_scale() -> void:
	"""Reset scale multiplier to 1.0"""
	scale_multiplier = 1.0
	non_uniform_multiplier = Vector3.ONE


func reset_all() -> void:
	"""Reset all transform values to defaults"""
	position = Vector3.ZERO
	target_position = Vector3.ZERO
	base_position = Vector3.ZERO
	reset_position()
	reset_all_rotation()
	reset_scale()


## SETTERS WITH VALIDATION

func set_scale_multiplier(multiplier: float) -> void:
	"""Set uniform scale multiplier with validation"""
	scale_multiplier = max(0.01, multiplier)  # Prevent zero/negative
	non_uniform_multiplier = Vector3(scale_multiplier, scale_multiplier, scale_multiplier)


func set_non_uniform_scale(scale_vec: Vector3) -> void:
	"""Set non-uniform scale with validation"""
	non_uniform_multiplier = Vector3(
		max(0.01, scale_vec.x),
		max(0.01, scale_vec.y),
		max(0.01, scale_vec.z)
	)
	# Update uniform multiplier to average
	scale_multiplier = (non_uniform_multiplier.x + non_uniform_multiplier.y + non_uniform_multiplier.z) / 3.0


func set_rotation_radians(rotation: Vector3) -> void:
	"""Set manual rotation in radians"""
	manual_rotation_offset = rotation
	_normalize_rotation()


func set_rotation_degrees(rotation_degrees: Vector3) -> void:
	"""Set manual rotation in degrees"""
	manual_rotation_offset = Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)
	_normalize_rotation()


## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize values to dictionary"""
	return {
		"position": position,
		"target_position": target_position,
		"base_position": base_position,
		"manual_position_offset": manual_position_offset,
		"manual_rotation_offset": manual_rotation_offset,
		"surface_alignment_rotation": surface_alignment_rotation,
		"surface_normal": surface_normal,
		"scale_multiplier": scale_multiplier,
		"non_uniform_multiplier": non_uniform_multiplier,
	}


func from_dictionary(data: Dictionary) -> void:
	"""Deserialize values from dictionary"""
	position = data.get("position", Vector3.ZERO)
	target_position = data.get("target_position", Vector3.ZERO)
	base_position = data.get("base_position", Vector3.ZERO)
	manual_position_offset = data.get("manual_position_offset", Vector3.ZERO)
	manual_rotation_offset = data.get("manual_rotation_offset", Vector3.ZERO)
	surface_alignment_rotation = data.get("surface_alignment_rotation", Vector3.ZERO)
	surface_normal = data.get("surface_normal", Vector3.UP)
	scale_multiplier = data.get("scale_multiplier", 1.0)
	non_uniform_multiplier = data.get("non_uniform_multiplier", Vector3.ONE)


## INTERNAL HELPERS

func _normalize_rotation() -> void:
	"""Normalize rotation angles to valid range"""
	manual_rotation_offset.x = fposmod(manual_rotation_offset.x, TAU)
	manual_rotation_offset.y = fposmod(manual_rotation_offset.y, TAU)
	manual_rotation_offset.z = fposmod(manual_rotation_offset.z, TAU)
