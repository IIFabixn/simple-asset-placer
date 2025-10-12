@tool
extends RefCounted

class_name TransformOperations

"""
TRANSFORM OPERATIONS FACADE
============================

PURPOSE: Unified facade for all transform operations (position, rotation, scale).

RESPONSIBILITIES:
- Provide simple, high-level transform API
- Delegate to appropriate managers (Position, Rotation, Scale)
- Hide complexity of multiple manager interactions
- Centralize common transform workflows
- Reduce coupling between callers and managers

ARCHITECTURE POSITION: Facade pattern over existing managers
- Does NOT replace existing managers (they still exist)
- Provides convenience methods for common operations
- Simplifies calling code
- Reduces direct manager dependencies

DESIGN PATTERN: Facade
- Wraps PositionManager, RotationManager, ScaleManager
- Provides unified interface
- Delegates to appropriate manager
- Can batch multiple manager calls

USAGE GUIDELINES:
=================

**When to use TransformOperations (this facade):**
- Simple, single-purpose operations (move left, rotate 15°, reset scale)
- When you need one transformation from one manager
- Quick convenience calls in simple code paths
- When you don't care about the underlying manager implementation

**When to use managers directly:**
- Complex operations requiring multiple manager calls
- Performance-critical code (avoids extra function call layer)
- When you need fine-grained control over manager state
- When operation doesn't exist in facade API
- Advanced features specific to one manager

**Both approaches are valid!**
The facade is a convenience, not a requirement. Mode handlers and coordinators
commonly use direct manager access for complex operations, while simple utility
code benefits from the facade's simplified API.

USED BY: TransformationCoordinator
DEPENDS ON: ServiceRegistry, TransformState, PositionManager, RotationManager, ScaleManager
"""

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const TransformMath = preload("res://addons/simpleassetplacer/utils/transform_math.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

# Service registry
var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "TransformOperations facade initialized")

## ============================================================================
## POSITION OPERATIONS
## ============================================================================

func calculate_position_from_mouse(
	state: TransformState,
	camera: Camera3D,
	mouse_pos: Vector2,
	lock_y_axis: bool = false,
	exclude_nodes: Array = []
) -> Vector3:
	"""Calculate world position from mouse using placement strategy
	
	Args:
		state: TransformState to update
		camera: Camera3D for ray projection
		mouse_pos: Mouse position in viewport
		lock_y_axis: Lock Y axis updates
		exclude_nodes: Nodes to exclude from raycasting
		
	Returns:
		Calculated world position
	"""
	if not _services.position_manager:
		PluginLogger.error(PluginConstants.COMPONENT_TRANSFORM, "PositionManager not available")
		return state.position
	
	return _services.position_manager.update_position_from_mouse(
		state, camera, mouse_pos, 1, lock_y_axis, exclude_nodes
	)

func adjust_position_offset(state: TransformState, offset: Vector3) -> Vector3:
	"""Apply manual position offset (e.g., from WASD input)
	
	Args:
		state: TransformState to modify
		offset: World-space offset to apply
		
	Returns:
		New position with offset
	"""
	if not _services.position_manager:
		return state.position
	
	return _services.position_manager.apply_position_offset(state, offset)

func adjust_offset_normal(state: TransformState, delta: float) -> void:
	"""Adjust offset along plane normal (e.g., from Q/E keys)
	
	Args:
		state: TransformState to modify
		delta: Normal offset change amount
	"""
	if not _services.position_manager:
		return
	
	_services.position_manager.adjust_offset_normal(state, delta)

func reset_position(state: TransformState, reset_height: bool = true, reset_offset: bool = true) -> void:
	"""Reset position-related state
	
	Args:
		state: TransformState to reset
		reset_height: Reset Y offset
		reset_offset: Reset manual position offset
	"""
	if not _services.position_manager:
		return
	
	_services.position_manager.reset_for_new_placement(state, reset_height, reset_offset)

## ============================================================================
## ROTATION OPERATIONS
## ============================================================================

func rotate_around_axis(state: TransformState, axis: String, degrees: float) -> void:
	"""Rotate around specified axis
	
	Args:
		state: TransformState to modify
		axis: Axis to rotate around ("X", "Y", or "Z")
		degrees: Rotation amount in degrees
	"""
	if not _services.rotation_manager:
		return
	
	_services.rotation_manager.rotate_axis(state, axis, degrees)

