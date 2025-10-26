@tool
extends RefCounted

class_name RawInputSnapshot

const TAP_DETECTION_KEYS := [
	"height_up", "height_down",
	"rotate_x", "rotate_y", "rotate_z",
	"scale_up", "scale_down",
	"position_left", "position_right", "position_forward", "position_backward"
]

var settings: Dictionary = {}

var _cached_viewport: SubViewport = null

var _current_keys: Dictionary = {}
var _previous_keys: Dictionary = {}
var _current_mouse: Dictionary = {}
var _previous_mouse: Dictionary = {}
var _current_actions: Dictionary = {}

var _key_press_times: Dictionary = {}
var _pending_taps: Dictionary = {}
var _wheel_interrupted_keys: Dictionary = {}
var _active_repeat_key: String = ""
var _active_repeat_modifiers: Dictionary = {}

var _use_buffer_a := true
var _keys_buffer_a: Dictionary = {}
var _keys_buffer_b: Dictionary = {}
var _mouse_buffer_a: Dictionary = {}
var _mouse_buffer_b: Dictionary = {}

var _key_tap_grace_period: float = 0.15
var _repeat_intervals := {
	"rotation": 0.1,
	"scale": 0.08,
	"height": 0.08,
	"position": 0.05
}

func update(new_settings: Dictionary, viewport: SubViewport) -> void:
	settings = new_settings if new_settings else {}
	if viewport:
		_cached_viewport = viewport
	_swap_buffers()
	_current_keys.clear()
	_current_mouse.clear()
	_current_actions.clear()
	_update_key_states()
	_update_mouse_states()
	_update_action_states()

func is_key_pressed(key_name: String) -> bool:
	return _current_keys.get(key_name, false)

func was_key_pressed(key_name: String) -> bool:
	return _previous_keys.get(key_name, false)

func is_key_just_pressed(key_name: String) -> bool:
	var current := _current_keys.get(key_name, false)
	var previous := _previous_keys.get(key_name, false)
	if key_name in TAP_DETECTION_KEYS:
		if not current and previous and _pending_taps.has(key_name):
			_pending_taps.erase(key_name)
			return true
		return false
	return current and not previous

func key_edge_pressed(key_name: String) -> bool:
	var current := _current_keys.get(key_name, false)
	var previous := _previous_keys.get(key_name, false)
	return current and not previous

func is_key_just_released(key_name: String) -> bool:
	var current := _current_keys.get(key_name, false)
	var previous := _previous_keys.get(key_name, false)
	return not current and previous

