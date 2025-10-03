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
	
	# Core navigation keys
	current_keys["tab"] = Input.is_key_pressed(string_to_keycode(settings.get("transform_mode_key", "TAB")))
	current_keys["escape"] = Input.is_key_pressed(KEY_ESCAPE)
	current_keys["shift"] = Input.is_key_pressed(KEY_SHIFT)
	current_keys["ctrl"] = Input.is_key_pressed(KEY_CTRL)
	current_keys["alt"] = Input.is_key_pressed(KEY_ALT)
	
	# Settings-based keys
	current_keys["cancel"] = Input.is_key_pressed(string_to_keycode(settings.get("cancel_key", "ESCAPE")))
	var height_up_key = settings.get("height_up_key", "Q")
	var height_down_key = settings.get("height_down_key", "E")
	var reset_height_key = settings.get("reset_height_key", "R")
	current_keys["height_up"] = Input.is_key_pressed(string_to_keycode(height_up_key))
	current_keys["height_down"] = Input.is_key_pressed(string_to_keycode(height_down_key))
	current_keys["reset_height"] = Input.is_key_pressed(string_to_keycode(reset_height_key))
	
	# Track key press times for grace period
	_track_key_press_time("height_up", current_time)
	_track_key_press_time("height_down", current_time)
	
	# Rotation keys
	current_keys["rotate_x"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_x_key", "X")))
	current_keys["rotate_y"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_y_key", "Y")))
	current_keys["rotate_z"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_z_key", "Z")))
	current_keys["reset_rotation"] = Input.is_key_pressed(string_to_keycode(settings.get("reset_rotation_key", "T")))
	
	# Track rotation key press times for grace period
	_track_key_press_time("rotate_x", current_time)
	_track_key_press_time("rotate_y", current_time)
	_track_key_press_time("rotate_z", current_time)
	
	# Scale keys
	var scale_up_key = settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = settings.get("scale_down_key", "PAGE_DOWN") 
	var scale_reset_key = settings.get("scale_reset_key", "HOME")
	current_keys["scale_up"] = Input.is_key_pressed(string_to_keycode(scale_up_key))
	current_keys["scale_down"] = Input.is_key_pressed(string_to_keycode(scale_down_key))
	current_keys["reset_scale"] = Input.is_key_pressed(string_to_keycode(scale_reset_key))
	
	# Track scale key press times for grace period
	_track_key_press_time("scale_up", current_time)
	_track_key_press_time("scale_down", current_time)

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
	For action keys (rotation, scale, height), this checks if it was a 'tap' (quick press/release)
	For other keys (tab, cancel, etc.), uses normal edge detection"""
	var current = current_keys.get(key_name, false)
	var previous = previous_keys.get(key_name, false)
	
	# List of keys that should use tap detection (for mouse wheel combos)
	var tap_detection_keys = ["height_up", "height_down", "rotate_x", "rotate_y", "rotate_z", "scale_up", "scale_down"]
	
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

static func is_action_pressed(action_name: String) -> bool:
	"""Check Godot action state"""
	return current_actions.get(action_name, false)

## Modifier Key Helpers

static func is_shift_held() -> bool:
	return is_key_pressed("shift")

static func is_ctrl_held() -> bool:
	return is_key_pressed("ctrl")

static func is_alt_held() -> bool:
	return is_key_pressed("alt")

## Input Utility Functions

static func string_to_keycode(key_string: String) -> Key:
	"""Convert string key name to Godot Key enum using built-in function"""
	return OS.find_keycode_from_string(key_string)

## Input State Queries for Managers

static func get_rotation_input() -> Dictionary:
	"""Get all rotation-related input state"""
	return {
		"x_pressed": is_key_just_pressed("rotate_x"),
		"y_pressed": is_key_just_pressed("rotate_y"), 
		"z_pressed": is_key_just_pressed("rotate_z"),
		"reset_pressed": is_key_just_pressed("reset_rotation"),
		"shift_held": is_shift_held(),
		"ctrl_held": is_ctrl_held(),
		"alt_held": is_alt_held()
	}

static func get_scale_input() -> Dictionary:
	"""Get all scale-related input state"""
	return {
		"up_pressed": is_key_just_pressed("scale_up"),
		"down_pressed": is_key_just_pressed("scale_down"),
		"reset_pressed": is_key_just_pressed("reset_scale"),
		"alt_held": is_alt_held()
	}

static func get_position_input() -> Dictionary:
	"""Get all position-related input state"""
	return {
		"height_up_pressed": is_key_just_pressed("height_up"),
		"height_down_pressed": is_key_just_pressed("height_down"),
		"reset_height_pressed": is_key_just_pressed("reset_height"),
		"mouse_position": get_mouse_position(),
		"left_clicked": is_mouse_button_just_pressed("left"),
		"shift_held": is_shift_held()
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
			"reverse_modifier": event.shift_pressed  # SHIFT reverses direction
		}
	
	# Scale adjustment keys (PAGE_UP/PAGE_DOWN)
	if is_key_held_for_wheel("scale_up") or is_key_held_for_wheel("scale_down"):
		# Remove from pending taps since wheel was used
		pending_taps.erase("scale_up")
		pending_taps.erase("scale_down")
		return {
			"action": "scale",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed  # ALT for large steps
		}
	
	# Rotation keys (X/Y/Z)
	if is_key_held_for_wheel("rotate_x"):
		pending_taps.erase("rotate_x")
		return {
			"action": "rotation",
			"axis": "X",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed,
			"reverse_modifier": event.shift_pressed
		}
	elif is_key_held_for_wheel("rotate_y"):
		pending_taps.erase("rotate_y")
		return {
			"action": "rotation",
			"axis": "Y",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed,
			"reverse_modifier": event.shift_pressed
		}
	elif is_key_held_for_wheel("rotate_z"):
		pending_taps.erase("rotate_z")
		return {
			"action": "rotation",
			"axis": "Z",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed,
			"reverse_modifier": event.shift_pressed
		}
	
	# No action key held - return empty dict (don't consume event, allow viewport zoom)
	return {}

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
		print("InputHandler: Pressed keys: ", pressed)