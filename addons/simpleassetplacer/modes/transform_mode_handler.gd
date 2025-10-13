@tool
extends RefCounted

class_name TransformModeHandler

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")
const UndoRedoHelper = preload("res://addons/simpleassetplacer/utils/undo_redo_helper.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")

var _services: ServiceRegistry

func _init(services: ServiceRegistry) -> void:
	_services = services

func enter_transform_mode(target_nodes: Variant, settings: Dictionary, transform_state: TransformState, undo_redo: EditorUndoRedoManager = null) -> Dictionary:
	if target_nodes is Node3D:
		target_nodes = [target_nodes]
	elif not target_nodes is Array:
		return {}
	if target_nodes.is_empty():
		return {}
	var valid_nodes = []
	for node in target_nodes:
		if NodeUtils.validate_node3d(node):
			valid_nodes.append(node)
	if valid_nodes.is_empty():
		PluginLogger.warning("TransformModeHandler", "No valid Node3D objects to transform")
		return {}
	var original_transforms = {}
	for node in valid_nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
	var center_pos = get_transform_center(valid_nodes)
	if center_pos == Vector3.ZERO:
		PluginLogger.error("TransformModeHandler", "No nodes in tree to transform")
		return {}
	var node_offsets = _calculate_node_offsets(valid_nodes, center_pos)
	_services.position_manager.configure(transform_state, settings)
	transform_state.position = center_pos
	transform_state.base_height = center_pos.y
	var transform_data = {
		"target_nodes": valid_nodes,
		"original_transforms": original_transforms,
		"center_position": center_pos,
		"node_offsets": node_offsets,
		"settings": settings,
		"undo_redo": undo_redo,
		"accumulated_y_delta": 0.0,
		"manual_position_offset": Vector3.ZERO
	}
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(2)
	update_overlays(transform_data)
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started transform mode for " + str(valid_nodes.size()) + " node(s)")
	return transform_data

func exit_transform_mode(transform_data: Dictionary, transform_state: TransformState, confirm_changes: bool, settings: Dictionary) -> void:
	if not confirm_changes:
		restore_original_state(transform_data)
	_reset_transforms_on_exit(transform_state, settings)
	_services.overlay_manager.hide_transform_overlay()
	_services.overlay_manager.set_mode(0)
	_services.overlay_manager.remove_grid_overlay()
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited transform mode")

func process_input(camera: Camera3D, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary, delta: float) -> void:
	if not camera:
		return
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	var position_input = _services.input_handler.get_position_input()
	var rotation_input = _services.input_handler.get_rotation_input()
	var scale_input = _services.input_handler.get_scale_input()
	
	# Process keyboard input (updates manual offsets and height)
	_process_height_input(position_input, transform_data, transform_state, settings)
	_process_position_input(camera, position_input, transform_data, transform_state, settings)
	
	# Update base position from mouse raycast
	var mouse_pos = position_input.get("mouse_position", Vector2.ZERO)
	_services.position_manager.update_position_from_mouse(transform_state, camera, mouse_pos, 1, true, target_nodes)
	
	# Get base position and add manual offsets from WASD
	var manual_offset = transform_data.get("manual_position_offset", Vector3.ZERO)
	var base_pos = _services.position_manager.get_base_position(transform_state)
	var center_pos = Vector3(
		base_pos.x + manual_offset.x, 
		transform_state.base_height + transform_state.height_offset, 
		base_pos.z + manual_offset.z
	)
	transform_state.position = center_pos
	transform_data["center_position"] = center_pos
	
	# Handle confirm action (left click or Enter key)
	if position_input.get("confirm_action", false):
		transform_data["_confirm_exit"] = true
		return
	
	# Handle scale input (including reset)
	var scale_changed = false
	if scale_input.get("up_pressed", false) or scale_input.get("down_pressed", false) or scale_input.get("reset_pressed", false):
		_process_scale_for_group(scale_input, transform_data, transform_state, settings)
		scale_changed = true
	
	# Handle rotation input (including reset)
	var rotation_changed = false
	if rotation_input.get("x_pressed", false) or rotation_input.get("y_pressed", false) or rotation_input.get("z_pressed", false) or rotation_input.get("reset_pressed", false):
		_process_rotation_for_group(rotation_input, transform_data, transform_state, settings)
		rotation_changed = true
	
	# Only apply smooth transformation when not actively rotating (rotation sets positions directly)
	if not rotation_changed:
		_apply_group_transformation(transform_data, transform_state)
	
	update_overlays(transform_data)

