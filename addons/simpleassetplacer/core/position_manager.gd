@tool
extends "res://addons/simpleassetplacer/core/instance_manager_base.gd"

class_name PositionManager

# === SINGLETON INSTANCE ===

static var _instance: PositionManager = null

static func _set_instance(instance: InstanceManagerBase) -> void:
	_instance = instance as PositionManager

static func _get_instance() -> InstanceManagerBase:
	return _instance

static func has_instance() -> bool:
	return _instance != null and is_instance_valid(_instance)

"""
3D POSITIONING AND COLLISION SYSTEM (REFACTORED - STATELESS)
============================================================

PURPOSE: Pure position calculation service working with TransformState.

RESPONSIBILITIES:
- Position calculations using placement strategies
- Height offset calculations
- Grid snapping calculations
- Position constraint validation
- Camera-relative movement calculations

ARCHITECTURE POSITION: Pure calculation service with NO state storage
- Does NOT store position state (uses TransformState)
- Does NOT handle input detection
- Does NOT handle UI or overlays
- Delegates actual raycasting to PlacementStrategyManager
- Focused solely on position math

REFACTORED: State moved to TransformState
PHASE 5.2: Converted to instance-based architecture with hybrid static pattern

USED BY: TransformationManager for positioning calculations
DEPENDS ON: TransformState, PlacementStrategyManager, IncrementCalculator
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")
const PlacementStrategy = preload("res://addons/simpleassetplacer/placement/placement_strategy.gd")
const IncrementCalculator = preload("res://addons/simpleassetplacer/utils/increment_calculator.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# Instance variables (Phase 5.2: Instance-based architecture)
var __height_step_size: float = 0.1
var __collision_mask: int = 1
var __use_half_step: bool = false
var __align_with_normal: bool = false
var __snap_to_ground: bool = true
var __interpolation_enabled: bool = false
var __interpolation_speed: float = 10.0

# Static properties forwarding to instance (Phase 5.2: Hybrid pattern)
static var height_step_size: float:
	get: return _get_instance().__height_step_size if has_instance() else 0.1
	set(value): if has_instance(): _get_instance().__height_step_size = value

static var collision_mask: int:
	get: return _get_instance().__collision_mask if has_instance() else 1
	set(value): if has_instance(): _get_instance().__collision_mask = value

static var use_half_step: bool:
	get: return _get_instance().__use_half_step if has_instance() else false
	set(value): if has_instance(): _get_instance().__use_half_step = value

static var align_with_normal: bool:
	get: return _get_instance().__align_with_normal if has_instance() else false
	set(value): if has_instance(): _get_instance().__align_with_normal = value

static var snap_to_ground: bool:
	get: return _get_instance().__snap_to_ground if has_instance() else true
	set(value): if has_instance(): _get_instance().__snap_to_ground = value

static var interpolation_enabled: bool:
	get: return _get_instance().__interpolation_enabled if has_instance() else false
	set(value): if has_instance(): _get_instance().__interpolation_enabled = value

static var interpolation_speed: float:
	get: return _get_instance().__interpolation_speed if has_instance() else 10.0
	set(value): if has_instance(): _get_instance().__interpolation_speed = value

## Core Position Management (REFACTORED)

static func update_position_from_mouse(state: TransformState, camera: Camera3D, mouse_pos: Vector2, collision_layer: int = 1, lock_y_axis: bool = false, exclude_nodes: Array = []) -> Vector3:
	"""Update target position based on mouse position using placement strategy
	
	Args:
		state: TransformState to update
		camera: Camera3D for ray projection
		mouse_pos: Mouse position in viewport coordinates
		collision_layer: Physics collision layer (legacy, now in config)
		lock_y_axis: If true, only XZ updates after initial setup
		exclude_nodes: Array of Node3D objects to exclude from collision (for transform mode)
	
	Returns:
		Calculated world position
	"""
	if not camera or not is_instance_valid(camera):
		PluginLogger.warning("PositionManager", "Invalid camera reference")
		return state.position
	
	if not state:
		PluginLogger.error("PositionManager", "Invalid TransformState reference")
		return Vector3.ZERO
	
	# Create ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Pass exclusion list to strategy manager (important for transform mode)
	var exclude_config = {"exclude_nodes": exclude_nodes} if exclude_nodes.size() > 0 else {}
	
	# Use strategy manager to calculate position with exclusions
	var result: PlacementStrategy.PlacementResult = PlacementStrategyManager.calculate_position(from, to, exclude_config)
	
	# Check if we got a valid result (null check added)
	if not result or result.position == Vector3.INF:
		# Invalid result - keep current position
		PluginLogger.debug("PositionManager", "Invalid placement result, keeping current position")
		return state.position
	
	var new_pos = result.position
	
	# Update surface normal for rotation alignment
	state.surface_normal = result.normal
	
	# Determine Y position based on lock_y_axis flag, alignment mode, and whether this is initial positioning
	var should_update_base_height = false
	
	if align_with_normal or not lock_y_axis or state.is_initial_position:
		should_update_base_height = true
	elif lock_y_axis:
		# Only update base height if XZ position changed significantly
		var new_xz = Vector2(new_pos.x, new_pos.z)
		var xz_distance = new_xz.distance_to(state.last_raycast_xz)
		should_update_base_height = xz_distance > 0.1
	
	if should_update_base_height:
		# Update base_height from strategy result
		state.base_height = new_pos.y
		state.last_raycast_xz = Vector2(new_pos.x, new_pos.z)
		
		# When aligning with normal, apply height offset along the surface normal direction
		if align_with_normal and state.height_offset != 0.0:
			var offset_vector = state.surface_normal.normalized() * state.height_offset
			state.target_position = new_pos + offset_vector
		else:
			# Standard: just offset Y-axis
			state.target_position.x = new_pos.x
			state.target_position.z = new_pos.z
			state.target_position.y = state.base_height + state.height_offset
		
		state.is_initial_position = false
	else:
		# Use base_height + height_offset (manual control only)
		state.target_position.x = new_pos.x
		state.target_position.z = new_pos.z
		state.target_position.y = state.base_height + state.height_offset
	
	# Apply grid snapping if enabled (to base position only)
	if state.snap_enabled:
		state.target_position = _apply_grid_snap(state, state.target_position)
	
	# Apply manual position offset (from WASD keys) AFTER snapping
	state.target_position += state.manual_position_offset
	
	# Update current position
	state.position = state.target_position
	
	return state.position

static func _apply_grid_snap(state: TransformState, pos: Vector3) -> Vector3:
	"""Apply grid snapping to a position (pivot-based with optional center snapping)"""
	if not state.snap_enabled or state.snap_step <= 0.0:
		return pos
	
	# Determine effective snap step (half if modifier active)
	var effective_step_x = state.snap_step if not use_half_step else state.snap_step * 0.5
	var effective_step_z = state.snap_step if not use_half_step else state.snap_step * 0.5
	var effective_step_y = state.snap_y_step if not use_half_step else state.snap_y_step * 0.5
	
	var snapped_pos = pos
	
	# Snap the position directly (no AABB center offset)
	snapped_pos.x = snappedf(pos.x - state.snap_offset.x, effective_step_x) + state.snap_offset.x
	snapped_pos.z = snappedf(pos.z - state.snap_offset.z, effective_step_z) + state.snap_offset.z
	
	# Handle Y-axis if enabled
	if state.snap_y_enabled:
		snapped_pos.y = snappedf(pos.y - state.snap_offset.y, effective_step_y) + state.snap_offset.y
	else:
		snapped_pos.y = pos.y  # Keep original Y
	
	return snapped_pos

## Height Management

static func update_base_height_from_raycast(state: TransformState, y_position: float) -> void:
	"""Update base height when a new raycast hit is detected (for initial placement)"""
	state.base_height = y_position
	state.target_position.y = state.base_height + state.height_offset
	state.position.y = state.target_position.y

static func adjust_height(state: TransformState, delta: float) -> void:
	"""Adjust the current height offset (state only - position will be updated on next mouse update)"""
	state.height_offset += delta

static func adjust_height_with_modifiers(state: TransformState, base_delta: float, modifiers: Dictionary) -> void:
	"""Adjust height with modifier-calculated step
	
	Args:
		state: TransformState to modify
		base_delta: Base height step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_height_step(base_delta, modifiers)
	adjust_height(state, step)

