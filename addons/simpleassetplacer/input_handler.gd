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

## Core Input Polling

static func update_input_state(input_settings: Dictionary = {}):
	"""Update all input state for the current frame. Call this once per frame."""
	settings = input_settings
	

	
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
	current_keys["height_up"] = Input.is_key_pressed(string_to_keycode(height_up_key))
	current_keys["height_down"] = Input.is_key_pressed(string_to_keycode(height_down_key))
	

	
	# Rotation keys
	current_keys["rotate_x"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_x_key", "X")))
	current_keys["rotate_y"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_y_key", "Y")))
	current_keys["rotate_z"] = Input.is_key_pressed(string_to_keycode(settings.get("rotate_z_key", "Z")))
	current_keys["reset_rotation"] = Input.is_key_pressed(string_to_keycode(settings.get("reset_rotation_key", "T")))
	
	# Scale keys
	var scale_up_key = settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = settings.get("scale_down_key", "PAGE_DOWN") 
	var scale_reset_key = settings.get("scale_reset_key", "HOME")
	current_keys["scale_up"] = Input.is_key_pressed(string_to_keycode(scale_up_key))
	current_keys["scale_down"] = Input.is_key_pressed(string_to_keycode(scale_down_key))
	current_keys["reset_scale"] = Input.is_key_pressed(string_to_keycode(scale_reset_key))
	


static func _update_mouse_states():
	"""Update mouse state"""
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
	"""Check if a key was just pressed this frame (edge detection)"""
	var current = current_keys.get(key_name, false)
	var previous = previous_keys.get(key_name, false)
	return current and not previous

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
	
	# Check which action keys are currently held
	# Height adjustment keys (Q/E)
	if is_key_pressed("height_up") or is_key_pressed("height_down"):
		return {
			"action": "height",
			"direction": wheel_direction,
			"reverse_modifier": event.shift_pressed  # SHIFT reverses direction
		}
	
	# Scale adjustment keys (PAGE_UP/PAGE_DOWN)
	if is_key_pressed("scale_up") or is_key_pressed("scale_down"):
		return {
			"action": "scale",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed  # ALT for large steps
		}
	
	# Rotation keys (X/Y/Z)
	if is_key_pressed("rotate_x"):
		return {
			"action": "rotation",
			"axis": "X",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed,
			"reverse_modifier": event.shift_pressed
		}
	elif is_key_pressed("rotate_y"):
		return {
			"action": "rotation",
			"axis": "Y",
			"direction": wheel_direction,
			"large_increment": event.alt_pressed,
			"reverse_modifier": event.shift_pressed
		}
	elif is_key_pressed("rotate_z"):
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