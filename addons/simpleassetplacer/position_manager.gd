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

# Position calculation settings
static var collision_enabled: bool = true
static var snap_to_ground: bool = true
static var height_step_size: float = 0.1
static var collision_mask: int = 1  # Default collision layer

## Core Position Management

static func update_position_from_mouse(camera: Camera3D, mouse_pos: Vector2, collision_layer: int = 1) -> Vector3:
	"""Update target position based on mouse position and camera raycast"""
	if not camera:
		return current_position
	
	# Create ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Perform collision detection if enabled
	if collision_enabled:
		var new_pos = _raycast_to_world(from, to, collision_layer)
		if new_pos != Vector3.INF:
			target_position = new_pos + Vector3(0, height_offset, 0)
			current_position = target_position
			return current_position
	
	# Fallback: project to horizontal plane
	return _project_to_plane(from, to)

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
		return result.position
	
	return Vector3.INF

static func _project_to_plane(from: Vector3, to: Vector3, plane_y: float = 0.0) -> Vector3:
	"""Project ray to horizontal plane when no collision detected"""
	var ray_dir = (to - from).normalized()
	
	# Create horizontal plane
	var plane = Plane(Vector3.UP, base_height + height_offset + plane_y)
	var intersection = plane.intersects_ray(from, ray_dir)
	
	if intersection:
		target_position = intersection
		current_position = target_position
		return current_position
	
	return current_position

## Height Management

static func adjust_height(delta: float):
	"""Adjust the current height offset"""
	height_offset += delta
	target_position.y = base_height + height_offset
	current_position = target_position

static func increase_height():
	"""Increase height by one step"""
	adjust_height(height_step_size)

static func decrease_height():
	"""Decrease height by one step"""
	adjust_height(-height_step_size)

static func reset_height():
	"""Reset height offset to zero"""
	height_offset = 0.0
	target_position.y = base_height
	current_position = target_position

static func set_base_height(y: float):
	"""Set the base height reference point"""
	base_height = y
	target_position.y = base_height + height_offset
	current_position = target_position

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

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"collision_enabled": collision_enabled,
		"snap_to_ground": snap_to_ground,
		"height_step_size": height_step_size,
		"collision_mask": collision_mask,
		"interpolation_enabled": interpolation_enabled,
		"interpolation_speed": interpolation_speed
	}

## Transform Node Positioning (for Transform Mode)

static func update_transform_node_position(transform_node: Node3D, camera: Camera3D, mouse_pos: Vector2):
	"""Update position of a transform mode node based on mouse input"""
	if not transform_node or not camera:
		return
	
	# Calculate world position from mouse
	var world_pos = update_position_from_mouse(camera, mouse_pos)
	
	# Apply position to transform node (with height offset applied)
	world_pos.y = base_height + height_offset
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
	print("PositionManager State:")
	print("  Current Position: ", current_position)
	print("  Target Position: ", target_position)
	print("  Base Height: ", base_height)
	print("  Height Offset: ", height_offset)
	print("  Collision Enabled: ", collision_enabled)

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