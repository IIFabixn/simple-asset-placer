@tool
extends RefCounted

class_name TransformActionRouter

# TRANSFORM ACTION ROUTER (SIMPLIFIED)
# ======================================
#
# PURPOSE: Coordinate input processing for transform operations.
#
# RESPONSIBILITIES:
# - Gather all input states once per frame
# - Build processing context
# - Delegate to keyboard processor for command population
# - Return unified TransformCommand
#
# SIMPLIFIED ARCHITECTURE:
# - No strategy pattern (only one processor)
# - No priority system needed
# - Direct delegation to KeyboardInputProcessor
# - Modal system removed (G/R/L keys no longer used)
# - Mouse positioning handled by mode handlers
#
# ARCHITECTURE POSITION: Input coordinator
# - Manages keyboard processor instance
# - Single entry point for transform input processing

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
const TransformCommand = preload("res://addons/simpleassetplacer/core/transform_command.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const KeyboardInputProcessor = preload("res://addons/simpleassetplacer/core/keyboard_input_processor.gd")

var _services
var _keyboard_processor: KeyboardInputProcessor

func _init(services):
	_services = services
	_keyboard_processor = KeyboardInputProcessor.new(_services)
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "TransformActionRouter: Initialized")

func process(params: Dictionary) -> Dictionary:
	"""
	Main entry point for input processing.
	
	EXECUTION FLOW:
	1. Gather all input states
	2. Build processing context
	3. Delegate to keyboard processor
	4. Return command with metadata
	"""
	var command := TransformCommand.new()
	
	# Gather all input states once
	var inputs = _gather_all_inputs()
	
	# Build processing context
	var context = _build_processing_context(params)
	
	# Add base metadata
	var base_metadata := {
		"timestamp_ms": Time.get_ticks_msec()
	}
	if params.has("mode") and params.get("mode") != null:
		base_metadata["mode"] = params.get("mode")
	var numeric_metadata = params.get("numeric_metadata", {})
	if numeric_metadata and not numeric_metadata.is_empty():
		base_metadata["numeric_metadata"] = numeric_metadata.duplicate(true)
	command.merge_metadata(base_metadata)
	
	# Process keyboard input (rotation/scale)
	_keyboard_processor.process(command, inputs, context)
	
	# Debug logging if enabled
	if _is_debug_enabled():
		command.merge_metadata(_build_debug_input_metadata(inputs, _keyboard_processor))
		if _should_log_command(command):
			_debug_log_command(command, _keyboard_processor)
	
	# Build result dictionary
	var result := {
		"command": command,
		"position_input": inputs.get("position"),
		"rotation_input": inputs.get("rotation"),
		"scale_input": inputs.get("scale"),
		"skip_normal_input": false
	}
	
	return result

## INPUT GATHERING

func _gather_all_inputs() -> Dictionary:
	"""Collect all input states from InputHandler"""
	if not _services or not _services.input_handler:
		return {}
	
	var input_handler = _services.input_handler
	return {
		"position": input_handler.get_position_input(),
		"rotation": input_handler.get_rotation_input(),
		"scale": input_handler.get_scale_input(),
		"control": input_handler.get_control_mode_input()
	}

func _build_processing_context(params: Dictionary) -> Dictionary:
	"""Build context dictionary for processors"""
	return {
		"transform_state": params.get("transform_state"),
		"camera": params.get("camera"),
		"settings": params.get("settings", {}),
		"mode": params.get("mode"),
		"services": _services
	}

## CONTROL MODE HANDLING (G/R/L and X/Y/Z keys)

func _handle_control_mode_input(control_mode, control_input, axis_origin) -> void:
	"""Handle axis constraints for X/Y/Z keys (G/R/L modal removed)"""
	if not control_mode or not control_input:
		return
	
	# MODAL SYSTEM REMOVED: G/R/L keys no longer activate modal controls
	# Mouse positioning is always active, keyboard shortcuts handle rotation/scale
	# X/Y/Z keys are used for direct rotation (handled by KeyboardInputProcessor)
	
	# Axis constraints removed - no longer needed without modal system
	pass

## DEBUG HELPERS

func _build_debug_input_metadata(inputs: Dictionary, active_processor) -> Dictionary:
	"""Build debug metadata with all input states and active processor"""
	return {
		"debug_inputs": {
			"position": inputs.get("position").to_dictionary() if inputs.get("position") else {},
			"rotation": inputs.get("rotation").to_dictionary() if inputs.get("rotation") else {},
			"scale": inputs.get("scale").to_dictionary() if inputs.get("scale") else {},
			"numeric": inputs.get("numeric").to_dictionary() if inputs.get("numeric") else {},
			"control_mode": inputs.get("control").to_dictionary() if inputs.get("control") else {}
		},
		"active_processor": active_processor.get_processor_name() if active_processor else "None"
	}

func _debug_log_command(command: TransformCommand, active_processor) -> void:
	"""Log command details for debugging"""
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
		"metadata_keys": command.metadata.keys(),
		"processor": active_processor.get_processor_name() if active_processor else "None"
	}
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "TransformCommand [%s]: %s" % [
		active_processor.get_processor_name() if active_processor else "None",
		str(debug_dict)
	])

func _should_log_command(command: TransformCommand) -> bool:
	if command.has_any_delta():
		return true
	if command.confirm or command.cancel:
		return true
	if not command.source_flags.is_empty():
		return true
	return false

func _is_debug_enabled() -> bool:
	if _services and _services.settings_manager:
		return _services.settings_manager.get_setting("debug_commands", false)
	return false
