@tool
extends RefCounted

class_name TransformMath

"""
TRANSFORM MATHEMATICS UTILITIES
================================

PURPOSE: Common mathematical utilities for transform calculations (position, rotation, scale).

RESPONSIBILITIES:
- Snapping functions (grid snapping for position, rotation, scale)
- Normalization functions (angle wrapping, vector normalization)
- Clamping functions (bounds checking, range limiting)
- Interpolation helpers (lerp, slerp utilities)
- Validation functions (bounds checking, value validation)

ARCHITECTURE POSITION: Pure utility class with static-like functions
- No state storage (all functions are stateless)
- No dependencies on managers or services
- Reusable across all transform managers
- Eliminates code duplication

USED BY: PositionManager, RotationManager, ScaleManager, TransformOperations facade
DEPENDS ON: Godot math functions only
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# Constants
const TAU = 2.0 * PI  # Full rotation in radians
const EPSILON = 0.001  # Small value for floating point comparisons

## ============================================================================
## SNAPPING FUNCTIONS
## ============================================================================

static func snap_value(value: float, step: float, offset: float = 0.0) -> float:
	"""Snap a single value to a grid
	
	Args:
		value: The value to snap
		step: Grid step size
		offset: Grid offset
		
	Returns:
		Snapped value
	"""
	if step <= 0.0:
		return value
	
	# Adjust for offset, snap, then restore offset
	var adjusted = value - offset
	var snapped = round(adjusted / step) * step
	return snapped + offset

static func snap_vector3(vec: Vector3, step: float, offset: Vector3 = Vector3.ZERO) -> Vector3:
	"""Snap a Vector3 to a grid (all axes use same step)
	
	Args:
		vec: Vector to snap
		step: Grid step size
		offset: Grid offset per axis
		
	Returns:
		Snapped vector
	"""
	return Vector3(
		snap_value(vec.x, step, offset.x),
		snap_value(vec.y, step, offset.y),
		snap_value(vec.z, step, offset.z)
	)

static func snap_vector3_xz(vec: Vector3, step: float, offset: Vector3 = Vector3.ZERO) -> Vector3:
	"""Snap only X and Z axes of a Vector3 to grid (leave Y unchanged)
	
	Args:
		vec: Vector to snap
		step: Grid step size for X and Z
		offset: Grid offset per axis
		
	Returns:
		Vector with X and Z snapped
	"""
	return Vector3(
		snap_value(vec.x, step, offset.x),
		vec.y,  # Y unchanged
		snap_value(vec.z, step, offset.z)
	)

static func snap_angle(angle_radians: float, step_radians: float) -> float:
	"""Snap an angle to a grid
	
	Args:
		angle_radians: Angle in radians
		step_radians: Step size in radians
		
	Returns:
		Snapped angle in radians
	"""
	if step_radians <= 0.0:
		return angle_radians
	
	return round(angle_radians / step_radians) * step_radians

static func snap_rotation(rotation: Vector3, step_degrees: float) -> Vector3:
	"""Snap rotation angles to grid
	
	Args:
		rotation: Rotation in radians
		step_degrees: Snap step in degrees
		
	Returns:
		Snapped rotation in radians
	"""
	if step_degrees <= 0.0:
		return rotation
	
	var step_rad = deg_to_rad(step_degrees)
	return Vector3(
		snap_angle(rotation.x, step_rad),
		snap_angle(rotation.y, step_rad),
		snap_angle(rotation.z, step_rad)
	)

static func snap_scale(scale: Vector3, step: float) -> Vector3:
	"""Snap scale values to grid
	
	Args:
		scale: Scale vector
		step: Snap step size
		
	Returns:
		Snapped scale vector
	"""
	if step <= 0.0:
		return scale
	
	return Vector3(
		snap_value(scale.x, step),
		snap_value(scale.y, step),
		snap_value(scale.z, step)
	)

## ============================================================================
## NORMALIZATION FUNCTIONS
## ============================================================================

static func normalize_angle(angle_radians: float) -> float:
	"""Normalize angle to [-PI, PI] range
	
	Args:
		angle_radians: Angle in radians
		
	Returns:
		Normalized angle in radians
	"""
	return fmod(angle_radians + PI, TAU) - PI

static func normalize_angle_positive(angle_radians: float) -> float:
	"""Normalize angle to [0, TAU) range
	
	Args:
		angle_radians: Angle in radians
		
	Returns:
		Normalized angle in radians (0 to 2π)
	"""
	return fmod(angle_radians, TAU)

static func normalize_rotation(rotation: Vector3) -> Vector3:
	"""Normalize rotation vector (keep angles within reasonable bounds)
	
	Args:
		rotation: Rotation in radians
		
	Returns:
		Normalized rotation vector
	"""
	return Vector3(
		fmod(rotation.x, TAU),
		fmod(rotation.y, TAU),
		fmod(rotation.z, TAU)
	)

static func normalize_rotation_degrees(rotation_degrees: Vector3) -> Vector3:
	"""Normalize rotation degrees to 0-360 range
	
	Args:
		rotation_degrees: Rotation in degrees
		
	Returns:
		Normalized rotation in degrees
	"""
	return Vector3(
		fmod(rotation_degrees.x + 360.0, 360.0),
		fmod(rotation_degrees.y + 360.0, 360.0),
		fmod(rotation_degrees.z + 360.0, 360.0)
	)

## ============================================================================
## CLAMPING FUNCTIONS
## ============================================================================

static func clamp_vector3(vec: Vector3, min_val: Vector3, max_val: Vector3) -> Vector3:
	"""Clamp each component of a Vector3
	
	Args:
		vec: Vector to clamp
		min_val: Minimum values per axis
		max_val: Maximum values per axis
		
	Returns:
		Clamped vector
	"""
	return Vector3(
		clampf(vec.x, min_val.x, max_val.x),
		clampf(vec.y, min_val.y, max_val.y),
		clampf(vec.z, min_val.z, max_val.z)
	)

static func clamp_vector3_uniform(vec: Vector3, min_val: float, max_val: float) -> Vector3:
	"""Clamp all components of a Vector3 to same range
	
	Args:
		vec: Vector to clamp
		min_val: Minimum value for all axes
		max_val: Maximum value for all axes
		
	Returns:
		Clamped vector
	"""
	return Vector3(
		clampf(vec.x, min_val, max_val),
		clampf(vec.y, min_val, max_val),
		clampf(vec.z, min_val, max_val)
	)

static func clamp_position_to_bounds(pos: Vector3, bounds: AABB) -> Vector3:
	"""Clamp position to AABB bounds
	
	Args:
		pos: Position to clamp
		bounds: Bounding box
		
	Returns:
		Position clamped to bounds
	"""
	if bounds.size == Vector3.ZERO:
		# Default bounds if empty AABB
		bounds = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	
	return Vector3(
		clampf(pos.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(pos.y, bounds.position.y, bounds.position.y + bounds.size.y),
		clampf(pos.z, bounds.position.z, bounds.position.z + bounds.size.z)
	)

static func clamp_scale(scale: Vector3, min_scale: float = 0.01, max_scale: float = 100.0) -> Vector3:
	"""Clamp scale values to prevent zero/negative or excessive scaling
	
	Args:
		scale: Scale vector to clamp
		min_scale: Minimum scale value (default 0.01)
		max_scale: Maximum scale value (default 100.0)
		
	Returns:
		Clamped scale vector
	"""
	return clamp_vector3_uniform(scale, min_scale, max_scale)

## ============================================================================
## VALIDATION FUNCTIONS
## ============================================================================

static func is_valid_position(pos: Vector3, max_distance: float = 10000.0) -> bool:
	"""Check if a position is valid (not too far from origin)
	
	Args:
		pos: Position to validate
		max_distance: Maximum allowed distance from origin
		
	Returns:
		True if position is valid
	"""
	# Check horizontal bounds
	if abs(pos.x) > max_distance or abs(pos.z) > max_distance:
		return false
	
	# Check vertical bounds
	if pos.y < -1000 or pos.y > 1000:
		return false
	
	return true

static func is_rotation_zero(rotation: Vector3, tolerance: float = EPSILON) -> bool:
	"""Check if rotation is approximately zero
	
	Args:
		rotation: Rotation vector in radians
		tolerance: Tolerance for comparison
		
	Returns:
		True if rotation is effectively zero
	"""
	return rotation.length_squared() < tolerance * tolerance

static func is_scale_uniform(scale: Vector3, tolerance: float = EPSILON) -> bool:
	"""Check if scale is uniform (all axes equal)
	
	Args:
		scale: Scale vector
		tolerance: Tolerance for comparison
		
	Returns:
		True if scale is uniform
	"""
	var avg = (scale.x + scale.y + scale.z) / 3.0
	return abs(scale.x - avg) < tolerance and abs(scale.y - avg) < tolerance and abs(scale.z - avg) < tolerance

static func is_scale_valid(scale: Vector3, min_scale: float = 0.01) -> bool:
	"""Check if scale values are valid (not zero or negative)
	
	Args:
		scale: Scale vector
		min_scale: Minimum allowed scale
		
	Returns:
		True if all scale components are valid
	"""
	return scale.x >= min_scale and scale.y >= min_scale and scale.z >= min_scale

## ============================================================================
## INTERPOLATION HELPERS
## ============================================================================

static func lerp_vector3_safe(from: Vector3, to: Vector3, weight: float) -> Vector3:
	"""Safely interpolate between two vectors (clamps weight to [0, 1])
	
	Args:
		from: Start vector
		to: End vector
		weight: Interpolation weight
		
	Returns:
		Interpolated vector
	"""
	weight = clampf(weight, 0.0, 1.0)
	return from.lerp(to, weight)

static func smooth_damp_vector3(current: Vector3, target: Vector3, velocity: Vector3, smooth_time: float, delta: float, max_speed: float = INF) -> Dictionary:
	"""Smooth damp for Vector3 (similar to Unity's SmoothDamp)
	
	Args:
		current: Current value
		target: Target value
		velocity: Current velocity (modified by reference via return dict)
		smooth_time: Approximate time to reach target
		delta: Time since last update
		max_speed: Maximum speed
		
	Returns:
		Dictionary with "value" and "velocity" keys
	"""
	smooth_time = maxf(0.0001, smooth_time)
	var omega = 2.0 / smooth_time
	var x = omega * delta
	var exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	
	var change = current - target
	var original_to = target
	
	# Clamp maximum change
	var max_change = max_speed * smooth_time
	var max_change_sq = max_change * max_change
	var change_sq = change.length_squared()
	if change_sq > max_change_sq:
		var mag = sqrt(change_sq)
		change = change / mag * max_change
	
	target = current - change
	var temp = (velocity + omega * change) * delta
	velocity = (velocity - omega * temp) * exp
	var output = target + (change + temp) * exp
	
	# Prevent overshooting
	if (original_to - current).dot(output - original_to) > 0:
		output = original_to
		velocity = (output - original_to) / delta
	
	return {
		"value": output,
		"velocity": velocity
	}

static func calculate_smooth_lerp_weight(speed: float, delta: float) -> float:
	"""Calculate lerp weight for smooth interpolation
	
	Args:
		speed: Interpolation speed (higher = faster)
		delta: Time delta
		
	Returns:
		Weight for lerp function [0, 1]
	"""
	return clampf(1.0 - exp(-speed * delta), 0.0, 1.0)

## ============================================================================
## ROTATION UTILITIES
## ============================================================================

static func euler_to_quaternion(euler: Vector3) -> Quaternion:
	"""Convert Euler angles to Quaternion
	
	Args:
		euler: Rotation in radians
		
	Returns:
		Quaternion representation
	"""
	return Quaternion.from_euler(euler)

static func quaternion_to_euler(quat: Quaternion) -> Vector3:
	"""Convert Quaternion to Euler angles
	
	Args:
		quat: Quaternion
		
	Returns:
		Euler angles in radians
	"""
	return quat.get_euler()

static func get_rotation_magnitude(rotation: Vector3) -> float:
	"""Get magnitude of rotation vector
	
	Args:
		rotation: Rotation in radians
		
	Returns:
		Magnitude of rotation
	"""
	return rotation.length()

## ============================================================================
## VECTOR UTILITIES
## ============================================================================

static func vector3_approximately_equal(a: Vector3, b: Vector3, tolerance: float = EPSILON) -> bool:
	"""Check if two vectors are approximately equal
	
	Args:
		a: First vector
		b: Second vector
		tolerance: Comparison tolerance
		
	Returns:
		True if vectors are approximately equal
	"""
	return (a - b).length_squared() < tolerance * tolerance

static func get_horizontal_distance(a: Vector3, b: Vector3) -> float:
	"""Get horizontal distance between two points (ignoring Y)
	
	Args:
		a: First point
		b: Second point
		
	Returns:
		Distance in XZ plane
	"""
	var dx = a.x - b.x
	var dz = a.z - b.z
	return sqrt(dx * dx + dz * dz)

static func project_onto_plane(vector: Vector3, plane_normal: Vector3) -> Vector3:
	"""Project vector onto plane defined by normal
	
	Args:
		vector: Vector to project
		plane_normal: Plane normal (should be normalized)
		
	Returns:
		Projected vector
	"""
	plane_normal = plane_normal.normalized()
	return vector - plane_normal * vector.dot(plane_normal)

## ============================================================================
## SCALE UTILITIES
## ============================================================================

static func get_uniform_scale(scale: Vector3) -> float:
	"""Get average scale value (converts non-uniform to uniform)
	
	Args:
		scale: Scale vector
		
	Returns:
		Average scale value
	"""
	return (scale.x + scale.y + scale.z) / 3.0

static func make_uniform_scale(value: float) -> Vector3:
	"""Create uniform scale vector
	
	Args:
		value: Scale value for all axes
		
	Returns:
		Uniform scale vector
	"""
	return Vector3(value, value, value)

## ============================================================================
## DEBUG UTILITIES
## ============================================================================

static func format_vector3(vec: Vector3, precision: int = 2) -> String:
	"""Format Vector3 for logging
	
	Args:
		vec: Vector to format
		precision: Decimal precision
		
	Returns:
		Formatted string
	"""
	var format_str = "%." + str(precision) + "f"
	return "(X:" + (format_str % vec.x) + " Y:" + (format_str % vec.y) + " Z:" + (format_str % vec.z) + ")"

static func format_rotation_degrees(rotation_radians: Vector3, precision: int = 1) -> String:
	"""Format rotation as degrees for logging
	
	Args:
		rotation_radians: Rotation in radians
		precision: Decimal precision
		
	Returns:
		Formatted string in degrees
	"""
	var deg = Vector3(
		rad_to_deg(rotation_radians.x),
		rad_to_deg(rotation_radians.y),
		rad_to_deg(rotation_radians.z)
	)
	return format_vector3(deg, precision) + "°"
