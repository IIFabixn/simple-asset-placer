@tool
extends "res://addons/simpleassetplacer/placement_strategy.gd"

class_name PlanePlacementStrategy

"""
PLANE-BASED PLACEMENT STRATEGY
==============================

PURPOSE: Calculate placement position by projecting onto a horizontal plane at fixed height.

STRATEGY: Project the camera ray onto a horizontal plane without using collision detection.
This is useful for level design where you want to place objects at a consistent height
regardless of scene geometry.

FEATURES:
- Simple plane intersection calculation
- No physics dependencies
- Configurable plane height
- Optional height tracking (updates plane height as user moves)
- Always returns UP normal (no surface alignment)

CONFIGURATION:
- plane_height: Y-coordinate of the horizontal plane
- track_height: Whether plane height updates with user input
- default_height: Fallback height if calculation fails

USED BY: PlacementStrategyManager when user selects plane-based placement
"""

const PluginLogger = preload("res://addons/simpleassetplacer/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/plugin_constants.gd")

# Configuration
var plane_height: float = 0.0
var track_height: bool = false
var default_height: float = 0.0

## Strategy Implementation

func calculate_position(from: Vector3, to: Vector3, config: Dictionary) -> PlacementResult:
	"""Calculate position by projecting onto horizontal plane"""
	
	# Update configuration from provided config
	plane_height = config.get("plane_height", 0.0)
	track_height = config.get("track_plane_height", false)
	default_height = config.get("default_height", 0.0)
	
	# Calculate ray direction
	var ray_dir = (to - from).normalized()
	
	# Project onto horizontal plane
	var position = project_to_horizontal_plane(from, ray_dir, plane_height)
	
	# Calculate distance from camera
	var distance = from.distance_to(position)
	
	# Plane strategy always has UP normal and no collision flag
	return PlacementResult.new(position, Vector3.UP, false, distance)

func get_strategy_name() -> String:
	return "Plane Placement"

func get_strategy_type() -> String:
	return "plane"

func configure(config: Dictionary) -> void:
	"""Configure plane strategy settings"""
	plane_height = config.get("plane_height", 0.0)
	track_height = config.get("track_plane_height", false)
	default_height = config.get("default_height", 0.0)

func reset() -> void:
	"""Reset strategy to defaults"""
	plane_height = 0.0
	track_height = false
	default_height = 0.0

func set_plane_height(height: float) -> void:
	"""Manually set the plane height (used when track_height is enabled)"""
	plane_height = height

func get_plane_height() -> float:
	"""Get current plane height"""
	return plane_height
