@tool
extends RefCounted

class_name RotationManager

"""
3D ROTATION MATHEMATICS SYSTEM
==============================

PURPOSE: Handles all rotation calculations and transformations with optional smooth interpolation.

RESPONSIBILITIES:
- Rotation state management (current rotation in radians/degrees)
- Rotation step application (X, Y, Z axis rotations)
- Rotation normalization (keeping angles in valid ranges)
- Node rotation application and copying (with optional smooth transforms)
- Rotation reset functionality
- Conversion between radians and degrees
- Surface alignment rotation (base rotation from surface normal)

ARCHITECTURE POSITION: Pure rotation math with optional smooth transform integration
- Does NOT handle input detection (receives rotation commands)
- Does NOT handle UI or feedback
- Does NOT know about placement/transform modes
- Works with any Node3D object

USED BY: TransformationManager for all rotation operations
DEPENDS ON: Godot math system (Vector3, Transform3D), SmoothTransformManager (optional)
"""

# Import smooth transform system for optional smooth rotation
const SmoothTransformManager = preload("res://addons/simpleassetplacer/smooth_transform_manager.gd")

# Current rotation state
static var manual_rotation_offset: Vector3 = Vector3.ZERO  # Manual rotation offset in radians (user input)
static var surface_alignment_rotation: Vector3 = Vector3.ZERO  # Base rotation from surface normal

## Configuration

static func configure_smooth_transforms(enabled: bool, speed: float = 8.0):
	"""Configure smooth transform settings for rotation"""
	# No local caching - SmoothTransformManager handles the settings

## Core Rotation Functions

static func set_rotation_offset(rotation: Vector3):
	"""Set manual rotation offset (in radians)"""
	manual_rotation_offset = rotation
	_normalize_rotation()

static func set_rotation_offset_degrees(rotation_degrees: Vector3):
	"""Set manual rotation offset (in degrees)"""
	manual_rotation_offset = Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)
	_normalize_rotation()

static func get_rotation_offset() -> Vector3:
	"""Get current manual rotation offset in radians"""
	return manual_rotation_offset

static func get_rotation_offset_degrees() -> Vector3:
	"""Get current manual rotation offset in degrees"""
	return Vector3(
		rad_to_deg(manual_rotation_offset.x),
		rad_to_deg(manual_rotation_offset.y),
		rad_to_deg(manual_rotation_offset.z)
	)

static func reset_rotation():
	"""Reset manual rotation offset to zero (keeps surface alignment)"""
	manual_rotation_offset = Vector3.ZERO
	PluginLogger.debug("RotationManager", "Manual rotation offset reset to zero")

static func reset_surface_alignment():
	"""Reset surface alignment rotation to zero"""
	surface_alignment_rotation = Vector3.ZERO

static func reset_all_rotation():
	"""Reset both manual offset and surface alignment rotation"""
	manual_rotation_offset = Vector3.ZERO
	surface_alignment_rotation = Vector3.ZERO
	PluginLogger.debug("RotationManager", "All rotation reset to zero")

## Rotation Modifications

static func rotate_x(degrees: float):
	"""Rotate around X axis by degrees"""
	manual_rotation_offset.x += deg_to_rad(degrees)
	_normalize_rotation()

static func rotate_y(degrees: float):
	"""Rotate around Y axis by degrees"""
	manual_rotation_offset.y += deg_to_rad(degrees)
	_normalize_rotation()

static func rotate_z(degrees: float):
	"""Rotate around Z axis by degrees"""
	manual_rotation_offset.z += deg_to_rad(degrees)
	_normalize_rotation()

static func rotate_axis(axis: String, degrees: float):
	"""Rotate around specified axis by degrees"""
	match axis.to_upper():
		"X":
			rotate_x(degrees)
		"Y":
			rotate_y(degrees)
		"Z":
			rotate_z(degrees)
		_:
			PluginLogger.warning("RotationManager", "Invalid axis: " + axis)

