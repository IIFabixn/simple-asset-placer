@tool
extends RefCounted

class_name AxisOperationsHelper

"""
AXIS OPERATIONS HELPER (Shared Utility)
========================================

PURPOSE: Provide axis-constrained transform operations for mode handlers.

PROVIDES:
- Axis-constrained position calculation (X/Y/Z constraints)
- Cursor warping

This helper centralizes transform operation logic used across mode handlers.

ARCHITECTURE POSITION: Shared utility service
- Used by: TransformationCoordinator
- Provides: Common transform operations with axis constraints
- Depends on: ServiceRegistry, TransformState, ControlModeState

BENEFITS:
- DRY: Write once, use everywhere
- Consistency: Same behavior in all modes
- Maintainability: Fix bugs in one place
- Testability: Test once, works everywhere
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
const CursorWarpAdapter = preload("res://addons/simpleassetplacer/utils/cursor_warp_adapter.gd")

var _services: ServiceRegistry
var _warp_disabled: bool = false

func _init(services: ServiceRegistry) -> void:
	_services = services
	_warp_disabled = false

func set_warp_disabled(disabled: bool) -> void:
	_warp_disabled = disabled

## CONSTRAINED POSITION (Axis constraints for X/Y/Z keys)

func calculate_constrained_position(
	camera: Camera3D,
	mouse_pos: Vector2,
	current_pos: Vector3,
	control_mode: ControlModeState
) -> Vector3:
	"""
	Calculate constrained position based on axis constraints.
	
	Supports:
	- Single axis constraint (line)
	- Two axis constraint (plane)
	- Three axis constraint (free movement, same as no constraint)
	
	Args:
		camera: Camera for ray casting
		mouse_pos: Mouse position in viewport
		current_pos: Current position (fallback)
		control_mode: Control mode with axis constraints
	
	Returns:
		New constrained position
	"""
	if not camera or not control_mode:
		return current_pos
	
	var constraints = control_mode.get_constrained_axes()
	var origin = control_mode.get_constraint_origin() if control_mode.has_constraint_origin() else current_pos
	
	# Project mouse position to ray
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# Count active constraints
	var active_count = int(constraints.get("X", false)) + int(constraints.get("Y", false)) + int(constraints.get("Z", false))
	
	match active_count:
		1:
			# Single axis - line constraint
			return _calculate_line_constraint(ray_origin, ray_direction, origin, constraints)
		2:
			# Two axes - plane constraint
			return _calculate_plane_constraint(ray_origin, ray_direction, origin, constraints)
		_:
			# No constraint or all axes (free movement)
			return current_pos

func _calculate_line_constraint(ray_origin: Vector3, ray_dir: Vector3, origin: Vector3, constraints: Dictionary) -> Vector3:
	"""Calculate position constrained to a line (single axis)"""
	var axis = Vector3.ZERO
	if constraints.get("X", false):
		axis = Vector3.RIGHT
	elif constraints.get("Y", false):
		axis = Vector3.UP
	elif constraints.get("Z", false):
		axis = Vector3.FORWARD
	
	# Project ray onto axis line
	var t = project_ray_onto_line(ray_origin, ray_dir, origin, axis)
	return origin + axis * t

func _calculate_plane_constraint(ray_origin: Vector3, ray_dir: Vector3, origin: Vector3, constraints: Dictionary) -> Vector3:
	"""Calculate position constrained to a plane (two axes)"""
	var plane_normal = Vector3.ZERO
	if not constraints.get("X", false):
		plane_normal = Vector3.RIGHT
	elif not constraints.get("Y", false):
		plane_normal = Vector3.UP
	elif not constraints.get("Z", false):
		plane_normal = Vector3.FORWARD
	
	# Intersect ray with plane
	var plane = Plane(plane_normal, origin.dot(plane_normal))
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		return intersection
	return origin  # Fallback

func project_ray_onto_line(ray_origin: Vector3, ray_dir: Vector3, line_origin: Vector3, line_dir: Vector3) -> float:
	"""
	Project a ray onto a line and return the parameter t along the line.
	
	Classic computational geometry problem - find closest point on line to ray.
	"""
	var w = ray_origin - line_origin
	var a = line_dir.dot(line_dir)
	var b = line_dir.dot(ray_dir)
	var c = ray_dir.dot(ray_dir)
	var d = line_dir.dot(w)
	var e = ray_dir.dot(w)
	
	var denom = a * c - b * b
	if abs(denom) < 0.0001:
		return 0.0
	
	var t = (b * e - c * d) / denom
	return t

## CURSOR WARPING

func maybe_warp_cursor(
	transform_state: TransformState,
	meta_key: String,
	mouse_pos: Vector2,
	settings: Dictionary,
	viewport: SubViewport
) -> bool:
	"""
	Maybe warp cursor if it reaches viewport edge.
	
	Returns:
		true if cursor was warped, false otherwise
	"""
	# Unified cursor warp key: 'cursor_warp_enabled'.
	if not settings.get("cursor_warp_enabled", true) or _warp_disabled:
		return false
	
	if not viewport:
		return false
	
	var adapter = CursorWarpAdapter.new()
	var warp_result = adapter.maybe_warp_cursor_in_viewport(mouse_pos, viewport)
	
	if warp_result.warped:
		# Update meta with warped position
		transform_state.set_meta(meta_key, warp_result.new_position)
		return true
	
	return false
