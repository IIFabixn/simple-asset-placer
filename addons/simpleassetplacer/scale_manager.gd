@tool
extends RefCounted

class_name ScaleManager

"""
3D SCALING MATHEMATICS SYSTEM
=============================

PURPOSE: Handles all scaling calculations and transformations with support for uniform and non-uniform scaling.

RESPONSIBILITIES:
- Scale state management (uniform and non-uniform scaling)
- Scale step application (increase/decrease by configurable amounts)
- Scale bounds enforcement (prevents zero/negative scaling)
- Node scale application and copying  
- Scale reset functionality
- Conversion between uniform and Vector3 scaling

ARCHITECTURE POSITION: Pure scaling math with no dependencies
- Does NOT handle input detection (receives scale commands)
- Does NOT handle UI or feedback
- Does NOT know about placement/transform modes
- Works with any Node3D object

USED BY: TransformationManager for all scaling operations
DEPENDS ON: Only Godot math system (Vector3, scale properties)
"""

# Current scale state
static var current_scale: float = 1.0  # Uniform scale multiplier
static var non_uniform_scale: Vector3 = Vector3.ONE  # For non-uniform scaling

## Core Scale Functions

static func set_scale(scale: float):
	"""Set uniform scale"""
	current_scale = max(0.01, scale)  # Prevent zero/negative scale
	non_uniform_scale = Vector3(current_scale, current_scale, current_scale)

static func set_non_uniform_scale(scale: Vector3):
	"""Set non-uniform scale"""
	non_uniform_scale = Vector3(
		max(0.01, scale.x),
		max(0.01, scale.y),
		max(0.01, scale.z)
	)
	# Update uniform scale to average
	current_scale = (non_uniform_scale.x + non_uniform_scale.y + non_uniform_scale.z) / 3.0

static func get_scale() -> float:
	"""Get current uniform scale"""
	return current_scale

static func get_scale_vector() -> Vector3:
	"""Get current scale as Vector3"""
	return non_uniform_scale

static func reset_scale():
	"""Reset scale to 1.0"""
	set_scale(1.0)
	print("ScaleManager: Scale reset to 1.0")

## Scale Modifications

static func increase_scale(amount: float = 0.1):
	"""Increase scale by amount"""
	set_scale(current_scale + amount)
	print("ScaleManager: Increased scale by ", amount, " to ", current_scale)

static func decrease_scale(amount: float = 0.1):
	"""Decrease scale by amount"""
	set_scale(current_scale - amount)
	print("ScaleManager: Decreased scale by ", amount, " to ", current_scale)

static func multiply_scale(multiplier: float):
	"""Multiply current scale by a factor"""
	set_scale(current_scale * multiplier)
	print("ScaleManager: Multiplied scale by ", multiplier, " to ", current_scale)

static func scale_up(factor: float = 1.1):
	"""Scale up by a factor (default 10% increase)"""
	multiply_scale(factor)

static func scale_down(factor: float = 0.9):
	"""Scale down by a factor (default 10% decrease)"""
	multiply_scale(factor)

## Non-Uniform Scale Modifications

static func scale_axis(axis: String, amount: float):
	"""Scale a specific axis by amount"""
	match axis.to_upper():
		"X":
			non_uniform_scale.x = max(0.01, non_uniform_scale.x + amount)
		"Y":
			non_uniform_scale.y = max(0.01, non_uniform_scale.y + amount)
		"Z":
			non_uniform_scale.z = max(0.01, non_uniform_scale.z + amount)
		_:
			print("ScaleManager: Invalid axis: ", axis)
			return
	
	# Update uniform scale
	current_scale = (non_uniform_scale.x + non_uniform_scale.y + non_uniform_scale.z) / 3.0

static func multiply_axis_scale(axis: String, multiplier: float):
	"""Multiply a specific axis scale by a factor"""
	match axis.to_upper():
		"X":
			non_uniform_scale.x = max(0.01, non_uniform_scale.x * multiplier)
		"Y":
			non_uniform_scale.y = max(0.01, non_uniform_scale.y * multiplier)
		"Z":
			non_uniform_scale.z = max(0.01, non_uniform_scale.z * multiplier)
		_:
			print("ScaleManager: Invalid axis: ", axis)
			return
	
	# Update uniform scale
	current_scale = (non_uniform_scale.x + non_uniform_scale.y + non_uniform_scale.z) / 3.0

## Node Application

static func apply_scale_to_node(node: Node3D):
	"""Apply current scale to a node"""
	if node:
		node.scale = non_uniform_scale

