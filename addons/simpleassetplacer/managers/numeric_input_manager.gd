@tool
extends RefCounted

class_name NumericInputManager

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
NUMERIC INPUT SYSTEM (Blender-style)
====================================

PURPOSE: Provides Blender-style numeric input for precise transformations.

FEATURES:
- Type numbers directly after initiating an action (rotation, scale, position, height)
- Absolute mode: = prefix (e.g., =90 sets rotation to exactly 90 degrees)
- Relative mode: +/- prefix or no prefix (e.g., +5, -10, or just 5 for relative change)
- Prefix can be changed even after typing numbers
- Decimal support (e.g., 1.5, 0.25)
- Grace period: 2 seconds after action initiation before numeric input becomes inactive
- Action confirmation: Left click, Enter, or pressing same action key again
- Action cancellation: Escape, or starting a different action
- Tab detection: Tab + number = activate, Tab hold without number = don't activate

ARCHITECTURE POSITION: Pure input interpretation system
- Tracks numeric input state across frames
- Manages action context and timing
- Provides clean API for querying and applying numeric values
- Does NOT perform transformations directly

USED BY: TransformModeHandler, PlacementModeHandler
DEPENDS ON: InputHandler for raw key events
"""

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === CONSTANTS ===

const GRACE_PERIOD: float = 2.0  # 2 seconds after action to accept numeric input
const TAB_HOLD_THRESHOLD: float = 0.15  # 150ms - if tab held longer, don't activate numeric input

# === ENUMS ===

enum ActionType {
	NONE,
	ROTATE_X,
	ROTATE_Y,
	ROTATE_Z,
	SCALE,
	HEIGHT,
	POSITION_X,
	POSITION_Z,
	POSITION_FORWARD,
	POSITION_BACKWARD,
	POSITION_LEFT,
	POSITION_RIGHT
}

enum PrefixMode {
	RELATIVE,      # Default - adds to current value (no prefix, or +)
	RELATIVE_SUB,  # Subtracts from current value (-)
	ABSOLUTE       # Sets exact value (=)
}

# === STATE ===

# Current action being tracked
var _active_action: ActionType = ActionType.NONE
var _action_start_time: float = 0.0

# Context tracking - which action key was last pressed (even if not active yet)
var _last_action_context: ActionType = ActionType.NONE
var _context_time: float = 0.0

# Input buffer
var _input_buffer: String = ""
var _prefix_mode: PrefixMode = PrefixMode.RELATIVE
var _has_decimal: bool = false
var _user_has_typed: bool = false  # True once user types any character (stays true even if buffer cleared)

# Tab detection
var _tab_pressed_time: float = 0.0
var _tab_was_quick_press: bool = false
var _action_initiated_by_tab: bool = false

# Confirmation state
var _is_confirmed: bool = false
var _pending_value: float = 0.0

## Public API - State Queries

func is_active() -> bool:
	"""Check if numeric input system is currently active"""
	return _active_action != ActionType.NONE

func get_active_action() -> ActionType:
	"""Get the currently active action type"""
	return _active_action

func get_input_string() -> String:
	"""Get the current input buffer as display string"""
	var prefix = ""
	match _prefix_mode:
		PrefixMode.ABSOLUTE:
			prefix = "="
		PrefixMode.RELATIVE_SUB:
			prefix = "-"
		PrefixMode.RELATIVE:
			if _input_buffer.length() > 0:
				prefix = "+"  # Show + for clarity when there's input
	
	return prefix + _input_buffer

func get_numeric_value() -> float:
	"""Parse and return the current numeric value. Returns 0.0 if empty or invalid."""
	if _input_buffer.is_empty():
		return 0.0
	
	# Remove any prefix characters that might have been included
	var clean_buffer = _input_buffer.replace("=", "").replace("+", "").replace("-", "")
	
	if clean_buffer.is_valid_float():
		return clean_buffer.to_float()
	return 0.0

func get_prefix_mode() -> PrefixMode:
	"""Get the current prefix mode"""
	return _prefix_mode

func is_confirmed() -> bool:
	"""Check if the current input has been confirmed"""
	return _is_confirmed

func is_within_grace_period() -> bool:
	"""Check if we're still within the grace period for accepting input.
	Grace period only applies BEFORE user starts typing. Once they've typed
	at least one character, they can continue typing indefinitely (even if they backspace everything)."""
	if _active_action == ActionType.NONE:
		return false
	
	# If user has already started typing (even if buffer is now empty), no grace period limit
	if _user_has_typed:
		return true
	
	# Only check grace period for initial activation (before first character)
	var current_time = Time.get_ticks_msec() / 1000.0
	return (current_time - _action_start_time) <= GRACE_PERIOD

func has_context() -> bool:
	"""Check if there's an action context set (even if not active yet)"""
	if _last_action_context == ActionType.NONE:
		return false
	
	# Check if context is still fresh
	var current_time = Time.get_ticks_msec() / 1000.0
	return (current_time - _context_time) <= GRACE_PERIOD