func rotate_with_modifiers(state: TransformState, axis: String, base_degrees: float, modifiers: Dictionary) -> void:
	"""Rotate with modifier-adjusted step
	
	Args:
		state: TransformState to modify
		axis: Axis to rotate around
		base_degrees: Base rotation step
		modifiers: Modifier state from InputHandler
	"""
	if not _services.rotation_manager:
		return
	
	_services.rotation_manager.rotate_axis_with_modifiers(state, axis, base_degrees, modifiers)

func set_rotation_degrees(state: TransformState, rotation_degrees: Vector3) -> void:
	"""Set rotation offset in degrees
	
	Args:
		state: TransformState to modify
		rotation_degrees: Rotation in degrees
	"""
	if not _services.rotation_manager:
		return
	
	_services.rotation_manager.set_rotation_offset_degrees(state, rotation_degrees)

func reset_rotation(state: TransformState, reset_surface_alignment: bool = false) -> void:
	"""Reset rotation state
	
	Args:
		state: TransformState to reset
		reset_surface_alignment: Also reset surface alignment rotation
	"""
	if not _services.rotation_manager:
		return
	
	_services.rotation_manager.reset_rotation(state)
	if reset_surface_alignment:
		_services.rotation_manager.reset_surface_alignment(state)

func get_total_rotation(state: TransformState) -> Vector3:
	"""Get combined rotation (manual + surface alignment)
	
	Args:
		state: TransformState to query
		
	Returns:
		Total rotation in radians
	"""
	if not _services.rotation_manager:
		return Vector3.ZERO
	
	return _services.rotation_manager.get_current_rotation(state)

## ============================================================================
## SCALE OPERATIONS
## ============================================================================

func adjust_scale(state: TransformState, delta: float) -> void:
	"""Adjust scale by delta amount
	
	Args:
		state: TransformState to modify
		delta: Scale change amount
	"""
	if not _services.scale_manager:
		return
	
	if delta > 0:
		_services.scale_manager.increase_scale(state, delta)
	else:
		_services.scale_manager.decrease_scale(state, abs(delta))

func adjust_scale_with_modifiers(state: TransformState, base_amount: float, modifiers: Dictionary) -> void:
	"""Adjust scale with modifier-calculated step
	
	Args:
		state: TransformState to modify
		base_amount: Base scale step
		modifiers: Modifier state from InputHandler
	"""
	if not _services.scale_manager:
		return
	
	_services.scale_manager.adjust_scale_with_modifiers(state, base_amount, modifiers)

func multiply_scale(state: TransformState, factor: float) -> void:
	"""Multiply current scale by factor
	
	Args:
		state: TransformState to modify
		factor: Scale multiplier
	"""
	if not _services.scale_manager:
		return
	
	_services.scale_manager.multiply_scale(state, factor)

func set_scale(state: TransformState, scale: float) -> void:
	"""Set uniform scale multiplier
	
	Args:
		state: TransformState to modify
		scale: Scale multiplier (1.0 = original size)
	"""
	if not _services.scale_manager:
		return
	
	_services.scale_manager.set_scale_multiplier(state, scale)

func reset_scale(state: TransformState) -> void:
	"""Reset scale to 1.0
	
	Args:
		state: TransformState to reset
	"""
	if not _services.scale_manager:
		return
	
	_services.scale_manager.reset_scale(state)

func get_current_scale(state: TransformState) -> float:
	"""Get current uniform scale multiplier
	
	Args:
		state: TransformState to query
		
	Returns:
		Current scale multiplier
	"""
	if not _services.scale_manager:
		return 1.0
	
	return _services.scale_manager.get_scale(state)

## ============================================================================
## COMBINED OPERATIONS
## ============================================================================

func reset_all_transforms(state: TransformState) -> void:
	"""Reset all transform components (position, rotation, scale)
	
	Args:
		state: TransformState to reset
	"""
	reset_position(state, true, true)
	reset_rotation(state, true)
	reset_scale(state)
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "All transforms reset")

