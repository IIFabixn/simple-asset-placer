@tool
extends RefCounted

class_name PlacementStrategyService

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PlacementStrategy = preload("res://addons/simpleassetplacer/placement/placement_strategy.gd")
const CollisionPlacementStrategy = preload("res://addons/simpleassetplacer/placement/collision_placement_strategy.gd")
const PlanePlacementStrategy = preload("res://addons/simpleassetplacer/placement/plane_placement_strategy.gd")

var _collision_strategy: CollisionPlacementStrategy
var _plane_strategy: PlanePlacementStrategy
var _active_strategy: PlacementStrategy
var _active_strategy_type: String = "collision"
var _config: Dictionary = {}

func initialize() -> void:
	"""Initialize placement strategies and default configuration"""
	if not _collision_strategy:
		_collision_strategy = CollisionPlacementStrategy.new()
	if not _plane_strategy:
		_plane_strategy = PlanePlacementStrategy.new()
	if not _active_strategy:
		_active_strategy = _collision_strategy
		_active_strategy_type = "collision"
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, "PlacementStrategyService initialized")

func cleanup() -> void:
	"""Release strategy references"""
	_collision_strategy = null
	_plane_strategy = null
	_active_strategy = null
	_active_strategy_type = "collision"
	_config.clear()

func set_strategy(strategy_type: String) -> bool:
	"""Activate the requested strategy"""
	_initialize_if_needed()
	var normalized := strategy_type.to_lower()
	if normalized == _active_strategy_type:
		return false
	match normalized:
		"collision":
			_active_strategy = _collision_strategy
			_active_strategy_type = "collision"
			PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Switched to collision placement strategy")
			return true
		"plane":
			_active_strategy = _plane_strategy
			_active_strategy_type = "plane"
			PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Switched to plane placement strategy")
			return true
		_:
			PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "Invalid strategy type: %s" % strategy_type)
			return false

func get_active_strategy_type() -> String:
	_initialize_if_needed()
	return _active_strategy_type

func get_active_strategy_name() -> String:
	_initialize_if_needed()
	return _active_strategy.get_strategy_name() if _active_strategy else "None"

func cycle_strategy() -> String:
	"""Cycle between available strategies"""
	_initialize_if_needed()
	var next_type := "plane" if _active_strategy_type == "collision" else "collision"
	set_strategy(next_type)
	return _active_strategy_type

func configure(settings: Dictionary) -> void:
	"""Cache configuration and forward to all strategies"""
	_initialize_if_needed()
	_config = settings.duplicate(true)
	
	# Configure both strategies so they're ready to use
	_collision_strategy.configure(_config)
	_plane_strategy.configure(_config)
	
	# Switch strategy if explicitly requested in settings
	if settings.has("placement_strategy"):
		var requested := settings.get("placement_strategy")
		if requested != _active_strategy_type:
			set_strategy(requested)

func calculate_position(from: Vector3, to: Vector3, additional_config: Dictionary = {}) -> PlacementStrategy.PlacementResult:
	"""Delegate position calculation to the active strategy"""
	_initialize_if_needed()
	var merged := _config.duplicate(true)
	for key in additional_config.keys():
		merged[key] = additional_config[key]
	return _active_strategy.calculate_position(from, to, merged)

func calculate_position_with_strategy(from: Vector3, to: Vector3, strategy_type: String) -> PlacementStrategy.PlacementResult:
	_initialize_if_needed()
	match strategy_type.to_lower():
		"collision":
			return _collision_strategy.calculate_position(from, to, _config)
		"plane":
			return _plane_strategy.calculate_position(from, to, _config)
		_:
			PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "Invalid strategy type for calculation: %s" % strategy_type)
			return PlacementStrategy.PlacementResult.new()

func get_available_strategies() -> Array:
	return ["collision", "plane"]

func get_strategy_info() -> Dictionary:
	_initialize_if_needed()
	return {
		"active": _active_strategy_type,
		"strategies": {
			"collision": {
				"name": _collision_strategy.get_strategy_name() if _collision_strategy else "Collision",
				"type": _collision_strategy.get_strategy_type() if _collision_strategy else "collision"
			},
			"plane": {
				"name": _plane_strategy.get_strategy_name() if _plane_strategy else "Plane",
				"type": _plane_strategy.get_strategy_type() if _plane_strategy else "plane"
			}
		}
	}

func reset_all_strategies() -> void:
	_initialize_if_needed()
	_collision_strategy.reset()
	_plane_strategy.reset()

func get_collision_strategy() -> CollisionPlacementStrategy:
	_initialize_if_needed()
	return _collision_strategy

func get_plane_strategy() -> PlanePlacementStrategy:
	_initialize_if_needed()
	return _plane_strategy

func get_active_strategy() -> PlacementStrategy:
	_initialize_if_needed()
	return _active_strategy

func cycle_plane(current_position: Vector3 = Vector3.ZERO, mouse_position: Vector2 = Vector2.ZERO) -> String:
	"""Cycle through plane types when plane strategy is active
	Args:
		current_position: Current preview position to avoid jumping when cycling
		mouse_position: Current mouse position to freeze updates until mouse moves
	Returns:
		The name of the new plane type
	"""
	_initialize_if_needed()
	
	# Only cycle if plane strategy is active
	if _active_strategy_type != "plane":
		PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "Cannot cycle plane - plane strategy is not active")
		return ""
	
	# Cycle the plane type with current position and mouse position to prevent jumping
	_plane_strategy.cycle_plane(current_position, mouse_position)
	
	# Return the new plane name
	return _plane_strategy.get_plane_name()

func get_current_plane_name() -> String:
	"""Get the name of the current plane (only valid when plane strategy is active)"""
	_initialize_if_needed()
	
	if _active_strategy_type != "plane":
		return ""
	
	return _plane_strategy.get_plane_name()

func initialize_plane_from_position(position: Vector3) -> void:
	"""Initialize plane height from a position (for transform mode)"""
	_initialize_if_needed()
	
	if _active_strategy_type == "plane":
		_plane_strategy.initialize_plane_from_position(position)

func initialize_plane_for_placement() -> void:
	"""Initialize plane for placement mode (starts at ground level)"""
	_initialize_if_needed()
	
	if _active_strategy_type == "plane":
		_plane_strategy.initialize_plane_for_placement()

func update_plane_height(position: Vector3) -> void:
	"""Update plane height to match a position (for height offset adjustments in transform mode)"""
	_initialize_if_needed()
	
	if _active_strategy_type == "plane":
		_plane_strategy.update_plane_height_from_position(position)

func get_current_plane_normal() -> Vector3:
	"""Get the current plane's normal vector (for height adjustments)"""
	_initialize_if_needed()
	
	if _active_strategy_type == "plane":
		return _plane_strategy.get_current_normal()
	
	return Vector3.UP  # Default for non-plane strategies

func get_current_plane_data() -> Dictionary:
	"""Get the current plane's data (normal, axis_u, axis_v, axis_index) for WASD movement"""
	_initialize_if_needed()
	
	if _active_strategy_type == "plane":
		return _plane_strategy.get_plane_data()
	
	# Default for non-plane strategies (XZ plane)
	return {
		"normal": Vector3.UP,
		"axis_u": Vector3.RIGHT,
		"axis_v": Vector3.FORWARD,
		"axis_index": 1
	}

func _initialize_if_needed() -> void:
	if not _collision_strategy or not _plane_strategy or not _active_strategy:
		initialize()
