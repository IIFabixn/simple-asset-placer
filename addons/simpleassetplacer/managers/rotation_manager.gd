@tool
extends RefCounted

class_name RotationManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
3D ROTATION CALCULATIONS SERVICE (REFACTORED - STATELESS)
=========================================================

PURPOSE: Pure rotation calculation service working with TransformState.

RESPONSIBILITIES:
- Rotation step calculations (X, Y, Z axis rotations)
- Surface alignment calculations
- Rotation normalization utilities
- Conversion between radians and degrees

ARCHITECTURE POSITION: Pure calculation service with NO state storage
- Does NOT store rotation state (uses TransformState)
- Does NOT handle input detection
- Does NOT handle UI or feedback
- Does NOT know about placement/transform modes
- Focused solely on rotation math

REFACTORED: State moved to TransformState, application moved to TransformApplicator

USED BY: TransformationManager for rotation calculations
DEPENDS ON: TransformState, IncrementCalculator, Godot math
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const IncrementCalculator = preload("res://addons/simpleassetplacer/utils/increment_calculator.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

## Configuration

func configure(state: TransformState, settings: Dictionary):
	"""Configure rotation manager with settings"""
	# Handle smooth transform settings
	if settings.has("smooth_enabled") and settings.has("smooth_speed"):
		_services.smooth_transform_manager.configure(settings.smooth_enabled, settings.smooth_speed)
	
	# Handle initial rotation
	if settings.has("initial_rotation"):
		var initial = settings.initial_rotation
		if initial is Vector3:
			set_rotation_offset_degrees(state, initial)

## Core Rotation Functions

func set_rotation_offset(state: TransformState, rotation: Vector3):
	"""Set manual rotation offset (in radians)"""
	state.values.manual_rotation_offset = rotation
	_normalize_rotation(state)

func set_rotation_offset_degrees(state: TransformState, rotation_degrees: Vector3):
	"""Set manual rotation offset (in degrees)"""
	state.values.manual_rotation_offset = Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)
	_normalize_rotation(state)

func get_rotation_offset(state: TransformState) -> Vector3:
	"""Get current manual rotation offset in radians"""
	return state.values.manual_rotation_offset

func get_rotation_offset_degrees(state: TransformState) -> Vector3:
	"""Get current manual rotation offset in degrees"""
	return Vector3(
		rad_to_deg(state.values.manual_rotation_offset.x),
		rad_to_deg(state.values.manual_rotation_offset.y),
		rad_to_deg(state.values.manual_rotation_offset.z)
	)

func get_current_rotation(state: TransformState) -> Vector3:
	"""Return combined surface alignment and manual rotation."""
	if not state:
		return Vector3.ZERO
	return state.values.surface_alignment_rotation + state.values.manual_rotation_offset

func reset_rotation(state: TransformState):
	"""Reset manual rotation offset to zero (keeps surface alignment)"""
	state.values.manual_rotation_offset = Vector3.ZERO
	PluginLogger.debug("RotationManager", "Manual rotation offset reset to zero")

func reset_surface_alignment(state: TransformState):
	"""Reset surface alignment rotation to zero"""
	state.values.surface_alignment_rotation = Vector3.ZERO

func reset_all_rotation(state: TransformState):
	"""Reset both manual offset and surface alignment rotation"""
	state.values.manual_rotation_offset = Vector3.ZERO
	state.values.surface_alignment_rotation = Vector3.ZERO
	PluginLogger.debug("RotationManager", "All rotation reset to zero")

## Rotation Modifications

func rotate_x(state: TransformState, degrees: float):
	"""Rotate around X axis by degrees"""
	state.values.manual_rotation_offset.x += deg_to_rad(degrees)
	_normalize_rotation(state)

func rotate_y(state: TransformState, degrees: float):
	"""Rotate around Y axis by degrees"""
	state.values.manual_rotation_offset.y += deg_to_rad(degrees)
	_normalize_rotation(state)

func rotate_z(state: TransformState, degrees: float):
	"""Rotate around Z axis by degrees"""
	state.values.manual_rotation_offset.z += deg_to_rad(degrees)
	_normalize_rotation(state)

