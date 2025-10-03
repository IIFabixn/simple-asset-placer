@tool
extends RefCounted

class_name PositionManager

"""
3D POSITIONING AND COLLISION SYSTEM
===================================

PURPOSE: Handles all 3D positioning logic including raycast collision and height management.

RESPONSIBILITIES:
- Mouse-to-world position conversion using camera raycasting  
- Collision detection with configurable layers and masks
- Height offset management (base height + adjustments)
- Smooth interpolation between positions
- Transform mode positioning (maintains height while following mouse)
- Ground snapping and collision-based positioning

ARCHITECTURE POSITION: Pure positioning math and collision logic
- Does NOT handle input detection (receives requests from TransformationManager)
- Does NOT handle UI or overlays  
- Does NOT know about placement/transform modes (works with any node)

USED BY: TransformationManager for all positioning operations
DEPENDS ON: Godot 3D physics system, camera for raycasting
"""

# Current position state
static var current_position: Vector3 = Vector3.ZERO
static var target_position: Vector3 = Vector3.ZERO
static var height_offset: float = 0.0
static var base_height: float = 0.0
static var surface_normal: Vector3 = Vector3.UP  # Normal of the surface at current position
static var is_initial_position: bool = true  # Track if this is the first position update
static var manual_position_offset: Vector3 = Vector3.ZERO  # Accumulated WASD position adjustments
static var last_raycast_xz: Vector2 = Vector2.ZERO  # Track last raycast XZ position (without offsets) for change detection

# Position calculation settings
static var collision_enabled: bool = true
static var snap_to_ground: bool = true
static var height_step_size: float = 0.1
static var collision_mask: int = 1  # Default collision layer
static var snap_enabled: bool = false  # Grid snapping enabled
static var snap_step: float = 1.0  # Grid size for snapping
static var snap_offset: Vector3 = Vector3.ZERO  # Grid offset from world origin
static var snap_y_enabled: bool = false  # Enable Y-axis snapping
static var snap_y_step: float = 1.0  # Grid size for Y-axis snapping
static var snap_center_x: bool = false  # Snap to grid using center position on X-axis
static var snap_center_y: bool = false  # Snap to grid using center position on Y-axis
static var snap_center_z: bool = false  # Snap to grid using center position on Z-axis
static var use_half_step: bool = false  # Use half-step snapping (for CTRL modifier)
static var align_with_normal: bool = false  # Align rotation with surface normal

## Core Position Management

