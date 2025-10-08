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

USED BY: PlacementStrategyManager to delegate positioning calculations
"""

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
	push_error("PlacementStrategy.calculate_position() must be overridden in subclass")
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

static func get_world_space_state() -> PhysicsDirectSpaceState3D:
	"""Helper to get the current 3D world space state for raycasting"""
	var world = EditorInterface.get_edited_scene_root()
	if not world:
		return null
	
	var world_3d = world.get_world_3d()
	if not world_3d:
		return null
	
	return world_3d.direct_space_state

static func project_to_horizontal_plane(from: Vector3, direction: Vector3, plane_height: float) -> Vector3:
	"""Helper to project a ray onto a horizontal plane at given height"""
	var plane = Plane(Vector3.UP, plane_height)
	var intersection = plane.intersects_ray(from, direction)
	
	if intersection:
		return intersection
	
	# If no intersection, return position at plane height
	return Vector3(from.x, plane_height, from.z)







