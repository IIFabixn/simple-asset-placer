@tool
extends RefCounted

class_name NumericInputController

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const NumericInputManager = preload("res://addons/simpleassetplacer/managers/numeric_input_manager.gd")
const RotationInputState = preload("res://addons/simpleassetplacer/managers/input/rotation_input_state.gd")
const ScaleInputState = preload("res://addons/simpleassetplacer/managers/input/scale_input_state.gd")
const PositionInputState = preload("res://addons/simpleassetplacer/managers/input/position_input_state.gd")
const NumericInputState = preload("res://addons/simpleassetplacer/managers/input/numeric_input_state.gd")

var _services: ServiceRegistry
var _current_context: Dictionary = {}

func _init(services: ServiceRegistry) -> void:
	_services = services

func action_types():
	return NumericInputManager.ActionType

func prefix_modes():
	return NumericInputManager.PrefixMode

func is_active() -> bool:
	var manager = _manager()
	return manager != null and manager.is_active()

func is_confirmed() -> bool:
	var manager = _manager()
	return manager != null and manager.is_confirmed()

func is_within_grace_period() -> bool:
	var manager = _manager()
	return manager != null and manager.is_within_grace_period()

func get_active_action() -> int:
	var manager = _manager()
	return manager.get_active_action() if manager else NumericInputManager.ActionType.NONE

func get_numeric_value() -> float:
	var manager = _manager()
	return manager.get_numeric_value() if manager else 0.0

func get_prefix_mode() -> int:
	var manager = _manager()
	return manager.get_prefix_mode() if manager else NumericInputManager.PrefixMode.RELATIVE

func is_absolute_mode() -> bool:
	var manager = _manager()
	return manager != null and manager.is_absolute_mode()

func apply_to_value(current_value: float) -> float:
	var manager = _manager()
	return manager.apply_to_value(current_value) if manager else current_value

func get_action_display_name() -> String:
	var manager = _manager()
	return manager.get_action_display_name() if manager else ""

func get_input_string() -> String:
	var manager = _manager()
	return manager.get_input_string() if manager else ""

func get_display_state() -> Dictionary:
	if not is_active():
		return {}
	return {
		"action_name": get_action_display_name(),
		"input_string": get_input_string(),
		"context": _current_context.duplicate(true)
	}

func track_action_context(rotation_input: RotationInputState, scale_input: ScaleInputState, position_input: PositionInputState, metadata: Dictionary = {}) -> void:
	var manager = _manager()
	if not manager:
		return

	var control_mode = _services.control_mode_state
	var is_position_mode = control_mode.is_position_mode() if control_mode else false
	var action_types = action_types()

	if rotation_input and rotation_input.x_tapped:
		var axis_meta = _merge_metadata(metadata, {"axis": "X"})
		if is_position_mode:
			_set_action_context(action_types.POSITION_RIGHT, axis_meta)
		else:
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "NumericInput: ROTATE_X context")
			_set_action_context(action_types.ROTATE_X, axis_meta)
	elif rotation_input and rotation_input.y_tapped:
		var axis_meta_y = _merge_metadata(metadata, {"axis": "Y"})
		if is_position_mode:
			_set_action_context(action_types.HEIGHT, axis_meta_y)
		else:
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "NumericInput: ROTATE_Y context")
			_set_action_context(action_types.ROTATE_Y, axis_meta_y)
	elif rotation_input and rotation_input.z_tapped:
		var axis_meta_z = _merge_metadata(metadata, {"axis": "Z"})
		if is_position_mode:
			_set_action_context(action_types.POSITION_FORWARD, axis_meta_z)
		else:
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "NumericInput: ROTATE_Z context")
			_set_action_context(action_types.ROTATE_Z, axis_meta_z)
	elif scale_input and (scale_input.up_tapped or scale_input.down_tapped):
		_set_action_context(action_types.SCALE, metadata)
	elif position_input and (position_input.height_up_tapped or position_input.height_down_tapped):
		_set_action_context(action_types.HEIGHT, metadata)
	elif position_input and position_input.position_forward_tapped:
		_set_action_context(action_types.POSITION_FORWARD, metadata)
	elif position_input and position_input.position_backward_tapped:
		_set_action_context(action_types.POSITION_BACKWARD, metadata)
	elif position_input and position_input.position_left_tapped:
		_set_action_context(action_types.POSITION_LEFT, metadata)
	elif position_input and position_input.position_right_tapped:
		_set_action_context(action_types.POSITION_RIGHT, metadata)

