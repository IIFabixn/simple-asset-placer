@tool
extends RefCounted

class_name SnapConfiguration

"""
SNAP CONFIGURATION
==================

PURPOSE: All snap-related settings for grid, rotation, and scale snapping.

RESPONSIBILITIES:
- Store position/grid snap settings
- Store rotation snap settings
- Store scale snap settings
- Configure from settings dictionary
- Serialize/deserialize snap configuration

ARCHITECTURE POSITION: Pure configuration class
- No calculation logic
- No state validation (delegates to managers)
- Just holds snap-related settings

USED BY: TransformState (composition), PositionManager, RotationManager, ScaleManager
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

## POSITION/GRID SNAP SETTINGS

var snap_enabled: bool = false
var snap_step: float = 1.0
var snap_offset: Vector3 = Vector3.ZERO
var snap_y_enabled: bool = false
var snap_y_step: float = 1.0
var snap_center_x: bool = false
var snap_center_y: bool = false
var snap_center_z: bool = false
var use_half_step: bool = false

## ROTATION SNAP SETTINGS

var snap_rotation_enabled: bool = false
var snap_rotation_step: float = 15.0  # Degrees

## SCALE SNAP SETTINGS

var snap_scale_enabled: bool = false
var snap_scale_step: float = 0.1

## CONFIGURATION

func configure_from_settings(settings: Dictionary) -> void:
	"""Configure snap settings from settings dictionary"""
	# Position snap
	snap_enabled = settings.get("snap_enabled", false)
	snap_step = settings.get("snap_step", 1.0)
	snap_offset = settings.get("snap_offset", Vector3.ZERO)
	snap_y_enabled = settings.get("snap_y_enabled", false)
	snap_y_step = settings.get("snap_y_step", 1.0)
	snap_center_x = settings.get("snap_center_x", false)
	snap_center_y = settings.get("snap_center_y", false)
	snap_center_z = settings.get("snap_center_z", false)
	
	# Rotation and scale snap settings
	snap_rotation_enabled = settings.get("snap_rotation_enabled", false)
	snap_rotation_step = settings.get("snap_rotation_step", 15.0)
	snap_scale_enabled = settings.get("snap_scale_enabled", false)
	snap_scale_step = settings.get("snap_scale_step", 0.1)
	
	# Debug logging for snap settings
	if snap_rotation_enabled or snap_scale_enabled or snap_enabled:
		PluginLogger.debug("SnapConfiguration", 
			"Snap settings | Pos:%s step:%s Rot:%s step:%s Scale:%s step:%s half_step:%s" % [
				snap_enabled, snap_step, snap_rotation_enabled, snap_rotation_step, 
				snap_scale_enabled, snap_scale_step, use_half_step
			])


func reset() -> void:
	"""Reset all snap settings to defaults"""
	snap_enabled = false
	snap_step = 1.0
	snap_offset = Vector3.ZERO
	snap_y_enabled = false
	snap_y_step = 1.0
	snap_center_x = false
	snap_center_y = false
	snap_center_z = false
	use_half_step = false
	snap_rotation_enabled = false
	snap_rotation_step = 15.0
	snap_scale_enabled = false
	snap_scale_step = 0.1


## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize snap configuration to dictionary"""
	return {
		"snap_enabled": snap_enabled,
		"snap_step": snap_step,
		"snap_offset": snap_offset,
		"snap_y_enabled": snap_y_enabled,
		"snap_y_step": snap_y_step,
		"snap_center_x": snap_center_x,
		"snap_center_y": snap_center_y,
		"snap_center_z": snap_center_z,
		"use_half_step": use_half_step,
		"snap_rotation_enabled": snap_rotation_enabled,
		"snap_rotation_step": snap_rotation_step,
		"snap_scale_enabled": snap_scale_enabled,
		"snap_scale_step": snap_scale_step,
	}


func from_dictionary(data: Dictionary) -> void:
	"""Deserialize snap configuration from dictionary"""
	snap_enabled = data.get("snap_enabled", false)
	snap_step = data.get("snap_step", 1.0)
	snap_offset = data.get("snap_offset", Vector3.ZERO)
	snap_y_enabled = data.get("snap_y_enabled", false)
	snap_y_step = data.get("snap_y_step", 1.0)
	snap_center_x = data.get("snap_center_x", false)
	snap_center_y = data.get("snap_center_y", false)
	snap_center_z = data.get("snap_center_z", false)
	use_half_step = data.get("use_half_step", false)
	snap_rotation_enabled = data.get("snap_rotation_enabled", false)
	snap_rotation_step = data.get("snap_rotation_step", 15.0)
	snap_scale_enabled = data.get("snap_scale_enabled", false)
	snap_scale_step = data.get("snap_scale_step", 0.1)