## Public API - Action Management

func set_action_context(action: ActionType) -> void:
	"""Set the action context - this is called when an action key is pressed.
	Numeric input will only activate when the user actually types a number."""
	# If pressing the same action again while active and within grace period, confirm it
	if _active_action == action and _active_action != ActionType.NONE and is_within_grace_period():
		confirm_action()
		PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Confirmed action %s by pressing again" % _action_to_string(action))
		return
	
	# Store as context (not active yet - will activate on first number typed)
	_last_action_context = action
	_context_time = Time.get_ticks_msec() / 1000.0
	
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Set context to %s (not active yet)" % _action_to_string(action))

func _activate_from_context() -> bool:
	"""Activate numeric input using the stored context. Returns true if successful."""
	if _last_action_context == ActionType.NONE:
		return false
	
	# Check if context is still fresh (within grace period)
	var current_time = Time.get_ticks_msec() / 1000.0
	if (current_time - _context_time) > GRACE_PERIOD:
		_last_action_context = ActionType.NONE
		return false
	
	# Activate the action
	_active_action = _last_action_context
	_action_start_time = _context_time  # Use context time as start time
	_is_confirmed = false
	
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Activated action %s from context" % _action_to_string(_active_action))
	return true

func confirm_action() -> void:
	"""Confirm the current numeric input"""
	if not is_active():
		return
	
	_is_confirmed = true
	_pending_value = get_numeric_value()
	
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Confirmed value %.3f for action %s" % [_pending_value, _action_to_string(_active_action)])

func cancel_action() -> void:
	"""Cancel the current numeric input and reset"""
	if is_active():
		PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Cancelled action %s" % _action_to_string(_active_action))
	reset()

func reset() -> void:
	"""Reset all numeric input state"""
	_active_action = ActionType.NONE
	_action_start_time = 0.0
	_last_action_context = ActionType.NONE
	_context_time = 0.0
	_input_buffer = ""
	_prefix_mode = PrefixMode.RELATIVE
	_has_decimal = false
	_user_has_typed = false
	_is_confirmed = false
	_pending_value = 0.0
	_tab_pressed_time = 0.0
	_tab_was_quick_press = false
	_action_initiated_by_tab = false

## Public API - Input Processing

func process_numeric_key(key_char: String) -> bool:
	"""Process numeric key input (0-9). Returns true if consumed."""
	# Only accept single digit characters
	if key_char.length() != 1:
		return false
	
	var char_code = key_char.unicode_at(0)
	if char_code < 48 or char_code > 57:  # Must be 0-9
		return false
	
	# If not active yet but we have context, activate now!
	if not is_active() and _last_action_context != ActionType.NONE:
		if not _activate_from_context():
			return false  # Context expired
	
	# If still not active, don't consume the key
	if not is_active():
		return false
	
	# Check grace period after activation
	if not is_within_grace_period():
		return false
	
	# Add digit to buffer
	_input_buffer += key_char
	_user_has_typed = true  # Mark that user has started typing
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Added digit, buffer now: %s" % get_input_string())
	return true

func process_decimal_key() -> bool:
	"""Process decimal point key. Returns true if consumed."""
	# If not active yet but we have context, activate now!
	if not is_active() and _last_action_context != ActionType.NONE:
		if not _activate_from_context():
			return false  # Context expired
	
	if not is_within_grace_period():
		return false
	
	# Only allow one decimal point
	if _has_decimal:
		return true  # Consume but don't add
	
	_input_buffer += "."
	_has_decimal = true
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Added decimal, buffer now: %s" % get_input_string())
	return true

func process_minus_key() -> bool:
	"""Process minus/subtract key. Returns true if consumed."""
	# If not active yet but we have context, activate now!
	if not is_active() and _last_action_context != ActionType.NONE:
		if not _activate_from_context():
			return false  # Context expired
	
	if not is_within_grace_period():
		return false
	
	# If buffer is empty, set to RELATIVE_SUB mode
	# If buffer has content, toggle between RELATIVE and RELATIVE_SUB
	if _input_buffer.is_empty():
		_prefix_mode = PrefixMode.RELATIVE_SUB
	else:
		# Toggle between RELATIVE and RELATIVE_SUB
		if _prefix_mode == PrefixMode.RELATIVE_SUB:
			_prefix_mode = PrefixMode.RELATIVE
		else:
			_prefix_mode = PrefixMode.RELATIVE_SUB
	
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Changed prefix mode to %s" % _prefix_mode)
	return true

func process_plus_key() -> bool:
	"""Process plus/add key. Returns true if consumed."""
	# If not active yet but we have context, activate now!
	if not is_active() and _last_action_context != ActionType.NONE:
		if not _activate_from_context():
			return false  # Context expired
	
	if not is_within_grace_period():
		return false
	
	# Set to RELATIVE mode
	_prefix_mode = PrefixMode.RELATIVE
	
	PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Changed prefix mode to RELATIVE")
	return true

