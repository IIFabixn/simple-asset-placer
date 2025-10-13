@tool
extends RefCounted

class_name InputHandler

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

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

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === INSTANCE VARIABLES ===

# Current frame input state (private instance storage)
var _current_keys: Dictionary = {}
var _current_mouse: Dictionary = {}
var _current_actions: Dictionary = {}
var _settings: Dictionary = {}
var _previous_keys: Dictionary = {}
var _previous_mouse: Dictionary = {}
var _keys_buffer_a: Dictionary = {}
var _keys_buffer_b: Dictionary = {}
var _mouse_buffer_a: Dictionary = {}
var _mouse_buffer_b: Dictionary = {}
var _use_buffer_a: bool = true

# Additional instance variables (tracking state)
var _key_press_times: Dictionary = {}
var _key_tap_grace_period: float = 0.15
var _pending_taps: Dictionary = {}
var _active_repeat_key: String = ""
var _active_repeat_modifiers: Dictionary = {}
var _wheel_interrupted_keys: Dictionary = {}
var _repeat_intervals: Dictionary = {
	"rotation": 0.1,
	"scale": 0.08,
	"height": 0.08,
	"position": 0.05
}
var _cached_viewport: SubViewport = null

## Core Input Polling

func update_input_state(input_settings: Dictionary = {}, viewport: SubViewport = null):
	"""Update all input state for the current frame. Call this once per frame."""
	_settings = input_settings
	
	# Track Tab key for numeric input system
	if _services.numeric_input_manager:
		_update_tab_key_tracking()
	
	# Store viewport for mouse position calculations
	if viewport:
		_cached_viewport = viewport
	
	# Swap buffers instead of duplicate() - avoids per-frame allocation
	# This optimization reduces GC pressure in hot path (called every frame)
	if _use_buffer_a:
		# A is current, B becomes previous
		_previous_keys = _keys_buffer_a
		_previous_mouse = _mouse_buffer_a
		# B becomes current
		_current_keys = _keys_buffer_b
		_current_mouse = _mouse_buffer_b
	else:
		# B is current, A becomes previous
		_previous_keys = _keys_buffer_b
		_previous_mouse = _mouse_buffer_b
		# A becomes current
		_current_keys = _keys_buffer_a
		_current_mouse = _mouse_buffer_a
	
	# Toggle buffer selection for next frame
	_use_buffer_a = not _use_buffer_a
	
	# Clear current state (reusing buffer)
	_current_keys.clear()
	_current_mouse.clear() 
	_current_actions.clear()
	
	# Update key states
	_update_key_states()
	_update_mouse_states()
	_update_action_states()

func _update_tab_key_tracking():
	"""Track Tab key press/release for numeric input system"""
	var tab_key = _settings.get("transform_mode_key", "TAB")
	var is_tab_pressed = _check_key_with_modifiers(tab_key)
	var was_tab_pressed = _previous_keys.get("tab", false)
	
	# Tab just pressed
	if is_tab_pressed and not was_tab_pressed:
		_services.numeric_input_manager.process_tab_pressed()
	# Tab just released
	elif not is_tab_pressed and was_tab_pressed:
		_services.numeric_input_manager.process_tab_released()

