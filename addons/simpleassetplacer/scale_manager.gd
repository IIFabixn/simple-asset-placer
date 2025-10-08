@tool
extends RefCounted

class_name ScaleManager

"""
3D SCALING MATHEMATICS SYSTEM (MULTIPLIER-BASED OFFSET)
=======================================================

PURPOSE: Handles all scaling calculations using a multiplier-based offset system with optional smooth interpolation.

RESPONSIBILITIES:
- Scale multiplier management (1.0 = no change, 2.0 = double size, 0.5 = half size)
- Scale step application (increase/decrease by configurable amounts)
- Scale bounds enforcement (prevents zero/negative scaling)
- Node scale application (original_scale * multiplier = final_scale) with optional smoothing
- Scale reset functionality
- Conversion between uniform and Vector3 multipliers

ARCHITECTURE POSITION: Pure scaling math with optional smooth transform integration
- Does NOT handle input detection (receives scale commands)
- Does NOT handle UI or feedback
- Does NOT know about placement/transform modes
- Works with any Node3D object

USED BY: TransformationManager for all scaling operations
DEPENDS ON: Godot math system (Vector3, scale properties), SmoothTransformManager (optional)
"""

# Import smooth transform system for optional smooth scaling
const SmoothTransformManager = preload("res://addons/simpleassetplacer/smooth_transform_manager.gd")

# Current scale state (multiplier-based offset system - like rotation offsets)
static var scale_multiplier: float = 1.0  # Uniform scale multiplier (1.0 = no change, applied to original scale)
static var non_uniform_multiplier: Vector3 = Vector3.ONE  # For non-uniform scaling multipliers

## Configuration

static func configure_smooth_transforms(enabled: bool, speed: float = 8.0):
	"""Configure smooth transform settings for scaling"""
	# No local caching - SmoothTransformManager handles the settings

## Core Scale Functions

static func set_scale_multiplier(multiplier: float):
	"""Set uniform scale multiplier (1.0 = original size, 2.0 = double, 0.5 = half)"""
	scale_multiplier = max(0.01, multiplier)  # Prevent zero/negative scale
	non_uniform_multiplier = Vector3(scale_multiplier, scale_multiplier, scale_multiplier)

static func set_non_uniform_multiplier(multiplier: Vector3):
	"""Set non-uniform scale multiplier"""
	non_uniform_multiplier = Vector3(
		max(0.01, multiplier.x),
		max(0.01, multiplier.y),
		max(0.01, multiplier.z)
	)
	# Update uniform scale to average
	scale_multiplier = (non_uniform_multiplier.x + non_uniform_multiplier.y + non_uniform_multiplier.z) / 3.0

static func get_scale() -> float:
	"""Get current uniform scale multiplier"""
	return scale_multiplier

static func get_scale_vector() -> Vector3:
	"""Get current scale multiplier as Vector3"""
	return non_uniform_multiplier

static func reset_scale():
	"""Reset scale multiplier to 1.0 (original size)"""
	set_scale_multiplier(1.0)
	PluginLogger.debug("ScaleManager", "Scale multiplier reset to 1.0")

## Scale Modifications

static func increase_scale(amount: float = 0.1):
	"""Increase scale multiplier by amount"""
	set_scale_multiplier(scale_multiplier + amount)
	PluginLogger.debug("ScaleManager", "Increased scale multiplier by " + str(amount) + " to " + str(scale_multiplier))

static func decrease_scale(amount: float = 0.1):
	"""Decrease scale multiplier by amount"""
	set_scale_multiplier(scale_multiplier - amount)
	PluginLogger.debug("ScaleManager", "Decreased scale multiplier by " + str(amount) + " to " + str(scale_multiplier))

