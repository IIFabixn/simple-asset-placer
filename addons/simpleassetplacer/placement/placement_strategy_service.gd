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
	_collision_strategy.configure(_config)
	_plane_strategy.configure(_config)
	var requested := settings.get("placement_strategy", _active_strategy_type)
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

func _initialize_if_needed() -> void:
	if not _collision_strategy or not _plane_strategy or not _active_strategy:
		initialize()