func apply_transform_preset(state: TransformState, preset_name: String) -> void:
	"""Apply a named transform preset
	
	Args:
		state: TransformState to modify
		preset_name: Name of preset to apply
	"""
	match preset_name.to_lower():
		"identity", "reset":
			reset_all_transforms(state)
		"rotate_90y":
			set_rotation_degrees(state, Vector3(0, 90, 0))
		"rotate_180y":
			set_rotation_degrees(state, Vector3(0, 180, 0))
		"rotate_270y":
			set_rotation_degrees(state, Vector3(0, 270, 0))
		"scale_half":
			set_scale(state, 0.5)
		"scale_double":
			set_scale(state, 2.0)
		_:
			PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, "Unknown preset: " + preset_name)

## ============================================================================
## VALIDATION & QUERIES
## ============================================================================

func is_position_valid(state: TransformState) -> bool:
	"""Check if current position is valid
	
	Args:
		state: TransformState to check
		
	Returns:
		True if position is valid
	"""
	return TransformMath.is_valid_position(state.position)

func is_rotation_zero(state: TransformState) -> bool:
	"""Check if rotation is approximately zero
	
	Args:
		state: TransformState to check
		
	Returns:
		True if rotation is zero
	"""
	if not _services.rotation_manager:
		return true
	
	return _services.rotation_manager.is_rotation_zero(state)

func is_scale_default(state: TransformState) -> bool:
	"""Check if scale is at default (1.0)
	
	Args:
		state: TransformState to check
		
	Returns:
		True if scale is default
	"""
	return abs(state.scale_multiplier - 1.0) < 0.001

func get_transform_info(state: TransformState) -> Dictionary:
	"""Get comprehensive transform information
	
	Args:
		state: TransformState to query
		
	Returns:
		Dictionary with transform information
	"""
	return {
		"position": state.values.position,
		"base_position": state.values.base_position,
		"offset_y": state.values.manual_position_offset.y,
		"rotation_degrees": _services.rotation_manager.get_rotation_offset_degrees(state) if _services.rotation_manager else Vector3.ZERO,
		"rotation_radians": state.values.manual_rotation_offset,
		"scale": state.values.scale_multiplier,
		"scale_vector": state.values.non_uniform_multiplier,
		"is_valid": is_position_valid(state),
		"has_rotation": not is_rotation_zero(state),
		"has_custom_scale": not is_scale_default(state)
	}

## ============================================================================
## SMOOTH TRANSFORMS
## ============================================================================

func enable_smooth_transforms(enabled: bool, speed: float = 8.0) -> void:
	"""Configure smooth transform interpolation
	
	Args:
		enabled: Enable/disable smooth transforms
		speed: Interpolation speed
	"""
	if not _services.smooth_transform_manager:
		return
	
	_services.smooth_transform_manager.configure(enabled, speed)

func update_smooth_transform(node: Node3D, target_transform: Transform3D, delta: float) -> void:
	"""Update smooth transform for a node
	
	Args:
		node: Node to transform
		target_transform: Target transform
		delta: Time delta
	"""
	if not _services.smooth_transform_manager:
		return
	
	# Register node if not already registered
	_services.smooth_transform_manager.register_object(node)
	
	# Update target and process interpolation
	_services.smooth_transform_manager.set_target_transform(node, target_transform.origin, target_transform.basis.get_euler(), target_transform.basis.get_scale())
	_services.smooth_transform_manager.process_frame(delta)

## ============================================================================
## SNAPPING UTILITIES (Using TransformMath)
## ============================================================================

func snap_position_to_grid(position: Vector3, step: float, offset: Vector3 = Vector3.ZERO, snap_y: bool = true) -> Vector3:
	"""Snap position to grid
	
	Args:
		position: Position to snap
		step: Grid step size
		offset: Grid offset
		snap_y: Include Y axis in snapping
		
	Returns:
		Snapped position
	"""
	if snap_y:
		return TransformMath.snap_vector3(position, step, offset)
	else:
		return TransformMath.snap_vector3_xz(position, step, offset)

func snap_rotation_to_grid(rotation: Vector3, step_degrees: float) -> Vector3:
	"""Snap rotation to grid
	
	Args:
		rotation: Rotation in radians
		step_degrees: Step size in degrees
		
	Returns:
		Snapped rotation in radians
	"""
	return TransformMath.snap_rotation(rotation, step_degrees)

