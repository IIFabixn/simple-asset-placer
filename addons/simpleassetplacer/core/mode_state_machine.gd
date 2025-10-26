@tool
extends RefCounted

class_name ModeStateMachine

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
MODE STATE MACHINE
==================

PURPOSE: Centralized mode state management and transition logic

RESPONSIBILITIES:
- Mode enumeration (NONE, PLACEMENT, TRANSFORM)
- Current mode state tracking
- Mode transition validation
- State queries (is_placement_mode, is_transform_mode, etc.)

ARCHITECTURE POSITION: Core state manager
- Used by TransformationCoordinator for mode control
- Provides single source of truth for current mode
- No business logic - pure state management

USED BY: TransformationCoordinator, mode handlers
USES: PluginLogger, PluginConstants
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === MODE ENUM ===

enum Mode {
	NONE,        # No active mode
	PLACEMENT,   # Placing new assets
	TRANSFORM    # Transforming selected objects
}

# === STATE ===

var _current_mode: Mode = Mode.NONE

## STATE QUERIES

func is_any_mode_active() -> bool:
	"""Check if any transformation mode is currently active"""
	return _current_mode != Mode.NONE

func is_placement_mode() -> bool:
	"""Check if placement mode is active"""
	return _current_mode == Mode.PLACEMENT

func is_transform_mode() -> bool:
	"""Check if transform mode is active"""
	return _current_mode == Mode.TRANSFORM

func get_current_mode() -> Mode:
	"""Get the current mode (returns Mode enum)"""
	return _current_mode

func get_current_mode_string() -> String:
	"""Get the current mode as a string (for display/logging purposes)"""
	match _current_mode:
		Mode.NONE:
			return "none"
		Mode.PLACEMENT:
			return "placement"
		Mode.TRANSFORM:
			return "transform"
		_:
			return "unknown"

## MODE TRANSITIONS

func can_enter_mode(new_mode: Mode) -> bool:
	"""Check if we can transition to the specified mode
	
	Args:
		new_mode: The mode we want to enter
		
	Returns:
		bool: True if transition is allowed, False otherwise
	"""
	# Can always exit to NONE
	if new_mode == Mode.NONE:
		return true
	
	# Can't enter same mode twice
	if new_mode == _current_mode:
		PluginLogger.warning("ModeStateMachine", "Already in " + get_mode_name(new_mode) + " mode")
		return false
	
	# Can enter any mode from NONE
	if _current_mode == Mode.NONE:
		return true
	
	# Can't enter new mode while another is active (must exit first)
	if _current_mode != Mode.NONE and new_mode != Mode.NONE:
		PluginLogger.warning("ModeStateMachine", "Must exit " + get_mode_name(_current_mode) + " mode before entering " + get_mode_name(new_mode) + " mode")
		return false
	
	return true

func transition_to_mode(new_mode: Mode) -> bool:
	"""Attempt to transition to a new mode
	
	Args:
		new_mode: The mode to transition to
		
	Returns:
		bool: True if transition succeeded, False if blocked
	"""
	if not can_enter_mode(new_mode):
		return false
	
	var old_mode = _current_mode
	_current_mode = new_mode
	
	# Log transition
	if old_mode != new_mode:
		PluginLogger.info(
			PluginConstants.COMPONENT_TRANSFORM,
			"Mode transition: " + get_mode_name(old_mode) + " → " + get_mode_name(new_mode)
		)
	
	return true

func set_mode(mode: Mode) -> void:
	"""Directly set the mode (low-level, use transition_to_mode for validation)
	
	Args:
		mode: The mode to set
	"""
	_current_mode = mode

func clear_mode() -> void:
	"""Clear the current mode (set to NONE)"""
	_current_mode = Mode.NONE

## VALIDATION HELPERS

func validate_mode_transition(from_mode: Mode, to_mode: Mode) -> bool:
	"""Validate a specific mode transition
	
	Args:
		from_mode: The current mode
		to_mode: The desired mode
		
	Returns:
		bool: True if transition is valid, False otherwise
	"""
	# Exit to NONE is always valid
	if to_mode == Mode.NONE:
		return true
	
	# Can't enter same mode
	if from_mode == to_mode:
		return false
	
	# Can enter any mode from NONE
	if from_mode == Mode.NONE:
		return true
	
	# Can't switch directly between non-NONE modes
	if from_mode != Mode.NONE and to_mode != Mode.NONE:
		return false
	
	return true

func require_mode(required_mode: Mode, operation_name: String = "Operation") -> bool:
	"""Check if current mode matches required mode, log error if not
	
	Args:
		required_mode: The mode that must be active
		operation_name: Name of operation requiring this mode (for error message)
		
	Returns:
		bool: True if in required mode, False otherwise
	"""
	if _current_mode != required_mode:
		PluginLogger.error(
			"ModeStateMachine",
			operation_name + " requires " + get_mode_name(required_mode) + " mode, but current mode is " + get_mode_name(_current_mode)
		)
		return false
	return true

func require_no_mode(operation_name: String = "Operation") -> bool:
	"""Check that no mode is active, log error if one is
	
	Args:
		operation_name: Name of operation requiring no mode (for error message)
		
	Returns:
		bool: True if no mode active, False otherwise
	"""
	if _current_mode != Mode.NONE:
		PluginLogger.error(
			"ModeStateMachine",
			operation_name + " requires no active mode, but " + get_mode_name(_current_mode) + " mode is active"
		)
		return false
	return true

## UTILITY HELPERS

func get_mode_name(mode: Mode) -> String:
	"""Get human-readable name for a mode
	
	Args:
		mode: The mode to get name for
		
	Returns:
		String: Human-readable mode name
	"""
	match mode:
		Mode.NONE:
			return "NONE"
		Mode.PLACEMENT:
			return "PLACEMENT"
		Mode.TRANSFORM:
			return "TRANSFORM"
		_:
			return "UNKNOWN"

func get_mode_from_string(mode_string: String) -> Mode:
	"""Get Mode enum from string representation
	
	Args:
		mode_string: String representation of mode ("none", "placement", "transform")
		
	Returns:
		Mode: The corresponding Mode enum value
	"""
	match mode_string.to_lower():
		"none":
			return Mode.NONE
		"placement":
			return Mode.PLACEMENT
		"transform":
			return Mode.TRANSFORM
		_:
			PluginLogger.warning("ModeStateMachine", "Unknown mode string: " + mode_string)
			return Mode.NONE

## DEBUG

func debug_print_state() -> void:
	"""Print current state for debugging"""
	PluginLogger.debug(
		"ModeStateMachine",
		"Current mode: " + get_mode_name(_current_mode) + " (" + str(_current_mode) + ")"
	)