static func update_position_from_mouse(camera: Camera3D, mouse_pos: Vector2, collision_layer: int = 1, lock_y_axis: bool = false) -> Vector3:
	"""Update target position based on mouse position and camera raycast
	lock_y_axis: If true, only XZ is updated after initial setup, Y is calculated from base_height + height_offset
	align_with_normal: Y always follows the surface (updates base_height every frame)
	snap_to_ground + lock_y_axis: base_height only updates when XZ position changes (not from height offset changes)"""
	if not camera:
		return current_position
	
	# Create ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Perform collision detection if enabled
	if collision_enabled:
		var new_pos = _raycast_to_world(from, to, collision_layer)
		if new_pos != Vector3.INF:
			# Determine Y position based on lock_y_axis flag, alignment mode, snap_to_ground, and whether this is initial positioning
			# When aligning with normal, Y should always follow the surface
			# When snap_to_ground with lock_y_axis, only update base_height if XZ changed significantly (not from height offset changes)
			var should_update_base_height = false
			if align_with_normal or not lock_y_axis or is_initial_position:
				should_update_base_height = true
			elif snap_to_ground and lock_y_axis:
				# Only update base height if XZ position changed (not just height offset)
				# Compare against last raycast XZ position to avoid interference from manual_position_offset
				var new_xz = Vector2(new_pos.x, new_pos.z)
				var xz_distance = new_xz.distance_to(last_raycast_xz)
				should_update_base_height = xz_distance > 0.01  # Small threshold to avoid floating point issues
			
			if should_update_base_height:
				# Update base_height from raycast and apply offset
				base_height = new_pos.y
				last_raycast_xz = Vector2(new_pos.x, new_pos.z)  # Store XZ for next frame comparison
				
				# When aligning with normal, apply height offset along the surface normal direction
				if align_with_normal and height_offset != 0.0:
					# Move along the surface normal by the height offset amount
					var offset_vector = surface_normal.normalized() * height_offset
					target_position = new_pos + offset_vector
				else:
					# Standard: just offset Y-axis
					target_position.x = new_pos.x
					target_position.z = new_pos.z
					target_position.y = base_height + height_offset
				
				is_initial_position = false  # Mark that we've set initial position
			else:
				# Use base_height + height_offset (manual control only)
				target_position.x = new_pos.x
				target_position.z = new_pos.z
				target_position.y = base_height + height_offset
			
			# Apply grid snapping if enabled (to base position only)
			if snap_enabled:
				target_position = _apply_grid_snap(target_position)
			
			# Apply manual position offset (from WASD keys) AFTER snapping
			# This allows manual adjustments to work immediately without fighting the snap
			target_position += manual_position_offset
			
			current_position = target_position
			return current_position
	
	# Fallback: project to horizontal plane
	var pos = _project_to_plane(from, to)
	
	# When aligning with normal or not initial, handle Y appropriately
	# When snap_to_ground with lock_y_axis, only update if XZ changed
	var should_update_base_height_fallback = false
	if align_with_normal or not lock_y_axis or is_initial_position:
		should_update_base_height_fallback = true
	elif snap_to_ground and lock_y_axis:
		# Only update base height if XZ position changed
		# Compare against last raycast XZ position to avoid interference from manual_position_offset
		var new_xz = Vector2(pos.x, pos.z)
		var xz_distance = new_xz.distance_to(last_raycast_xz)
		should_update_base_height_fallback = xz_distance > 0.01
	
	if should_update_base_height_fallback:
		# Set base_height from plane and mark as initialized
		base_height = pos.y
		last_raycast_xz = Vector2(pos.x, pos.z)  # Store XZ for next frame comparison
		
		# When aligning with normal, apply height offset along surface normal
		if align_with_normal and height_offset != 0.0:
			var offset_vector = surface_normal.normalized() * height_offset
			pos = pos + offset_vector
		else:
			# Standard Y-axis offset
			pos.y = base_height + height_offset
		
		is_initial_position = false
	else:
		# If Y is locked and not initial, use base_height + offset
		pos.y = base_height + height_offset
	
	# Apply grid snapping if enabled (to base position only)
	if snap_enabled:
		pos = _apply_grid_snap(pos)
	
	# Apply manual position offset (from WASD keys) AFTER snapping
	# This allows manual adjustments to work immediately without fighting the snap
	pos += manual_position_offset
	
	# Update current/target positions before returning
	current_position = pos
	target_position = pos
	
	return pos

static func _raycast_to_world(from: Vector3, to: Vector3, collision_layer: int) -> Vector3:
	"""Perform raycast collision detection"""
	# Get the current 3D world
	var world = EditorInterface.get_edited_scene_root()
	if not world:
		return Vector3.INF
	
	var world_3d = world.get_world_3d()
	if not world_3d:
		return Vector3.INF
	
	# Create ray query
	var space_state = world_3d.direct_space_state
	if not space_state:
		return Vector3.INF
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_layer
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		# Store the surface normal for rotation alignment
		if result.has("normal"):
			surface_normal = result.normal
		else:
			surface_normal = Vector3.UP
		return result.position
	
	# No collision - reset to default up normal
	surface_normal = Vector3.UP
	return Vector3.INF

static func _project_to_plane(from: Vector3, to: Vector3, plane_y: float = 0.0) -> Vector3:
	"""Project ray to horizontal plane when no collision detected"""
	var ray_dir = (to - from).normalized()
	
	# Create horizontal plane at current base_height (NOT including height_offset yet - that's applied by caller)
	var plane = Plane(Vector3.UP, base_height + plane_y)
	var intersection = plane.intersects_ray(from, ray_dir)
	
	# No actual surface, so normal is always up
	surface_normal = Vector3.UP
	
	if intersection:
		return intersection
	
	# If no intersection, return a position at base_height
	return Vector3(from.x, base_height, from.z)

static func _apply_grid_snap(pos: Vector3) -> Vector3:
	"""Apply grid snapping to a position (pivot-based with optional center snapping)"""
	if not snap_enabled or snap_step <= 0.0:
		return pos
	
	# Determine effective snap step (half if modifier active)
	var effective_step_x = snap_step if not use_half_step else snap_step * 0.5
	var effective_step_z = snap_step if not use_half_step else snap_step * 0.5
	var effective_step_y = snap_y_step if not use_half_step else snap_y_step * 0.5
	
	var snapped_pos = pos
	
	# Snap the position directly (no AABB center offset)
	snapped_pos.x = snappedf(pos.x - snap_offset.x, effective_step_x) + snap_offset.x
	snapped_pos.z = snappedf(pos.z - snap_offset.z, effective_step_z) + snap_offset.z
	
	# Handle Y-axis if enabled
	if snap_y_enabled:
		snapped_pos.y = snappedf(pos.y - snap_offset.y, effective_step_y) + snap_offset.y
	else:
		snapped_pos.y = pos.y  # Keep original Y
	
	return snapped_pos

