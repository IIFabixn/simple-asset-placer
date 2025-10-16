@tool
extends RefCounted

class_name TransformActionRouter

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
const TransformCommand = preload("res://addons/simpleassetplacer/core/transform_command.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")

var _services

func _init(services):
	_services = services

func process(params: Dictionary) -> Dictionary:
	var command := TransformCommand.new()
	var result := {
		"command": command,
		"position_input": null,
		"rotation_input": null,
		"scale_input": null,
		"numeric_input": null,
		"modal_active": false,
		"skip_normal_input": false,
		"numeric_was_confirmed": false
	}

	if not _services:
		return result

	var input_handler = _services.input_handler if _services else null
	var control_mode = _services.control_mode_state if _services else null
	var numeric_controller = _services.numeric_input_controller if _services else null
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

	var base_metadata := {
		"timestamp_ms": Time.get_ticks_msec()
	}
	if params.has("mode") and params.get("mode") != null:
		base_metadata["mode"] = params.get("mode")
	var numeric_metadata = params.get("numeric_metadata", {})
	if numeric_metadata and not numeric_metadata.is_empty():
		base_metadata["numeric_metadata"] = numeric_metadata.duplicate(true)
	command.merge_metadata(base_metadata)

	var axis_origin = params.get("axis_origin", null)
	if not axis_origin and params.has("transform_state") and params.transform_state:
		axis_origin = params.transform_state.position
	_handle_control_mode_input(control_mode, control_input, axis_origin)

	var modal_active = control_mode and control_mode.is_modal_active()
	result.modal_active = modal_active

	var axis_constraints = control_mode.get_constrained_axes() if control_mode else {}
	if axis_constraints.is_empty():
		axis_constraints = {"X": false, "Y": false, "Z": false}
	var axis_source = TransformCommand.SOURCE_KEY_DIRECT
	if modal_active:
		axis_source = TransformCommand.SOURCE_MOUSE_MODAL
	command.set_axis_constraints_from_dict(axis_constraints, axis_source)
	command.merge_metadata({
		"modal_active": modal_active,
		"control_mode": control_mode.get_control_mode_string() if control_mode else "Unknown"
	})
	if modal_active:
		command.source_flags[TransformCommand.SOURCE_MOUSE_MODAL] = true

	if position_input and position_input.confirm_action:
		command.set_confirm(true)
		command.source_flags[TransformCommand.SOURCE_KEY_DIRECT] = true

	if _has_direct_keyboard_input(position_input, rotation_input, scale_input):
		command.source_flags[TransformCommand.SOURCE_KEY_DIRECT] = true

	if numeric_controller:
		numeric_controller.track_action_context(rotation_input, scale_input, position_input, numeric_metadata)
		numeric_controller.process_numeric_input(numeric_input)
		result.numeric_was_confirmed = numeric_controller.is_confirmed()
		result.skip_normal_input = numeric_controller.is_active() and not numeric_controller.is_confirmed()
		if numeric_controller.is_active():
			command.source_flags[TransformCommand.SOURCE_NUMERIC] = true
			command.merge_metadata({"numeric_state": numeric_controller.get_display_state()})
		if result.numeric_was_confirmed:
			command.merge_metadata({"numeric_confirmed_state": numeric_controller.get_display_state()})

	if modal_active and not result.skip_normal_input:
		_dispatch_modal_callbacks(params, position_input, rotation_input, scale_input)

	if _is_debug_enabled():
		command.merge_metadata(_build_debug_input_metadata(position_input, rotation_input, scale_input, numeric_input, control_input))
		_debug_log_command(command)

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


func _invoke_callback(callback, base_args: Array, extra_args: Array) -> void:
	if typeof(callback) != TYPE_CALLABLE:
		return
	if not callback.is_valid():
		return
	var args := base_args.duplicate()
	if extra_args:
		args.append_array(extra_args)
	callback.callv(args)

func _has_direct_keyboard_input(position_input, rotation_input, scale_input) -> bool:
	if position_input and (
		position_input.height_up_pressed or
		position_input.height_down_pressed or
		position_input.position_forward_pressed or
		position_input.position_backward_pressed or
		position_input.position_left_pressed or
		position_input.position_right_pressed or
		position_input.reset_position_pressed or
		position_input.reset_height_pressed
	):
		return true
	if rotation_input and (
		rotation_input.x_pressed or
		rotation_input.y_pressed or
		rotation_input.z_pressed or
		rotation_input.reset_pressed
	):
		return true
	if scale_input and (
		scale_input.up_pressed or
		scale_input.down_pressed or
		scale_input.reset_pressed
	):
		return true
	return false

func _build_debug_input_metadata(position_input, rotation_input, scale_input, numeric_input, control_input) -> Dictionary:
	return {
		"debug_inputs": {
			"position": position_input.to_dictionary() if position_input else {},
			"rotation": rotation_input.to_dictionary() if rotation_input else {},
			"scale": scale_input.to_dictionary() if scale_input else {},
			"numeric": numeric_input.to_dictionary() if numeric_input else {},
			"control_mode": control_input.to_dictionary() if control_input else {}
		}
	}

func _debug_log_command(command: TransformCommand) -> void:
	if not _should_log_command(command):
		return
	var debug_dict := {
		"position_delta": command.position_delta,
		"rotation_delta": command.rotation_delta,
		"scale_delta": command.scale_delta,
		"confirm": command.confirm,
		"cancel": command.cancel,
		"source_flags": command.source_flags.keys(),
		"axis_constraints": command.axis_constraints,
		"metadata_keys": command.metadata.keys()
	}
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "TransformCommand: %s" % str(debug_dict))

func _should_log_command(command: TransformCommand) -> bool:
	if command.has_any_delta():
		return true
	if command.confirm or command.cancel:
		return true
	if not command.source_flags.is_empty():
		return true
	return false

func _is_debug_enabled() -> bool:
	return SettingsManager.get_setting("debug_commands", false)
