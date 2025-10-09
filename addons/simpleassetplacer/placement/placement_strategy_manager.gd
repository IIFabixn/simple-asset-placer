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

# Strategy instances
static var collision_strategy: CollisionPlacementStrategy = null
static var plane_strategy: PlanePlacementStrategy = null

# Active strategy
static var active_strategy: PlacementStrategy = null
static var active_strategy_type: String = "collision"

# Configuration
static var config: Dictionary = {}

## Initialization

static func initialize():
	"""Initialize all placement strategies"""
	if not collision_strategy:
		collision_strategy = CollisionPlacementStrategy.new()
	
	if not plane_strategy:
		plane_strategy = PlanePlacementStrategy.new()
	
	# Default to collision strategy
	if not active_strategy:
		active_strategy = collision_strategy
		active_strategy_type = "collision"
	
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, "PlacementStrategyManager initialized")

static func cleanup():
	"""Clean up strategy instances"""
	collision_strategy = null
	plane_strategy = null
	active_strategy = null
	config.clear()

## Strategy Selection

static func set_strategy(strategy_type: String) -> bool:
	"""Set active placement strategy by type
	
	Args:
		strategy_type: Strategy identifier ('collision' or 'plane')
	
	Returns:
		true if strategy was changed, false if invalid type or already active
	"""
	# Ensure strategies are initialized
	if not collision_strategy or not plane_strategy:
		initialize()
	
	var normalized_type = strategy_type.to_lower()
	
	# Check if already using this strategy (avoid spam)
	if active_strategy_type == normalized_type:
		return false  # No change needed
	
	match normalized_type:
		"collision":
			active_strategy = collision_strategy
			active_strategy_type = "collision"
			PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Switched to collision placement strategy")
			return true
		"plane":
			active_strategy = plane_strategy
			active_strategy_type = "plane"
			PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Switched to plane placement strategy")
			return true
		_:
			PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "Invalid strategy type: " + strategy_type)
			return false

static func get_active_strategy_type() -> String:
	"""Get the type identifier of the active strategy"""
	return active_strategy_type

static func get_active_strategy_name() -> String:
	"""Get the human-readable name of the active strategy"""
	if active_strategy:
		return active_strategy.get_strategy_name()
	return "None"

static func cycle_strategy() -> String:
	"""Cycle to the next placement strategy
	
	Returns:
		The new active strategy type
	"""
	# Ensure strategies are initialized
	if not collision_strategy or not plane_strategy:
		initialize()
	
	# Cycle: collision -> plane -> collision
	var new_strategy = ""
	match active_strategy_type:
		"collision":
			new_strategy = "plane"
		"plane":
			new_strategy = "collision"
		_:
			# Default to collision if unknown
			new_strategy = "collision"
	
	set_strategy(new_strategy)
	
	return new_strategy

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
	config = settings
	
	# Ensure strategies are initialized
	if not collision_strategy or not plane_strategy:
		initialize()
	
	# Determine which strategy to use
	var strategy_type = settings.get("placement_strategy", "auto")
	
	# Auto-select based on legacy snap_to_ground setting
	if strategy_type == "auto":
		var snap_to_ground = settings.get("snap_to_ground", true)
		strategy_type = "collision" if snap_to_ground else "plane"
	
	# Only set strategy if it actually changed (avoids redundant logging)
	if strategy_type != active_strategy_type:
		set_strategy(strategy_type)
	
	# Configure both strategies (so switching is seamless)
	collision_strategy.configure(settings)
	plane_strategy.configure(settings)

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
	# Ensure we have an active strategy
	if not active_strategy:
		initialize()
	
	# Merge additional config with base config
	var merged_config = config.duplicate()
	for key in additional_config:
		merged_config[key] = additional_config[key]
	
	# Debug: Log which strategy is being used and if exclusions are present
	var strategy_name = "Collision" if active_strategy == collision_strategy else "Plane"
	var exclude_count = merged_config.get("exclude_nodes", []).size()
	
	# Delegate to active strategy with merged config
	return active_strategy.calculate_position(from, to, merged_config)

static func calculate_position_with_strategy(from: Vector3, to: Vector3, strategy_type: String) -> PlacementStrategy.PlacementResult:
	"""Calculate position using a specific strategy (without changing active strategy)
	
	Args:
		from: Ray origin
		to: Ray end point
		strategy_type: Strategy to use ('collision' or 'plane')
	
	Returns:
		PlacementResult from specified strategy
	"""
	# Ensure strategies are initialized
	if not collision_strategy or not plane_strategy:
		initialize()
	
	match strategy_type.to_lower():
		"collision":
			return collision_strategy.calculate_position(from, to, config)
		"plane":
			return plane_strategy.calculate_position(from, to, config)
		_:
			PluginLogger.warning(PluginConstants.COMPONENT_POSITION, "Invalid strategy type for calculation: " + strategy_type)
			return PlacementStrategy.PlacementResult.new()

## Strategy Access

static func get_collision_strategy() -> CollisionPlacementStrategy:
	"""Get collision strategy instance"""
	if not collision_strategy:
		initialize()
	return collision_strategy

static func get_plane_strategy() -> PlanePlacementStrategy:
	"""Get plane strategy instance"""
	if not plane_strategy:
		initialize()
	return plane_strategy

## Utility

static func reset_all_strategies():
	"""Reset all strategies to default state"""
	if collision_strategy:
		collision_strategy.reset()
	if plane_strategy:
		plane_strategy.reset()

static func get_available_strategies() -> Array:
	"""Get list of available strategy types"""
	return ["collision", "plane"]

static func get_strategy_info() -> Dictionary:
	"""Get information about all available strategies"""
	if not collision_strategy or not plane_strategy:
		initialize()
	
	return {
		"active": active_strategy_type,
		"strategies": {
			"collision": {
				"name": collision_strategy.get_strategy_name(),
				"type": collision_strategy.get_strategy_type()
			},
			"plane": {
				"name": plane_strategy.get_strategy_name(),
				"type": plane_strategy.get_strategy_type()
			}
		}
	}







