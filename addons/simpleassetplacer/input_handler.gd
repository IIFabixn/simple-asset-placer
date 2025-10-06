@tool
extends RefCounted

class_name InputHandler

"""
CENTRALIZED INPUT DETECTION SYSTEM
==================================

PURPOSE: Single source of truth for all input detection with proper edge detection.

RESPONSIBILITIES:
- Polls all input state once per frame (keys, mouse, actions)
- Provides edge detection (just pressed vs held) to prevent rapid-fire actions
- Maps custom key settings to input queries
- Provides clean input APIs for rotation, scale, position, and navigation
- Handles modifier key detection (SHIFT, CTRL, ALT)

ARCHITECTURE POSITION: Pure input detection with no business logic
- Does NOT handle what actions to take (delegates to callers)
- Does NOT know about placement/transform modes
- Does NOT handle UI or positioning

USED BY: TransformationManager for all input queries
DEPENDS ON: User settings for key mappings, Godot Input system
"""

# Current frame input state
static var current_keys: Dictionary = {}
static var current_mouse: Dictionary = {}
static var current_actions: Dictionary = {}

# Settings reference for key mappings
static var settings: Dictionary = {}

# Key state tracking for edge detection
static var previous_keys: Dictionary = {}
static var previous_mouse: Dictionary = {}

# Grace period tracking for tap vs hold detection
static var key_press_times: Dictionary = {}  # Track when each key was pressed
static var key_tap_grace_period: float = 0.15  # 150ms to distinguish tap from hold
static var pending_taps: Dictionary = {}  # Keys that might be taps, waiting for release

# Hold-to-repeat tracking for action keys
static var active_repeat_key: String = ""  # Single key currently repeating (only one at a time)
static var active_repeat_modifiers: Dictionary = {}  # Modifier state when repeat started
static var wheel_interrupted_keys: Dictionary = {}  # Keys interrupted by wheel, require re-press
static var repeat_intervals: Dictionary = {
	"rotation": 0.1,  # 100ms for responsive rotation
	"scale": 0.08,    # 80ms for smooth scaling
	"height": 0.08,   # 80ms for height adjustment
	"position": 0.05  # 50ms for smooth movement
}

# Viewport cache for proper mouse coordinate conversion
static var cached_viewport: SubViewport = null

## Core Input Polling

static func update_input_state(input_settings: Dictionary = {}, viewport: SubViewport = null):
	"""Update all input state for the current frame. Call this once per frame."""
	settings = input_settings
	
	# Store viewport for mouse position calculations
	if viewport:
		cached_viewport = viewport
	

	
	# Store previous state for edge detection
	previous_keys = current_keys.duplicate()
	previous_mouse = current_mouse.duplicate()
	
	# Clear current state
	current_keys.clear()
	current_mouse.clear() 
	current_actions.clear()
	
	# Update key states
	_update_key_states()
	_update_mouse_states()
	_update_action_states()