static func increase_height(state: TransformState) -> void:
	"""Increase height by one step"""
	# Use Y snap step if Y snapping is enabled, otherwise use height step size
	var step = state.snap_y_step if state.snap_y_enabled else height_step_size
	adjust_height(state, step)

static func decrease_height(state: TransformState) -> void:
	"""Decrease height by one step"""
	# Use Y snap step if Y snapping is enabled, otherwise use height step size
	var step = state.snap_y_step if state.snap_y_enabled else height_step_size
	adjust_height(state, -step)

static func reset_height(state: TransformState) -> void:
	"""Reset height offset to zero"""
	state.height_offset = 0.0
	state.target_position.y = state.base_height
	state.position = state.target_position

# Position adjustment functions (camera-relative)
static func move_left(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position left relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_right_direction(camera) * -1.0  # Left is negative right
	var movement = move_dir * delta
	state.manual_position_offset += movement

static func move_right(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position right relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_right_direction(camera)
	var movement = move_dir * delta
	state.manual_position_offset += movement

static func move_forward(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position forward relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_forward_direction(camera)
	var movement = move_dir * delta
	state.manual_position_offset += movement

static func move_backward(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position backward relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_forward_direction(camera) * -1.0  # Backward is negative forward
	var movement = move_dir * delta
	state.manual_position_offset += movement

static func move_direction_with_modifiers(state: TransformState, direction: String, base_delta: float, modifiers: Dictionary, camera: Camera3D = null) -> void:
	"""Move in a direction with modifier-calculated step
	
	Args:
		state: TransformState to modify
		direction: Movement direction ("left", "right", "forward", "backward")
		base_delta: Base movement step (e.g., 0.5 units)
		modifiers: Modifier state from InputHandler.get_modifier_state()
		camera: Camera for relative movement
	"""
	var step = IncrementCalculator.calculate_position_step(base_delta, modifiers)
	
	match direction.to_lower():
		"left":
			move_left(state, step, camera)
		"right":
			move_right(state, step, camera)
		"forward":
			move_forward(state, step, camera)
		"backward":
			move_backward(state, step, camera)
		_:
			PluginLogger.warning("PositionManager", "Invalid direction: " + direction)

static func _get_camera_forward_direction(camera: Camera3D) -> Vector3:
	"""Get the nearest axis-aligned direction for camera forward (snaps to +Z or -Z or +X or -X)"""
	if not camera:
		return Vector3(0, 0, -1)  # Default forward
	
	# Get camera forward direction and project onto XZ plane (ignore Y)
	var forward = -camera.global_transform.basis.z
	forward.y = 0  # Project to ground plane
	forward = forward.normalized()
	
	# Snap to nearest axis (Z or X)
	if abs(forward.z) > abs(forward.x):
		# Primarily Z-axis movement
		return Vector3(0, 0, sign(forward.z))
	else:
		# Primarily X-axis movement
		return Vector3(sign(forward.x), 0, 0)

static func _get_camera_right_direction(camera: Camera3D) -> Vector3:
	"""Get the nearest axis-aligned direction for camera right (snaps to +X or -X or +Z or -Z)"""
	if not camera:
		return Vector3(1, 0, 0)  # Default right
	
	# Get camera right direction and project onto XZ plane (ignore Y)
	var right = camera.global_transform.basis.x
	right.y = 0  # Project to ground plane
	right = right.normalized()
	
	# Snap to nearest axis (X or Z)
	if abs(right.x) > abs(right.z):
		# Primarily X-axis movement
		return Vector3(sign(right.x), 0, 0)
	else:
		# Primarily Z-axis movement
		return Vector3(0, 0, sign(right.z))

static func reset_position(state: TransformState) -> void:
	"""Reset manual position offset to zero"""
	# Remove the current offset from positions
	state.position -= state.manual_position_offset
	state.target_position -= state.manual_position_offset
	# Clear the offset
	state.manual_position_offset = Vector3.ZERO

static func rotate_manual_offset(state: TransformState, axis: String, angle_degrees: float) -> void:
	"""Rotate the manual position offset around the specified axis
	This is called when the preview mesh rotates so the offset rotates with it"""
	if state.manual_position_offset.length_squared() < 0.0001:
		# No offset to rotate
		return
	
	# Convert degrees to radians
	var angle_rad = deg_to_rad(angle_degrees)
	
	var rotated_offset = Vector3.ZERO
	
	# Rotate around the specified axis
	match axis.to_upper():
		"X":
			# Rotate around X axis (affects Y and Z)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.manual_position_offset.x,  # X doesn't change
				state.manual_position_offset.y * cos_angle - state.manual_position_offset.z * sin_angle,
				state.manual_position_offset.y * sin_angle + state.manual_position_offset.z * cos_angle
			)
		"Y":
			# Rotate around Y axis (affects X and Z)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.manual_position_offset.x * cos_angle - state.manual_position_offset.z * sin_angle,
				state.manual_position_offset.y,  # Y doesn't change
				state.manual_position_offset.x * sin_angle + state.manual_position_offset.z * cos_angle
			)
		"Z":
			# Rotate around Z axis (affects X and Y)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.manual_position_offset.x * cos_angle - state.manual_position_offset.y * sin_angle,
				state.manual_position_offset.x * sin_angle + state.manual_position_offset.y * cos_angle,
				state.manual_position_offset.z  # Z doesn't change
			)
		_:
			return
	
	# Update positions to account for the rotated offset
	state.position -= state.manual_position_offset  # Remove old offset
	state.manual_position_offset = rotated_offset  # Update to rotated offset
	state.position += state.manual_position_offset  # Apply new offset
	state.target_position = state.position

static func set_base_height(state: TransformState, y: float) -> void:
	"""Set the base height reference point"""
	state.base_height = y
	state.target_position.y = state.base_height + state.height_offset
	state.position = state.target_position

static func reset_for_new_placement(state: TransformState, reset_height_offset: bool = true, reset_position_offset: bool = true) -> void:
	"""Reset position manager state for a new placement session
	
	reset_height_offset: If true, reset height_offset to 0. If false, preserve current height.
	reset_position_offset: If true, reset manual_position_offset to 0. If false, preserve current position offset."""
	state.is_initial_position = true
	if reset_height_offset:
		state.height_offset = 0.0
	
	state.position = Vector3.ZERO
	state.target_position = Vector3.ZERO
	state.base_height = 0.0
	state.surface_normal = Vector3.UP
	state.last_raycast_xz = Vector2.ZERO
	if reset_position_offset:
		state.manual_position_offset = Vector3.ZERO  # Reset WASD offset for new placement

## Position Getters and Setters

static func get_current_position(state: TransformState) -> Vector3:
	"""Get the current calculated position"""
	return state.position

static func get_target_position(state: TransformState) -> Vector3:
	"""Get the target position (may be different during interpolation)"""
	return state.target_position

static func set_position(state: TransformState, pos: Vector3) -> void:
	"""Directly set the current position"""
	state.position = pos
	state.target_position = pos
	state.base_height = pos.y
	state.height_offset = 0.0

static func get_height_offset(state: TransformState) -> float:
	"""Get the current height offset from base"""
	return state.height_offset

static func get_base_position(state: TransformState) -> Vector3:
	"""Get the base position (current position without height offset applied)
	This is useful for positioning the grid overlay at ground level"""
	var base_pos = state.position
	base_pos.y = state.base_height
	return base_pos

static func get_surface_normal(state: TransformState) -> Vector3:
	"""Get the surface normal at the current position"""
	return state.surface_normal

## Position Validation and Constraints

static func is_valid_position(pos: Vector3) -> bool:
	"""Check if a position is valid for object placement"""
	# Basic bounds checking
	if abs(pos.x) > 10000 or abs(pos.z) > 10000:
		return false
	
	# Check for reasonable Y values
	if pos.y < -1000 or pos.y > 1000:
		return false
	
	return true

static func clamp_position_to_bounds(pos: Vector3, bounds: AABB = AABB()) -> Vector3:
	"""Clamp position to specified bounds"""
	if bounds.size == Vector3.ZERO:
		# Default bounds if none specified
		bounds = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	
	return Vector3(
		clampf(pos.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(pos.y, bounds.position.y, bounds.position.y + bounds.size.y),
		clampf(pos.z, bounds.position.z, bounds.position.z + bounds.size.z)
	)

## Position Interpolation and Smoothing

static func enable_smooth_positioning(speed: float = 10.0) -> void:
	"""Enable smooth position interpolation"""
	interpolation_enabled = true
	interpolation_speed = speed

static func disable_smooth_positioning() -> void:
	"""Disable position interpolation"""
	interpolation_enabled = false

static func update_smooth_position(state: TransformState, delta: float) -> void:
	"""Update position with smooth interpolation (call from _process)"""
	if not interpolation_enabled:
		return
	
	if state.position.distance_to(state.target_position) > 0.01:
		state.position = state.position.lerp(state.target_position, interpolation_speed * delta)

## Configuration

static func configure(state: TransformState, config: Dictionary) -> void:
	"""Configure position manager settings and placement strategies"""
	# Configure global settings
	snap_to_ground = config.get("snap_to_ground", true)
	height_step_size = config.get("height_step_size", 0.1)
	collision_mask = config.get("collision_mask", 1)
	interpolation_enabled = config.get("interpolation_enabled", false)
	interpolation_speed = config.get("interpolation_speed", 10.0)
	align_with_normal = config.get("align_with_normal", false)
	
	# Configure state-specific settings
	state.snap_enabled = config.get("snap_enabled", false)
	state.snap_step = config.get("snap_step", 1.0)
	state.snap_offset = config.get("snap_offset", Vector3.ZERO)
	state.snap_y_enabled = config.get("snap_y_enabled", false)
	state.snap_y_step = config.get("snap_y_step", 1.0)
	state.snap_center_x = config.get("snap_center_x", false)
	state.snap_center_y = config.get("snap_center_y", false)
	state.snap_center_z = config.get("snap_center_z", false)
	
	# Configure placement strategy manager
	PlacementStrategyManager.configure(config)

static func get_configuration(state: TransformState) -> Dictionary:
	"""Get current configuration"""
	return {
		"snap_to_ground": snap_to_ground,
		"height_step_size": height_step_size,
		"collision_mask": collision_mask,
		"interpolation_enabled": interpolation_enabled,
		"snap_enabled": state.snap_enabled,
		"snap_step": state.snap_step,
		"interpolation_speed": interpolation_speed,
		"align_with_normal": align_with_normal,
		"placement_strategy": PlacementStrategyManager.get_active_strategy_type()
	}

## Transform Node Positioning (for Transform Mode)

static func update_transform_node_position(state: TransformState, transform_node: Node3D, camera: Camera3D, mouse_pos: Vector2) -> void:
	"""Update position of a transform mode node based on mouse input"""
	if not transform_node or not camera:
		return
	
	# Calculate world position from mouse
	var world_pos = update_position_from_mouse(state, camera, mouse_pos)
	
	# Position is already calculated with proper height offset in update_position_from_mouse
	# Just apply it directly (no need to recalculate)
	
	if transform_node.is_inside_tree():
		transform_node.global_position = world_pos

static func start_transform_positioning(state: TransformState, node: Node3D) -> void:
	"""Initialize positioning for transform mode"""
	if node and node.is_inside_tree():
		set_position(state, node.global_position)
		state.base_height = node.global_position.y
		state.height_offset = 0.0  # Reset height offset for transform mode

## Utility Functions

static func get_distance_to_camera(state: TransformState, camera: Camera3D) -> float:
	"""Get distance from current position to camera"""
	if camera:
		return state.position.distance_to(camera.global_position)
	return 0.0

static func is_position_in_camera_view(state: TransformState, camera: Camera3D) -> bool:
	"""Check if current position is within camera view frustum"""
	if not camera:
		return false
	
	# Simple distance-based check
	var distance = get_distance_to_camera(state, camera)
	return distance > 0.1 and distance < 1000.0

static func get_surface_normal_at_position(pos: Vector3) -> Vector3:
	"""Get surface normal at a given position (if collision detection finds one)"""
	# This would require more complex collision detection
	# For now, return up vector as default
	return Vector3.UP

## Debug and Visualization

static func debug_print_position_state(state: TransformState) -> void:
	"""Print current position state for debugging"""
	PluginLogger.debug("PositionManager", "Position: %v, Height: %.2f" % [state.position, state.height_offset])

static func get_position_info(state: TransformState) -> Dictionary:
	"""Get comprehensive position information"""
	return {
		"current_position": state.position,
		"target_position": state.target_position,
		"base_height": state.base_height,
		"height_offset": state.height_offset,
		"total_height": state.base_height + state.height_offset,
		"is_interpolating": interpolation_enabled and state.position.distance_to(state.target_position) > 0.01
	}






