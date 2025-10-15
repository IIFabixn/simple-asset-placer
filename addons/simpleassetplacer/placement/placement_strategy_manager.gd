@tool
extends RefCounted

class_name PlacementStrategyManager

"""
PLACEMENT STRATEGY MANAGER (STRATEGY COORDINATOR)
=================================================

PURPOSE: Manage and coordinate different placement strategies for position calculation.

RESPONSIBILITIES:
- Maintain available placement strategies
- Select active strategy based on settings
- Delegate position calculations to active strategy
- Handle strategy switching at runtime
- Provide unified interface for position calculation

STRATEGY PATTERN: This class acts as the Context in the Strategy pattern,
delegating work to the appropriate Strategy implementation.

AVAILABLE STRATEGIES:
- CollisionPlacementStrategy: Raycast-based collision detection
- PlanePlacementStrategy: Fixed horizontal plane projection

USED BY: PositionManager to calculate world positions
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PlacementStrategy = preload("res://addons/simpleassetplacer/placement/placement_strategy.gd")
const CollisionPlacementStrategy = preload("res://addons/simpleassetplacer/placement/collision_placement_strategy.gd")
const PlanePlacementStrategy = preload("res://addons/simpleassetplacer/placement/plane_placement_strategy.gd")

const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

static var _service: PlacementStrategyService = null

static func set_service(service: PlacementStrategyService) -> void:
	"""Assign the shared placement strategy service (for DI)"""
	_service = service

static func _ensure_service() -> PlacementStrategyService:
	if not _service:
		_service = PlacementStrategyService.new()
		_service.initialize()
	return _service

## Initialization

static func initialize():
	"""Initialize all placement strategies"""
	_ensure_service().initialize()
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, "PlacementStrategyManager initialized (service-backed)")

static func cleanup():
	"""Clean up strategy instances"""
	if _service:
		_service.cleanup()
	_service = null

## Strategy Selection

static func set_strategy(strategy_type: String) -> bool:
	"""Set active placement strategy by type
	
	Args:
		strategy_type: Strategy identifier ('collision' or 'plane')
	
	Returns:
		true if strategy was changed, false if invalid type or already active
	"""
	return _ensure_service().set_strategy(strategy_type)

static func get_active_strategy_type() -> String:
	"""Get the type identifier of the active strategy"""
	return _ensure_service().get_active_strategy_type()

static func get_active_strategy_name() -> String:
	"""Get the human-readable name of the active strategy"""
	return _ensure_service().get_active_strategy_name()

static func cycle_strategy() -> String:
	"""Cycle to the next placement strategy
	
	Returns:
		The new active strategy type
	"""
	return _ensure_service().cycle_strategy()

## Configuration

static func configure(settings: Dictionary):
	"""Configure the placement strategy manager and active strategy
	
	Args:
		settings: Configuration dictionary containing:
			- placement_strategy: Which strategy to use ('collision' or 'plane')
			- collision_mask: Collision detection mask
			- plane_height: Height for plane strategy
			- snap_to_ground: Legacy setting (maps to collision strategy)
			- And other strategy-specific settings
	"""
	_ensure_service().configure(settings)

## Position Calculation

static func calculate_position(from: Vector3, to: Vector3, additional_config: Dictionary = {}) -> PlacementStrategy.PlacementResult:
	"""Calculate position using the active placement strategy
	
	Args:
		from: Ray origin (camera position)
		to: Ray end point (camera forward * distance)
		additional_config: Additional configuration (e.g., exclude_nodes for transform mode)
	
	Returns:
		PlacementResult with position, normal, and metadata
	"""
	return _ensure_service().calculate_position(from, to, additional_config)

static func calculate_position_with_strategy(from: Vector3, to: Vector3, strategy_type: String) -> PlacementStrategy.PlacementResult:
	"""Calculate position using a specific strategy (without changing active strategy)
	
	Args:
		from: Ray origin
		to: Ray end point
		strategy_type: Strategy to use ('collision' or 'plane')
	
	Returns:
		PlacementResult from specified strategy
	"""
	return _ensure_service().calculate_position_with_strategy(from, to, strategy_type)

## Strategy Access


static func get_collision_strategy() -> CollisionPlacementStrategy:
	return _ensure_service().get_collision_strategy()

static func get_plane_strategy() -> PlanePlacementStrategy:
	"""Get plane strategy instance"""
	return _ensure_service().get_plane_strategy()

## Utility

static func reset_all_strategies():
	"""Reset all strategies to default state"""
	_ensure_service().reset_all_strategies()

static func get_available_strategies() -> Array:
	"""Get list of available strategy types"""
	return _ensure_service().get_available_strategies()

static func get_strategy_info() -> Dictionary:
	"""Get information about all available strategies"""
	return _ensure_service().get_strategy_info()