static func _update_key_states():
	"""Update all key states based on current settings"""
	var current_time = Time.get_ticks_msec() / 1000.0  # Convert to seconds
	
	# Core navigation keys - use universal modifier support
	current_keys["tab"] = _check_key_with_modifiers(settings.get("transform_mode_key", "TAB"))
	current_keys["escape"] = Input.is_key_pressed(KEY_ESCAPE)
	current_keys["shift"] = Input.is_key_pressed(KEY_SHIFT)
	current_keys["ctrl"] = Input.is_key_pressed(KEY_CTRL)
	current_keys["alt"] = Input.is_key_pressed(KEY_ALT)
	
	# Configurable modifier keys
	current_keys["reverse_modifier"] = _check_key_with_modifiers(settings.get("reverse_modifier_key", "SHIFT"))
	current_keys["large_increment_modifier"] = _check_key_with_modifiers(settings.get("large_increment_modifier_key", "ALT"))
	current_keys["fine_increment_modifier"] = _check_key_with_modifiers(settings.get("fine_increment_modifier_key", "CTRL"))
	
	# Settings-based keys - use universal modifier support
	current_keys["cancel"] = _check_key_with_modifiers(settings.get("cancel_key", "ESCAPE"))
	var height_up_key = settings.get("height_up_key", "Q")
	var height_down_key = settings.get("height_down_key", "E")
	var reset_height_key = settings.get("reset_height_key", "R")
	current_keys["height_up"] = _check_key_with_modifiers(height_up_key)
	current_keys["height_down"] = _check_key_with_modifiers(height_down_key)
	current_keys["reset_height"] = _check_key_with_modifiers(reset_height_key)
	
	# Position adjustment keys - use universal modifier support
	var position_left_key = settings.get("position_left_key", "A")
	var position_right_key = settings.get("position_right_key", "D")
	var position_forward_key = settings.get("position_forward_key", "W")
	var position_backward_key = settings.get("position_backward_key", "S")
	var reset_position_key = settings.get("reset_position_key", "G")
	current_keys["position_left"] = _check_key_with_modifiers(position_left_key)
	current_keys["position_right"] = _check_key_with_modifiers(position_right_key)
	current_keys["position_forward"] = _check_key_with_modifiers(position_forward_key)
	current_keys["position_backward"] = _check_key_with_modifiers(position_backward_key)
	current_keys["reset_position"] = _check_key_with_modifiers(reset_position_key)
	
	# Track key press times for grace period
	_track_key_press_time("height_up", current_time)
	_track_key_press_time("height_down", current_time)
	_track_key_press_time("reset_height", current_time)
	_track_key_press_time("position_left", current_time)
	_track_key_press_time("position_right", current_time)
	_track_key_press_time("position_forward", current_time)
	_track_key_press_time("position_backward", current_time)
	_track_key_press_time("reset_position", current_time)
	
	# Rotation keys - use universal modifier support
	current_keys["rotate_x"] = _check_key_with_modifiers(settings.get("rotate_x_key", "X"))
	current_keys["rotate_y"] = _check_key_with_modifiers(settings.get("rotate_y_key", "Y"))
	current_keys["rotate_z"] = _check_key_with_modifiers(settings.get("rotate_z_key", "Z"))
	current_keys["reset_rotation"] = _check_key_with_modifiers(settings.get("reset_rotation_key", "T"))
	
	# Track rotation key press times for grace period
	_track_key_press_time("rotate_x", current_time)
	_track_key_press_time("rotate_y", current_time)
	_track_key_press_time("rotate_z", current_time)
	
	# Scale keys - use universal modifier support
	var scale_up_key = settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = settings.get("scale_down_key", "PAGE_DOWN") 
	var scale_reset_key = settings.get("scale_reset_key", "HOME")
	current_keys["scale_up"] = _check_key_with_modifiers(scale_up_key)
	current_keys["scale_down"] = _check_key_with_modifiers(scale_down_key)
	current_keys["reset_scale"] = _check_key_with_modifiers(scale_reset_key)
	
	# Track scale key press times for grace period
	_track_key_press_time("scale_up", current_time)
	_track_key_press_time("scale_down", current_time)
	
	# Asset cycling keys - support both direct key and modifier combinations
	var cycle_next_key = settings.get("cycle_next_asset_key", "BRACKETRIGHT")
	var cycle_prev_key = settings.get("cycle_previous_asset_key", "BRACKETLEFT")
	current_keys["cycle_next_asset"] = _check_key_with_modifiers(cycle_next_key)
	current_keys["cycle_previous_asset"] = _check_key_with_modifiers(cycle_prev_key)
	
	# Track cycling key press times for tap vs hold detection
	_track_key_press_time("cycle_next_asset", current_time)
	_track_key_press_time("cycle_previous_asset", current_time)

