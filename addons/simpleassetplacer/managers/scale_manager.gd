@tool
extends RefCounted

class_name ScaleManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
3D SCALING CALCULATIONS SERVICE (REFACTORED - INSTANCE-BASED)
==============================================================

PURPOSE: Pure scaling calculation service working with TransformState.

RESPONSIBILITIES:
- Scale multiplier calculations (1.0 = no change, 2.0 = double size, 0.5 = half size)
- Scale step calculations (increase/decrease by configurable amounts)
- Scale bounds enforcement (prevents zero/negative scaling)
- Scale reset functionality
- Conversion between uniform and Vector3 multipliers

ARCHITECTURE POSITION: Pure calculation service with NO state storage
- Does NOT store scale state (uses TransformState)
- Does NOT handle input detection
- Does NOT handle UI or feedback
- Does NOT know about placement/transform modes
- Focused solely on scaling math

FULLY INSTANCE-BASED with ServiceRegistry injection (matches PositionManager and RotationManager)

USED BY: TransformationCoordinator for scaling calculations
DEPENDS ON: TransformState, IncrementCalculator, Godot math
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const IncrementCalculator = preload("res://addons/simpleassetplacer/utils/increment_calculator.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

## Configuration

func configure(state: TransformState, settings: Dictionary):
	"""Configure scale manager with settings"""
	# Note: Smooth transform settings should be configured by the coordinator,
	# not by ScaleManager (to avoid cross-manager dependencies)
	
	# Handle initial scale
	if settings.has("initial_scale"):
		var initial = settings.initial_scale
		if initial is float or initial is int:
			set_scale_multiplier(state, float(initial))
		elif initial is Vector3:
			set_non_uniform_multiplier(state, initial)
	
	# Handle scale limits
	if settings.has("min_scale"):
		var min_val = settings.get("min_scale", 0.01)
		var max_val = settings.get("max_scale", 100.0)
		clamp_scale(state, min_val, max_val)

## Core Scale Functions

func set_scale_multiplier(state: TransformState, multiplier: float):
	"""Set uniform scale multiplier (1.0 = original size, 2.0 = double, 0.5 = half)"""
	state.values.scale_multiplier = max(0.01, multiplier)  # Prevent zero/negative scale
	state.values.non_uniform_multiplier = Vector3(state.values.scale_multiplier, state.values.scale_multiplier, state.values.scale_multiplier)

func set_non_uniform_multiplier(state: TransformState, multiplier: Vector3):
	"""Set non-uniform scale multiplier"""
	state.values.non_uniform_multiplier = Vector3(
		max(0.01, multiplier.x),
		max(0.01, multiplier.y),
		max(0.01, multiplier.z)
	)
	# Update uniform scale to average
	state.values.scale_multiplier = (state.values.non_uniform_multiplier.x + state.values.non_uniform_multiplier.y + state.values.non_uniform_multiplier.z) / 3.0

func get_scale(state: TransformState) -> float:
	"""Get current uniform scale multiplier"""
	return state.values.scale_multiplier

func get_scale_vector(state: TransformState) -> Vector3:
	"""Get current scale multiplier as Vector3"""
	return state.values.non_uniform_multiplier

func reset_scale(state: TransformState):
	"""Reset scale multiplier to 1.0 (original size)"""
	set_scale_multiplier(state, 1.0)
	PluginLogger.debug("ScaleManager", "Scale multiplier reset to 1.0")

## Scale Modifications

func increase_scale(state: TransformState, amount: float = 0.1):
	"""Increase scale multiplier by amount"""
	set_scale_multiplier(state, state.values.scale_multiplier + amount)
	PluginLogger.debug("ScaleManager", "Increased scale multiplier by " + str(amount) + " to " + str(state.values.scale_multiplier))

func decrease_scale(state: TransformState, amount: float = 0.1):
	"""Decrease scale multiplier by amount"""
	set_scale_multiplier(state, state.values.scale_multiplier - amount)
	PluginLogger.debug("ScaleManager", "Decreased scale multiplier by " + str(amount) + " to " + str(state.values.scale_multiplier))

func adjust_scale_with_modifiers(state: TransformState, base_amount: float, modifiers: Dictionary):
	"""Adjust scale with modifier-calculated step
	
	Args:
		state: TransformState to modify
		base_amount: Base scale step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_scale_step(base_amount, modifiers)
	set_scale_multiplier(state, state.values.scale_multiplier + step)
	PluginLogger.debug("ScaleManager", "Adjusted scale by " + str(step) + " to " + str(state.values.scale_multiplier))

func multiply_scale(state: TransformState, factor: float):
	"""Multiply current scale multiplier by a factor"""
	set_scale_multiplier(state, state.values.scale_multiplier * factor)
	PluginLogger.debug("ScaleManager", "Multiplied scale by " + str(factor) + " to " + str(state.values.scale_multiplier))

func scale_up(state: TransformState, factor: float = 1.1):
	"""Scale up by a factor (default 10% increase)"""
	multiply_scale(state, factor)

func scale_down(state: TransformState, factor: float = 0.9):
	"""Scale down by a factor (default 10% decrease)"""
	multiply_scale(state, factor)

## Non-Uniform Scale Modifications

func scale_axis(state: TransformState, axis: String, amount: float):
	"""Scale a specific axis multiplier by amount"""
	match axis.to_upper():
		"X":
			state.values.non_uniform_multiplier.x = max(0.01, state.values.non_uniform_multiplier.x + amount)
		"Y":
			state.values.non_uniform_multiplier.y = max(0.01, state.values.non_uniform_multiplier.y + amount)
		"Z":
			state.values.non_uniform_multiplier.z = max(0.01, state.values.non_uniform_multiplier.z + amount)
		_:
			PluginLogger.warning("ScaleManager", "Invalid axis: " + axis)
			return
	
	# Update uniform scale multiplier
	state.values.scale_multiplier = (state.values.non_uniform_multiplier.x + state.values.non_uniform_multiplier.y + state.values.non_uniform_multiplier.z) / 3.0

func scale_axis_with_modifiers(state: TransformState, axis: String, base_amount: float, modifiers: Dictionary):
	"""Scale a specific axis with modifier-calculated step
	
	Args:
		state: TransformState to modify
		axis: Scale axis ("X", "Y", or "Z")
		base_amount: Base scale step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_scale_step(base_amount, modifiers)
	scale_axis(state, axis, step)

func multiply_axis_scale(state: TransformState, axis: String, factor: float):
	"""Multiply a specific axis scale multiplier by a factor"""
	match axis.to_upper():
		"X":
			state.values.non_uniform_multiplier.x = max(0.01, state.values.non_uniform_multiplier.x * factor)
		"Y":
			state.values.non_uniform_multiplier.y = max(0.01, state.values.non_uniform_multiplier.y * factor)
		"Z":
			state.values.non_uniform_multiplier.z = max(0.01, state.values.non_uniform_multiplier.z * factor)
		_:
			PluginLogger.warning("ScaleManager", "Invalid axis: " + axis)
			return
	
	# Update uniform scale multiplier
	state.values.scale_multiplier = (state.values.non_uniform_multiplier.x + state.values.non_uniform_multiplier.y + state.values.non_uniform_multiplier.z) / 3.0

## Scale Constraints and Validation

func clamp_scale(state: TransformState, min_multiplier: float = 0.01, max_multiplier: float = 100.0):
	"""Clamp scale multiplier within specified bounds"""
	state.values.scale_multiplier = clampf(state.values.scale_multiplier, min_multiplier, max_multiplier)
	state.values.non_uniform_multiplier.x = clampf(state.values.non_uniform_multiplier.x, min_multiplier, max_multiplier)
	state.values.non_uniform_multiplier.y = clampf(state.values.non_uniform_multiplier.y, min_multiplier, max_multiplier)
	state.values.non_uniform_multiplier.z = clampf(state.values.non_uniform_multiplier.z, min_multiplier, max_multiplier)

func is_uniform_scale(state: TransformState) -> bool:
	"""Check if current scale multiplier is uniform"""
	var epsilon = 0.001
	return abs(state.values.non_uniform_multiplier.x - state.values.non_uniform_multiplier.y) < epsilon and \
		   abs(state.values.non_uniform_multiplier.y - state.values.non_uniform_multiplier.z) < epsilon

func is_scale_at_default(state: TransformState) -> bool:
	"""Check if scale multiplier is at default (1.0 = original size)"""
	return abs(state.values.scale_multiplier - 1.0) < 0.001

## Scale Presets

func set_scale_preset(state: TransformState, preset_name: String):
	"""Set scale multiplier to a common preset"""
	match preset_name.to_lower():
		"tiny":
			set_scale_multiplier(state, 0.1)
		"small":
			set_scale_multiplier(state, 0.5)
		"normal", "default":
			set_scale_multiplier(state, 1.0)
		"large":
			set_scale_multiplier(state, 2.0)
		"huge":
			set_scale_multiplier(state, 5.0)
		"double":
			set_scale_multiplier(state, 2.0)
		"half":
			set_scale_multiplier(state, 0.5)
		"quarter":
			set_scale_multiplier(state, 0.25)
		_:
			PluginLogger.warning("ScaleManager", "Unknown preset: " + preset_name)

## Scale Interpolation

func lerp_to_scale(state: TransformState, target_multiplier: float, weight: float):
	"""Smoothly interpolate to a target scale multiplier"""
	set_scale_multiplier(state, lerp(state.values.scale_multiplier, target_multiplier, weight))

func lerp_to_scale_vector(state: TransformState, target_multiplier: Vector3, weight: float):
	"""Smoothly interpolate to a target scale multiplier vector"""
	set_non_uniform_multiplier(state, state.values.non_uniform_multiplier.lerp(target_multiplier, weight))

## Configuration and Settings

func get_configuration(state: TransformState) -> Dictionary:
	"""Get current configuration"""
	return {
		"scale_multiplier": state.values.scale_multiplier,
		"scale_multiplier_vector": state.values.non_uniform_multiplier,
		"is_uniform": is_uniform_scale(state),
		"is_default": is_scale_at_default(state)
	}

## Display and Formatting

func get_scale_value(state: TransformState) -> float:
	"""Get scale multiplier as actual scale value (1.0 = normal size)"""
	return state.values.scale_multiplier

func get_scale_display_text(state: TransformState) -> String:
	"""Get formatted scale display text"""
	if is_uniform_scale(state):
		return "Scale: %.2fx" % get_scale_value(state)
	else:
		return "Scale: X:%.2fx Y:%.2fx Z:%.2fx" % [
			state.values.non_uniform_multiplier.x,
			state.values.non_uniform_multiplier.y,
			state.values.non_uniform_multiplier.z
		]

## Debug and Information

func debug_print_scale(state: TransformState):
	"""Print current scale state for debugging"""
	PluginLogger.debug("ScaleManager", "ScaleManager State:")
	PluginLogger.debug("ScaleManager", "  Uniform Scale Multiplier: %.3fx" % state.values.scale_multiplier)
	PluginLogger.debug("ScaleManager", "  Scale Multiplier Vector: X:%.3f Y:%.3f Z:%.3f" % [state.values.non_uniform_multiplier.x, state.values.non_uniform_multiplier.y, state.values.non_uniform_multiplier.z])
	PluginLogger.debug("ScaleManager", "  Is Uniform: " + str(is_uniform_scale(state)))
	PluginLogger.debug("ScaleManager", "  Is Default: " + str(is_scale_at_default(state)))

func get_scale_info(state: TransformState) -> Dictionary:
	"""Get comprehensive scale information"""
	return {
		"scale_multiplier": state.values.scale_multiplier,
		"scale_multiplier_vector": state.values.non_uniform_multiplier,
		"scale_value": get_scale_value(state),
		"is_uniform": is_uniform_scale(state),
		"is_default": is_scale_at_default(state),
		"display_text": get_scale_display_text(state)
	}