static func rotate_axis_with_modifiers(axis: String, base_degrees: float, modifiers: Dictionary):
	"""Rotate around specified axis with modifier-adjusted step
	
	Args:
		axis: Rotation axis ("X", "Y", or "Z")
		base_degrees: Base rotation step in degrees
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step_degrees = IncrementCalculator.calculate_rotation_step(base_degrees, modifiers)
	rotate_axis(axis, step_degrees)

static func add_rotation(delta_rotation: Vector3):
	"""Add a rotation delta (in radians)"""
	manual_rotation_offset += delta_rotation
	_normalize_rotation()

static func add_rotation_degrees(delta_rotation_degrees: Vector3):
	"""Add a rotation delta (in degrees)"""
	add_rotation(Vector3(
		deg_to_rad(delta_rotation_degrees.x),
		deg_to_rad(delta_rotation_degrees.y),
		deg_to_rad(delta_rotation_degrees.z)
	))

## Node Application

static func apply_rotation_to_node(node: Node3D, original_rotation: Vector3 = Vector3.ZERO):
	"""Apply rotation offset to a Node3D's original rotation
	Combines original rotation + surface alignment + manual offset
	
	Args:
		node: The Node3D to apply rotation to
		original_rotation: The node's original rotation (from transform mode) or Vector3.ZERO for placement mode
	"""
	if node and is_instance_valid(node) and node.is_inside_tree():
		# Build the final rotation by combining:
		# 1. Original rotation (from when transform mode started)
		# 2. Surface alignment (base rotation from surface normal)
		# 3. Manual offset (user input rotation changes)
		
		var original_transform = Transform3D(Basis.from_euler(original_rotation), Vector3.ZERO)
		var surface_transform = Transform3D(Basis.from_euler(surface_alignment_rotation), Vector3.ZERO)
		var manual_transform = Transform3D(Basis.from_euler(manual_rotation_offset), Vector3.ZERO)
		
		# Combine: original -> surface alignment -> manual offset
		var combined_transform = original_transform * surface_transform * manual_transform
		
		# Extract the combined rotation
		var target_rotation = combined_transform.basis.get_euler()
		
		# Apply to node with or without smoothing
		if SmoothTransformManager._smooth_enabled:
			SmoothTransformManager.set_target_rotation(node, target_rotation)
		else:
			node.rotation = target_rotation

static func align_with_surface_normal(surface_normal: Vector3):
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
	surface_alignment_rotation = basis.get_euler()
	_normalize_surface_rotation()

static func apply_rotation_step(node: Node3D, axis: String, degrees: float, original_rotation: Vector3 = Vector3.ZERO, rotate_position_offset: bool = false):
	"""Apply a rotation step to the MANUAL rotation offset and update the node
	This rotation offset is combined with the original rotation and surface alignment
	
	Args:
		node: The Node3D to rotate
		axis: Rotation axis ("X", "Y", or "Z")
		degrees: Rotation amount in degrees
		original_rotation: The node's original rotation (from transform mode) or Vector3.ZERO for placement mode
		rotate_position_offset: If true, also rotates the manual position offset (for placement mode)
	"""
	if not node:
		return
	
	var rotation_axis = axis.to_upper()
	
	# Update the internal manual rotation offset
	match rotation_axis:
		"X":
			rotate_x(degrees)
		"Y":
			rotate_y(degrees)
		"Z":
			rotate_z(degrees)
		_:
			PluginLogger.warning("RotationManager", "Invalid axis: " + axis)
			return
	
	# If in placement mode, also rotate the position offset so it follows the mesh rotation
	if rotate_position_offset:
		# Rotate the position offset to match the mesh rotation
		var PositionManager = preload("res://addons/simpleassetplacer/position_manager.gd")
		PositionManager.rotate_manual_offset(rotation_axis, degrees)
	
	# Apply the combined rotation (original + surface alignment + manual offset) to the node
	apply_rotation_to_node(node, original_rotation)
	PluginLogger.debug("RotationManager", "Applied " + str(degrees) + "° manual rotation offset to " + axis + " axis")

static func apply_rotation_step_with_modifiers(node: Node3D, axis: String, base_degrees: float, modifiers: Dictionary, original_rotation: Vector3 = Vector3.ZERO, rotate_position_offset: bool = false):
	"""Apply a rotation step with modifier-adjusted increment
	
	Args:
		node: The Node3D to rotate
		axis: Rotation axis ("X", "Y", or "Z")
		base_degrees: Base rotation step in degrees (e.g., 15.0)
		modifiers: Modifier state from InputHandler.get_modifier_state()
		original_rotation: The node's original rotation (from transform mode)
		rotate_position_offset: If true, also rotates the manual position offset
	"""
	var step_degrees = IncrementCalculator.calculate_rotation_step(base_degrees, modifiers)
	apply_rotation_step(node, axis, step_degrees, original_rotation, rotate_position_offset)

static func reset_node_rotation(node: Node3D):
	"""Reset a node's rotation to zero"""
	if node:
		node.rotation = Vector3.ZERO
		PluginLogger.debug("RotationManager", "Reset rotation for node: " + node.name)