static func _check_key_with_modifiers(key_string: String) -> bool:
	"""Check if key is pressed, supporting both direct keys and modifier combinations
	Handles cases like 'BRACKETLEFT', 'CTRL+ALT+8', or pure modifiers like 'ALT', 'CTRL'
	
	IMPORTANT: For modifier combinations, ALL specified modifiers must be pressed
	along with the base key. This allows proper detection of keyboard layouts that
	require modifier combinations to produce bracket characters.
	
	Pure modifiers (e.g., just 'ALT' or 'CTRL') are also supported as valid bindings."""
	
	# Normalize the key string
	var normalized_key = key_string.strip_edges().to_upper()
	
	# Check if this is a pure modifier key binding (just ALT, CTRL, SHIFT, or META)
	if normalized_key == "CTRL":
		return Input.is_key_pressed(KEY_CTRL)
	elif normalized_key == "ALT":
		return Input.is_key_pressed(KEY_ALT)
	elif normalized_key == "SHIFT":
		return Input.is_key_pressed(KEY_SHIFT)
	elif normalized_key == "META":
		return Input.is_key_pressed(KEY_META)
	
	# Check if the key string contains modifier combinations (e.g., "CTRL+ALT+8")
	if "+" in key_string:
		var parts = key_string.split("+")
		var required_modifiers = {
			"ctrl": false,
			"alt": false,
			"shift": false,
			"meta": false
		}
		var base_key = ""
		
		# Parse modifiers and base key
		for part in parts:
			part = part.strip_edges().to_upper()
			if part == "CTRL":
				required_modifiers["ctrl"] = true
			elif part == "ALT":
				required_modifiers["alt"] = true
			elif part == "SHIFT":
				required_modifiers["shift"] = true
			elif part == "META":
				required_modifiers["meta"] = true
			else:
				# Last non-modifier part is the base key
				base_key = part
		
		# Check that ALL required modifiers are currently pressed
		if required_modifiers["ctrl"] and not Input.is_key_pressed(KEY_CTRL):
			return false
		if required_modifiers["alt"] and not Input.is_key_pressed(KEY_ALT):
			return false
		if required_modifiers["shift"] and not Input.is_key_pressed(KEY_SHIFT):
			return false
		if required_modifiers["meta"] and not Input.is_key_pressed(KEY_META):
			return false
		
		# Check if base key is pressed (if there is one)
		if not base_key.is_empty():
			var keycode = string_to_keycode(base_key)
			if keycode != KEY_NONE:
				return Input.is_key_pressed(keycode)
			# Fallback: try to parse as a number key directly
			if base_key.is_valid_int():
				var key_num = base_key.to_int()
				if key_num >= 0 and key_num <= 9:
					# Map number to KEY enum (KEY_0 through KEY_9)
					var number_keycode = KEY_0 + key_num
					return Input.is_key_pressed(number_keycode)
			return false
		else:
			# No base key, just modifiers (e.g., "CTRL+ALT")
			# All required modifiers are pressed (checked above), so return true
			return true
	else:
		# Simple key without modifiers
		var keycode = string_to_keycode(key_string)
		if keycode != KEY_NONE:
			# Just check if the key is pressed
			# We DON'T prevent modifiers from being held alongside action keys
			# because the system checks modifiers separately (e.g., for reverse rotation)
			# Modifier conflict prevention is handled by having explicit modifier combinations
			# in the key binding itself (e.g., "CTRL+Y" vs "Y")
			return Input.is_key_pressed(keycode)
		return false

static func _track_key_press_time(key_name: String, current_time: float):
	"""Track when a key was just pressed for tap vs hold detection"""
	var is_pressed = current_keys.get(key_name, false)
	var was_pressed = previous_keys.get(key_name, false)
	
	# If key was just pressed this frame, record the time and mark as pending tap
	if is_pressed and not was_pressed:
		key_press_times[key_name] = current_time
		pending_taps[key_name] = true
	
	# If key is still held beyond grace period, remove from pending taps
	elif is_pressed and was_pressed and pending_taps.has(key_name):
		var time_held = current_time - key_press_times.get(key_name, current_time)
		if time_held > key_tap_grace_period:
			pending_taps.erase(key_name)  # It's a hold, not a tap
	
	# If key was released, clean up tracking
	elif not is_pressed and key_press_times.has(key_name):
		key_press_times.erase(key_name)
		# Clear wheel interruption flag on release (allows re-press to work)
		wheel_interrupted_keys.erase(key_name)
		# Clear active repeat if this was the repeating key
		if active_repeat_key == key_name:
			active_repeat_key = ""
			active_repeat_modifiers.clear()



