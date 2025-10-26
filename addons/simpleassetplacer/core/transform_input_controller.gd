@tool
extends RefCounted

class_name TransformInputController

"""
TRANSFORM INPUT CONTROLLER
==========================

PURPOSE: Unified keyboard input handling for both placement and transform modes

RESPONSIBILITIES:
- Process WASD movement (position adjustments)
- Process QE height adjustments
- Process XYZ rotation
- Process Page Up/Down scaling
- Process reset keys (R/T/G/Home)
- Apply modifiers (CTRL/ALT/SHIFT)

DESIGN: Updates TransformState only - does NOT apply to nodes/preview
- Mode controllers call this to process input
- Mode controllers handle applying state to their targets
- Eliminates duplication between modes

USED BY: PlacementModeController, TransformModeController
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PositionInputState = preload("res://addons/simpleassetplacer/managers/input/position_input_state.gd")
const RotationInputState = preload("res://addons/simpleassetplacer/managers/input/rotation_input_state.gd")
const ScaleInputState = preload("res://addons/simpleassetplacer/managers/input/scale_input_state.gd")

var _services  # ServiceRegistry

func _init(services) -> void:
	_services = services

## Main Input Processing

func process_keyboard_input(camera: Camera3D, state: TransformState, settings: Dictionary) -> Dictionary:
	"""Process all keyboard input and update state
	
	Returns a dictionary indicating what changed:
	{
		"height_changed": bool,
		"position_changed": bool,
		"rotation_changed": bool,
		"scale_changed": bool,
		"height_reset": bool,
		"position_reset": bool,
		"rotation_reset": bool,
		"scale_reset": bool,
		"confirm_action": bool
	}
	"""
	if not state or not camera:
		return {}
	
	var changes = {
		"height_changed": false,
		"position_changed": false,
		"rotation_changed": false,
		"scale_changed": false,
		"height_reset": false,
		"position_reset": false,
		"rotation_reset": false,
		"scale_reset": false,
		"confirm_action": false
	}
	
	# Get input states
	var pos_input = _services.input_handler.get_position_input()
	var rot_input = _services.input_handler.get_rotation_input()
	var scale_input = _services.input_handler.get_scale_input()
	
	# Process height adjustment (Q/E keys)
	if pos_input.height_up_pressed or pos_input.height_down_pressed:
		process_height_adjustment(pos_input, state, settings)
		changes["height_changed"] = true
	
	# Process WASD position movement
	if pos_input.position_forward_pressed or pos_input.position_backward_pressed or \
	   pos_input.position_left_pressed or pos_input.position_right_pressed:
		process_wasd_movement(pos_input, camera, state, settings)
		changes["position_changed"] = true
	
	# Process rotation (X/Y/Z keys)
	if rot_input.x_pressed or rot_input.y_pressed or rot_input.z_pressed:
		process_rotation(rot_input, state, settings)
		changes["rotation_changed"] = true
	
	# Process scale (Page Up/Down keys)
	if scale_input.up_pressed or scale_input.down_pressed:
		process_scale(scale_input, state, settings)
		changes["scale_changed"] = true
	
	# Process resets
	if pos_input.reset_height_pressed:
		_services.position_manager.reset_offset_normal(state)
		changes["height_reset"] = true
	
	if pos_input.reset_position_pressed:
		_services.position_manager.reset_position(state)
		changes["position_reset"] = true
	
	if rot_input.reset_pressed:
		_services.rotation_manager.reset_all_rotation(state)
		changes["rotation_reset"] = true
	
	if scale_input.reset_pressed:
		_services.scale_manager.reset_scale(state)
		changes["scale_reset"] = true
	
	# Check for confirmation
	if pos_input.confirm_action:
		changes["confirm_action"] = true
	
	return changes

## Individual Input Processors

func process_height_adjustment(pos_input: PositionInputState, state: TransformState, settings: Dictionary) -> void:
	"""Process height offset adjustments (Q/E keys)"""
	var step = settings.get("height_adjustment_step", 0.1)
	
	# Apply modifiers
	if pos_input.fine_increment_modifier_held:
		step = settings.get("fine_height_increment", 0.01)
	elif pos_input.large_increment_modifier_held:
		step = settings.get("large_height_increment", 1.0)
	
	var delta_normal = 0.0
	if pos_input.height_up_pressed:
		delta_normal = step
	elif pos_input.height_down_pressed:
		delta_normal = -step
	
	if delta_normal != 0.0:
		_services.position_manager.adjust_offset_normal(state, delta_normal)

func process_wasd_movement(pos_input: PositionInputState, camera: Camera3D, state: TransformState, settings: Dictionary) -> void:
	"""Process WASD position movement (plane-aware)"""
	var position_step = settings.get("position_adjustment_step", 0.1)
	
	# Apply modifiers
	if pos_input.fine_increment_modifier_held:
		position_step = settings.get("fine_position_increment", 0.01)
	elif pos_input.large_increment_modifier_held:
		position_step = settings.get("large_position_increment", 1.0)
	
	# Use plane-aware movement functions that handle all plane orientations correctly
	# - XZ plane (horizontal): W/S moves along camera-snapped Z/X, A/D moves perpendicular
	# - XY plane (vertical): W/S moves up/down (Y), A/D moves left/right on plane
	# - YZ plane (vertical): W/S moves up/down (Y), A/D moves left/right on plane
	
	if pos_input.position_forward_pressed:
		_services.position_manager.move_forward(state, position_step, camera)
	if pos_input.position_backward_pressed:
		_services.position_manager.move_backward(state, position_step, camera)
	if pos_input.position_right_pressed:
		_services.position_manager.move_right(state, position_step, camera)
	if pos_input.position_left_pressed:
		_services.position_manager.move_left(state, position_step, camera)

func process_rotation(rot_input: RotationInputState, state: TransformState, settings: Dictionary) -> void:
	"""Process rotation input (X/Y/Z keys)"""
	var rotation_step = settings.get("rotation_step", 15.0)
	
	# Apply modifiers
	if rot_input.fine_increment_modifier_held:
		rotation_step = settings.get("fine_rotation_increment", 1.0)
	elif rot_input.large_increment_modifier_held:
		rotation_step = settings.get("large_rotation_increment", 45.0)
	
	# Apply reverse modifier
	if rot_input.reverse_modifier_held:
		rotation_step = -rotation_step
	
	# Apply rotation
	if rot_input.x_pressed:
		_services.rotation_manager.rotate_x(state, rotation_step)
	if rot_input.y_pressed:
		_services.rotation_manager.rotate_y(state, rotation_step)
	if rot_input.z_pressed:
		_services.rotation_manager.rotate_z(state, rotation_step)

func process_scale(scale_input: ScaleInputState, state: TransformState, settings: Dictionary) -> void:
	"""Process scale input (Page Up/Down keys)"""
	var scale_step = settings.get("scale_increment", 0.1)
	
	# Apply modifiers
	if scale_input.fine_increment_modifier_held:
		scale_step = settings.get("fine_scale_increment", 0.01)
	elif scale_input.large_increment_modifier_held:
		scale_step = settings.get("large_scale_increment", 0.5)
	
	# Apply scale
	if scale_input.up_pressed:
		_services.scale_manager.increase_scale(state, scale_step)
	elif scale_input.down_pressed:
		_services.scale_manager.decrease_scale(state, scale_step)