static func adjust_scale_with_modifiers(base_amount: float, modifiers: Dictionary):
	"""Adjust scale with modifier-calculated step
	
	Args:
		base_amount: Base scale step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_scale_step(base_amount, modifiers)
	set_scale_multiplier(scale_multiplier + step)
	PluginLogger.debug("ScaleManager", "Adjusted scale by " + str(step) + " to " + str(scale_multiplier))

static func multiply_scale(factor: float):
	"""Multiply current scale multiplier by a factor"""
	set_scale_multiplier(scale_multiplier * factor)
	PluginLogger.debug("ScaleManager", "Multiplied scale by " + str(factor) + " to " + str(scale_multiplier))

static func scale_up(factor: float = 1.1):
	"""Scale up by a factor (default 10% increase)"""
	multiply_scale(factor)

static func scale_down(factor: float = 0.9):
	"""Scale down by a factor (default 10% decrease)"""
	multiply_scale(factor)

## Non-Uniform Scale Modifications

static func scale_axis(axis: String, amount: float):
	"""Scale a specific axis multiplier by amount"""
	match axis.to_upper():
		"X":
			non_uniform_multiplier.x = max(0.01, non_uniform_multiplier.x + amount)
		"Y":
			non_uniform_multiplier.y = max(0.01, non_uniform_multiplier.y + amount)
		"Z":
			non_uniform_multiplier.z = max(0.01, non_uniform_multiplier.z + amount)
		_:
			PluginLogger.warning("ScaleManager", "Invalid axis: " + axis)
			return
	
	# Update uniform scale multiplier
	scale_multiplier = (non_uniform_multiplier.x + non_uniform_multiplier.y + non_uniform_multiplier.z) / 3.0

static func scale_axis_with_modifiers(axis: String, base_amount: float, modifiers: Dictionary):
	"""Scale a specific axis with modifier-calculated step
	
	Args:
		axis: Scale axis ("X", "Y", or "Z")
		base_amount: Base scale step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_scale_step(base_amount, modifiers)
	scale_axis(axis, step)

static func multiply_axis_scale(axis: String, factor: float):
	"""Multiply a specific axis scale multiplier by a factor"""
	match axis.to_upper():
		"X":
			non_uniform_multiplier.x = max(0.01, non_uniform_multiplier.x * factor)
		"Y":
			non_uniform_multiplier.y = max(0.01, non_uniform_multiplier.y * factor)
		"Z":
			non_uniform_multiplier.z = max(0.01, non_uniform_multiplier.z * factor)
		_:
			PluginLogger.warning("ScaleManager", "Invalid axis: " + axis)
			return
	
	# Update uniform scale multiplier
	scale_multiplier = (non_uniform_multiplier.x + non_uniform_multiplier.y + non_uniform_multiplier.z) / 3.0

## Node Application

static func apply_scale_to_node(node: Node3D, original_scale: Vector3 = Vector3.ONE):
	"""Apply scale multiplier to a node's original scale
	
	Args:
		node: The Node3D to apply scale to
		original_scale: The node's original scale (from transform mode) or Vector3.ONE for placement mode
	"""
	if node:
		# Final scale = original_scale * multiplier
		node.scale = Vector3(
			original_scale.x * non_uniform_multiplier.x,
			original_scale.y * non_uniform_multiplier.y,
			original_scale.z * non_uniform_multiplier.z
		)

static func apply_uniform_scale_to_node(node: Node3D, original_scale: Vector3 = Vector3.ONE):
	"""Apply uniform scale multiplier to a node's original scale
	
	Args:
		node: The Node3D to apply scale to
		original_scale: The node's original scale (from transform mode) or Vector3.ONE for placement mode
	"""
	if node and node.is_inside_tree():
		# Final scale = original_scale * uniform_multiplier
		var target_scale = original_scale * scale_multiplier
		
		# Apply scale with or without smoothing
		if SmoothTransformManager._smooth_enabled:
			SmoothTransformManager.set_target_scale(node, target_scale)
		else:
			node.scale = target_scale

## Scale Constraints and Validation

static func clamp_scale(min_multiplier: float = 0.01, max_multiplier: float = 100.0):
	"""Clamp scale multiplier within specified bounds"""
	scale_multiplier = clampf(scale_multiplier, min_multiplier, max_multiplier)
	non_uniform_multiplier.x = clampf(non_uniform_multiplier.x, min_multiplier, max_multiplier)
	non_uniform_multiplier.y = clampf(non_uniform_multiplier.y, min_multiplier, max_multiplier)
	non_uniform_multiplier.z = clampf(non_uniform_multiplier.z, min_multiplier, max_multiplier)