## Height Management

static func update_base_height_from_raycast(y_position: float):
	"""Update base height when a new raycast hit is detected (for initial placement)"""
	base_height = y_position
	target_position.y = base_height + height_offset
	current_position.y = target_position.y

static func adjust_height(delta: float):
	"""Adjust the current height offset (state only - position will be updated on next mouse update)"""
	height_offset += delta

static func increase_height():
	"""Increase height by one step"""
	# Use Y snap step if Y snapping is enabled, otherwise use height step size
	var step = snap_y_step if snap_y_enabled else height_step_size
	adjust_height(step)

static func decrease_height():
	"""Decrease height by one step"""
	# Use Y snap step if Y snapping is enabled, otherwise use height step size
	var step = snap_y_step if snap_y_enabled else height_step_size
	adjust_height(-step)

static func reset_height():
	"""Reset height offset to zero"""
	height_offset = 0.0
	target_position.y = base_height
	current_position = target_position

# Position adjustment functions (camera-relative)
static func move_left(delta: float, camera: Camera3D = null):
	"""Move the position left relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_right_direction(camera) * -1.0  # Left is negative right
	var movement = move_dir * delta
	manual_position_offset += movement

static func move_right(delta: float, camera: Camera3D = null):
	"""Move the position right relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_right_direction(camera)
	var movement = move_dir * delta
	manual_position_offset += movement

