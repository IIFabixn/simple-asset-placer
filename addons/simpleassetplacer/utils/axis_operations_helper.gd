@tool
extends RefCounted

class_name AxisOperationsHelper

"""
AXIS OPERATIONS HELPER (Shared Utility)
========================================

PURPOSE: Provide axis-constrained transform operations for mode handlers.

PROVIDES:
- Mouse rotation processing
- Mouse scale processing  
- Axis-constrained position calculation (X/Y/Z constraints)
- Cursor warping
- Sensitivity curve application

This helper centralizes transform operation logic used across mode handlers.

MODAL SYSTEM REMOVED:
Previously called "ModalOperationsHelper" when G/R/L modal system existed.
Now focuses on axis constraint operations (X/Y/Z keys) and mouse-based transforms.

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
const SensitivityCurve = preload("res://addons/simpleassetplacer/utils/sensitivity_curve.gd")
const CursorWarpAdapter = preload("res://addons/simpleassetplacer/utils/cursor_warp_adapter.gd")

var _services: ServiceRegistry
var _warp_disabled: bool = false

func _init(services: ServiceRegistry) -> void:
	_services = services
	_warp_disabled = false

func set_warp_disabled(disabled: bool) -> void:
	_warp_disabled = disabled

## MOUSE ROTATION (R key modal)

func process_mouse_rotation(
	camera: Camera3D,
	mouse_pos: Vector2,
	transform_state: TransformState,
	settings: Dictionary,
	meta_key: String = "_prev_mouse_pos"
) -> void:
	"""
	Process mouse movement for rotation control (R mode).
	
	Uses horizontal mouse movement to rotate around the constrained axis,
	or around Y-axis if no constraint is active.
	
	Args:
		camera: The 3D camera
		mouse_pos: Current mouse position in viewport
		transform_state: Transform state to modify
		settings: Settings dictionary
		meta_key: Metadata key for storing previous mouse position
	"""
	if not camera:
		return
	
	# Get viewport for delta calculation and cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport:
		return
	
	# Store previous mouse position for delta calculation
	if not transform_state.has_meta(meta_key):
		transform_state.set_meta(meta_key, mouse_pos)
		return
	
	var prev_mouse_pos = transform_state.get_meta(meta_key)
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Handle cursor warping
	var warp_handled: bool = false
	if not _warp_disabled:
		warp_handled = maybe_warp_cursor(transform_state, meta_key, mouse_pos, settings, viewport)
	if not warp_handled:
		transform_state.set_meta(meta_key, mouse_pos)
	
	# Determine which axis to rotate around
	var control_mode = _services.control_mode_state
	var rotate_around_axis = get_rotation_axis(control_mode)
	
	# Calculate rotation based on horizontal mouse movement
	var rotation_amount = calculate_rotation_from_mouse(mouse_delta.x, settings)
	
	# Apply rotation with snapping if enabled
	apply_rotation_to_axis(transform_state, rotate_around_axis, rotation_amount, settings)

func get_rotation_axis(control_mode: ControlModeState) -> String:
	"""
	Determine which axis to rotate around based on constraints.
	
	Priority: X > Y > Z (if multiple constraints, use first one)
	Default: Y axis if no constraint
	"""
	if control_mode and control_mode.has_axis_constraint():
		if control_mode.is_x_constrained():
			return "X"
		elif control_mode.is_y_constrained():
			return "Y"
		elif control_mode.is_z_constrained():
			return "Z"
	return "Y"  # Default: Rotate around Y axis

func calculate_rotation_from_mouse(mouse_delta_x: float, settings: Dictionary) -> float:
	"""
	Calculate rotation amount in degrees from mouse movement.
	
	Applies:
	- Sensitivity settings
	- Sensitivity curve
	- Fine/large modifiers
	
	Returns rotation in degrees
	"""
	# Calculate rotation based on horizontal mouse movement
	var rotation_sensitivity = settings.get("mouse_rotation_sensitivity", 0.5)
	var curve_type: String = settings.get("mouse_sensitivity_curve", SensitivityCurve.CURVE_LINEAR)
	var curved_delta = SensitivityCurve.apply(mouse_delta_x, curve_type, 400.0)
	var rotation_amount = -curved_delta * rotation_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler and input_handler.is_fine_increment_modifier_held():
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= fine_multiplier
	elif input_handler and input_handler.is_large_increment_modifier_held():
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= large_multiplier
	
	return rotation_amount

func apply_rotation_to_axis(
	transform_state: TransformState,
	axis: String,
	rotation_degrees: float,
	settings: Dictionary
) -> void:
	"""
	Apply rotation to the specified axis with optional snapping.
	
	Args:
		transform_state: State to modify
		axis: "X", "Y", or "Z"
		rotation_degrees: Rotation amount in degrees
		settings: Settings dictionary (for snapping)
	"""
	if transform_state.snap.snap_rotation_enabled:
		_apply_snapped_rotation(transform_state, axis, rotation_degrees)
	else:
		_apply_free_rotation(transform_state, axis, rotation_degrees)

func _apply_snapped_rotation(transform_state: TransformState, axis: String, rotation_amount_deg: float) -> void:
	"""Apply rotation with snapping"""
	# Get current rotation in degrees for the target axis
	var current_rotation_deg = 0.0
	match axis:
		"X":
			current_rotation_deg = rad_to_deg(transform_state.values.manual_rotation_offset.x)
		"Y":
			current_rotation_deg = rad_to_deg(transform_state.values.manual_rotation_offset.y)
		"Z":
			current_rotation_deg = rad_to_deg(transform_state.values.manual_rotation_offset.z)
	
	# Add the rotation amount
	var new_rotation_deg = current_rotation_deg + rotation_amount_deg
	
	# Apply snapping with half-step support
	var snap_step = transform_state.snap.snap_rotation_step
	if transform_state.use_half_step:
		snap_step = snap_step / 2.0
	
	# Snap to nearest increment
	new_rotation_deg = round(new_rotation_deg / snap_step) * snap_step
	
	# Set the snapped rotation (convert back to radians)
	match axis:
		"X":
			transform_state.values.manual_rotation_offset.x = deg_to_rad(new_rotation_deg)
		"Y":
			transform_state.values.manual_rotation_offset.y = deg_to_rad(new_rotation_deg)
		"Z":
			transform_state.values.manual_rotation_offset.z = deg_to_rad(new_rotation_deg)

func _apply_free_rotation(transform_state: TransformState, axis: String, rotation_amount_deg: float) -> void:
	"""Apply rotation without snapping"""
	var rotation_amount_rad = deg_to_rad(rotation_amount_deg)
	
	match axis:
		"X":
			transform_state.values.manual_rotation_offset.x += rotation_amount_rad
		"Y":
			transform_state.values.manual_rotation_offset.y += rotation_amount_rad
		"Z":
			transform_state.values.manual_rotation_offset.z += rotation_amount_rad

## MOUSE SCALE (L key modal)

func process_mouse_scale(
	mouse_pos: Vector2,
	transform_state: TransformState,
	settings: Dictionary,
	meta_key: String = "_prev_mouse_pos_scale"
) -> void:
	"""
	Process mouse movement for scale control (L mode).
	
	Uses vertical mouse movement to adjust scale.
	
	Args:
		mouse_pos: Current mouse position in viewport
		transform_state: Transform state to modify
		settings: Settings dictionary
		meta_key: Metadata key for storing previous mouse position
	"""
	# Get viewport for cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	
	# Store previous mouse position for delta calculation
	if not transform_state.has_meta(meta_key):
		transform_state.set_meta(meta_key, mouse_pos)
		return
	
	var prev_mouse_pos = transform_state.get_meta(meta_key)
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Handle cursor warping
	var warp_handled: bool = maybe_warp_cursor(transform_state, meta_key, mouse_pos, settings, viewport)
	if not warp_handled:
		transform_state.set_meta(meta_key, mouse_pos)
	
	# Calculate scale change from mouse movement
	var scale_change = calculate_scale_from_mouse(mouse_delta.y, settings)
	
	# Apply scale with snapping if enabled
	apply_scale_change(transform_state, scale_change)

func calculate_scale_from_mouse(mouse_delta_y: float, settings: Dictionary) -> float:
	"""
	Calculate scale change from mouse movement.
	
	Applies sensitivity settings and modifiers.
	Returns scale delta.
	"""
	var scale_sensitivity = settings.get("mouse_scale_sensitivity", 0.01)
	var curve_type: String = settings.get("mouse_sensitivity_curve", SensitivityCurve.CURVE_LINEAR)
	var curved_delta = SensitivityCurve.apply(mouse_delta_y, curve_type, 400.0)
	var scale_change = -curved_delta * scale_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler and input_handler.is_fine_increment_modifier_held():
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		scale_change *= fine_multiplier
	elif input_handler and input_handler.is_large_increment_modifier_held():
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		scale_change *= large_multiplier
	
	return scale_change

func apply_scale_change(transform_state: TransformState, scale_delta: float) -> void:
	"""Apply scale change with optional snapping"""
	if transform_state.snap_scale_enabled:
		_apply_snapped_scale(transform_state, scale_delta)
	else:
		_apply_free_scale(transform_state, scale_delta)

func _apply_snapped_scale(transform_state: TransformState, scale_delta: float) -> void:
	"""Apply scale with snapping"""
	var current_multiplier = _services.scale_manager.get_scale_multiplier(transform_state)
	var new_multiplier = current_multiplier + scale_delta
	
	# Apply snapping with half-step support
	var snap_step = transform_state.snap_scale_step
	if transform_state.use_half_step:
		snap_step = snap_step / 2.0
	
	# Snap to nearest increment
	new_multiplier = round(new_multiplier / snap_step) * snap_step
	
	# Clamp to reasonable bounds
	new_multiplier = clamp(new_multiplier, 0.01, 100.0)
	
	_services.scale_manager.set_scale_multiplier(transform_state, new_multiplier)

func _apply_free_scale(transform_state: TransformState, scale_delta: float) -> void:
	"""Apply scale without snapping"""
	_services.scale_manager.increase_scale(transform_state, scale_delta)

## CONSTRAINED POSITION (Axis constraints for G key modal)

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
