@tool
extends RefCounted

class_name IncrementCalculator

"""
INCREMENT CALCULATION UTILITY
=============================

PURPOSE: Centralized logic for calculating step increments based on modifiers.

RESPONSIBILITIES:
- Calculate modified step values based on modifier keys
- Provide consistent increment scaling across all transform types
- Handle reverse/large/fine increment modifiers
- Support configurable multipliers

ARCHITECTURE POSITION: Pure calculation utility with no state
- Does NOT handle input detection (receives modifier state)
- Does NOT know about specific transform types
- Works with any numeric step value

USED BY: RotationManager, ScaleManager, PositionManager
DEPENDS ON: Only Godot math system
"""

# Default multipliers for increment modifiers
static var large_increment_multiplier: float = 5.0  # ALT by default
static var fine_increment_multiplier: float = 0.1   # CTRL by default

## Core Increment Calculation

static func calculate_step(base_step: float, modifiers: Dictionary) -> float:
	"""Calculate modified step value based on active modifiers
	
	Args:
		base_step: The base step value (e.g., 15 degrees, 0.1 scale, 0.5 units)
		modifiers: Dictionary with keys: "reverse", "large", "fine"
	
	Returns:
		Modified step value (can be negative if reverse is true)
	"""
	var step = base_step
	
	# Apply multiplier modifiers (large takes precedence over fine)
	if modifiers.get("large", false):
		step *= large_increment_multiplier
	elif modifiers.get("fine", false):
		step *= fine_increment_multiplier
	
	# Apply reverse modifier (negative step)
	if modifiers.get("reverse", false):
		step = -step
	
	return step

static func calculate_rotation_step(base_degrees: float, modifiers: Dictionary) -> float:
	"""Calculate rotation step in degrees with modifier scaling
	
	Common usage:
		var step = IncrementCalculator.calculate_rotation_step(15.0, modifiers)
		# base_step=15°, large=75°, fine=1.5°
	"""
	return calculate_step(base_degrees, modifiers)

static func calculate_scale_step(base_multiplier: float, modifiers: Dictionary) -> float:
	"""Calculate scale step (multiplier) with modifier scaling
	
	Common usage:
		var step = IncrementCalculator.calculate_scale_step(0.1, modifiers)
		# base_step=0.1, large=0.5, fine=0.01
	"""
	return calculate_step(base_multiplier, modifiers)

static func calculate_position_step(base_distance: float, modifiers: Dictionary) -> float:
	"""Calculate position step (distance) with modifier scaling
	
	Common usage:
		var step = IncrementCalculator.calculate_position_step(0.5, modifiers)
		# base_step=0.5, large=2.5, fine=0.05
	"""
	return calculate_step(base_distance, modifiers)

static func calculate_height_step(base_step: float, modifiers: Dictionary) -> float:
	"""Calculate height step with modifier scaling
	
	Common usage:
		var step = IncrementCalculator.calculate_height_step(0.1, modifiers)
		# base_step=0.1, large=0.5, fine=0.01
	"""
	return calculate_step(base_step, modifiers)

## Increment Direction Helpers

static func get_direction_multiplier(modifiers: Dictionary) -> float:
	"""Get just the direction multiplier (1.0 or -1.0) from modifiers
	Useful when you want to handle magnitude separately"""
	return -1.0 if modifiers.get("reverse", false) else 1.0

static func get_magnitude_multiplier(modifiers: Dictionary) -> float:
	"""Get just the magnitude multiplier (no direction) from modifiers"""
	if modifiers.get("large", false):
		return large_increment_multiplier
	elif modifiers.get("fine", false):
		return fine_increment_multiplier
	return 1.0

static func apply_direction_only(value: float, modifiers: Dictionary) -> float:
	"""Apply only the direction modifier to a value (reverse or not)"""
	return value * get_direction_multiplier(modifiers)

static func apply_magnitude_only(value: float, modifiers: Dictionary) -> float:
	"""Apply only the magnitude modifier to a value (large/fine/normal)"""
	return value * get_magnitude_multiplier(modifiers)