func is_key_held_with_repeat(key_name: String, repeat_delay: float = 0.15) -> bool:
	if not is_key_pressed(key_name):
		return false
	if not _key_press_times.has(key_name):
		return false
	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_press: float = current_time - _key_press_times[key_name]
	if time_since_press < _key_tap_grace_period:
		return false
	var time_in_repeat_phase: float = time_since_press - _key_tap_grace_period
	var repeat_count := int(time_in_repeat_phase / repeat_delay)
	var next_repeat_time: float = _key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next: float = (_key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	return time_to_next <= 0.016

func is_action_key_held_with_repeat(key_name: String, action_type: String) -> bool:
	if _wheel_interrupted_keys.has(key_name):
		return false
	if not _key_press_times.has(key_name):
		return false
	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_press: float = current_time - _key_press_times[key_name]
	if time_since_press < _key_tap_grace_period:
		return false
	var current_modifiers := {
		"reverse_modifier": is_reverse_modifier_held(),
		"large_increment_modifier": is_large_increment_modifier_held(),
		"fine_increment_modifier": is_fine_increment_modifier_held()
	}
	if _active_repeat_key != key_name:
		_active_repeat_key = key_name
		_active_repeat_modifiers.clear()
		_active_repeat_modifiers["reverse_modifier"] = current_modifiers["reverse_modifier"]
		_active_repeat_modifiers["large_increment_modifier"] = current_modifiers["large_increment_modifier"]
		_active_repeat_modifiers["fine_increment_modifier"] = current_modifiers["fine_increment_modifier"]
	else:
		if current_modifiers != _active_repeat_modifiers:
			_active_repeat_key = ""
			_active_repeat_modifiers.clear()
			return false
	var repeat_delay := _repeat_intervals.get(action_type, 0.1)
	var time_in_repeat_phase: float = time_since_press - _key_tap_grace_period
	var repeat_count := int(time_in_repeat_phase / repeat_delay)
	var next_repeat_time: float = _key_tap_grace_period + (repeat_count * repeat_delay)
	var time_to_next: float = (_key_press_times[key_name] + next_repeat_time + repeat_delay) - current_time
	return time_to_next <= 0.016

func is_key_held_for_wheel(key_name: String) -> bool:
	if not is_key_pressed(key_name):
		return false
	if not _key_press_times.has(key_name):
		return false
	return true

func clear_pending_tap(key_name: String) -> void:
	_pending_taps.erase(key_name)

func mark_wheel_interrupt(keys: Array) -> void:
	for key_name in keys:
		if is_key_held_for_wheel(key_name):
			_wheel_interrupted_keys[key_name] = true

func clear_active_repeat() -> void:
	_active_repeat_key = ""
	_active_repeat_modifiers.clear()

func is_mouse_button_pressed(button: String) -> bool:
	match button:
		"left":
			return _current_mouse.get("left_pressed", false)
		"right":
			return _current_mouse.get("right_pressed", false)
		"middle":
			return _current_mouse.get("middle_pressed", false)
		_:
			return false

func is_mouse_button_just_pressed(button: String) -> bool:
	var current := false
	var previous := false
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
		_:
			return false
	return current and not previous

func mouse_position() -> Vector2:
	return _current_mouse.get("position", Vector2.ZERO)

func is_mouse_in_viewport() -> bool:
	if not _cached_viewport:
		return false
	var mouse_pos := mouse_position()
	var viewport_rect := _cached_viewport.get_visible_rect()
	return viewport_rect.has_point(mouse_pos)

func is_action_pressed(action_name: String) -> bool:
	return _current_actions.get(action_name, false)

func is_action_just_pressed(action_name: String) -> bool:
	var current := _current_actions.get(action_name, false)
	return current

func is_reverse_modifier_held() -> bool:
	return is_key_pressed("reverse_modifier")

func is_large_increment_modifier_held() -> bool:
	return is_key_pressed("large_increment_modifier")

func is_fine_increment_modifier_held() -> bool:
	return is_key_pressed("fine_increment_modifier")

func get_modifier_state() -> Dictionary:
	return {
		"reverse": is_reverse_modifier_held(),
		"large": is_large_increment_modifier_held(),
		"fine": is_fine_increment_modifier_held()
	}

func is_alias_pressed(alias: String) -> bool:
	return is_key_pressed(alias)

func was_alias_pressed(alias: String) -> bool:
	return was_key_pressed(alias)

func digit_just_pressed(index: int) -> bool:
	return is_key_just_pressed("digit_%d" % index)

func decimal_just_pressed() -> bool:
	return is_key_just_pressed("decimal_point")

func minus_just_pressed() -> bool:
	return is_key_just_pressed("minus")

func plus_just_pressed() -> bool:
	return is_key_just_pressed("plus")

func equals_just_pressed() -> bool:
	return is_key_just_pressed("equals")

func backspace_just_pressed() -> bool:
	return is_key_just_pressed("backspace")

func enter_just_pressed() -> bool:
	return is_key_just_pressed("enter")

func escape_just_pressed() -> bool:
	return is_key_just_pressed("escape")

func mark_pending_taps(keys: Array) -> void:
	for key_name in keys:
		_pending_taps.erase(key_name)

func get_all_pressed_keys() -> Array:
	var pressed := []
	for key_name in _current_keys.keys():
		if _current_keys[key_name]:
			pressed.append(key_name)
	return pressed

func string_to_keycode(key_string: String) -> Key:
	return OS.find_keycode_from_string(key_string)

func _swap_buffers() -> void:
	if _use_buffer_a:
		_previous_keys = _keys_buffer_a
		_previous_mouse = _mouse_buffer_a
		_current_keys = _keys_buffer_b
		_current_mouse = _mouse_buffer_b
	else:
		_previous_keys = _keys_buffer_b
		_previous_mouse = _mouse_buffer_b
		_current_keys = _keys_buffer_a
		_current_mouse = _mouse_buffer_a
	_use_buffer_a = not _use_buffer_a

func _update_key_states() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	_current_keys["tab"] = _check_key_with_modifiers(settings.get("transform_mode_key", "TAB"))
	_current_keys["confirm"] = _check_key_with_modifiers(settings.get("confirm_action_key", "ENTER"))
	_current_keys["escape"] = Input.is_key_pressed(KEY_ESCAPE)
	_current_keys["shift"] = Input.is_key_pressed(KEY_SHIFT)
	_current_keys["ctrl"] = Input.is_key_pressed(KEY_CTRL)
	_current_keys["alt"] = Input.is_key_pressed(KEY_ALT)
	_current_keys["reverse_modifier"] = _check_key_with_modifiers(settings.get("reverse_modifier_key", "SHIFT"))
	_current_keys["large_increment_modifier"] = _check_key_with_modifiers(settings.get("large_increment_modifier_key", "ALT"))
	_current_keys["fine_increment_modifier"] = _check_key_with_modifiers(settings.get("fine_increment_modifier_key", "CTRL"))
	_current_keys["cancel"] = _check_key_with_modifiers(settings.get("cancel_key", "ESCAPE"))
	var height_up_key := settings.get("height_up_key", "Q")
	var height_down_key := settings.get("height_down_key", "E")
	var reset_height_key := settings.get("reset_height_key", "R")
	_current_keys["height_up"] = _check_key_with_modifiers(height_up_key)
	_current_keys["height_down"] = _check_key_with_modifiers(height_down_key)
	_current_keys["reset_height"] = _check_key_with_modifiers(reset_height_key)
	_track_key_press_time("height_up", current_time)
	_track_key_press_time("height_down", current_time)
	_track_key_press_time("reset_height", current_time)
	var position_left_key := settings.get("position_left_key", "A")
	var position_right_key := settings.get("position_right_key", "D")
	var position_forward_key := settings.get("position_forward_key", "W")
	var position_backward_key := settings.get("position_backward_key", "S")
	var reset_position_key := settings.get("reset_position_key", "G")
	_current_keys["position_left"] = _check_key_with_modifiers(position_left_key)
	_current_keys["position_right"] = _check_key_with_modifiers(position_right_key)
	_current_keys["position_forward"] = _check_key_with_modifiers(position_forward_key)
	_current_keys["position_backward"] = _check_key_with_modifiers(position_backward_key)
	_current_keys["reset_position"] = _check_key_with_modifiers(reset_position_key)
	_track_key_press_time("position_left", current_time)
	_track_key_press_time("position_right", current_time)
	_track_key_press_time("position_forward", current_time)
	_track_key_press_time("position_backward", current_time)
	_track_key_press_time("reset_position", current_time)
	_current_keys["rotate_x"] = _check_key_with_modifiers(settings.get("rotate_x_key", "X"))
	_current_keys["rotate_y"] = _check_key_with_modifiers(settings.get("rotate_y_key", "Y"))
	_current_keys["rotate_z"] = _check_key_with_modifiers(settings.get("rotate_z_key", "Z"))
	_current_keys["reset_rotation"] = _check_key_with_modifiers(settings.get("reset_rotation_key", "T"))
	_track_key_press_time("rotate_x", current_time)
	_track_key_press_time("rotate_y", current_time)
	_track_key_press_time("rotate_z", current_time)
	_track_key_press_time("reset_rotation", current_time)
	var scale_up_key := settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key := settings.get("scale_down_key", "PAGE_DOWN")
	var scale_reset_key := settings.get("scale_reset_key", "HOME")
	_current_keys["scale_up"] = _check_key_with_modifiers(scale_up_key)
	_current_keys["scale_down"] = _check_key_with_modifiers(scale_down_key)
	_current_keys["reset_scale"] = _check_key_with_modifiers(scale_reset_key)
	_track_key_press_time("scale_up", current_time)
	_track_key_press_time("scale_down", current_time)
	_track_key_press_time("reset_scale", current_time)
	var cycle_next_key := settings.get("cycle_next_asset_key", "BRACKETRIGHT")
	var cycle_prev_key := settings.get("cycle_previous_asset_key", "BRACKETLEFT")
	_current_keys["cycle_next_asset"] = _check_key_with_modifiers(cycle_next_key)
	_current_keys["cycle_previous_asset"] = _check_key_with_modifiers(cycle_prev_key)
	_track_key_press_time("cycle_next_asset", current_time)
	_track_key_press_time("cycle_previous_asset", current_time)
	var cycle_mode_key := settings.get("cycle_placement_mode_key", "P")
	_current_keys["cycle_placement_mode"] = _check_key_with_modifiers(cycle_mode_key)
	_track_key_press_time("cycle_placement_mode", current_time)
	
	# Modal system removed - G/R/L keys no longer tracked
	
	var axis_x_key := settings.get("rotate_x_key", "X")
	var axis_y_key := settings.get("rotate_y_key", "Y")
	var axis_z_key := settings.get("rotate_z_key", "Z")
	_current_keys["axis_x"] = _check_key_with_modifiers(axis_x_key)
	_current_keys["axis_y"] = _check_key_with_modifiers(axis_y_key)
	_current_keys["axis_z"] = _check_key_with_modifiers(axis_z_key)
	_track_key_press_time("axis_x", current_time)
	_track_key_press_time("axis_y", current_time)
	_track_key_press_time("axis_z", current_time)
	_current_keys["decimal_point"] = Input.is_key_pressed(KEY_PERIOD)
	_current_keys["minus"] = Input.is_key_pressed(KEY_MINUS)
	_current_keys["plus"] = Input.is_key_pressed(KEY_PLUS) or (Input.is_key_pressed(KEY_EQUAL) and Input.is_key_pressed(KEY_SHIFT))
	_current_keys["equals"] = (Input.is_key_pressed(KEY_EQUAL) and not Input.is_key_pressed(KEY_SHIFT)) or (Input.is_key_pressed(KEY_0) and Input.is_key_pressed(KEY_SHIFT))
	_current_keys["backspace"] = Input.is_key_pressed(KEY_BACKSPACE)
	_current_keys["enter"] = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	for i in range(10):
		var digit_key := "digit_%d" % i
		var keycode := KEY_0 + i
		var is_digit := Input.is_key_pressed(keycode)
		if i == 0 and _current_keys["equals"]:
			is_digit = false
		elif i == 0 and Input.is_key_pressed(KEY_SHIFT):
			is_digit = false
		_current_keys[digit_key] = is_digit

func _update_mouse_states() -> void:
	if _cached_viewport:
		_current_mouse["position"] = _cached_viewport.get_mouse_position()
	else:
		_current_mouse["position"] = DisplayServer.mouse_get_position()
	_current_mouse["left_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_current_mouse["right_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_current_mouse["middle_pressed"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)

func _update_action_states() -> void:
	_current_actions["ui_cancel"] = Input.is_action_just_pressed("ui_cancel")

func _check_key_with_modifiers(key_string: String) -> bool:
	var normalized := key_string.strip_edges().to_upper()
	if normalized == "CTRL":
		return Input.is_key_pressed(KEY_CTRL)
	elif normalized == "ALT":
		return Input.is_key_pressed(KEY_ALT)
	elif normalized == "SHIFT":
		return Input.is_key_pressed(KEY_SHIFT)
	elif normalized == "META":
		return Input.is_key_pressed(KEY_META)
	if "+" in key_string:
		var parts := key_string.split("+")
		var required_modifiers := {
			"ctrl": false,
			"alt": false,
			"shift": false,
			"meta": false
		}
		var base_key := ""
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
				base_key = part
		if required_modifiers["ctrl"] and not Input.is_key_pressed(KEY_CTRL):
			return false
		if required_modifiers["alt"] and not Input.is_key_pressed(KEY_ALT):
			return false
		if required_modifiers["shift"] and not Input.is_key_pressed(KEY_SHIFT):
			return false
		if required_modifiers["meta"] and not Input.is_key_pressed(KEY_META):
			return false
		if not base_key.is_empty():
			var keycode := string_to_keycode(base_key)
			if keycode != KEY_NONE:
				return Input.is_key_pressed(keycode)
			if base_key.is_valid_int():
				var key_num := base_key.to_int()
				if key_num >= 0 and key_num <= 9:
					var number_keycode := KEY_0 + key_num
					return Input.is_key_pressed(number_keycode)
			return false
		else:
			return true
	else:
		var keycode_simple := string_to_keycode(key_string)
		if keycode_simple != KEY_NONE:
			return Input.is_key_pressed(keycode_simple)
		return false

func _track_key_press_time(key_name: String, current_time: float) -> void:
	var is_pressed := _current_keys.get(key_name, false)
	var was_pressed := _previous_keys.get(key_name, false)
	if is_pressed and not was_pressed:
		_key_press_times[key_name] = current_time
		_pending_taps[key_name] = true
	elif is_pressed and was_pressed and _pending_taps.has(key_name):
		var time_held: float = current_time - _key_press_times.get(key_name, current_time)
		if time_held > _key_tap_grace_period:
			_pending_taps.erase(key_name)
	elif not is_pressed and _key_press_times.has(key_name):
		_key_press_times.erase(key_name)
		_wheel_interrupted_keys.erase(key_name)
		if _active_repeat_key == key_name:
			_active_repeat_key = ""
			_active_repeat_modifiers.clear()