func process_numeric_input(numeric_input: NumericInputState) -> void:
	var manager = _manager()
	if not manager or numeric_input == null:
		if is_active():
			_update_overlay()
		return

	if not numeric_input.has_input():
		if is_active():
			_update_overlay()
		return

	var state_changed := false
	var digit = numeric_input.digit_pressed
	if digit >= 0:
		state_changed = manager.process_numeric_key(str(digit)) or state_changed
	if numeric_input.decimal_pressed:
		state_changed = manager.process_decimal_key() or state_changed
	if numeric_input.minus_pressed:
		state_changed = manager.process_minus_key() or state_changed
	if numeric_input.plus_pressed:
		state_changed = manager.process_plus_key() or state_changed
	if numeric_input.equals_pressed:
		state_changed = manager.process_equals_key() or state_changed
	if numeric_input.backspace_pressed:
		state_changed = manager.process_backspace() or state_changed
	if numeric_input.enter_pressed and manager.is_active():
		confirm_action()
		state_changed = true
	if numeric_input.escape_pressed and manager.is_active():
		manager.cancel_action()
		state_changed = true
		_clear_context()

	if manager.is_active() and (state_changed or manager.is_within_grace_period()):
		_update_overlay()
	elif state_changed and not manager.is_active():
		_update_overlay()

func handle_tab_pressed() -> void:
	var manager = _manager()
	if manager:
		manager.process_tab_pressed()

func handle_tab_released() -> void:
	var manager = _manager()
	if manager:
		manager.process_tab_released()

func confirm_action() -> void:
	var manager = _manager()
	if manager and manager.is_active():
		manager.confirm_action()
		_update_overlay()

func cancel_action() -> void:
	var manager = _manager()
	if manager and manager.is_active():
		manager.cancel_action()
	_clear_context()

func reset() -> void:
	var manager = _manager()
	if manager:
		manager.reset()
	_clear_context()

func consume_confirmed_value() -> Dictionary:
	var manager = _manager()
	if not manager or not manager.is_confirmed():
		return {}
	var result = {
		"action": manager.get_active_action(),
		"value": manager.get_numeric_value(),
		"prefix_mode": manager.get_prefix_mode(),
		"is_absolute": manager.is_absolute_mode(),
		"context": _current_context.duplicate(true)
	}
	manager.reset()
	_clear_context()
	return result

func _set_action_context(action: int, metadata: Dictionary) -> void:
	var manager = _manager()
	if not manager:
		return
	_current_context = metadata.duplicate(true)
	_current_context["action"] = action
	manager.set_action_context(action)

func _update_overlay() -> void:
	var overlay = _services.overlay_manager if _services else null
	if not overlay:
		return
	var display_state = get_display_state()
	if display_state.is_empty():
		overlay.clear_numeric_input()
		return
	overlay.show_numeric_input(display_state.get("action_name", ""), display_state.get("input_string", ""))

func _clear_context() -> void:
	_current_context.clear()

func _manager() -> NumericInputManager:
	return _services.numeric_input_manager if _services else null

func _merge_metadata(base: Dictionary, extra: Dictionary) -> Dictionary:
	var combined: Dictionary = {}
	if base:
		combined = base.duplicate(true)
	for key in extra.keys():
		combined[key] = extra[key]
	return combined
