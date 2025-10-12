@tool
extends "res://addons/simpleassetplacer/placement/placement_strategy.gd"

class_name CollisionPlacementStrategy

"""
COLLISION-BASED PLACEMENT STRATEGY
==================================

PURPOSE: Calculate placement position using physics raycasting and collision detection.

STRATEGY: Cast a ray from the camera through the mouse cursor and find the first
collision point with the scene geometry. This allows placing objects directly on
surfaces at the exact point where they intersect.

FEATURES:
- Physics-based raycast collision detection
- Surface normal extraction for rotation alignment
- Configurable collision layers and masks
- Fallback to plane placement if no collision detected

CONFIGURATION:
- collision_mask: Which physics layers to detect (default: 1)
- collision_layer: Which layer to use for raycasting
- align_with_normal: Whether to extract and return surface normal

USED BY: PlacementStrategyService when user selects collision-based placement"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PlacementStrategy = preload("res://addons/simpleassetplacer/placement/placement_strategy.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

# Configuration
var collision_mask: int = 1
var collision_layer: int = 1
var fallback_height: float = 0.0
var enable_fallback: bool = true

## Strategy Implementation

func calculate_position(from: Vector3, to: Vector3, config: Dictionary) -> PlacementResult:
	"""Calculate position using raycast collision detection"""
	
	# Update configuration from provided config
	collision_mask = config.get("collision_mask", 1)
	collision_layer = config.get("collision_layer", 1)
	fallback_height = config.get("fallback_height", 0.0)
	enable_fallback = config.get("enable_collision_fallback", true)
	
	# Get exclusion list (important for transform mode to avoid self-collision)
	var exclude_nodes = config.get("exclude_nodes", [])
	var exclude_rids = []
	
	# Recursively gather all collision RIDs from the entire hierarchy
	for node in exclude_nodes:
		if node:
			_gather_collision_rids_recursive(node, exclude_rids)
	
	# Get world space state from config or editor scene root
	var space_state: PhysicsDirectSpaceState3D = null
	
	# Try to get from config first (if world_root was passed)
	var world_root = config.get("world_root", null)
	if world_root:
		space_state = PlacementStrategy.get_world_space_state_static(world_root)
	
	# If not available, try to get from EditorInterface (plugin context)
	if not space_state:
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var edited_scene_root = editor_interface.get_edited_scene_root()
			if edited_scene_root:
				space_state = PlacementStrategy.get_world_space_state_static(edited_scene_root)
	
	if not space_state:
		PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "CollisionPlacementStrategy: No space state available")
		return _create_fallback_result(from, to)
	
	# Create and execute ray query with exclusions
	var query = create_ray_query(from, to, collision_mask, exclude_rids)
	var result = space_state.intersect_ray(query)
	
	if result:
		# Collision detected - extract position and normal
		var position = result.position
		var normal = result.get("normal", Vector3.UP)
		var distance = from.distance_to(position)
		
		return PlacementResult.new(position, normal, true, distance)
	
	# No collision - use fallback if enabled
	if enable_fallback:
		return _create_fallback_result(from, to)
	
	# No fallback - return invalid result
	return PlacementResult.new(Vector3.INF, Vector3.UP, false, 0.0)

func get_strategy_name() -> String:
	return "Collision Placement"

func get_strategy_type() -> String:
	return "collision"

func configure(config: Dictionary) -> void:
	"""Configure collision strategy settings"""
	collision_mask = config.get("collision_mask", 1)
	collision_layer = config.get("collision_layer", 1)
	fallback_height = config.get("fallback_height", 0.0)
	enable_fallback = config.get("enable_collision_fallback", true)

func reset() -> void:
	"""Reset strategy to defaults"""
	collision_mask = 1
	collision_layer = 1
	fallback_height = 0.0
	enable_fallback = true

## Private Methods

func _create_fallback_result(from: Vector3, to: Vector3) -> PlacementResult:
	"""Create fallback result when no collision is detected"""
	var ray_dir = (to - from).normalized()
	var position = project_to_horizontal_plane(from, ray_dir, fallback_height)
	var distance = from.distance_to(position)
	
	# Fallback always has UP normal and no collision
	return PlacementResult.new(position, Vector3.UP, false, distance)

func _gather_collision_rids_recursive(node: Node, rids: Array) -> void:
	"""Recursively gather all collision RIDs from node and its hierarchy
	
	This is crucial for transform mode to avoid self-collision. Gathers RIDs from
	CollisionObject3D nodes in the entire hierarchy.
	
	Args:
		node: Root node to start gathering from
		rids: Array to append RIDs to (modified in place)
	"""
	if not NodeUtils.is_valid(node):
		return
	
	# Handle CollisionObject3D nodes (StaticBody3D, RigidBody3D, Area3D, CharacterBody3D, etc.)
	if node is CollisionObject3D:
		var node_rid = node.get_rid()
		if node_rid and node_rid.is_valid() and not rids.has(node_rid):
			rids.append(node_rid)
	
	# Note: CSG nodes manage collision internally via automatically created StaticBody3D children
	# These are handled by the normal CollisionObject3D check above
	
	# Recursively process all children to catch nested structures
	for child in node.get_children():
		_gather_collision_rids_recursive(child, rids)







