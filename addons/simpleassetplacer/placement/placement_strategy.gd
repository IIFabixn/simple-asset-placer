@tool
extends RefCounted

class_name PlacementStrategy

"""
PLACEMENT STRATEGY BASE CLASS (STRATEGY PATTERN)
================================================

PURPOSE: Abstract base class defining the interface for different placement strategies.

STRATEGY PATTERN: Each placement strategy implements a different approach to calculating
where objects should be placed in the 3D world based on mouse input.

RESPONSIBILITIES:
- Define common interface for all placement strategies
- Provide result structure for placement calculations
- Allow strategies to be swapped at runtime

IMPLEMENTATIONS:
- CollisionPlacementStrategy: Raycast-based collision detection
- PlanePlacementStrategy: Fixed horizontal plane projection

USED BY: PlacementStrategyService to delegate positioning calculations"""

# Result structure returned by placement strategies
class PlacementResult:
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var hit_collision: bool = false
	var distance_from_camera: float = 0.0
	
	func _init(p_position: Vector3 = Vector3.ZERO, p_normal: Vector3 = Vector3.UP, p_hit: bool = false, p_distance: float = 0.0):
		position = p_position
		normal = p_normal
		hit_collision = p_hit
		distance_from_camera = p_distance

## Virtual Methods (Override in subclasses)

func calculate_position(from: Vector3, to: Vector3, config: Dictionary) -> PlacementResult:
	"""Calculate world position based on camera ray
	
	Args:
		from: Ray origin (camera position)
		to: Ray end point (camera forward * 1000)
		config: Strategy configuration dictionary
	
	Returns:
		PlacementResult with position, normal, and metadata
	"""
	PluginLogger.error("PlacementStrategy", "calculate_position() must be overridden in subclass")
	return PlacementResult.new()

func get_strategy_name() -> String:
	"""Return human-readable name of this strategy"""
	return "Base Strategy"

func get_strategy_type() -> String:
	"""Return internal identifier for this strategy (e.g., 'collision', 'plane')"""
	return "base"

func configure(config: Dictionary) -> void:
	"""Configure strategy with settings dictionary"""
	pass

func reset() -> void:
	"""Reset strategy state"""
	pass

## Utility Methods (Available to all strategies)

static func create_ray_query(from: Vector3, to: Vector3, collision_mask: int, exclude: Array = []) -> PhysicsRayQueryParameters3D:
	"""Helper to create a physics ray query with common settings
	
	Args:
		from: Ray start position
		to: Ray end position
		collision_mask: Collision mask for filtering
		exclude: Array of RIDs to exclude from collision (e.g., the node being transformed)
	"""
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclude specified objects (important for transform mode to avoid self-collision)
	if exclude.size() > 0:
		query.exclude = exclude
	
	return query

func get_world_space_state() -> PhysicsDirectSpaceState3D:
	"""Helper to get the current 3D world space state for raycasting
	
	Note: This method can remain as instance method since PlacementStrategy
	is used through PlacementStrategyService which has ServiceRegistry access.
	The service will provide the world root through configuration.
	"""
	# This will be called by subclasses that need world state
	# The world root should be passed via config dictionary
	return null  # Subclasses should override or get from config

static func get_world_space_state_static(world_root: Node) -> PhysicsDirectSpaceState3D:
	"""Static helper to get world space state from any node in the scene tree
	
	This function accepts any Node type and will:
	1. If it's a Node3D, use it directly
	2. Otherwise, search for a Node3D in the hierarchy
	3. Fall back to viewport's World3D if available
	"""
	if not world_root:
		return null
	
	if not world_root.is_inside_tree():
		return null
	
	var node_3d: Node3D = null
	
	# If world_root is already a Node3D, use it
	if world_root is Node3D:
		node_3d = world_root
	else:
		# Search for any Node3D in the scene hierarchy
		node_3d = _find_node_3d_recursive(world_root)
	
	# Try to get World3D from Node3D
	if node_3d:
		var world_3d = node_3d.get_world_3d()
		if world_3d:
			return world_3d.direct_space_state
	
	# Fallback: try viewport directly (works if 3D scene is open in editor)
	var viewport = world_root.get_viewport()
	if viewport:
		var world_3d = viewport.get_world_3d()
		if world_3d:
			return world_3d.direct_space_state
	
	return null

static func _find_node_3d_recursive(node: Node) -> Node3D:
	"""Recursively find the first Node3D in the hierarchy"""
	if node is Node3D:
		return node
	
	for child in node.get_children():
		var found = _find_node_3d_recursive(child)
		if found:
			return found
	
	return null

static func project_to_horizontal_plane(from: Vector3, direction: Vector3, plane_height: float, fallback: Vector3 = Vector3.ZERO, use_fallback: bool = false) -> Vector3:
	"""Helper to project a ray onto a horizontal plane at given height (XZ plane)
	
	Godot Plane: The 'd' parameter is the distance from origin along the normal.
	For a plane at Y=y0, with normal pointing in +Y (UP = (0,1,0)):
	- Plane equation: dot(normal, point) = d
	- For point on plane: (0,1,0)·(x,y0,z) = y0
	- So d = plane_height (the Y coordinate itself)
	"""
	var plane = Plane(Vector3.UP, plane_height)
	var intersection = plane.intersects_ray(from, direction)
    
	if intersection:
		return intersection
    
	if use_fallback:
		var result = fallback
		result.y = plane_height
		return result
    
	# If no intersection, return position at plane height
	return Vector3(from.x, plane_height, from.z)

static func project_to_xy_plane(from: Vector3, direction: Vector3, plane_distance: float, fallback: Vector3 = Vector3.ZERO, use_fallback: bool = false) -> Vector3:
	"""Helper to project a ray onto a vertical XY plane at given Z distance
	
	Godot Plane: The 'd' parameter is the distance from origin along the normal.
	For a plane at Z=z0, with normal pointing in +Z (BACK = (0,0,1)):
	- Plane equation: dot(normal, point) = d
	- For point on plane: (0,0,1)·(x,y,z0) = z0
	- So d = plane_distance (the Z coordinate itself)
	"""
	var plane = Plane(Vector3.BACK, plane_distance)
	var intersection = plane.intersects_ray(from, direction)
    
	if intersection:
		return intersection
    
	if use_fallback:
		var result = fallback
		result.z = plane_distance
		return result
    
	# If no intersection, return position at plane distance
	return Vector3(from.x, from.y, plane_distance)

static func project_to_yz_plane(from: Vector3, direction: Vector3, plane_distance: float, fallback: Vector3 = Vector3.ZERO, use_fallback: bool = false) -> Vector3:
	"""Helper to project a ray onto a vertical YZ plane at given X distance
	
	Godot Plane: The 'd' parameter is the distance from origin along the normal.
	For a plane at X=x0, with normal pointing in +X (RIGHT = (1,0,0)):
	- Plane equation: dot(normal, point) = d
	- For point on plane: (1,0,0)·(x0,y,z) = x0
	- So d = plane_distance (the X coordinate itself)
	"""
	var plane = Plane(Vector3.RIGHT, plane_distance)
	var intersection = plane.intersects_ray(from, direction)
    
	if intersection:
		return intersection
    
	if use_fallback:
		var result = fallback
		result.x = plane_distance
		return result
    
	# If no intersection, return position at plane distance
	return Vector3(plane_distance, from.y, from.z)