static func lerp_to_rotation(target_rotation: Vector3, weight: float):
	"""Smoothly interpolate to a target rotation offset"""
	manual_rotation_offset = manual_rotation_offset.lerp(target_rotation, weight)

## Utility Functions

static func _normalize_rotation():
	"""Keep rotation offset values within reasonable bounds"""
	manual_rotation_offset.x = fmod(manual_rotation_offset.x, TAU)  # TAU = 2 * PI
	manual_rotation_offset.y = fmod(manual_rotation_offset.y, TAU)
	manual_rotation_offset.z = fmod(manual_rotation_offset.z, TAU)

static func _normalize_surface_rotation():
	"""Keep surface alignment rotation values within reasonable bounds"""
	surface_alignment_rotation.x = fmod(surface_alignment_rotation.x, TAU)
	surface_alignment_rotation.y = fmod(surface_alignment_rotation.y, TAU)
	surface_alignment_rotation.z = fmod(surface_alignment_rotation.z, TAU)

static func _normalize_rotation_degrees(rotation_degrees: Vector3) -> Vector3:
	"""Normalize rotation degrees to 0-360 range"""
	return Vector3(
		fmod(rotation_degrees.x + 360.0, 360.0),
		fmod(rotation_degrees.y + 360.0, 360.0),
		fmod(rotation_degrees.z + 360.0, 360.0)
	)

## Rotation Queries

static func is_rotation_zero() -> bool:
	"""Check if rotation offset is at zero"""
	return manual_rotation_offset.length_squared() < 0.001

static func get_rotation_magnitude() -> float:
	"""Get the magnitude of current rotation offset"""
	return manual_rotation_offset.length()

static func get_euler_angles() -> Vector3:
	"""Get rotation offset as Euler angles (alias for get_rotation_offset)"""
	return get_rotation_offset()

## Rotation Presets

static func set_rotation_preset(preset_name: String):
	"""Set rotation offset to a common preset"""
	match preset_name.to_lower():
		"identity", "zero":
			reset_rotation()
		"90x":
			set_rotation_offset_degrees(Vector3(90, 0, 0))
		"90y":
			set_rotation_offset_degrees(Vector3(0, 90, 0))
		"90z":
			set_rotation_offset_degrees(Vector3(0, 0, 90))
		"180x":
			set_rotation_offset_degrees(Vector3(180, 0, 0))
		"180y":
			set_rotation_offset_degrees(Vector3(0, 180, 0))
		"180z":
			set_rotation_offset_degrees(Vector3(0, 0, 180))
		_:
			PluginLogger.warning("RotationManager", "Unknown preset: " + preset_name)

## Configuration and Settings

static func configure(settings: Dictionary):
	"""Configure rotation manager with settings"""
	if settings.has("initial_rotation"):
		var initial = settings.initial_rotation
		if initial is Vector3:
			set_rotation_offset_degrees(initial)

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"current_rotation_offset_degrees": get_rotation_offset_degrees(),
		"current_rotation_offset_radians": get_rotation_offset()
	}

## Debug and Information

static func debug_print_rotation():
	"""Print current rotation state for debugging"""
	var rot_deg = get_rotation_offset_degrees()
	PluginLogger.debug("RotationManager", "RotationManager State:")
	PluginLogger.debug("RotationManager", "  Rotation Offset (degrees): X:%.1f Y:%.1f Z:%.1f" % [rot_deg.x, rot_deg.y, rot_deg.z])
	PluginLogger.debug("RotationManager", "  Rotation Offset (radians): X:%.3f Y:%.3f Z:%.3f" % [manual_rotation_offset.x, manual_rotation_offset.y, manual_rotation_offset.z])
	PluginLogger.debug("RotationManager", "  Magnitude: %.3f" % get_rotation_magnitude())

static func get_rotation_info() -> Dictionary:
	"""Get comprehensive rotation information"""
	return {
		"rotation_offset_radians": manual_rotation_offset,
		"rotation_offset_degrees": get_rotation_offset_degrees(),
		"magnitude": get_rotation_magnitude(),
		"is_zero": is_rotation_zero()
	}