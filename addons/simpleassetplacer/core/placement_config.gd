@tool
extends RefCounted

class_name PlacementConfig

"""
PLACEMENT CONFIGURATION
=======================

PURPOSE: Placement-specific configuration and tracking state.

RESPONSIBILITIES:
- Store placement behavior settings (align_with_normal, collision_mask)
- Track placement position state (is_initial_position, last_raycast)
- Configure from settings dictionary
- Reset for new placements

ARCHITECTURE POSITION: Placement-specific configuration
- Only relevant during placement mode
- Not used in transform mode
- Separate from general transform settings

USED BY: TransformState (composition), PositionManager, PlacementStrategyService
"""

## PLACEMENT BEHAVIOR SETTINGS

var align_with_normal: bool = false  # Align rotation with surface
var collision_mask: int = 1  # Physics collision layer mask
var height_adjustment_step: float = 0.1  # Height adjustment increment

## PLACEMENT POSITION TRACKING

var is_initial_position: bool = true  # First position update flag
var last_raycast_xz: Vector2 = Vector2.ZERO  # Track XZ position changes for updates

## CONFIGURATION

func configure_from_settings(settings: Dictionary) -> void:
	"""Configure placement settings from settings dictionary"""
	align_with_normal = bool(settings.get("align_with_normal", false))
	collision_mask = settings.get("collision_mask", 1)
	height_adjustment_step = settings.get("height_adjustment_step", 0.1)


func reset_for_new_placement() -> void:
	"""Reset placement tracking state for new placement"""
	is_initial_position = true
	last_raycast_xz = Vector2.ZERO


func reset() -> void:
	"""Reset all placement configuration to defaults"""
	align_with_normal = false
	collision_mask = 1
	height_adjustment_step = 0.1
	reset_for_new_placement()


## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize placement configuration to dictionary"""
	return {
		"align_with_normal": align_with_normal,
		"collision_mask": collision_mask,
		"height_adjustment_step": height_adjustment_step,
		"is_initial_position": is_initial_position,
		"last_raycast_xz": last_raycast_xz,
	}


func from_dictionary(data: Dictionary) -> void:
	"""Deserialize placement configuration from dictionary"""
	align_with_normal = data.get("align_with_normal", false)
	collision_mask = data.get("collision_mask", 1)
	height_adjustment_step = data.get("height_adjustment_step", 0.1)
	is_initial_position = data.get("is_initial_position", true)
	last_raycast_xz = data.get("last_raycast_xz", Vector2.ZERO)
