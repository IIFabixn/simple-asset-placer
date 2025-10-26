@tool
extends RefCounted

class_name InputHandler

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")
const RotationInputState = preload("res://addons/simpleassetplacer/managers/input/rotation_input_state.gd")
const ScaleInputState = preload("res://addons/simpleassetplacer/managers/input/scale_input_state.gd")
const PositionInputState = preload("res://addons/simpleassetplacer/managers/input/position_input_state.gd")
const NavigationInputState = preload("res://addons/simpleassetplacer/managers/input/navigation_input_state.gd")
const ControlModeInputState = preload("res://addons/simpleassetplacer/managers/input/control_mode_input_state.gd")

"""
CENTRALIZED INPUT FACADE
=========================

PURPOSE: Single source of truth for all input detection with proper edge detection.

RESPONSIBILITIES:
- Polls all input state once per frame (keys, mouse, actions)
- Provides edge detection (just pressed vs held) to prevent rapid-fire actions
- Maps custom key settings to input queries
- Provides clean input APIs for rotation, scale, position, and navigation
- Handles modifier key detection (SHIFT, CTRL, ALT)

ARCHITECTURE POSITION: Pure input aggregation with no business logic
- Does NOT decide actions to perform
- Does NOT know about placement/transform behaviors

USED BY: Mode handlers, transformation coordinator, numeric input systems
DEPENDS ON: User settings for key mappings, Godot Input system
"""

var _services: ServiceRegistry
var _snapshot: RawInputSnapshot

var _current_settings: Dictionary = {}
var _cached_viewport: SubViewport = null

var _rotation_input_cache: RotationInputState = null
var _scale_input_cache: ScaleInputState = null
var _position_input_cache: PositionInputState = null
var _navigation_input_cache: NavigationInputState = null
var _control_mode_input_cache: ControlModeInputState = null

func _init(services: ServiceRegistry) -> void:
	_services = services
	_snapshot = RawInputSnapshot.new()

func update_input_state(settings: Dictionary, viewport: SubViewport = null) -> void:
	if settings and not settings.is_empty():
		_current_settings = settings.duplicate(true)
	elif _current_settings.is_empty():
		_current_settings = {}

	if viewport:
		_cached_viewport = viewport

	_snapshot.update(_current_settings, _cached_viewport)
	_clear_cached_views()

func get_rotation_input() -> RotationInputState:
	if _rotation_input_cache == null:
		_rotation_input_cache = RotationInputState.new(_snapshot)
	return _rotation_input_cache

func get_scale_input() -> ScaleInputState:
	if _scale_input_cache == null:
		_scale_input_cache = ScaleInputState.new(_snapshot)
	return _scale_input_cache

func get_position_input() -> PositionInputState:
	if _position_input_cache == null:
		_position_input_cache = PositionInputState.new(_snapshot)
	return _position_input_cache

func get_navigation_input() -> NavigationInputState:
	if _navigation_input_cache == null:
		_navigation_input_cache = NavigationInputState.new(_snapshot)
	return _navigation_input_cache

func get_control_mode_input() -> ControlModeInputState:
	if _control_mode_input_cache == null:
		_control_mode_input_cache = ControlModeInputState.new(_snapshot)
	return _control_mode_input_cache

func is_key_pressed(key_name: String) -> bool:
	return _snapshot.is_key_pressed(key_name)

func was_key_pressed(key_name: String) -> bool:
	return _snapshot.was_key_pressed(key_name)

func is_key_just_pressed(key_name: String) -> bool:
	return _snapshot.is_key_just_pressed(key_name)

func key_edge_pressed(key_name: String) -> bool:
	return _snapshot.key_edge_pressed(key_name)

func is_key_just_released(key_name: String) -> bool:
	return _snapshot.is_key_just_released(key_name)

func is_key_held_with_repeat(key_name: String, repeat_delay: float = 0.15) -> bool:
	return _snapshot.is_key_held_with_repeat(key_name, repeat_delay)

func is_action_key_held_with_repeat(key_name: String, action_type: String) -> bool:
	return _snapshot.is_action_key_held_with_repeat(key_name, action_type)

func is_key_held_for_wheel(key_name: String) -> bool:
	return _snapshot.is_key_held_for_wheel(key_name)

func is_mouse_button_pressed(button: String) -> bool:
	return _snapshot.is_mouse_button_pressed(button)

func is_mouse_button_just_pressed(button: String) -> bool:
	return _snapshot.is_mouse_button_just_pressed(button)

func get_mouse_position() -> Vector2:
	return _snapshot.mouse_position()

func is_mouse_in_viewport() -> bool:
	return _snapshot.is_mouse_in_viewport()

func is_action_pressed(action_name: String) -> bool:
	return _snapshot.is_action_pressed(action_name)

func is_reverse_modifier_held() -> bool:
	return _snapshot.is_reverse_modifier_held()

func is_large_increment_modifier_held() -> bool:
	return _snapshot.is_large_increment_modifier_held()

func is_fine_increment_modifier_held() -> bool:
	return _snapshot.is_fine_increment_modifier_held()

func get_modifier_state() -> Dictionary:
	return _snapshot.get_modifier_state()