static func apply_uniform_scale_to_node(node: Node3D):
	"""Apply uniform scale to a node"""
	if node:
		node.scale = Vector3(current_scale, current_scale, current_scale)

static func copy_scale_from_node(node: Node3D):
	"""Copy scale from a node to the manager state"""
	if node:
		non_uniform_scale = node.scale
		current_scale = (non_uniform_scale.x + non_uniform_scale.y + non_uniform_scale.z) / 3.0

## Scale Constraints and Validation

static func clamp_scale(min_scale: float = 0.01, max_scale: float = 100.0):
	"""Clamp scale within specified bounds"""
	current_scale = clampf(current_scale, min_scale, max_scale)
	non_uniform_scale.x = clampf(non_uniform_scale.x, min_scale, max_scale)
	non_uniform_scale.y = clampf(non_uniform_scale.y, min_scale, max_scale)
	non_uniform_scale.z = clampf(non_uniform_scale.z, min_scale, max_scale)

static func is_uniform_scale() -> bool:
	"""Check if current scale is uniform"""
	var epsilon = 0.001
	return abs(non_uniform_scale.x - non_uniform_scale.y) < epsilon and \
		   abs(non_uniform_scale.y - non_uniform_scale.z) < epsilon

static func is_scale_at_default() -> bool:
	"""Check if scale is at default (1.0)"""
	return abs(current_scale - 1.0) < 0.001

## Scale Presets

static func set_scale_preset(preset_name: String):
	"""Set scale to a common preset"""
	match preset_name.to_lower():
		"tiny":
			set_scale(0.1)
		"small":
			set_scale(0.5)
		"normal", "default":
			set_scale(1.0)
		"large":
			set_scale(2.0)
		"huge":
			set_scale(5.0)
		"double":
			set_scale(2.0)
		"half":
			set_scale(0.5)
		"quarter":
			set_scale(0.25)
		_:
			print("ScaleManager: Unknown preset: ", preset_name)

## Scale Interpolation

static func lerp_to_scale(target_scale: float, weight: float):
	"""Smoothly interpolate to a target scale"""
	set_scale(lerp(current_scale, target_scale, weight))

static func lerp_to_scale_vector(target_scale: Vector3, weight: float):
	"""Smoothly interpolate to a target scale vector"""
	set_non_uniform_scale(non_uniform_scale.lerp(target_scale, weight))

## Configuration and Settings

static func configure(settings: Dictionary):
	"""Configure scale manager with settings"""
	if settings.has("initial_scale"):
		var initial = settings.initial_scale
		if initial is float or initial is int:
			set_scale(float(initial))
		elif initial is Vector3:
			set_non_uniform_scale(initial)
	
	if settings.has("min_scale"):
		var min_val = settings.get("max_scale", 100.0)
		var max_val = settings.get("min_scale", 0.01)
		clamp_scale(min_val, max_val)

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"current_scale": current_scale,
		"scale_vector": non_uniform_scale,
		"is_uniform": is_uniform_scale(),
		"is_default": is_scale_at_default()
	}

## Display and Formatting

static func get_scale_percentage() -> float:
	"""Get scale as percentage (1.0 = 100%)"""
	return current_scale * 100.0

static func get_scale_display_text() -> String:
	"""Get formatted scale display text"""
	if is_uniform_scale():
		return "Scale: %.1f%%" % get_scale_percentage()
	else:
		return "Scale: X:%.1f%% Y:%.1f%% Z:%.1f%%" % [
			non_uniform_scale.x * 100.0,
			non_uniform_scale.y * 100.0,
			non_uniform_scale.z * 100.0
		]

## Debug and Information

static func debug_print_scale():
	"""Print current scale state for debugging"""
	print("ScaleManager State:")
	print("  Uniform Scale: %.3f (%.1f%%)" % [current_scale, get_scale_percentage()])
	print("  Scale Vector: X:%.3f Y:%.3f Z:%.3f" % [non_uniform_scale.x, non_uniform_scale.y, non_uniform_scale.z])
	print("  Is Uniform: ", is_uniform_scale())
	print("  Is Default: ", is_scale_at_default())

static func get_scale_info() -> Dictionary:
	"""Get comprehensive scale information"""
	return {
		"uniform_scale": current_scale,
		"scale_vector": non_uniform_scale,
		"scale_percentage": get_scale_percentage(),
		"is_uniform": is_uniform_scale(),
		"is_default": is_scale_at_default(),
		"display_text": get_scale_display_text()
	}