## Configuration

static func configure_multipliers(large: float = 5.0, fine: float = 0.1) -> void:
	"""Configure the multiplier values used for large/fine increments
	
	Args:
		large: Multiplier for large increment modifier (default 5.0 = 5x base)
		fine: Multiplier for fine increment modifier (default 0.1 = 0.1x base)
	"""
	large_increment_multiplier = max(1.0, large)  # Must be >= 1.0
	fine_increment_multiplier = clamp(fine, 0.01, 1.0)  # Must be 0.01-1.0
	PluginLogger.debug("IncrementCalculator", "Configured multipliers - Large: %.1f, Fine: %.2f" % [large_increment_multiplier, fine_increment_multiplier])

static func get_configuration() -> Dictionary:
	"""Get current multiplier configuration"""
	return {
		"large_multiplier": large_increment_multiplier,
		"fine_multiplier": fine_increment_multiplier
	}

## Step Presets

static func calculate_with_preset(preset_name: String, base_step: float, modifiers: Dictionary) -> float:
	"""Calculate step using a named preset configuration
	
	Useful for context-specific increment behaviors"""
	match preset_name.to_lower():
		"rotation":
			# Rotation uses standard multipliers
			return calculate_rotation_step(base_step, modifiers)
		"scale":
			# Scale might want different sensitivity
			return calculate_scale_step(base_step, modifiers)
		"position":
			# Position uses standard multipliers
			return calculate_position_step(base_step, modifiers)
		"height":
			# Height uses standard multipliers
			return calculate_height_step(base_step, modifiers)
		_:
			return calculate_step(base_step, modifiers)

## Validation and Constraints

static func calculate_clamped_step(base_step: float, modifiers: Dictionary, min_step: float = 0.0, max_step: float = INF) -> float:
	"""Calculate step and clamp to valid range (useful for scale, etc.)"""
	var step = calculate_step(base_step, modifiers)
	return clamp(abs(step), min_step, max_step) * sign(step)

static func is_reverse_active(modifiers: Dictionary) -> bool:
	"""Check if reverse modifier is active"""
	return modifiers.get("reverse", false)

static func is_large_active(modifiers: Dictionary) -> bool:
	"""Check if large increment modifier is active"""
	return modifiers.get("large", false)

static func is_fine_active(modifiers: Dictionary) -> bool:
	"""Check if fine increment modifier is active"""
	return modifiers.get("fine", false)

## Debug and Information

static func debug_print_step_calculation(base_step: float, modifiers: Dictionary) -> void:
	"""Print step calculation details for debugging"""
	var final_step = calculate_step(base_step, modifiers)
	PluginLogger.debug("IncrementCalculator", "Step Calculation:")
	PluginLogger.debug("IncrementCalculator", "  Base Step: %.3f" % base_step)
	PluginLogger.debug("IncrementCalculator", "  Modifiers: %s" % str(modifiers))
	PluginLogger.debug("IncrementCalculator", "  Large Active: %s (x%.1f)" % [is_large_active(modifiers), large_increment_multiplier])
	PluginLogger.debug("IncrementCalculator", "  Fine Active: %s (x%.2f)" % [is_fine_active(modifiers), fine_increment_multiplier])
	PluginLogger.debug("IncrementCalculator", "  Reverse Active: %s" % is_reverse_active(modifiers))
	PluginLogger.debug("IncrementCalculator", "  Final Step: %.3f" % final_step)

static func get_step_info(base_step: float, modifiers: Dictionary) -> Dictionary:
	"""Get comprehensive step calculation information"""
	return {
		"base_step": base_step,
		"final_step": calculate_step(base_step, modifiers),
		"direction": get_direction_multiplier(modifiers),
		"magnitude": get_magnitude_multiplier(modifiers),
		"modifiers_active": {
			"reverse": is_reverse_active(modifiers),
			"large": is_large_active(modifiers),
			"fine": is_fine_active(modifiers)
		},
		"configuration": get_configuration()
	}







