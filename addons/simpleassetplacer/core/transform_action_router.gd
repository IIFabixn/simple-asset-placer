@tool
extends RefCounted

class_name TransformActionRouter

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")

var _services

func _init(services):
	_services = services

func process(params: Dictionary) -> Dictionary:
	var input_handler = _services.input_handler if _services else null
	var control_mode = _services.control_mode_state if _services else null
	var numeric_controller = _services.numeric_input_controller if _services else null
	var result := {
		"position_input": null,
		"rotation_input": null,
		"scale_input": null,
		"numeric_input": null,
		"modal_active": false,
		"skip_normal_input": false,
		"numeric_was_confirmed": false
	}
	if not input_handler:
		return result

	var position_input = input_handler.get_position_input()
	var rotation_input = input_handler.get_rotation_input()
	var scale_input = input_handler.get_scale_input()
	var numeric_input = input_handler.get_numeric_input()
	var control_input = input_handler.get_control_mode_input()

	result.position_input = position_input
	result.rotation_input = rotation_input
	result.scale_input = scale_input
	result.numeric_input = numeric_input

	var axis_origin = params.get("axis_origin", null)
	if not axis_origin and params.has("transform_state") and params.transform_state:
		axis_origin = params.transform_state.position
	_handle_control_mode_input(control_mode, control_input, axis_origin)

	var modal_active = control_mode and control_mode.is_modal_active()
	result.modal_active = modal_active

	var numeric_metadata = params.get("numeric_metadata", {})
	if numeric_controller:
		if not modal_active:
			numeric_controller.track_action_context(rotation_input, scale_input, position_input, numeric_metadata)
		numeric_controller.process_numeric_input(numeric_input)
		result.numeric_was_confirmed = numeric_controller.is_confirmed()
		result.skip_normal_input = numeric_controller.is_active() and not numeric_controller.is_confirmed()

	if modal_active and not result.skip_normal_input:
		_dispatch_modal_callbacks(params, position_input, rotation_input, scale_input)

	return result

func _handle_control_mode_input(control_mode, control_input, axis_origin) -> void:
	if not control_mode or not control_input:
		return
	var current_time = Time.get_ticks_msec() / 1000.0
	if control_input.position_control_pressed:
		control_mode.switch_to_position_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Position control (G)")
	elif control_input.rotation_control_pressed:
		control_mode.switch_to_rotation_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Rotation control (R)")
	elif control_input.scale_control_pressed:
		control_mode.switch_to_scale_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Scale control (L)")

	var origin = axis_origin if axis_origin else Vector3.ZERO
	if control_input.axis_x_pressed:
		control_mode.process_axis_key_press("X", current_time, origin)
	elif control_input.axis_y_pressed:
		control_mode.process_axis_key_press("Y", current_time, origin)
	elif control_input.axis_z_pressed:
		control_mode.process_axis_key_press("Z", current_time, origin)

func _dispatch_modal_callbacks(params: Dictionary, position_input, rotation_input, scale_input) -> void:
	var control_mode = _services.control_mode_state if _services else null
	if not control_mode:
		return
	match control_mode.get_control_mode():
		ControlModeState.ControlMode.POSITION:
			_invoke_callback(params.get("position_modal_callback"), [position_input], params.get("position_modal_args", []))
		ControlModeState.ControlMode.ROTATION:
			_invoke_callback(params.get("rotation_modal_callback"), [position_input, rotation_input], params.get("rotation_modal_args", []))
		ControlModeState.ControlMode.SCALE:
			_invoke_callback(params.get("scale_modal_callback"), [position_input, scale_input], params.get("scale_modal_args", []))

func _invoke_callback(callback: Callable, base_args: Array, extra_args: Array) -> void:
	if not callback or not callback.is_valid():
		return
	var args := base_args.duplicate()
	if extra_args:
		args.append_array(extra_args)
	callback.callv(args)