func rotate_axis(state: TransformState, axis: String, degrees: float):
	"""Rotate around specified axis by degrees"""
	match axis.to_upper():
		"X":
			rotate_x(state, degrees)
		"Y":
			rotate_y(state, degrees)
		"Z":
			rotate_z(state, degrees)
		_:
			PluginLogger.warning("RotationManager", "Invalid axis: " + axis)

func rotate_axis_with_modifiers(state: TransformState, axis: String, base_degrees: float, modifiers: Dictionary):
	"""Rotate around specified axis with modifier-adjusted step
	
	Args:
		state: TransformState to modify
		axis: Rotation axis ("X", "Y", or "Z")
		base_degrees: Base rotation step in degrees
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step_degrees = IncrementCalculator.calculate_rotation_step(base_degrees, modifiers)
	rotate_axis(state, axis, step_degrees)

func add_rotation(state: TransformState, delta_rotation: Vector3):
	"""Add a rotation delta (in radians)"""
	state.values.manual_rotation_offset += delta_rotation
	_normalize_rotation(state)

func add_rotation_degrees(state: TransformState, delta_rotation_degrees: Vector3):
	"""Add a rotation delta (in degrees)"""
	add_rotation(state, Vector3(
		deg_to_rad(delta_rotation_degrees.x),
		deg_to_rad(delta_rotation_degrees.y),
		deg_to_rad(delta_rotation_degrees.z)
	))

func align_with_surface_normal(state: TransformState, surface_normal: Vector3):
	"""Calculate rotation to align object's up vector with surface normal
	This creates a BASE rotation where the object's Y-axis points along the surface normal.
	User manual rotations are applied ON TOP of this base rotation."""
	
	# Normalize the surface normal
	var normal = surface_normal.normalized()
	
	# Use Godot's built-in method to align the Y-axis with the normal
	# We need to use align_with_y which rotates the basis so Y points in the given direction
	var basis = Basis()
	
	# Method 1: Use looking_at but swap the axes
	# The default "up" for looking_at is Y, but we want Y to point along the normal
	# So we use a trick: look at a point in the normal direction, using a perpendicular up vector
	
	# Find a perpendicular vector to use as "up" for the looking_at
	var reference_up = Vector3.UP
	if abs(normal.dot(reference_up)) > 0.99:  # Nearly parallel to world up
		reference_up = Vector3.FORWARD
	
	# Create a basis using the normal as the Y-axis
	# looking_at expects: target position, up vector
	# But we want to align Y with normal, so we use a different approach
	
	# Better method: Use the from_euler after calculating proper rotation
	# Calculate rotation needed to rotate from UP to the normal
	var rotation_axis = Vector3.UP.cross(normal)
	var rotation_angle = Vector3.UP.angle_to(normal)
	
	if rotation_axis.length_squared() > 0.0001:  # Not parallel
		rotation_axis = rotation_axis.normalized()
		basis = basis.rotated(rotation_axis, rotation_angle)
	elif normal.dot(Vector3.UP) < 0:  # Pointing down
		# 180 degree rotation around X axis
		basis = basis.rotated(Vector3.RIGHT, PI)
	
	# Extract Euler angles from the basis and store as SURFACE ALIGNMENT (base rotation)
	# This does NOT overwrite the user's manual rotation
	state.values.surface_alignment_rotation = basis.get_euler()
	_normalize_surface_rotation(state)

func reset_node_rotation(node: Node3D):
	"""Reset a node's rotation to zero"""
	if node:
		node.rotation = Vector3.ZERO
		PluginLogger.debug("RotationManager", "Reset rotation for node: " + node.name)

func lerp_to_rotation(state: TransformState, target_rotation: Vector3, weight: float):
	"""Smoothly interpolate to a target rotation offset"""
	state.values.manual_rotation_offset = state.values.manual_rotation_offset.lerp(target_rotation, weight)

## Utility Functions