static func is_uniform_scale() -> bool:
	"""Check if current scale multiplier is uniform"""
	var epsilon = 0.001
	return abs(non_uniform_multiplier.x - non_uniform_multiplier.y) < epsilon and \
		   abs(non_uniform_multiplier.y - non_uniform_multiplier.z) < epsilon

static func is_scale_at_default() -> bool:
	"""Check if scale multiplier is at default (1.0 = original size)"""
	return abs(scale_multiplier - 1.0) < 0.001

## Scale Presets

static func set_scale_preset(preset_name: String):
	"""Set scale multiplier to a common preset"""
	match preset_name.to_lower():
		"tiny":
			set_scale_multiplier(0.1)
		"small":
			set_scale_multiplier(0.5)
		"normal", "default":
			set_scale_multiplier(1.0)
		"large":
			set_scale_multiplier(2.0)
		"huge":
			set_scale_multiplier(5.0)
		"double":
			set_scale_multiplier(2.0)
		"half":
			set_scale_multiplier(0.5)
		"quarter":
			set_scale_multiplier(0.25)
		_:
			PluginLogger.warning("ScaleManager", "Unknown preset: " + preset_name)

## Scale Interpolation

static func lerp_to_scale(target_multiplier: float, weight: float):
	"""Smoothly interpolate to a target scale multiplier"""
	set_scale_multiplier(lerp(scale_multiplier, target_multiplier, weight))

static func lerp_to_scale_vector(target_multiplier: Vector3, weight: float):
	"""Smoothly interpolate to a target scale multiplier vector"""
	set_non_uniform_multiplier(non_uniform_multiplier.lerp(target_multiplier, weight))

## Configuration and Settings

static func configure(settings: Dictionary):
	"""Configure scale manager with settings"""
	if settings.has("initial_scale"):
		var initial = settings.initial_scale
		if initial is float or initial is int:
			set_scale_multiplier(float(initial))
		elif initial is Vector3:
			set_non_uniform_multiplier(initial)
	
	if settings.has("min_scale"):
		var min_val = settings.get("min_scale", 0.01)
		var max_val = settings.get("max_scale", 100.0)
		clamp_scale(min_val, max_val)

static func get_configuration() -> Dictionary:
	"""Get current configuration"""
	return {
		"scale_multiplier": scale_multiplier,
		"scale_multiplier_vector": non_uniform_multiplier,
		"is_uniform": is_uniform_scale(),
		"is_default": is_scale_at_default()
	}

## Display and Formatting

static func get_scale_percentage() -> float:
	"""Get scale multiplier as percentage (1.0 = 100%)"""
	return scale_multiplier * 100.0

static func get_scale_display_text() -> String:
	"""Get formatted scale display text"""
	if is_uniform_scale():
		return "Scale: %.1f%%" % get_scale_percentage()
	else:
		return "Scale: X:%.1f%% Y:%.1f%% Z:%.1f%%" % [
			non_uniform_multiplier.x * 100.0,
			non_uniform_multiplier.y * 100.0,
			non_uniform_multiplier.z * 100.0
		]

## Debug and Information

static func debug_print_scale():
	"""Print current scale state for debugging"""
	PluginLogger.debug("ScaleManager", "ScaleManager State:")
	PluginLogger.debug("ScaleManager", "  Uniform Scale Multiplier: %.3f (%.1f%%)" % [scale_multiplier, get_scale_percentage()])
	PluginLogger.debug("ScaleManager", "  Scale Multiplier Vector: X:%.3f Y:%.3f Z:%.3f" % [non_uniform_multiplier.x, non_uniform_multiplier.y, non_uniform_multiplier.z])
	PluginLogger.debug("ScaleManager", "  Is Uniform: " + str(is_uniform_scale()))
	PluginLogger.debug("ScaleManager", "  Is Default: " + str(is_scale_at_default()))

static func get_scale_info() -> Dictionary:
	"""Get comprehensive scale information"""
	return {
		"scale_multiplier": scale_multiplier,
		"scale_multiplier_vector": non_uniform_multiplier,
		"scale_percentage": get_scale_percentage(),
		"is_uniform": is_uniform_scale(),
		"is_default": is_scale_at_default(),
		"display_text": get_scale_display_text()
	}