func should_cycle_next_asset() -> bool:
	return _snapshot.is_key_just_pressed("cycle_next_asset") or _snapshot.is_key_held_with_repeat("cycle_next_asset")

func should_cycle_previous_asset() -> bool:
	return _snapshot.is_key_just_pressed("cycle_previous_asset") or _snapshot.is_key_held_with_repeat("cycle_previous_asset")

func should_cycle_placement_mode() -> bool:
	return _snapshot.is_key_just_pressed("cycle_placement_mode")

func should_cycle_plane() -> bool:
	"""Check if plane cycling should occur (middle mouse button by default)"""
	return _snapshot.is_mouse_button_just_pressed("middle")

func get_mouse_wheel_input(event: InputEventMouseButton) -> Dictionary:
	if not event or not event.pressed:
		return {}

	var wheel_up := event.button_index == MOUSE_BUTTON_WHEEL_UP
	var wheel_down := event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if not wheel_up and not wheel_down:
		return {}

	var wheel_direction := 1 if wheel_up else -1

	var monitored_keys = [
		"rotate_x", "rotate_y", "rotate_z",
		"scale_up", "scale_down",
		"height_up", "height_down",
		"position_forward", "position_backward", "position_left", "position_right"
	]
	_snapshot.mark_wheel_interrupt(monitored_keys)
	_snapshot.clear_active_repeat()

	if _snapshot.is_key_held_for_wheel("height_up") or _snapshot.is_key_held_for_wheel("height_down"):
		_snapshot.mark_pending_taps(["height_up", "height_down"])
		return _with_wheel_modifiers({
			"action": "height",
			"direction": wheel_direction
		})

	if _snapshot.is_key_held_for_wheel("scale_up") or _snapshot.is_key_held_for_wheel("scale_down"):
		_snapshot.mark_pending_taps(["scale_up", "scale_down"])
		return _with_wheel_modifiers({
			"action": "scale",
			"direction": wheel_direction
		})

	if _snapshot.is_key_held_for_wheel("rotate_x"):
		_snapshot.mark_pending_taps(["rotate_x"])
		return _with_wheel_modifiers({
			"action": "rotation",
			"axis": "X",
			"direction": wheel_direction
		})
	elif _snapshot.is_key_held_for_wheel("rotate_y"):
		_snapshot.mark_pending_taps(["rotate_y"])
		return _with_wheel_modifiers({
			"action": "rotation",
			"axis": "Y",
			"direction": wheel_direction
		})
	elif _snapshot.is_key_held_for_wheel("rotate_z"):
		_snapshot.mark_pending_taps(["rotate_z"])
		return _with_wheel_modifiers({
			"action": "rotation",
			"axis": "Z",
			"direction": wheel_direction
		})

	if _snapshot.is_key_held_for_wheel("position_forward"):
		_snapshot.mark_pending_taps(["position_forward"])
		return _with_wheel_modifiers({
			"action": "position",
			"axis": "forward",
			"direction": wheel_direction
		})
	elif _snapshot.is_key_held_for_wheel("position_backward"):
		_snapshot.mark_pending_taps(["position_backward"])
		return _with_wheel_modifiers({
			"action": "position",
			"axis": "backward",
			"direction": wheel_direction
		})
	elif _snapshot.is_key_held_for_wheel("position_left"):
		_snapshot.mark_pending_taps(["position_left"])
		return _with_wheel_modifiers({
			"action": "position",
			"axis": "left",
			"direction": wheel_direction
		})
	elif _snapshot.is_key_held_for_wheel("position_right"):
		_snapshot.mark_pending_taps(["position_right"])
		return _with_wheel_modifiers({
			"action": "position",
			"axis": "right",
			"direction": wheel_direction
		})

	# Modal system removed - default mouse wheel behavior
	# If axis constraints are active, apply them
	if _services and _services.control_mode_state:
		var control_state = _services.control_mode_state
		if control_state.has_axis_constraint():
			return _with_wheel_modifiers({
				"action": "position_axis",
				"axes": control_state.get_constrained_axes(),
				"direction": wheel_direction
			})
	
	# Default: mouse wheel controls height
	return _with_wheel_modifiers({
		"action": "height",
		"direction": wheel_direction
	})

func _with_wheel_modifiers(payload: Dictionary) -> Dictionary:
	if not payload.has("reverse_modifier"):
		payload["reverse_modifier"] = _snapshot.is_reverse_modifier_held()
	if not payload.has("large_increment"):
		payload["large_increment"] = _snapshot.is_large_increment_modifier_held()
	if not payload.has("fine_increment"):
		payload["fine_increment"] = _snapshot.is_fine_increment_modifier_held()
	return payload

func string_to_keycode(key_string: String) -> Key:
	return _snapshot.string_to_keycode(key_string)

func get_all_pressed_keys() -> Array:
	return _snapshot.get_all_pressed_keys()

func debug_print_input_state() -> void:
	var pressed = get_all_pressed_keys()
	if not pressed.is_empty():
		PluginLogger.debug("InputHandler", "Pressed keys: " + str(pressed))

func _clear_cached_views() -> void:
	_rotation_input_cache = null
	_scale_input_cache = null
	_position_input_cache = null
	_navigation_input_cache = null
	_control_mode_input_cache = null