func process_equals_key() -> bool:
	"""Process equals key for absolute mode. Returns true if consumed."""
	# If not active yet but we have context, activate now!
	if not is_active() and _last_action_context != ActionType.NONE:
		if not _activate_from_context():
			return false  # Context expired
	
	if not is_within_grace_period():
		return false
	
	# Toggle absolute mode
	if _prefix_mode == PrefixMode.ABSOLUTE:
		_prefix_mode = PrefixMode.RELATIVE
	else:
		_prefix_mode = PrefixMode.ABSOLUTE
	
	PluginLogger.info(PluginConstants.COMPONENT_INPUT, "NumericInput: Changed prefix mode to %s" % _prefix_mode)
	return true

func process_backspace() -> bool:
	"""Process backspace to remove last character. Returns true if consumed."""
	if not is_within_grace_period():
		return false
	
	if _input_buffer.length() > 0:
		var last_char = _input_buffer[_input_buffer.length() - 1]
		_input_buffer = _input_buffer.substr(0, _input_buffer.length() - 1)
		
		# If we removed a decimal point, reset decimal flag
		if last_char == ".":
			_has_decimal = false
		
		PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Removed character, buffer now: %s" % get_input_string())
		return true
	
	return false

## Public API - Tab Detection

func process_tab_pressed() -> void:
	"""Called when tab key is initially pressed"""
	_tab_pressed_time = Time.get_ticks_msec() / 1000.0
	_tab_was_quick_press = false

func process_tab_released() -> void:
	"""Called when tab key is released"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var hold_duration = current_time - _tab_pressed_time
	
	if hold_duration < TAB_HOLD_THRESHOLD:
		_tab_was_quick_press = true
		PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Tab was quick press (%.3fs)" % hold_duration)
	else:
		PluginLogger.debug(PluginConstants.COMPONENT_INPUT, "NumericInput: Tab was hold (%.3fs)" % hold_duration)

func was_tab_quick_press() -> bool:
	"""Check if the last tab press was a quick tap (not a hold)"""
	return _tab_was_quick_press

func should_activate_numeric_input_for_tab() -> bool:
	"""Check if numeric input should be activated based on tab press pattern.
	Only activate if tab was a quick press AND a number was typed shortly after."""
	return _tab_was_quick_press and is_active() and _input_buffer.length() > 0

## Public API - Application

func apply_to_value(current_value: float) -> float:
	"""Apply the numeric input to a current value based on prefix mode.
	
	Args:
		current_value: The current value (e.g., current rotation angle, scale, etc.)
	
	Returns:
		The new value after applying the input
	"""
	var input_value = get_numeric_value()
	
	match _prefix_mode:
		PrefixMode.ABSOLUTE:
			return input_value
		PrefixMode.RELATIVE:
			return current_value + input_value
		PrefixMode.RELATIVE_SUB:
			return current_value - input_value
	
	return current_value

func is_absolute_mode() -> bool:
	"""Check if numeric input is in absolute mode (= prefix)"""
	return _prefix_mode == PrefixMode.ABSOLUTE

## Helper Methods

func _action_to_string(action: ActionType) -> String:
	"""Convert action type to string for logging"""
	match action:
		ActionType.NONE:
			return "NONE"
		ActionType.ROTATE_X:
			return "ROTATE_X"
		ActionType.ROTATE_Y:
			return "ROTATE_Y"
		ActionType.ROTATE_Z:
			return "ROTATE_Z"
		ActionType.SCALE:
			return "SCALE"
		ActionType.HEIGHT:
			return "HEIGHT"
		ActionType.POSITION_X:
			return "POSITION_X"
		ActionType.POSITION_Z:
			return "POSITION_Z"
		ActionType.POSITION_FORWARD:
			return "POSITION_FORWARD"
		ActionType.POSITION_BACKWARD:
			return "POSITION_BACKWARD"
		ActionType.POSITION_LEFT:
			return "POSITION_LEFT"
		ActionType.POSITION_RIGHT:
			return "POSITION_RIGHT"
	
	return "UNKNOWN"

func get_action_display_name() -> String:
	"""Get a user-friendly display name for the current action"""
	match _active_action:
		ActionType.ROTATE_X:
			return "Rotate X"
		ActionType.ROTATE_Y:
			return "Rotate Y"
		ActionType.ROTATE_Z:
			return "Rotate Z"
		ActionType.SCALE:
			return "Scale"
		ActionType.HEIGHT:
			return "Height"
		ActionType.POSITION_X:
			return "Position X"
		ActionType.POSITION_Z:
			return "Position Z"
		ActionType.POSITION_FORWARD:
			return "Move Forward"
		ActionType.POSITION_BACKWARD:
			return "Move Backward"
		ActionType.POSITION_LEFT:
			return "Move Left"
		ActionType.POSITION_RIGHT:
			return "Move Right"
	
	return ""