func _normalize_rotation(state: TransformState):
	"""Keep rotation offset values within reasonable bounds"""
	state.values.manual_rotation_offset.x = fmod(state.values.manual_rotation_offset.x, TAU)  # TAU = 2 * PI
	state.values.manual_rotation_offset.y = fmod(state.values.manual_rotation_offset.y, TAU)
	state.values.manual_rotation_offset.z = fmod(state.values.manual_rotation_offset.z, TAU)

func _normalize_surface_rotation(state: TransformState):
	"""Keep surface alignment rotation values within reasonable bounds"""
	state.values.surface_alignment_rotation.x = fmod(state.values.surface_alignment_rotation.x, TAU)
	state.values.surface_alignment_rotation.y = fmod(state.values.surface_alignment_rotation.y, TAU)
	state.values.surface_alignment_rotation.z = fmod(state.values.surface_alignment_rotation.z, TAU)

func _normalize_rotation_degrees(rotation_degrees: Vector3) -> Vector3:
	"""Normalize rotation degrees to 0-360 range"""
	return Vector3(
		fmod(rotation_degrees.x + 360.0, 360.0),
		fmod(rotation_degrees.y + 360.0, 360.0),
		fmod(rotation_degrees.z + 360.0, 360.0)
	)

## Rotation Queries

func is_rotation_zero(state: TransformState) -> bool:
	"""Check if rotation offset is at zero"""
	return state.values.manual_rotation_offset.length_squared() < 0.001

func get_rotation_magnitude(state: TransformState) -> float:
	"""Get the magnitude of current rotation offset"""
	return state.values.manual_rotation_offset.length()

func get_euler_angles(state: TransformState) -> Vector3:
	"""Get rotation offset as Euler angles (alias for get_rotation_offset)"""
	return get_rotation_offset(state)

## Rotation Presets

func set_rotation_preset(state: TransformState, preset_name: String):
	"""Set rotation offset to a common preset"""
	match preset_name.to_lower():
		"identity", "zero":
			reset_rotation(state)
		"90x":
			set_rotation_offset_degrees(state, Vector3(90, 0, 0))
		"90y":
			set_rotation_offset_degrees(state, Vector3(0, 90, 0))
		"90z":
			set_rotation_offset_degrees(state, Vector3(0, 0, 90))
		"180x":
			set_rotation_offset_degrees(state, Vector3(180, 0, 0))
		"180y":
			set_rotation_offset_degrees(state, Vector3(0, 180, 0))
		"180z":
			set_rotation_offset_degrees(state, Vector3(0, 0, 180))
		_:
			PluginLogger.warning("RotationManager", "Unknown preset: " + preset_name)

## Configuration and Settings

func get_configuration(state: TransformState) -> Dictionary:
	"""Get current configuration"""
	return {
		"current_rotation_offset_degrees": get_rotation_offset_degrees(state),
		"current_rotation_offset_radians": get_rotation_offset(state)
	}

## Debug and Information

func debug_print_rotation(state: TransformState):
	"""Print current rotation state for debugging"""
	var rot_deg = get_rotation_offset_degrees(state)
	PluginLogger.debug("RotationManager", "RotationManager State:")
	PluginLogger.debug("RotationManager", "  Rotation Offset (degrees): X:%.1f Y:%.1f Z:%.1f" % [rot_deg.x, rot_deg.y, rot_deg.z])
	PluginLogger.debug("RotationManager", "  Rotation Offset (radians): X:%.3f Y:%.3f Z:%.3f" % [state.values.manual_rotation_offset.x, state.values.manual_rotation_offset.y, state.values.manual_rotation_offset.z])
	PluginLogger.debug("RotationManager", "  Magnitude: %.3f" % get_rotation_magnitude(state))

func get_rotation_info(state: TransformState) -> Dictionary:
	"""Get comprehensive rotation information"""
	return {
		"rotation_offset_radians": state.values.manual_rotation_offset,
		"rotation_offset_degrees": get_rotation_offset_degrees(state),
		"magnitude": get_rotation_magnitude(state),
		"is_zero": is_rotation_zero(state)
	}