static func move_forward(delta: float, camera: Camera3D = null):
	"""Move the position forward relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_forward_direction(camera)
	var movement = move_dir * delta
	manual_position_offset += movement

static func move_backward(delta: float, camera: Camera3D = null):
	"""Move the position backward relative to camera view (state only - position will be updated on next mouse update)"""
	var move_dir = _get_camera_forward_direction(camera) * -1.0  # Backward is negative forward
	var movement = move_dir * delta
	manual_position_offset += movement

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

static func reset_position():
	"""Reset manual position offset to zero"""
	# Remove the current offset from positions
	current_position -= manual_position_offset
	target_position -= manual_position_offset
	# Clear the offset
	manual_position_offset = Vector3.ZERO

static func rotate_manual_offset(axis: String, angle_degrees: float):
	"""Rotate the manual position offset around the specified axis
	This is called when the preview mesh rotates so the offset rotates with it"""
	if manual_position_offset.length_squared() < 0.0001:
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
				manual_position_offset.x,  # X doesn't change
				manual_position_offset.y * cos_angle - manual_position_offset.z * sin_angle,
				manual_position_offset.y * sin_angle + manual_position_offset.z * cos_angle
			)
		"Y":
			# Rotate around Y axis (affects X and Z)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				manual_position_offset.x * cos_angle - manual_position_offset.z * sin_angle,
				manual_position_offset.y,  # Y doesn't change
				manual_position_offset.x * sin_angle + manual_position_offset.z * cos_angle
			)
		"Z":
			# Rotate around Z axis (affects X and Y)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				manual_position_offset.x * cos_angle - manual_position_offset.y * sin_angle,
				manual_position_offset.x * sin_angle + manual_position_offset.y * cos_angle,
				manual_position_offset.z  # Z doesn't change
			)
		_:
			return
	
	# Update positions to account for the rotated offset
	current_position -= manual_position_offset  # Remove old offset
	manual_position_offset = rotated_offset  # Update to rotated offset
	current_position += manual_position_offset  # Apply new offset
	target_position = current_position

static func set_base_height(y: float):
	"""Set the base height reference point"""
	base_height = y
	target_position.y = base_height + height_offset
	current_position = target_position

static func reset_for_new_placement(reset_height_offset: bool = true, reset_position_offset: bool = true):
	"""Reset position manager state for a new placement session
	
	reset_height_offset: If true, reset height_offset to 0. If false, preserve current height.
	reset_position_offset: If true, reset manual_position_offset to 0. If false, preserve current position offset."""
	is_initial_position = true
	if reset_height_offset:
		height_offset = 0.0
	
	current_position = Vector3.ZERO
	target_position = Vector3.ZERO
	base_height = 0.0
	surface_normal = Vector3.UP
	last_raycast_xz = Vector2.ZERO
	if reset_position_offset:
		manual_position_offset = Vector3.ZERO  # Reset WASD offset for new placement

## Position Getters and Setters

static func get_current_position() -> Vector3:
	"""Get the current calculated position"""
	return current_position

static func get_target_position() -> Vector3:
	"""Get the target position (may be different during interpolation)"""
	return target_position

static func set_position(pos: Vector3):
	"""Directly set the current position"""
	current_position = pos
	target_position = pos
	base_height = pos.y
	height_offset = 0.0

static func get_height_offset() -> float:
	"""Get the current height offset from base"""
	return height_offset

static func get_surface_normal() -> Vector3:
	"""Get the surface normal at the current position"""
	return surface_normal

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

static var interpolation_enabled: bool = false
static var interpolation_speed: float = 10.0

static func enable_smooth_positioning(speed: float = 10.0):
	"""Enable smooth position interpolation"""
	interpolation_enabled = true
	interpolation_speed = speed

static func disable_smooth_positioning():
	"""Disable position interpolation"""
	interpolation_enabled = false

static func update_smooth_position(delta: float):
	"""Update position with smooth interpolation (call from _process)"""
	if not interpolation_enabled:
		return
	
	if current_position.distance_to(target_position) > 0.01:
		current_position = current_position.lerp(target_position, interpolation_speed * delta)

## Configuration

static func configure(config: Dictionary):
	"""Configure position manager settings"""
	collision_enabled = config.get("collision_enabled", true)
	snap_to_ground = config.get("snap_to_ground", true) 
	height_step_size = config.get("height_step_size", 0.1)
	collision_mask = config.get("collision_mask", 1)
	interpolation_enabled = config.get("interpolation_enabled", false)
	interpolation_speed = config.get("interpolation_speed", 10.0)
	snap_enabled = config.get("snap_enabled", false)
	snap_step = config.get("snap_step", 1.0)
	snap_offset = config.get("snap_offset", Vector3.ZERO)
	snap_y_enabled = config.get("snap_y_enabled", false)
	snap_y_step = config.get("snap_y_step", 1.0)
	snap_center_x = config.get("snap_center_x", false)
	snap_center_y = config.get("snap_center_y", false)
	snap_center_z = config.get("snap_center_z", false)
	align_with_normal = config.get("align_with_normal", false)

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"collision_enabled": collision_enabled,
		"snap_to_ground": snap_to_ground,
		"height_step_size": height_step_size,
		"collision_mask": collision_mask,
		"interpolation_enabled": interpolation_enabled,
		"snap_enabled": snap_enabled,
		"snap_step": snap_step,
		"interpolation_speed": interpolation_speed
	}

## Transform Node Positioning (for Transform Mode)

static func update_transform_node_position(transform_node: Node3D, camera: Camera3D, mouse_pos: Vector2):
	"""Update position of a transform mode node based on mouse input"""
	if not transform_node or not camera:
		return
	
	# Calculate world position from mouse
	var world_pos = update_position_from_mouse(camera, mouse_pos)
	
	# Position is already calculated with proper height offset in update_position_from_mouse
	# Just apply it directly (no need to recalculate)
	
	if transform_node.is_inside_tree():
		transform_node.global_position = world_pos

static func start_transform_positioning(node: Node3D):
	"""Initialize positioning for transform mode"""
	if node and node.is_inside_tree():
		set_position(node.global_position)
		base_height = node.global_position.y
		height_offset = 0.0  # Reset height offset for transform mode

## Utility Functions

static func get_distance_to_camera(camera: Camera3D) -> float:
	"""Get distance from current position to camera"""
	if camera:
		return current_position.distance_to(camera.global_position)
	return 0.0

static func is_position_in_camera_view(camera: Camera3D) -> bool:
	"""Check if current position is within camera view frustum"""
	if not camera:
		return false
	
	# Simple distance-based check
	var distance = get_distance_to_camera(camera)
	return distance > 0.1 and distance < 1000.0

static func get_surface_normal_at_position(pos: Vector3) -> Vector3:
	"""Get surface normal at a given position (if collision detection finds one)"""
	# This would require more complex collision detection
	# For now, return up vector as default
	return Vector3.UP

## Debug and Visualization

static func debug_print_position_state():
	"""Print current position state for debugging"""
	pass

static func get_position_info() -> Dictionary:
	"""Get comprehensive position information"""
	return {
		"current_position": current_position,
		"target_position": target_position,
		"base_height": base_height,
		"height_offset": height_offset,
		"total_height": base_height + height_offset,
		"is_interpolating": interpolation_enabled and current_position.distance_to(target_position) > 0.01
	}