func _process_height_input(position_input: Dictionary, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	var height_up = position_input.get("height_up_pressed", false)
	var height_down = position_input.get("height_down_pressed", false)
	var reset_height = position_input.get("reset_height_pressed", false)
	
	if reset_height:
		_services.position_manager.reset_height(transform_state)
		var center_pos = Vector3(transform_state.position.x, transform_state.base_height + transform_state.height_offset, transform_state.position.z)
		transform_state.position = center_pos
		transform_data["center_position"] = center_pos
		return
	
	if not (height_up or height_down):
		return
	
	# Determine height step based on modifiers (use proper settings)
	var height_step: float
	if position_input.get("large_increment_modifier_held", false):
		height_step = settings.get("large_height_increment", 1.0)
	elif position_input.get("fine_increment_modifier_held", false):
		height_step = settings.get("fine_height_increment", 0.01)
	else:
		height_step = settings.get("height_adjustment_step", 0.1)
	
	var reverse_modifier = position_input.get("reverse_modifier_held", false)
	
	if height_up:
		var height_change = height_step if not reverse_modifier else -height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	elif height_down:
		var height_change = -height_step if not reverse_modifier else height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	
	# CRITICAL: Update actual position.y to base_height + height_offset
	var center_pos = Vector3(transform_state.position.x, transform_state.base_height + transform_state.height_offset, transform_state.position.z)
	transform_state.position = center_pos
	transform_data["center_position"] = center_pos

func _process_position_input(camera: Camera3D, position_input: Dictionary, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	var move_forward = position_input.get("position_forward_pressed", false)
	var move_backward = position_input.get("position_backward_pressed", false)
	var move_left = position_input.get("position_left_pressed", false)
	var move_right = position_input.get("position_right_pressed", false)
	if not (move_forward or move_backward or move_left or move_right):
		return
	
	# Get camera-relative directions snapped to nearest axis (same as placement mode)
	var camera_forward = Vector3(0, 0, -1)
	var camera_right = Vector3(1, 0, 0)
	
	if camera:
		# Get camera forward and project to XZ plane
		var cam_forward = -camera.global_transform.basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		
		# Snap forward to nearest axis (Z or X)
		if abs(cam_forward.z) > abs(cam_forward.x):
			camera_forward = Vector3(0, 0, sign(cam_forward.z))
		else:
			camera_forward = Vector3(sign(cam_forward.x), 0, 0)
		
		# Get camera right and project to XZ plane
		var cam_right = camera.global_transform.basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()
		
		# Snap right to nearest axis (X or Z)
		if abs(cam_right.x) > abs(cam_right.z):
			camera_right = Vector3(sign(cam_right.x), 0, 0)
		else:
			camera_right = Vector3(0, 0, sign(cam_right.z))
	
	var movement = Vector3.ZERO
	if move_forward:
		movement += camera_forward
	if move_backward:
		movement -= camera_forward
	if move_left:
		movement -= camera_right
	if move_right:
		movement += camera_right
	if movement.length_squared() > 0:
		movement = movement.normalized()
		
		# Determine position step based on modifiers (use proper settings)
		var position_step: float
		if position_input.get("large_increment_modifier_held", false):
			position_step = settings.get("large_position_increment", 1.0)
		elif position_input.get("fine_increment_modifier_held", false):
			position_step = settings.get("fine_position_increment", 0.01)
		else:
			position_step = settings.get("position_increment", 0.1)
		
		movement *= position_step
		# Apply movement to manual offset (so it works with mouse position)
		var manual_offset = transform_data.get("manual_position_offset", Vector3.ZERO)
		manual_offset.x += movement.x
		manual_offset.z += movement.z
		transform_data["manual_position_offset"] = manual_offset

func _process_scale_for_group(scale_input: Dictionary, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	var increase = scale_input.get("up_pressed", false)
	var decrease = scale_input.get("down_pressed", false)
	var reset_scale = scale_input.get("reset_pressed", false)
	
	if reset_scale:
		_services.scale_manager.reset_scale(transform_state)
		var target_nodes = transform_data.get("target_nodes", [])
		var original_transforms = transform_data.get("original_transforms", {})
		for node in target_nodes:
			if node and node.is_inside_tree():
				var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
				_apply_scale_to_node(transform_state, node, node_original_scale)
		return
	
	if not (increase or decrease):
		return
	
	# Determine scale step based on modifiers
	var scale_step: float
	if scale_input.get("large_increment_modifier_held", false):
		scale_step = settings.get("large_scale_increment", 0.5)
	elif scale_input.get("fine_increment_modifier_held", false):
		scale_step = settings.get("fine_scale_increment", 0.01)
	else:
		scale_step = settings.get("scale_increment", 0.1)
	
	if increase:
		_services.scale_manager.increase_scale(transform_state, scale_step)
	else:
		_services.scale_manager.decrease_scale(transform_state, scale_step)
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	for node in target_nodes:
		if node and node.is_inside_tree():
			var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
			_apply_scale_to_node(transform_state, node, node_original_scale)

func _process_rotation_for_group(rotation_input: Dictionary, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	var rotate_x = rotation_input.get("x_pressed", false)
	var rotate_y = rotation_input.get("y_pressed", false)
	var rotate_z = rotation_input.get("z_pressed", false)
	var reset_rotation = rotation_input.get("reset_pressed", false)
	
	if reset_rotation:
		var target_nodes = transform_data.get("target_nodes", [])
		for node in target_nodes:
			if node and node.is_inside_tree():
				_services.rotation_manager.reset_node_rotation(node)
		return
	
	# Determine rotation step based on modifiers
	var rotation_step: float
	if rotation_input.get("large_increment_modifier_held", false):
		rotation_step = settings.get("large_rotation_increment", 90.0)
	elif rotation_input.get("fine_increment_modifier_held", false):
		rotation_step = settings.get("fine_rotation_increment", 5.0)
	else:
		rotation_step = settings.get("rotation_increment", 15.0)
	
	# Apply reverse modifier to change direction
	if rotation_input.get("reverse_modifier_held", false):
		rotation_step = -rotation_step
	
	var axis = ""
	if rotate_x:
		axis = "X"
	elif rotate_y:
		axis = "Y"
	elif rotate_z:
		axis = "Z"
	
	if axis == "":
		return
	
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	var center = transform_data.get("center_position", Vector3.ZERO)
	
	# CRITICAL: Recalculate node offsets from current positions
	# (center may have moved since last rotation due to mouse/WASD/wheel input)
	var node_offsets = {}
	for node in target_nodes:
		if node and node.is_inside_tree():
			node_offsets[node] = node.global_position - center
	
	# Create rotation basis for the specified axis
	var rotation_radians = deg_to_rad(rotation_step)
	var rotation_axis_vector = Vector3.ZERO
	match axis:
		"X":
			rotation_axis_vector = Vector3(1, 0, 0)
		"Y":
			rotation_axis_vector = Vector3(0, 1, 0)
		"Z":
			rotation_axis_vector = Vector3(0, 0, 1)
	
	var rotation_basis = Basis(rotation_axis_vector, rotation_radians)
	var rotated_offsets = {}
	
	for node in target_nodes:
		if not node or not node.is_inside_tree():
			continue
		
		# Get the current offset from center
		var offset = node_offsets.get(node, Vector3.ZERO)
		
		# Rotate the offset using the rotation basis
		var rotated_offset = rotation_basis * offset
		rotated_offsets[node] = rotated_offset
		
		# Calculate new position and rotation
		var new_position = center + rotated_offset
		var new_basis = rotation_basis * node.global_transform.basis
		var new_rotation = new_basis.get_euler()
		var current_scale = node.scale
		
		# Apply immediately without smoothing to prevent jittering
		_services.smooth_transform_manager.apply_transform_immediately(
			node, 
			new_position, 
			new_rotation, 
			current_scale
		)
		
		# Update the basis separately (apply_transform_immediately uses rotation property)
		node.global_transform.basis = new_basis
	
	# Update the stored offsets for next rotation
	transform_data["node_offsets"] = rotated_offsets

func rotate_group_by_step(axis: String, rotation_step: float, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Helper function to rotate group by a specific step amount (used by mouse wheel)"""
	if axis == "" or rotation_step == 0.0:
		return
	
	var target_nodes = transform_data.get("target_nodes", [])
	var center = transform_data.get("center_position", Vector3.ZERO)
	
	# CRITICAL: Recalculate node offsets from current positions
	var node_offsets = {}
	for node in target_nodes:
		if node and node.is_inside_tree():
			node_offsets[node] = node.global_position - center
	
	# Create rotation basis for the specified axis
	var rotation_radians = deg_to_rad(rotation_step)
	var rotation_axis_vector = Vector3.ZERO
	match axis:
		"X":
			rotation_axis_vector = Vector3(1, 0, 0)
		"Y":
			rotation_axis_vector = Vector3(0, 1, 0)
		"Z":
			rotation_axis_vector = Vector3(0, 0, 1)
	
	var rotation_basis = Basis(rotation_axis_vector, rotation_radians)
	var rotated_offsets = {}
	
	for node in target_nodes:
		if not node or not node.is_inside_tree():
			continue
		
		var offset = node_offsets.get(node, Vector3.ZERO)
		var rotated_offset = rotation_basis * offset
		rotated_offsets[node] = rotated_offset
		
		var new_position = center + rotated_offset
		var new_basis = rotation_basis * node.global_transform.basis
		var new_rotation = new_basis.get_euler()
		var current_scale = node.scale
		
		_services.smooth_transform_manager.apply_transform_immediately(
			node, 
			new_position, 
			new_rotation, 
			current_scale
		)
		
		node.global_transform.basis = new_basis
	
	# Update the stored offsets for next rotation
	transform_data["node_offsets"] = rotated_offsets

func _apply_group_transformation(transform_data: Dictionary, transform_state: TransformState) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	var center = transform_data.get("center_position", Vector3.ZERO)
	var node_offsets = transform_data.get("node_offsets", {})
	for node in target_nodes:
		if node and node.is_inside_tree():
			var offset = node_offsets.get(node, Vector3.ZERO)
			var new_pos = center + offset
			_services.smooth_transform_manager.set_target_position(node, new_pos)

func _apply_scale_to_node(transform_state: TransformState, node: Node3D, original_scale: Vector3) -> void:
	if not node or not is_instance_valid(node):
		return
	# Use ADDITIVE scaling logic (same as scale_manager.apply_uniform_scale_to_node)
	# offset = multiplier - 1.0
	# target = original + offset (per axis)
	var scale_mult = _services.scale_manager.get_scale(transform_state)
	var offset = scale_mult - 1.0
	var new_scale = original_scale + Vector3(offset, offset, offset)
	
	# Prevent negative or zero scale
	new_scale.x = max(0.01, new_scale.x)
	new_scale.y = max(0.01, new_scale.y)
	new_scale.z = max(0.01, new_scale.z)
	
	_services.smooth_transform_manager.set_target_scale(node, new_scale)

func get_transform_center(target_nodes: Array) -> Vector3:
	if target_nodes.is_empty():
		return Vector3.ZERO
	var valid_nodes = []
	for node in target_nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			valid_nodes.append(node)
	if valid_nodes.is_empty():
		return Vector3.ZERO
	var sum = Vector3.ZERO
	for node in valid_nodes:
		sum += node.global_position
	return sum / valid_nodes.size()

func capture_original_state(nodes: Array) -> Dictionary:
	var state = {}
	for node in nodes:
		if is_instance_valid(node):
			state[node] = node.transform
	return state

func restore_original_state(transform_data: Dictionary) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	for node in target_nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			var original_transform = original_transforms.get(node)
			if original_transform:
				node.transform = original_transform

func _calculate_node_offsets(nodes: Array, center: Vector3) -> Dictionary:
	var offsets = {}
	for node in nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			offsets[node] = node.global_position - center
	return offsets

func update_overlays(transform_data: Dictionary) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	var center = transform_data.get("center_position", Vector3.ZERO)
	var first_node = target_nodes[0] if target_nodes.size() > 0 else null
	var node_name = first_node.name if first_node else ""
	var position = center
	var rotation = first_node.rotation if first_node else Vector3.ZERO
	var scale_val = first_node.scale.x if first_node else 1.0
	_services.overlay_manager.show_transform_overlay(1, node_name, position, rotation, scale_val, 0.0)

func _reset_transforms_on_exit(transform_state: TransformState, settings: Dictionary) -> void:
	var reset_rotation = settings.get("reset_rotation_on_exit", false)
	var reset_scale = settings.get("reset_scale_on_exit", false)
	if reset_rotation and transform_state:
		_services.rotation_manager.reset_all_rotation(transform_state)
	if reset_scale and transform_state:
		_services.scale_manager.reset_scale(transform_state)
