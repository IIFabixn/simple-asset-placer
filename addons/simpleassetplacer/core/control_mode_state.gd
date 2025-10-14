@tool
extends RefCounted

class_name ControlModeState

"""
CONTROL MODE STATE MANAGER (Blender-like Modal Controls)
=========================================================

PURPOSE: Manages G/R/L control modes and X/Y/Z axis constraints for transform operations.

RESPONSIBILITIES:
- Track active control mode (POSITION/ROTATION/SCALE)
- Manage axis constraints (X/Y/Z) with double-tap toggle
- Provide state queries for input routing
- Handle mode transitions and constraint changes
- Track constraint timing for UI feedback

ARCHITECTURE POSITION: Core state manager for modal transform controls
- Works alongside ModeStateMachine (which handles PLACEMENT vs TRANSFORM)
- Provides fine-grained control routing within a mode
- Single source of truth for "what am I controlling right now"

USED BY: InputHandler, PlacementModeHandler, TransformModeHandler, OverlayManager
DEPENDS ON: Nothing (pure state)
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

# === CONTROL MODE ENUM ===

enum ControlMode {
	POSITION,   # G key - Position/movement control
	ROTATION,   # R key - Rotation control
	SCALE       # L key - Scale control
}

# === STATE ===

var _current_control_mode: ControlMode = ControlMode.POSITION
var _modal_active: bool = false  # True when user explicitly activated a modal control (G/R/L pressed)

# Multi-axis constraint support: Each axis can be independently toggled
var _axis_constraints: Dictionary = {
	"X": false,
	"Y": false,
	"Z": false
}

# Constraint reference position: Stored when first axis is activated, used as origin for line/plane
var _constraint_origin: Vector3 = Vector3.ZERO
var _has_constraint_origin: bool = false
var _constraint_changed_time: float = 0.0

## Initialization

func _init():
	"""Initialize with default state"""
	reset()

## State Queries

func get_control_mode() -> ControlMode:
	"""Get the current control mode"""
	return _current_control_mode

func get_control_mode_string() -> String:
	"""Get control mode as string for display"""
	match _current_control_mode:
		ControlMode.POSITION:
			return "Position"
		ControlMode.ROTATION:
			return "Rotation"
		ControlMode.SCALE:
			return "Scale"
		_:
			return "Unknown"

func get_control_mode_key() -> String:
	"""Get the key letter for current control mode"""
	match _current_control_mode:
		ControlMode.POSITION:
			return "G"
		ControlMode.ROTATION:
			return "R"
		ControlMode.SCALE:
			return "L"
		_:
			return ""

func is_position_mode() -> bool:
	"""Check if in position control mode"""
	return _current_control_mode == ControlMode.POSITION

func is_rotation_mode() -> bool:
	"""Check if in rotation control mode"""
	return _current_control_mode == ControlMode.ROTATION

func is_scale_mode() -> bool:
	"""Check if in scale control mode"""
	return _current_control_mode == ControlMode.SCALE

func get_axis_constraint_string() -> String:
	"""Get axis constraint as string for display (e.g., 'X', 'XY', 'XYZ')"""
	var axes = []
	if _axis_constraints["X"]:
		axes.append("X")
	if _axis_constraints["Y"]:
		axes.append("Y")
	if _axis_constraints["Z"]:
		axes.append("Z")
	return "".join(axes)

func has_axis_constraint() -> bool:
	"""Check if any axis constraint is active"""
	return _axis_constraints["X"] or _axis_constraints["Y"] or _axis_constraints["Z"]

func get_constraint_origin() -> Vector3:
	"""Get the origin position for constraint calculations"""
	return _constraint_origin

func has_constraint_origin() -> bool:
	"""Check if constraint origin is set"""
	return _has_constraint_origin

func is_x_constrained() -> bool:
	"""Check if X-axis is constrained"""
	return _axis_constraints["X"]

func is_y_constrained() -> bool:
	"""Check if Y-axis is constrained"""
	return _axis_constraints["Y"]

func is_z_constrained() -> bool:
	"""Check if Z-axis is constrained"""
	return _axis_constraints["Z"]

func get_constrained_axes() -> Dictionary:
	"""Get dictionary of constrained axes (for direct access)"""
	return _axis_constraints.duplicate()

func is_modal_active() -> bool:
	"""Check if user has explicitly activated a modal control (G/R/L pressed)"""
	return _modal_active

## Mode Transitions

func set_control_mode(mode: ControlMode, activate_modal: bool = true) -> void:
	"""Set the control mode
	
	Args:
		mode: New control mode to activate
		activate_modal: Whether this is an explicit modal activation (user pressed G/R/L)
	"""
	if _current_control_mode != mode:
		_current_control_mode = mode
		# Clear axis constraints when changing modes
		clear_all_axis_constraints()
		PluginLogger.debug("ControlModeState", "Control mode changed to: %s" % get_control_mode_string())
	
	if activate_modal:
		_modal_active = true

func switch_to_position_mode() -> void:
	"""Switch to position control mode (G) - explicitly activated by user"""
	set_control_mode(ControlMode.POSITION, true)

func switch_to_rotation_mode() -> void:
	"""Switch to rotation control mode (R) - explicitly activated by user"""
	set_control_mode(ControlMode.ROTATION, true)

func switch_to_scale_mode() -> void:
	"""Switch to scale control mode (L) - explicitly activated by user"""
	set_control_mode(ControlMode.SCALE, true)

func deactivate_modal() -> void:
	"""Deactivate modal control (return to normal mode)"""
	_modal_active = false
	clear_all_axis_constraints()
	PluginLogger.debug("ControlModeState", "Modal control deactivated")

## Axis Constraint Management

func process_axis_key_press(axis: String, current_time: float, current_position: Vector3 = Vector3.ZERO) -> void:
	"""Process axis key press for constraint toggle
	
	Each key press toggles that axis on/off independently.
	Allows multiple axes to be active simultaneously (e.g., X+Y, X+Z, X+Y+Z).
	
	Args:
		axis: "X", "Y", or "Z"
		current_time: Current time in seconds
		current_position: Current object position (stored as constraint origin if this is first constraint)
	"""
	if not axis in ["X", "Y", "Z"]:
		return
	
	# Check if we're enabling the first constraint
	var had_constraints = has_axis_constraint()
	
	# Toggle the axis constraint
	_axis_constraints[axis] = not _axis_constraints[axis]
	_constraint_changed_time = current_time
	
	# If this is the first constraint being enabled, store the origin
	if _axis_constraints[axis] and not had_constraints:
		_constraint_origin = current_position
		_has_constraint_origin = true
		PluginLogger.debug("ControlModeState", "Stored constraint origin: %s" % _constraint_origin)
	
	# If all constraints are now disabled, clear the origin
	if not has_axis_constraint():
		_has_constraint_origin = false
	
	var state = "enabled" if _axis_constraints[axis] else "disabled"
	PluginLogger.debug("ControlModeState", "Axis %s constraint %s (current: %s)" % [axis, state, get_axis_constraint_string()])

func clear_all_axis_constraints() -> void:
	"""Clear all axis constraints"""
	var had_constraints = has_axis_constraint()
	_axis_constraints["X"] = false
	_axis_constraints["Y"] = false
	_axis_constraints["Z"] = false
	_has_constraint_origin = false
	_constraint_origin = Vector3.ZERO
	if had_constraints:
		_constraint_changed_time = Time.get_ticks_msec() / 1000.0
		PluginLogger.debug("ControlModeState", "All axis constraints cleared")

func get_constraint_age() -> float:
	"""Get time since last constraint change (for UI feedback)"""
	return (Time.get_ticks_msec() / 1000.0) - _constraint_changed_time

## Reset

func reset() -> void:
	"""Reset to default state (position mode, no constraints, modal inactive)"""
	_current_control_mode = ControlMode.POSITION
	_modal_active = false
	_axis_constraints = {
		"X": false,
		"Y": false,
		"Z": false
	}
	_constraint_changed_time = 0.0
	_has_constraint_origin = false
	_constraint_origin = Vector3.ZERO

## Debug

func get_state_string() -> String:
	"""Get current state as debug string"""
	var constraint_str = get_axis_constraint_string()
	if constraint_str.is_empty():
		constraint_str = "None"
	return "Control: %s | Axis: %s" % [get_control_mode_string(), constraint_str]

func debug_print_state() -> void:
	"""Print current state for debugging"""
	print("[ControlModeState] ", get_state_string())