func snap_scale_to_grid(scale: Vector3, step: float) -> Vector3:
	"""Snap scale to grid
	
	Args:
		scale: Scale vector
		step: Step size
		
	Returns:
		Snapped scale
	"""
	return TransformMath.snap_scale(scale, step)

## ============================================================================
## DEBUG & LOGGING
## ============================================================================

func log_transform_state(state: TransformState, prefix: String = "") -> void:
	"""Log current transform state
	
	Args:
		state: TransformState to log
		prefix: Optional prefix for log message
	"""
	var info = get_transform_info(state)
	var msg = prefix + " Transform State:\n"
	msg += "  Position: " + TransformMath.format_vector3(info.position) + "\n"
	msg += "  Rotation: " + TransformMath.format_rotation_degrees(info.rotation_radians) + "\n"
	msg += "  Scale: %.2f" % info.scale
	
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, msg)

func validate_state(state: TransformState) -> Dictionary:
	"""Validate transform state and return issues
	
	Args:
		state: TransformState to validate
		
	Returns:
		Dictionary with validation results
	"""
	var issues = []
	var valid = true
	
	if not TransformMath.is_valid_position(state.position):
		issues.append("Position out of valid bounds")
		valid = false
	
	if not TransformMath.is_scale_valid(state.non_uniform_multiplier):
		issues.append("Scale has invalid values (zero or negative)")
		valid = false
	
	if state.snap_enabled and state.snap_step <= 0:
		issues.append("Snapping enabled but step is invalid")
		valid = false
	
	return {
		"valid": valid,
		"issues": issues,
		"warnings": []
	}

## ============================================================================
## CONFIGURATION HELPERS
## ============================================================================

func configure_from_settings(state: TransformState, settings: Dictionary) -> void:
	"""Configure transform state from settings dictionary
	
	Args:
		state: TransformState to configure
		settings: Settings dictionary
	"""
	# Position settings
	if settings.has("snap_enabled"):
		state.snap_enabled = settings.snap_enabled
	if settings.has("snap_step"):
		state.snap_step = settings.snap_step
	if settings.has("snap_offset"):
		state.snap_offset = settings.snap_offset
	
	# Y-axis snap settings
	if settings.has("snap_y_enabled"):
		state.snap_y_enabled = settings.snap_y_enabled
	if settings.has("snap_y_step"):
		state.snap_y_step = settings.snap_y_step
	
	# Rotation settings
	if settings.has("snap_rotation_enabled"):
		state.snap_rotation_enabled = settings.snap_rotation_enabled
	if settings.has("snap_rotation_step"):
		state.snap_rotation_step = settings.snap_rotation_step
	
	# Scale settings
	if settings.has("snap_scale_enabled"):
		state.snap_scale_enabled = settings.snap_scale_enabled
	if settings.has("snap_scale_step"):
		state.snap_scale_step = settings.snap_scale_step
	
	# Initial values
	if settings.has("initial_scale"):
		set_scale(state, float(settings.initial_scale))
	if settings.has("initial_rotation"):
		var rot = settings.initial_rotation
		if rot is Vector3:
			set_rotation_degrees(state, rot)
	
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Configured transform state from settings")

func get_settings_snapshot(state: TransformState) -> Dictionary:
	"""Get current settings as dictionary
	
	Args:
		state: TransformState to snapshot
		
	Returns:
		Settings dictionary
	"""
	return {
		"snap_enabled": state.snap_enabled,
		"snap_step": state.snap_step,
		"snap_offset": state.snap_offset,
		"snap_y_enabled": state.snap_y_enabled,
		"snap_y_step": state.snap_y_step,
		"snap_rotation_enabled": state.snap_rotation_enabled,
		"snap_rotation_step": state.snap_rotation_step,
		"snap_scale_enabled": state.snap_scale_enabled,
		"snap_scale_step": state.snap_scale_step,
		"current_scale": state.scale_multiplier,
		"current_rotation_degrees": _services.rotation_manager.get_rotation_offset_degrees(state) if _services.rotation_manager else Vector3.ZERO
	}
