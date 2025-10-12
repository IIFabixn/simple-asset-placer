@tool
extends RefCounted

class_name KeyboardInputProcessor

"""
KEYBOARD INPUT PROCESSOR (SIMPLIFIED)
======================================

PURPOSE: Process direct keyboard input for transformations.

HANDLES:
- Rotation keys (X/Y/Z) for direct axis rotation
- Scale keys (PageUp/PageDown)
- Modifier keys (CTRL/ALT/SHIFT) for increment adjustments
- Confirm action (ENTER)

NOTE: Position/height input (WASD/QE) is handled directly by mode handlers
to avoid double-processing. This processor focuses on rotation and scale.

ARCHITECTURE: Simplified from strategy pattern (removed base class)
- Directly instantiated by TransformActionRouter
- No priority system needed (only processor remaining)
- Clean, focused responsibility
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const TransformCommand = preload("res://addons/simpleassetplacer/core/transform_command.gd")
const RotationInputState = preload("res://addons/simpleassetplacer/managers/input/rotation_input_state.gd")
const ScaleInputState = preload("res://addons/simpleassetplacer/managers/input/scale_input_state.gd")
const PositionInputState = preload("res://addons/simpleassetplacer/managers/input/position_input_state.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

var _services: ServiceRegistry

func _init(services: ServiceRegistry) -> void:
	_services = services

func process(command: TransformCommand, inputs: Dictionary, context: Dictionary) -> void:
	"""Process keyboard input and populate command"""
	var rotation_input: RotationInputState = inputs.get("rotation")
	var position_input: PositionInputState = inputs.get("position")
	var scale_input: ScaleInputState = inputs.get("scale")
	
	# Mark as keyboard input
	command.source_flags[TransformCommand.SOURCE_KEY_DIRECT] = true
	
	# Process each input type
	if rotation_input:
		_process_rotation(command, rotation_input, context)
	
	# POSITION INPUT REMOVED: WASD movement is now handled by mode handlers directly
	# This prevents double-processing of keyboard position input
	# if position_input:
	# 	_process_position(command, position_input, context)
	
	if scale_input:
		_process_scale(command, scale_input, context)
	
	# Handle confirm action
	if position_input and position_input.confirm_action:
		command.set_confirm(true)

## ROTATION PROCESSING

func _process_rotation(command: TransformCommand, rotation_input: RotationInputState, context: Dictionary) -> void:
	"""Process keyboard rotation (X/Y/Z keys)"""
	if not rotation_input:
		return
	
	var settings = _get_settings(context)
	var transform_state = _get_transform_state(context)
	
	# Get rotation increments based on modifiers
	var increment = _get_rotation_increment(rotation_input, settings)
	
	var delta_vector = Vector3.ZERO
	var axis_rotated = ""
	
	# Check which axis was pressed (using pressed to support hold-to-repeat)
	if rotation_input.x_pressed:
		# Rotate around X axis
		_services.rotation_manager.rotate_x(transform_state, increment)
		delta_vector.x = deg_to_rad(increment)
		axis_rotated = "X"
	elif rotation_input.y_pressed:
		# Rotate around Y axis
		_services.rotation_manager.rotate_y(transform_state, increment)
		delta_vector.y = deg_to_rad(increment)
		axis_rotated = "Y"
	elif rotation_input.z_pressed:
		# Rotate around Z axis
		_services.rotation_manager.rotate_z(transform_state, increment)
		delta_vector.z = deg_to_rad(increment)
		axis_rotated = "Z"
	elif rotation_input.reset_pressed:
		# Reset rotation to zero
		var previous_rotation = transform_state.manual_rotation_offset
		_services.rotation_manager.reset_all_rotation(transform_state)
		delta_vector = transform_state.manual_rotation_offset - previous_rotation
		axis_rotated = "ALL"
	
	# Add rotation delta to command if any rotation occurred
	if delta_vector != Vector3.ZERO:
		command.set_rotation_delta(delta_vector, TransformCommand.SOURCE_KEY_DIRECT)
		command.merge_metadata({
			"rotation_axis": axis_rotated,
			"rotation_step_degrees": increment,
			"keyboard_rotation": true,
			"input_mode": "keyboard"
		})
		_log_debug("Keyboard rotation: %s axis by %.1f degrees" % [axis_rotated, increment])

func _get_rotation_increment(rotation_input: RotationInputState, settings: Dictionary) -> float:
	"""Calculate rotation increment based on modifier keys"""
	var base_increment = settings.get("rotation_increment", 15.0)
	var fine_increment = settings.get("fine_rotation_increment", 5.0)
	var large_increment = settings.get("large_rotation_increment", 90.0)
	
	var increment = base_increment
	if rotation_input.fine_increment_modifier_held:
		increment = fine_increment
	elif rotation_input.large_increment_modifier_held:
		increment = large_increment
	
	# Apply reverse modifier (negate the increment)
	if rotation_input.reverse_modifier_held:
		increment = -increment
	
	return increment

## NOTE: Position/height input (WASD/QE) removed from KeyboardInputProcessor
## These are now handled directly by TransformationCoordinator
## to avoid double-processing and maintain clear separation of concerns.

## SCALE PROCESSING

func _process_scale(command: TransformCommand, scale_input: ScaleInputState, context: Dictionary) -> void:
	"""Process keyboard scale input (PageUp/PageDown)"""
	if not scale_input:
		return
	
	var settings = _get_settings(context)
	var transform_state = _get_transform_state(context)
	
	var increment = _get_scale_increment(scale_input, settings)
	var previous_scale = _services.scale_manager.get_scale_vector(transform_state)
	
	if scale_input.up_pressed:
		_services.scale_manager.increase_scale(transform_state, increment)
	elif scale_input.down_pressed:
		_services.scale_manager.decrease_scale(transform_state, increment)
	elif scale_input.reset_pressed:
		_services.scale_manager.reset_scale(transform_state)
	
	var new_scale = _services.scale_manager.get_scale_vector(transform_state)
	var scale_delta = new_scale - previous_scale
	
	if scale_delta != Vector3.ZERO:
		command.set_scale_delta(scale_delta, TransformCommand.SOURCE_KEY_DIRECT)
		command.merge_metadata({
			"scale_multiplier": new_scale,
			"keyboard_scale": true,
			"input_mode": "keyboard"
		})
		_log_debug("Keyboard scale adjustment: %.3f" % new_scale.x)

func _get_scale_increment(scale_input: ScaleInputState, settings: Dictionary) -> float:
	"""Calculate scale increment based on modifier keys"""
	var base_increment = settings.get("scale_increment", 0.1)
	var fine_increment = settings.get("fine_scale_increment", 0.01)
	var large_increment = settings.get("large_scale_increment", 0.5)
	
	if scale_input.fine_increment_modifier_held:
		return fine_increment
	elif scale_input.large_increment_modifier_held:
		return large_increment
	else:
		return base_increment

## HELPER METHODS

func _get_transform_state(context: Dictionary) -> TransformState:
	"""Extract TransformState from context"""
	return context.get("transform_state")

func _get_camera(context: Dictionary) -> Camera3D:
	"""Extract Camera3D from context"""
	return context.get("camera")

func _get_settings(context: Dictionary) -> Dictionary:
	"""Extract settings dictionary from context"""
	return context.get("settings", {})

func _log_debug(message: String) -> void:
	"""Helper for debug logging"""
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, message)

func get_processor_name() -> String:
	"""Return human-readable name for this processor (for logging)"""
	return "KeyboardInputProcessor"