static func _update_mouse_states():
	"""Update mouse state"""
	# Get viewport-relative mouse position for proper 3D viewport raycasting
	if cached_viewport:
		current_mouse["position"] = cached_viewport.get_mouse_position()
	else:
		# Fallback to global position if viewport not available (shouldn't happen in normal use)
		current_mouse["position"] = DisplayServer.mouse_get_position()
	
	current_mouse["left_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	current_mouse["right_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	current_mouse["middle_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)

static func _update_action_states():
	"""Update Godot action states"""
	current_actions["ui_cancel"] = Input.is_action_just_pressed("ui_cancel")

## Public Input Query API

static func is_key_pressed(key_name: String) -> bool:
	"""Check if a key is currently pressed"""
	return current_keys.get(key_name, false)

static func is_key_just_pressed(key_name: String) -> bool:
	"""Check if a key was just pressed this frame (edge detection)
	For action keys (rotation, scale, height, position), this checks if it was a 'tap' (quick press/release)
	For other keys (tab, cancel, etc.), uses normal edge detection"""
	var current = current_keys.get(key_name, false)
	var previous = previous_keys.get(key_name, false)
	
	# List of keys that should use tap detection (for mouse wheel combos)
	var tap_detection_keys = [
		"height_up", "height_down", 
		"rotate_x", "rotate_y", "rotate_z", 
		"scale_up", "scale_down",
		"position_left", "position_right", "position_forward", "position_backward"
	]
	
	# For tap detection keys, only return true on release if it was a quick tap
	if key_name in tap_detection_keys:
		# Check if key was just released after being in pending_taps
		# This means it was released within the grace period = it's a tap!
		if not current and previous and pending_taps.has(key_name):
			pending_taps.erase(key_name)
			return true  # This was a quick tap, perform the action
		
		# Key is still held or was just pressed - no action yet
		return false
	
	# For all other keys (tab, cancel, etc.), use normal edge detection
	return current and not previous

static func is_key_held_for_wheel(key_name: String) -> bool:
	"""Check if a key is being held long enough to be used with mouse wheel"""
	if not is_key_pressed(key_name):
		return false
	
	if not key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - key_press_times[key_name]
	
	# Key is held beyond grace period OR still within grace period (waiting to see if it's a tap)
	return time_since_press >= 0.0

static func is_key_just_released(key_name: String) -> bool:
	"""Check if a key was just released this frame"""
	var current = current_keys.get(key_name, false)
	var previous = previous_keys.get(key_name, false)
	return not current and previous

static func is_mouse_button_pressed(button: String) -> bool:
	"""Check mouse button state"""
	match button:
		"left": return current_mouse.get("left_pressed", false)
		"right": return current_mouse.get("right_pressed", false)  
		"middle": return current_mouse.get("middle_pressed", false)
		_: return false

static func is_mouse_button_just_pressed(button: String) -> bool:
	"""Check if mouse button was just pressed this frame"""
	var current = false
	var previous = false
	
	match button:
		"left": 
			current = current_mouse.get("left_pressed", false)
			previous = previous_mouse.get("left_pressed", false)
		"right":
			current = current_mouse.get("right_pressed", false) 
			previous = previous_mouse.get("right_pressed", false)
		"middle":
			current = current_mouse.get("middle_pressed", false)
			previous = previous_mouse.get("middle_pressed", false)
		_: return false
			
	return current and not previous

static func get_mouse_position() -> Vector2:
	"""Get current mouse position"""
	return current_mouse.get("position", Vector2.ZERO)

static func is_mouse_in_viewport() -> bool:
	"""Check if mouse is within the 3D viewport bounds"""
	if not cached_viewport:
		return false
	
	var mouse_pos = get_mouse_position()
	var viewport_rect = cached_viewport.get_visible_rect()
	
	# Check if mouse position is within viewport bounds
	return viewport_rect.has_point(mouse_pos)

static func is_action_pressed(action_name: String) -> bool:
	"""Check Godot action state"""
	return current_actions.get(action_name, false)

## Modifier Key Helpers

static func is_reverse_modifier_held() -> bool:
	"""Check if the configured reverse modifier key is held"""
	return is_key_pressed("reverse_modifier")

static func is_large_increment_modifier_held() -> bool:
	"""Check if the configured large increment modifier key is held"""
	return is_key_pressed("large_increment_modifier")

static func is_fine_increment_modifier_held() -> bool:
	"""Check if the configured fine/half-step increment modifier key is held"""
	return is_key_pressed("fine_increment_modifier")

static func get_modifier_state() -> Dictionary:
	"""Get the current state of all configured increment modifiers in one call
	
	Returns the state of user-configured modifier keys, not raw keyboard modifiers.
	Raw keyboard modifiers (SHIFT/CTRL/ALT) are only used internally for key binding
	detection and should not be exposed in the public API.
	
	Returns: {
		"reverse": bool,  # Configured reverse modifier (default: SHIFT)
		"large": bool,    # Configured large increment modifier (default: ALT)
		"fine": bool      # Configured fine increment modifier (default: CTRL)
	}"""
	return {
		"reverse": is_reverse_modifier_held(),
		"large": is_large_increment_modifier_held(),
		"fine": is_fine_increment_modifier_held()
	}

## Input Utility Functions

static func string_to_keycode(key_string: String) -> Key:
	"""Convert string key name to Godot Key enum using built-in function"""
	return OS.find_keycode_from_string(key_string)

## Input State Queries for Managers

static func get_rotation_input() -> Dictionary:
	"""Get all rotation-related input state"""
	# Disable rotation controls when right mouse button is held (viewport navigation)
	var right_mouse_held = is_mouse_button_pressed("right")
	
	return {
		"x_pressed": (is_key_just_pressed("rotate_x") or is_action_key_held_with_repeat("rotate_x", "rotation")) and not right_mouse_held,
		"y_pressed": (is_key_just_pressed("rotate_y") or is_action_key_held_with_repeat("rotate_y", "rotation")) and not right_mouse_held, 
		"z_pressed": (is_key_just_pressed("rotate_z") or is_action_key_held_with_repeat("rotate_z", "rotation")) and not right_mouse_held,
		"reset_pressed": is_key_just_pressed("reset_rotation") and not right_mouse_held,
		"reverse_modifier_held": is_reverse_modifier_held(),
		"large_increment_modifier_held": is_large_increment_modifier_held(),
		"fine_increment_modifier_held": is_fine_increment_modifier_held()
	}

static func get_scale_input() -> Dictionary:
	"""Get all scale-related input state"""
	# Disable scale controls when right mouse button is held (viewport navigation)
	var right_mouse_held = is_mouse_button_pressed("right")
	
	return {
		"up_pressed": (is_key_just_pressed("scale_up") or is_action_key_held_with_repeat("scale_up", "scale")) and not right_mouse_held,
		"down_pressed": (is_key_just_pressed("scale_down") or is_action_key_held_with_repeat("scale_down", "scale")) and not right_mouse_held,
		"reset_pressed": is_key_just_pressed("reset_scale") and not right_mouse_held,
		"reverse_modifier_held": is_reverse_modifier_held(),
		"large_increment_modifier_held": is_large_increment_modifier_held(),
		"fine_increment_modifier_held": is_fine_increment_modifier_held()
	}

static func get_position_input() -> Dictionary:
	"""Get all position-related input state"""
	# Disable position controls when right mouse button is held (viewport navigation)
	var right_mouse_held = is_mouse_button_pressed("right")
	
	return {
		"height_up_pressed": (is_key_just_pressed("height_up") or is_action_key_held_with_repeat("height_up", "height")) and not right_mouse_held,
		"height_down_pressed": (is_key_just_pressed("height_down") or is_action_key_held_with_repeat("height_down", "height")) and not right_mouse_held,
		"reset_height_pressed": is_key_just_pressed("reset_height") and not right_mouse_held,
		"position_left_pressed": (is_key_just_pressed("position_left") or is_action_key_held_with_repeat("position_left", "position")) and not right_mouse_held,
		"position_right_pressed": (is_key_just_pressed("position_right") or is_action_key_held_with_repeat("position_right", "position")) and not right_mouse_held,
		"position_forward_pressed": (is_key_just_pressed("position_forward") or is_action_key_held_with_repeat("position_forward", "position")) and not right_mouse_held,
		"position_backward_pressed": (is_key_just_pressed("position_backward") or is_action_key_held_with_repeat("position_backward", "position")) and not right_mouse_held,
		"reset_position_pressed": is_key_just_pressed("reset_position") and not right_mouse_held,
		"mouse_position": get_mouse_position(),
		"left_clicked": is_mouse_button_just_pressed("left") and is_mouse_in_viewport(),
		"reverse_modifier_held": is_reverse_modifier_held(),
		"large_increment_modifier_held": is_large_increment_modifier_held(),
		"fine_increment_modifier_held": is_fine_increment_modifier_held()
	}

static func get_navigation_input() -> Dictionary:
	"""Get navigation and control input state"""
	return {
		"tab_just_pressed": is_key_just_pressed("tab"),
		"cancel_pressed": is_key_just_pressed("cancel") or is_action_pressed("ui_cancel"),
		"escape_pressed": is_key_just_pressed("escape")
	}

static func get_mouse_wheel_input(event: InputEventMouseButton) -> Dictionary:
	"""Interpret mouse wheel event based on currently held action keys
	Returns semantic action data: what should be adjusted and by how much
	Returns empty dict if no action key is held (event should not be consumed)"""
	
	if not event.pressed:
		return {}
	
	var wheel_up = event.button_index == MOUSE_BUTTON_WHEEL_UP
	var wheel_down = event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	
	if not wheel_up and not wheel_down:
		return {}
	
	# Determine wheel direction (+1 for up, -1 for down)
	var wheel_direction = 1 if wheel_up else -1
	
	# Wheel usage interrupts any active hold-to-repeat
	# Mark currently held action keys as wheel-interrupted (require re-press)
	var action_keys = [
		"rotate_x", "rotate_y", "rotate_z",
		"scale_up", "scale_down",
		"height_up", "height_down",
		"position_forward", "position_backward", "position_left", "position_right"
	]
	for key in action_keys:
		if is_key_held_for_wheel(key):
			wheel_interrupted_keys[key] = true
	
	# Cancel active repeat
	active_repeat_key = ""
	active_repeat_modifiers.clear()
	
	# Check which action keys are currently held for wheel combo
	# When wheel is used, any key that's being held (even if just pressed) can be used
	# Height adjustment keys (Q/E)
	if is_key_held_for_wheel("height_up") or is_key_held_for_wheel("height_down"):
		# Remove from pending taps since wheel was used
		pending_taps.erase("height_up")
		pending_taps.erase("height_down")
		return {
			"action": "height",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# Scale adjustment keys (PAGE_UP/PAGE_DOWN)
	if is_key_held_for_wheel("scale_up") or is_key_held_for_wheel("scale_down"):
		# Remove from pending taps since wheel was used
		pending_taps.erase("scale_up")
		pending_taps.erase("scale_down")
		return {
			"action": "scale",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held()
		}
	
	# Rotation keys (X/Y/Z)
	if is_key_held_for_wheel("rotate_x"):
		pending_taps.erase("rotate_x")
		return {
			"action": "rotation",
			"axis": "X",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("rotate_y"):
		pending_taps.erase("rotate_y")
		return {
			"action": "rotation",
			"axis": "Y",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("rotate_z"):
		pending_taps.erase("rotate_z")
		return {
			"action": "rotation",
			"axis": "Z",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# Position adjustment keys (W/A/S/D)
	if is_key_held_for_wheel("position_forward"):
		pending_taps.erase("position_forward")
		return {
			"action": "position",
			"axis": "forward",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_backward"):
		pending_taps.erase("position_backward")
		return {
			"action": "position",
			"axis": "backward",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_left"):
		pending_taps.erase("position_left")
		return {
			"action": "position",
			"axis": "left",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_right"):
		pending_taps.erase("position_right")
		return {
			"action": "position",
			"axis": "right",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# No action key held - return empty dict (don't consume event, allow viewport zoom)
	return {}

## Asset Cycling Input Detection

static func should_cycle_next_asset() -> bool:
	"""Check if user wants to cycle to next asset (tap or hold)"""
	return is_key_just_pressed("cycle_next_asset") or is_key_held_with_repeat("cycle_next_asset")

static func should_cycle_previous_asset() -> bool:
	"""Check if user wants to cycle to previous asset (tap or hold)"""
	return is_key_just_pressed("cycle_previous_asset") or is_key_held_with_repeat("cycle_previous_asset")

static func is_key_held_with_repeat(key_name: String, repeat_delay: float = 0.15) -> bool:
	"""Check if key is held long enough to trigger repeated actions"""
	if not is_key_pressed(key_name):
		return false
	
	if not key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - key_press_times[key_name]
	
	# Key must be held beyond grace period
	if time_since_press < key_tap_grace_period:
		return false
	
	# Calculate how many repeats should have occurred
	var time_in_repeat_phase = time_since_press - key_tap_grace_period
	var repeat_count = int(time_in_repeat_phase / repeat_delay)
	
	# Check if we should trigger this frame based on repeat timing
	var next_repeat_time = key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next = (key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	
	# Trigger if we're within one frame of the next repeat
	return time_to_next <= 0.016  # ~1 frame at 60fps

static func is_action_key_held_with_repeat(key_name: String, action_type: String) -> bool:
	"""
	Check if an action key should trigger continuous actions while held.
	
	Features:
	- Grace period: 150ms before repeat starts (preserves tap behavior)
	- Only one action repeats at a time (new key cancels previous)
	- Wheel interruption: using wheel requires key re-press
	- Modifier changes: SHIFT/ALT press/release cancels repeat
	
	Args:
		key_name: The key setting name (e.g., "rotate_x")
		action_type: The action category ("rotation", "scale", "height", "position")
	
	Returns:
		bool: True if the key should trigger this frame
	"""
	# Don't repeat if key is wheel-interrupted
	if wheel_interrupted_keys.has(key_name):
		return false
	
	# Check if key is held and get timing
	if not key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - key_press_times[key_name]
	
	# Key must be held beyond grace period
	if time_since_press < key_tap_grace_period:
		return false
	
	# Get current modifier state (using configured modifier keys)
	var current_modifiers = {
		"reverse_modifier": is_reverse_modifier_held(),
		"large_increment_modifier": is_large_increment_modifier_held(),
		"fine_increment_modifier": is_fine_increment_modifier_held()
	}
	
	# If this is a new repeat or different key, initialize tracking
	if active_repeat_key != key_name:
		# Cancel previous repeat (only one at a time)
		active_repeat_key = key_name
		active_repeat_modifiers = current_modifiers.duplicate()
	else:
		# Check if modifier state changed - cancel repeat if so
		if current_modifiers != active_repeat_modifiers:
			active_repeat_key = ""
			active_repeat_modifiers.clear()
			return false
	
	# Get repeat interval for this action type
	var repeat_delay = repeat_intervals.get(action_type, 0.1)
	
	# Calculate how many repeats should have occurred
	var time_in_repeat_phase = time_since_press - key_tap_grace_period
	var repeat_count = int(time_in_repeat_phase / repeat_delay)
	
	# Check if we should trigger this frame based on repeat timing
	var next_repeat_time = key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next = (key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	
	# Trigger if we're within one frame of the next repeat
	return time_to_next <= 0.016  # ~1 frame at 60fps

## Debug and Inspection

static func get_all_pressed_keys() -> Array:
	"""Get list of all currently pressed keys (for debugging)"""
	var pressed = []
	for key_name in current_keys:
		if current_keys[key_name]:
			pressed.append(key_name)
	return pressed

static func debug_print_input_state():
	"""Print current input state (for debugging)"""
	var pressed = get_all_pressed_keys()
	if not pressed.is_empty():
		PluginLogger.debug("InputHandler", "Pressed keys: " + str(pressed))