func _update_key_states():
	"""Update all key states based on current settings"""
	var current_time = Time.get_ticks_msec() / 1000.0  # Convert to seconds
	
	# Core navigation keys - use universal modifier support
	_current_keys["tab"] = _check_key_with_modifiers(_settings.get("transform_mode_key", "TAB"))
	_current_keys["confirm"] = _check_key_with_modifiers(_settings.get("confirm_action_key", "ENTER"))
	_current_keys["escape"] = Input.is_key_pressed(KEY_ESCAPE)
	_current_keys["shift"] = Input.is_key_pressed(KEY_SHIFT)
	_current_keys["ctrl"] = Input.is_key_pressed(KEY_CTRL)
	_current_keys["alt"] = Input.is_key_pressed(KEY_ALT)
	
	# Configurable modifier keys
	_current_keys["reverse_modifier"] = _check_key_with_modifiers(_settings.get("reverse_modifier_key", "SHIFT"))
	_current_keys["large_increment_modifier"] = _check_key_with_modifiers(_settings.get("large_increment_modifier_key", "ALT"))
	_current_keys["fine_increment_modifier"] = _check_key_with_modifiers(_settings.get("fine_increment_modifier_key", "CTRL"))
	
	# Settings-based keys - use universal modifier support
	_current_keys["cancel"] = _check_key_with_modifiers(_settings.get("cancel_key", "ESCAPE"))
	var height_up_key = _settings.get("height_up_key", "Q")
	var height_down_key = _settings.get("height_down_key", "E")
	var reset_height_key = _settings.get("reset_height_key", "R")
	_current_keys["height_up"] = _check_key_with_modifiers(height_up_key)
	_current_keys["height_down"] = _check_key_with_modifiers(height_down_key)
	_current_keys["reset_height"] = _check_key_with_modifiers(reset_height_key)
	
	# Position adjustment keys - use universal modifier support
	var position_left_key = _settings.get("position_left_key", "A")
	var position_right_key = _settings.get("position_right_key", "D")
	var position_forward_key = _settings.get("position_forward_key", "W")
	var position_backward_key = _settings.get("position_backward_key", "S")
	var reset_position_key = _settings.get("reset_position_key", "G")
	_current_keys["position_left"] = _check_key_with_modifiers(position_left_key)
	_current_keys["position_right"] = _check_key_with_modifiers(position_right_key)
	_current_keys["position_forward"] = _check_key_with_modifiers(position_forward_key)
	_current_keys["position_backward"] = _check_key_with_modifiers(position_backward_key)
	_current_keys["reset_position"] = _check_key_with_modifiers(reset_position_key)
	
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
	_current_keys["rotate_x"] = _check_key_with_modifiers(_settings.get("rotate_x_key", "X"))
	_current_keys["rotate_y"] = _check_key_with_modifiers(_settings.get("rotate_y_key", "Y"))
	_current_keys["rotate_z"] = _check_key_with_modifiers(_settings.get("rotate_z_key", "Z"))
	_current_keys["reset_rotation"] = _check_key_with_modifiers(_settings.get("reset_rotation_key", "T"))
	
	# Track rotation key press times for grace period
	_track_key_press_time("rotate_x", current_time)
	_track_key_press_time("rotate_y", current_time)
	_track_key_press_time("rotate_z", current_time)
	
	# Scale keys - use universal modifier support
	var scale_up_key = _settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = _settings.get("scale_down_key", "PAGE_DOWN") 
	var scale_reset_key = _settings.get("scale_reset_key", "HOME")
	_current_keys["scale_up"] = _check_key_with_modifiers(scale_up_key)
	_current_keys["scale_down"] = _check_key_with_modifiers(scale_down_key)
	_current_keys["reset_scale"] = _check_key_with_modifiers(scale_reset_key)
	
	# Track scale key press times for grace period
	_track_key_press_time("scale_up", current_time)
	_track_key_press_time("scale_down", current_time)
	
	# Asset cycling keys - support both direct key and modifier combinations
	var cycle_next_key = _settings.get("cycle_next_asset_key", "BRACKETRIGHT")
	var cycle_prev_key = _settings.get("cycle_previous_asset_key", "BRACKETLEFT")
	_current_keys["cycle_next_asset"] = _check_key_with_modifiers(cycle_next_key)
	_current_keys["cycle_previous_asset"] = _check_key_with_modifiers(cycle_prev_key)
	
	# Placement mode cycling key
	var cycle_mode_key = _settings.get("cycle_placement_mode_key", "P")
	_current_keys["cycle_placement_mode"] = _check_key_with_modifiers(cycle_mode_key)
	
	# Track cycling key press times for tap vs hold detection
	_track_key_press_time("cycle_next_asset", current_time)
	_track_key_press_time("cycle_previous_asset", current_time)
	_track_key_press_time("cycle_placement_mode", current_time)
	
	# Numeric input special keys - CHECK THESE FIRST before digits to avoid conflicts
	_current_keys["decimal_point"] = Input.is_key_pressed(KEY_PERIOD)
	_current_keys["minus"] = Input.is_key_pressed(KEY_MINUS)
	_current_keys["plus"] = Input.is_key_pressed(KEY_PLUS) or (Input.is_key_pressed(KEY_EQUAL) and Input.is_key_pressed(KEY_SHIFT))
	# Equals key: US layout = KEY_EQUAL without SHIFT, German/EU layout = KEY_0 with SHIFT
	_current_keys["equals"] = (Input.is_key_pressed(KEY_EQUAL) and not Input.is_key_pressed(KEY_SHIFT)) or \
	                          (Input.is_key_pressed(KEY_0) and Input.is_key_pressed(KEY_SHIFT))
	_current_keys["backspace"] = Input.is_key_pressed(KEY_BACKSPACE)
	_current_keys["enter"] = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	
	# Numeric input keys (0-9) - poll directly without modifier checks
	# NOTE: Check digits AFTER special keys since = shares physical key with 0 on some keyboards
	for i in range(10):
		var digit_key = "digit_%d" % i
		var keycode = KEY_0 + i
		var is_digit = Input.is_key_pressed(keycode)
		
		# Don't detect digit if special key is already detected (e.g., Shift+0 = equals on German keyboards)
		if i == 0 and _current_keys["equals"]:
			is_digit = false  # Equals takes priority over 0
		# On German/EU keyboards, Shift+0 produces =, so only detect 0 without SHIFT
		elif i == 0 and Input.is_key_pressed(KEY_SHIFT):
			is_digit = false  # Shift+0 is reserved for equals on German keyboards
		
		_current_keys[digit_key] = is_digit

func _check_key_with_modifiers(key_string: String) -> bool:
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

func _track_key_press_time(key_name: String, current_time: float):
	"""Track when a key was just pressed for tap vs hold detection"""
	var is_pressed = _current_keys.get(key_name, false)
	var was_pressed = _previous_keys.get(key_name, false)
	
	# If key was just pressed this frame, record the time and mark as pending tap
	if is_pressed and not was_pressed:
		_key_press_times[key_name] = current_time
		_pending_taps[key_name] = true
	
	# If key is still held beyond grace period, remove from pending taps
	elif is_pressed and was_pressed and _pending_taps.has(key_name):
		var time_held = current_time - _key_press_times.get(key_name, current_time)
		if time_held > _key_tap_grace_period:
			_pending_taps.erase(key_name)  # It's a hold, not a tap
	
	# If key was released, clean up tracking
	elif not is_pressed and _key_press_times.has(key_name):
		_key_press_times.erase(key_name)
		# Clear wheel interruption flag on release (allows re-press to work)
		_wheel_interrupted_keys.erase(key_name)
		# Clear active repeat if this was the repeating key
		if _active_repeat_key == key_name:
			_active_repeat_key = ""
			_active_repeat_modifiers.clear()

func _update_mouse_states():
	"""Update mouse state"""
	# Get viewport-relative mouse position for proper 3D viewport raycasting
	if _cached_viewport:
		_current_mouse["position"] = _cached_viewport.get_mouse_position()
	else:
		# Fallback to global position if viewport not available (shouldn't happen in normal use)
		_current_mouse["position"] = DisplayServer.mouse_get_position()
	
	_current_mouse["left_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_current_mouse["right_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_current_mouse["middle_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)

func _update_action_states():
	"""Update Godot action states"""
	_current_actions["ui_cancel"] = Input.is_action_just_pressed("ui_cancel")

## Public Input Query API

func is_key_pressed(key_name: String) -> bool:
	"""Check if a key is currently pressed"""
	return _current_keys.get(key_name, false)

func is_key_just_pressed(key_name: String) -> bool:
	"""Check if a key was just pressed this frame (edge detection)
	For action keys (rotation, scale, height, position), this checks if it was a 'tap' (quick press/release)
	For other keys (tab, cancel, etc.), uses normal edge detection"""
	var current = _current_keys.get(key_name, false)
	var previous = _previous_keys.get(key_name, false)
	
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
		if not current and previous and _pending_taps.has(key_name):
			_pending_taps.erase(key_name)
			return true  # This was a quick tap, perform the action
		
		# Key is still held or was just pressed - no action yet
		return false
	
	# For all other keys (tab, cancel, etc.), use normal edge detection
	return current and not previous

func _is_key_edge_pressed(key_name: String) -> bool:
	"""Simple edge detection - true when key transitions from not pressed to pressed.
	This is used for numeric input context setting, where we want to detect the initial
	key press regardless of how long the user holds it."""
	var current = _current_keys.get(key_name, false)
	var previous = _previous_keys.get(key_name, false)
	return current and not previous

func was_action_key_tapped(key_name: String) -> bool:
	"""Check if an action key was tapped (not held).
	This is specifically for numeric input activation - we only want to activate
	numeric input on quick taps, not when holding for repeated actions."""
	var current = _current_keys.get(key_name, false)
	var previous = _previous_keys.get(key_name, false)
	
	# Key was just released and it was in pending_taps = it was a quick tap
	if not current and previous and _pending_taps.has(key_name):
		return true
	
	return false

func is_key_held_for_wheel(key_name: String) -> bool:
	"""Check if a key is being held long enough to be used with mouse wheel"""
	if not is_key_pressed(key_name):
		return false
	
	if not _key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - _key_press_times[key_name]
	
	# Key is held beyond grace period OR still within grace period (waiting to see if it's a tap)
	return time_since_press >= 0.0

func is_key_just_released(key_name: String) -> bool:
	"""Check if a key was just released this frame"""
	var current = _current_keys.get(key_name, false)
	var previous = _previous_keys.get(key_name, false)
	return not current and previous

func is_mouse_button_pressed(button: String) -> bool:
	"""Check mouse button state"""
	match button:
		"left": return _current_mouse.get("left_pressed", false)
		"right": return _current_mouse.get("right_pressed", false)  
		"middle": return _current_mouse.get("middle_pressed", false)
		_: return false

func is_mouse_button_just_pressed(button: String) -> bool:
	"""Check if mouse button was just pressed this frame"""
	var current = false
	var previous = false
	
	match button:
		"left": 
			current = _current_mouse.get("left_pressed", false)
			previous = _previous_mouse.get("left_pressed", false)
		"right":
			current = _current_mouse.get("right_pressed", false) 
			previous = _previous_mouse.get("right_pressed", false)
		"middle":
			current = _current_mouse.get("middle_pressed", false)
			previous = _previous_mouse.get("middle_pressed", false)
		_: return false
	
	# Edge detection: current is pressed AND previous was NOT pressed
	return current and not previous

func get_mouse_position() -> Vector2:
	"""Get current mouse position"""
	return _current_mouse.get("position", Vector2.ZERO)

func is_mouse_in_viewport() -> bool:
	"""Check if mouse is within the 3D viewport bounds"""
	if not _cached_viewport:
		return false
	
	var mouse_pos = get_mouse_position()
	var viewport_rect = _cached_viewport.get_visible_rect()
	
	# Check if mouse position is within viewport bounds
	return viewport_rect.has_point(mouse_pos)

func is_action_pressed(action_name: String) -> bool:
	"""Check Godot action state"""
	return _current_actions.get(action_name, false)

## Modifier Key Helpers

func is_reverse_modifier_held() -> bool:
	"""Check if the configured reverse modifier key is held"""
	return is_key_pressed("reverse_modifier")

func is_large_increment_modifier_held() -> bool:
	"""Check if the configured large increment modifier key is held"""
	return is_key_pressed("large_increment_modifier")

func is_fine_increment_modifier_held() -> bool:
	"""Check if the configured fine/half-step increment modifier key is held"""
	return is_key_pressed("fine_increment_modifier")

func get_modifier_state() -> Dictionary:
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

func string_to_keycode(key_string: String) -> Key:
	"""Convert string key name to Godot Key enum using built-in function"""
	return OS.find_keycode_from_string(key_string)

## Input State Queries for Managers

func get_rotation_input() -> Dictionary:
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
		"fine_increment_modifier_held": is_fine_increment_modifier_held(),
		# Tap detection for numeric input - use edge trigger (key just pressed, not released)
		"x_tapped": _is_key_edge_pressed("rotate_x") and not right_mouse_held,
		"y_tapped": _is_key_edge_pressed("rotate_y") and not right_mouse_held,
		"z_tapped": _is_key_edge_pressed("rotate_z") and not right_mouse_held
	}

func get_scale_input() -> Dictionary:
	"""Get all scale-related input state"""
	# Disable scale controls when right mouse button is held (viewport navigation)
	var right_mouse_held = is_mouse_button_pressed("right")
	
	return {
		"up_pressed": (is_key_just_pressed("scale_up") or is_action_key_held_with_repeat("scale_up", "scale")) and not right_mouse_held,
		"down_pressed": (is_key_just_pressed("scale_down") or is_action_key_held_with_repeat("scale_down", "scale")) and not right_mouse_held,
		"reset_pressed": is_key_just_pressed("reset_scale") and not right_mouse_held,
		"reverse_modifier_held": is_reverse_modifier_held(),
		"large_increment_modifier_held": is_large_increment_modifier_held(),
		"fine_increment_modifier_held": is_fine_increment_modifier_held(),
		# Tap detection for numeric input - use edge trigger (key just pressed, not released)
		"up_tapped": _is_key_edge_pressed("scale_up") and not right_mouse_held,
		"down_tapped": _is_key_edge_pressed("scale_down") and not right_mouse_held
	}

func get_position_input() -> Dictionary:
	"""Get all position-related input state"""
	# Disable position controls when right mouse button is held (viewport navigation)
	var right_mouse_held = is_mouse_button_pressed("right")
	
	# Get tap detection result ONCE per key (calling is_key_just_pressed twice erases _pending_taps on first call!)
	var height_up_just_pressed = is_key_just_pressed("height_up")
	var height_down_just_pressed = is_key_just_pressed("height_down")
	var pos_forward_just_pressed = is_key_just_pressed("position_forward")
	var pos_backward_just_pressed = is_key_just_pressed("position_backward")
	var pos_left_just_pressed = is_key_just_pressed("position_left")
	var pos_right_just_pressed = is_key_just_pressed("position_right")
	
	# Apply right mouse held check for tapped flags (for numeric input context)
	var height_up_tapped = height_up_just_pressed and not right_mouse_held
	var height_down_tapped = height_down_just_pressed and not right_mouse_held
	var pos_forward_tapped = pos_forward_just_pressed and not right_mouse_held
	var pos_backward_tapped = pos_backward_just_pressed and not right_mouse_held
	var pos_left_tapped = pos_left_just_pressed and not right_mouse_held
	var pos_right_tapped = pos_right_just_pressed and not right_mouse_held
	
	return {
		"height_up_pressed": (height_up_just_pressed or is_action_key_held_with_repeat("height_up", "height")) and not right_mouse_held,
		"height_down_pressed": (height_down_just_pressed or is_action_key_held_with_repeat("height_down", "height")) and not right_mouse_held,
		"reset_height_pressed": is_key_just_pressed("reset_height") and not right_mouse_held,
		"position_left_pressed": (pos_left_just_pressed or is_action_key_held_with_repeat("position_left", "position")) and not right_mouse_held,
		"position_right_pressed": (pos_right_just_pressed or is_action_key_held_with_repeat("position_right", "position")) and not right_mouse_held,
		"position_forward_pressed": (pos_forward_just_pressed or is_action_key_held_with_repeat("position_forward", "position")) and not right_mouse_held,
		"position_backward_pressed": (pos_backward_just_pressed or is_action_key_held_with_repeat("position_backward", "position")) and not right_mouse_held,
		"reset_position_pressed": is_key_just_pressed("reset_position") and not right_mouse_held,
		"mouse_position": get_mouse_position(),
		"confirm_action": (is_mouse_button_just_pressed("left") and is_mouse_in_viewport()) or is_key_just_pressed("confirm"),
		"reverse_modifier_held": is_reverse_modifier_held(),
		"large_increment_modifier_held": is_large_increment_modifier_held(),
		"fine_increment_modifier_held": is_fine_increment_modifier_held(),
		# Tap detection for numeric input
		"height_up_tapped": height_up_tapped,
		"height_down_tapped": height_down_tapped,
		"position_forward_tapped": pos_forward_tapped,
		"position_backward_tapped": pos_backward_tapped,
		"position_left_tapped": pos_left_tapped,
		"position_right_tapped": pos_right_tapped
	}

func get_navigation_input() -> Dictionary:
	"""Get navigation and control input state"""
	return {
		"tab_just_pressed": is_key_just_pressed("tab"),
		"cancel_pressed": is_key_just_pressed("cancel") or is_action_pressed("ui_cancel"),
		"escape_pressed": is_key_just_pressed("escape")
	}

func get_numeric_input() -> Dictionary:
	"""Get numeric input state for Blender-style direct value entry
	Returns which digit/special keys were just pressed (not held)"""
	var result = {
		"digit_pressed": -1,  # -1 = no digit, 0-9 = which digit
		"decimal_pressed": is_key_just_pressed("decimal_point"),
		"minus_pressed": is_key_just_pressed("minus"),
		"plus_pressed": is_key_just_pressed("plus"),
		"equals_pressed": is_key_just_pressed("equals"),
		"backspace_pressed": is_key_just_pressed("backspace"),
		"enter_pressed": is_key_just_pressed("enter"),
		"escape_pressed": is_key_just_pressed("escape")
	}
	
	# Check which digit was just pressed (only one at a time)
	for i in range(10):
		if is_key_just_pressed("digit_%d" % i):
			result["digit_pressed"] = i
			break
	
	return result

func get_mouse_wheel_input(event: InputEventMouseButton) -> Dictionary:
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
			_wheel_interrupted_keys[key] = true
	
	# Cancel active repeat
	_active_repeat_key = ""
	_active_repeat_modifiers.clear()
	
	# Check which action keys are currently held for wheel combo
	# When wheel is used, any key that's being held (even if just pressed) can be used
	# Height adjustment keys (Q/E)
	if is_key_held_for_wheel("height_up") or is_key_held_for_wheel("height_down"):
		# Remove from pending taps since wheel was used
		_pending_taps.erase("height_up")
		_pending_taps.erase("height_down")
		return {
			"action": "height",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# Scale adjustment keys (PAGE_UP/PAGE_DOWN)
	if is_key_held_for_wheel("scale_up") or is_key_held_for_wheel("scale_down"):
		# Remove from pending taps since wheel was used
		_pending_taps.erase("scale_up")
		_pending_taps.erase("scale_down")
		return {
			"action": "scale",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held()
		}
	
	# Rotation keys (X/Y/Z)
	if is_key_held_for_wheel("rotate_x"):
		_pending_taps.erase("rotate_x")
		return {
			"action": "rotation",
			"axis": "X",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("rotate_y"):
		_pending_taps.erase("rotate_y")
		return {
			"action": "rotation",
			"axis": "Y",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("rotate_z"):
		_pending_taps.erase("rotate_z")
		return {
			"action": "rotation",
			"axis": "Z",
			"direction": wheel_direction,
			"large_increment": is_large_increment_modifier_held(),
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# Position adjustment keys (W/A/S/D)
	if is_key_held_for_wheel("position_forward"):
		_pending_taps.erase("position_forward")
		return {
			"action": "position",
			"axis": "forward",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_backward"):
		_pending_taps.erase("position_backward")
		return {
			"action": "position",
			"axis": "backward",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_left"):
		_pending_taps.erase("position_left")
		return {
			"action": "position",
			"axis": "left",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	elif is_key_held_for_wheel("position_right"):
		_pending_taps.erase("position_right")
		return {
			"action": "position",
			"axis": "right",
			"direction": wheel_direction,
			"reverse_modifier": is_reverse_modifier_held()
		}
	
	# No action key held - return empty dict (don't consume event, allow viewport zoom)
	return {}

## Asset Cycling Input Detection

func should_cycle_next_asset() -> bool:
	"""Check if user wants to cycle to next asset (tap or hold)"""
	return is_key_just_pressed("cycle_next_asset") or is_key_held_with_repeat("cycle_next_asset")

func should_cycle_previous_asset() -> bool:
	"""Check if user wants to cycle to previous asset (tap or hold)"""
	return is_key_just_pressed("cycle_previous_asset") or is_key_held_with_repeat("cycle_previous_asset")

func should_cycle_placement_mode() -> bool:
	"""Check if user wants to cycle placement mode (collision/plane)"""
	return is_key_just_pressed("cycle_placement_mode")

func is_key_held_with_repeat(key_name: String, repeat_delay: float = 0.15) -> bool:
	"""Check if key is held long enough to trigger repeated actions"""
	if not is_key_pressed(key_name):
		return false
	
	if not _key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - _key_press_times[key_name]
	
	# Key must be held beyond grace period
	if time_since_press < _key_tap_grace_period:
		return false
	
	# Calculate how many repeats should have occurred
	var time_in_repeat_phase = time_since_press - _key_tap_grace_period
	var repeat_count = int(time_in_repeat_phase / repeat_delay)
	
	# Check if we should trigger this frame based on repeat timing
	var next_repeat_time = _key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next = (_key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	
	# Trigger if we're within one frame of the next repeat
	return time_to_next <= 0.016  # ~1 frame at 60fps

func is_action_key_held_with_repeat(key_name: String, action_type: String) -> bool:
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
	if _wheel_interrupted_keys.has(key_name):
		return false
	
	# Check if key is held and get timing
	if not _key_press_times.has(key_name):
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_press = current_time - _key_press_times[key_name]
	
	# Key must be held beyond grace period
	if time_since_press < _key_tap_grace_period:
		return false
	
	# Get current modifier state (using configured modifier keys)
	var current_modifiers = {
		"reverse_modifier": is_reverse_modifier_held(),
		"large_increment_modifier": is_large_increment_modifier_held(),
		"fine_increment_modifier": is_fine_increment_modifier_held()
	}
	
	# If this is a new repeat or different key, initialize tracking
	if _active_repeat_key != key_name:
		# Cancel previous repeat (only one at a time)
		_active_repeat_key = key_name
		# Avoid duplicate() - just assign values directly (small dict, 3 keys)
		_active_repeat_modifiers.clear()
		_active_repeat_modifiers["reverse_modifier"] = current_modifiers["reverse_modifier"]
		_active_repeat_modifiers["large_increment_modifier"] = current_modifiers["large_increment_modifier"]
		_active_repeat_modifiers["fine_increment_modifier"] = current_modifiers["fine_increment_modifier"]
	else:
		# Check if modifier state changed - cancel repeat if so
		if current_modifiers != _active_repeat_modifiers:
			_active_repeat_key = ""
			_active_repeat_modifiers.clear()
			return false
	
	# Get repeat interval for this action type
	var repeat_delay = _repeat_intervals.get(action_type, 0.1)
	
	# Calculate how many repeats should have occurred
	var time_in_repeat_phase = time_since_press - _key_tap_grace_period
	var repeat_count = int(time_in_repeat_phase / repeat_delay)
	
	# Check if we should trigger this frame based on repeat timing
	var next_repeat_time = _key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next = (_key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	
	# Trigger if we're within one frame of the next repeat
	return time_to_next <= 0.016  # ~1 frame at 60fps

## Debug and Inspection

func get_all_pressed_keys() -> Array:
	"""Get list of all currently pressed keys (for debugging)"""
	var pressed = []
	for key_name in _current_keys:
		if _current_keys[key_name]:
			pressed.append(key_name)
	return pressed

func debug_print_input_state():
	"""Print current input state (for debugging)"""
	var pressed = get_all_pressed_keys()
	if not pressed.is_empty():
		PluginLogger.debug("InputHandler", "Pressed keys: " + str(pressed))
