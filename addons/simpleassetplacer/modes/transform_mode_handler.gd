@tool
extends RefCounted

class_name TransformModeHandler

"""
TRANSFORM MODE HANDLER
======================

PURPOSE: Handles all transform mode logic (multi-object transformation)

RESPONSIBILITIES:
- Multi-object transformation setup
- Original transform state capture
- Transform mode input processing (position, rotation, scale)
- Group positioning with offset system
- Transform mode overlay updates
- Transform confirmation/cancellation

ARCHITECTURE POSITION: Mode-specific handler
- Called by TransformationCoordinator when in transform mode
- Manages transform_data dictionary
- Delegates to specialist managers (PositionManager, RotationManager, etc.)

USED BY: TransformationCoordinator
USES: PositionManager, RotationManager, ScaleManager, SmoothTransformManager,
      OverlayManager, InputHandler, NodeUtils, PluginLogger
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")
const UndoRedoHelper = preload("res://addons/simpleassetplacer/utils/undo_redo_helper.gd")

# Import managers
const InputHandler = preload("res://addons/simpleassetplacer/managers/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
const SmoothTransformManager = preload("res://addons/simpleassetplacer/core/smooth_transform_manager.gd")

# Import settings manager
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")

# Import state
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")

## MODE ENTRY/EXIT

static func enter_transform_mode(
	target_nodes: Variant,  # Node3D or Array of Node3D
	settings: Dictionary,
	transform_state: TransformState,
	undo_redo: EditorUndoRedoManager = null
) -> Dictionary:
	"""Initialize transform mode and return transform data
	
	Args:
		target_nodes: Single Node3D or Array of Node3D objects to transform together
		settings: Transform settings dictionary
		transform_state: Transform state to configure
		undo_redo: EditorUndoRedoManager for undo/redo support
		
	Returns:
		Dictionary: transform_data containing all transform state
	"""
	# Handle single node parameter - convert to array
	if target_nodes is Node3D:
		target_nodes = [target_nodes]
	elif not target_nodes is Array:
		return {}
	
	if target_nodes.is_empty():
		return {}
	
	# Filter to only valid Node3D objects
	var valid_nodes = []
	for node in target_nodes:
		if NodeUtils.validate_node3d(node):
			valid_nodes.append(node)
	
	if valid_nodes.is_empty():
		PluginLogger.warning("TransformModeHandler", "No valid Node3D objects to transform")
		return {}
	
	# Store transform data for all nodes
	var original_transforms = {}
	for node in valid_nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
	
	# Calculate center position of all nodes for positioning reference
	var center_pos = get_transform_center(valid_nodes)
	
	if center_pos == Vector3.ZERO:
		PluginLogger.error("TransformModeHandler", "No nodes in tree to transform")
		return {}
	
	# Calculate each node's offset from the original center (store once, use every frame)
	var node_offsets = _calculate_node_offsets(valid_nodes, center_pos)
	
	var transform_data = {
		"target_nodes": valid_nodes,  # Array of nodes
		"original_transforms": original_transforms,  # Dictionary mapping node to original transform
		"original_center": center_pos,  # Store the original center position
		"node_offsets": node_offsets,  # Store each node's offset from original center
		"dock_reference": null,
		"accumulated_y_delta": 0.0,  # Track accumulated height adjustments
		"undo_redo": undo_redo  # Store undo/redo manager
	}
	
	# Initialize managers for transform mode
	OverlayManager.initialize_overlays()
	OverlayManager.set_mode(2)  # TRANSFORM mode (compatible with both old and new enum)
	
	# Configure smooth transformations (get current settings)
	var current_settings = settings if not settings.is_empty() else SettingsManager.get_combined_settings()
	var smooth_enabled = current_settings.get("smooth_transforms", true)
	var smooth_speed = current_settings.get("smooth_transform_speed", 8.0)
	SmoothTransformManager.configure(smooth_enabled, smooth_speed)
	RotationManager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	ScaleManager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	
	# Register all target nodes for smooth transforms
	for node in valid_nodes:
		if node and node.is_inside_tree():
			SmoothTransformManager.register_object(node)
			# Ensure smooth transform targets are initialized to current transform
			SmoothTransformManager.apply_transform_immediately(
				node,
				node.global_position,
				node.rotation,
				node.scale
			)
	
	# Initialize position manager with center position
	if transform_state:
		PositionManager.set_position(transform_state, center_pos)
		PositionManager.start_transform_positioning(transform_state, valid_nodes[0])  # Use first node as reference
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started transform mode with " + str(valid_nodes.size()) + " node(s)")
	
	return transform_data

static func exit_transform_mode(
	transform_data: Dictionary,
	transform_state: TransformState,
	confirm_changes: bool,
	settings: Dictionary
) -> void:
	"""Clean up transform mode and create undo action if confirming
	
	Args:
		transform_data: Transform data dictionary (contains undo_redo if available)
		transform_state: Transform state to reset
		confirm_changes: If false, restore original transforms; if true, create undo action
		settings: Settings dictionary for reset behavior
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	var undo_redo = transform_data.get("undo_redo")
	
	if not confirm_changes:
		# Restore original transforms if not confirming changes (CANCEL)
		for node in target_nodes:
			if node and original_transforms.has(node):
				node.transform = original_transforms[node]
	else:
		# Create undo/redo action if confirming changes (CONFIRM)
		if undo_redo and UndoRedoHelper.should_create_undo(confirm_changes):
			# Check if this is single or multiple object transformation
			if target_nodes.size() == 1:
				# Single object transform
				var node = target_nodes[0]
				if UndoRedoHelper.is_valid_for_undo(node) and original_transforms.has(node):
					var original = original_transforms[node]
					var new_transform = node.transform
					var success = UndoRedoHelper.create_transform_undo(
						undo_redo,
						node,
						original,
						new_transform,
						"Transform " + node.name
					)
					if not success:
						PluginLogger.warning("TransformModeHandler", "Failed to create undo action for single node transform")
			else:
				# Multiple object transform
				var success = UndoRedoHelper.create_multi_transform_undo(
					undo_redo,
					target_nodes,
					original_transforms,
					"Transform " + str(target_nodes.size()) + " objects"
				)
				if not success:
					PluginLogger.warning("TransformModeHandler", "Failed to create undo action for multi-node transform")
	
	# Unregister all target nodes from smooth transforms
	for node in target_nodes:
		if node and node.is_inside_tree():
			SmoothTransformManager.unregister_object(node)
	
	# Reset transforms based on user settings
	_reset_transforms_on_exit(transform_state, settings)
	
	# Hide and cleanup overlays
	OverlayManager.hide_transform_overlay()
	OverlayManager.set_mode(0)  # NONE mode (compatible with both old and new enum)
	OverlayManager.remove_grid_overlay()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited transform mode (confirmed: " + str(confirm_changes) + ")")

## INPUT PROCESSING

static func process_input(
	camera: Camera3D,
	transform_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary,
	delta: float
) -> void:
	"""Process input for transform mode
	
	Args:
		camera: The 3D camera for raycasting
		transform_data: Transform data dictionary
		transform_state: Current transform state
		settings: Current settings dictionary
		delta: Frame delta time
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty() or not camera:
		return
	
	var position_input = InputHandler.get_position_input()
	var rotation_input = InputHandler.get_rotation_input()
	var scale_input = InputHandler.get_scale_input()
	
	# Handle height adjustments
	_process_height_delta(position_input, transform_data, transform_state, settings)
	
	# Handle position adjustments (WASD-style movement)
	_process_position_input(camera, position_input, transform_state, settings)
	
	# Process scale input ONCE for the group (before applying to nodes)
	_process_scale_for_group(scale_input, transform_state, settings)
	
	# Set half-step mode based on configured fine increment modifier
	PositionManager.use_half_step = position_input.fine_increment_modifier_held
	
	# Get stored original center and node offsets
	var original_center = transform_data.get("original_center", Vector3.ZERO)
	var node_offsets = transform_data.get("node_offsets", {})
	
	# Update position from mouse (with snapping if enabled)
	# IMPORTANT: Pass target_nodes as exclusions to prevent self-collision
	PositionManager.update_position_from_mouse(transform_state, camera, position_input.mouse_position, 1, false, target_nodes)
	var new_center = PositionManager.get_current_position(transform_state)
	
	# Update surface normal alignment if enabled
	if settings.get("align_with_normal", false):
		RotationManager.align_with_surface_normal(transform_state, PositionManager.get_surface_normal(transform_state))
	else:
		RotationManager.reset_surface_alignment(transform_state)
	
	# Handle rotation input - process ONCE for all nodes to avoid accumulation
	var rotation_applied = _process_rotation_for_group(rotation_input, transform_data, transform_state, settings)
	
	# Apply transformations to ALL nodes using offset-based system
	_apply_group_transformation(transform_data, transform_state, new_center, original_center, settings, rotation_applied)
	
	# Handle transform confirmation - return true to signal coordinator to exit with confirmation
	if position_input.confirm_action:
		# Return special value to signal confirmation
		transform_data["_confirm_exit"] = true
	
	# Update overlays with current state (use first node as reference)
	if target_nodes.size() > 0 and target_nodes[0]:
		update_overlays(transform_data)

## INPUT HELPERS

static func _process_height_delta(
	position_input: Dictionary,
	transform_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process height adjustment input and update accumulated delta
	
	Args:
		position_input: Position input dictionary from InputHandler
		transform_data: Transform data dictionary (modified)
		transform_state: Transform state
		settings: Settings dictionary
	"""
	var reverse_height = position_input.reverse_modifier_held
	
	# Determine height step based on modifiers
	var height_step = PositionManager.height_step_size
	
	# Apply Y snap step if Y snapping is enabled
	if transform_state.snap_y_enabled:
		height_step = transform_state.snap_y_step
	
	# Apply modifier keys for increment size
	if position_input.fine_increment_modifier_held:
		height_step *= 0.1
	elif position_input.large_increment_modifier_held:
		height_step *= 10.0
	
	var accumulated_y_delta = transform_data.get("accumulated_y_delta", 0.0)
	
	if position_input.height_up_pressed:
		var height_change = height_step if not reverse_height else -height_step
		accumulated_y_delta += height_change
	elif position_input.height_down_pressed:
		var height_change = -height_step if not reverse_height else height_step
		accumulated_y_delta += height_change
	elif position_input.reset_height_pressed:
		accumulated_y_delta = 0.0
	
	# Store back to transform_data
	transform_data["accumulated_y_delta"] = accumulated_y_delta

static func _process_position_input(
	camera: Camera3D,
	position_input: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process WASD position adjustment input
	
	Args:
		camera: Camera for calculating relative directions
		position_input: Position input dictionary from InputHandler
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	var position_delta = settings.get("position_increment", 0.1)
	if position_input.fine_increment_modifier_held:
		position_delta = settings.get("fine_position_increment", 0.01)
	elif position_input.large_increment_modifier_held:
		position_delta = settings.get("large_position_increment", 1.0)
	
	# Get camera-relative directions snapped to nearest axis
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
	
	# Handle position adjustments - use transform_state.manual_position_offset
	if position_input.position_left_pressed:
		transform_state.manual_position_offset -= camera_right * position_delta
	elif position_input.position_right_pressed:
		transform_state.manual_position_offset += camera_right * position_delta
	
	if position_input.position_forward_pressed:
		transform_state.manual_position_offset += camera_forward * position_delta
	elif position_input.position_backward_pressed:
		transform_state.manual_position_offset -= camera_forward * position_delta
	
	# Handle position reset
	if position_input.reset_position_pressed:
		PositionManager.reset_position(transform_state)

static func _process_scale_for_group(
	scale_input: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process scale input for the entire group (once per frame)
	
	Args:
		scale_input: Scale input dictionary from InputHandler
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	# Determine which increment to use based on modifiers
	var scale_step: float
	if scale_input.large_increment_modifier_held:
		scale_step = settings.get("large_scale_increment", 0.5)
	elif scale_input.fine_increment_modifier_held:
		scale_step = settings.get("fine_scale_increment", 0.01)
	else:
		scale_step = settings.get("scale_increment", 0.1)
	
	# Update the scale multiplier in transform_state
	if scale_input.up_pressed:
		ScaleManager.increase_scale(transform_state, scale_step)
	elif scale_input.down_pressed:
		ScaleManager.decrease_scale(transform_state, scale_step)
	elif scale_input.reset_pressed:
		ScaleManager.reset_scale(transform_state)

static func _process_rotation_for_group(
	rotation_input: Dictionary,
	transform_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> bool:
	"""Process rotation input for the entire group
	
	Args:
		rotation_input: Rotation input dictionary from InputHandler
		transform_data: Transform data dictionary
		transform_state: Transform state to modify
		settings: Settings dictionary
		
	Returns:
		bool: True if rotation was applied, False otherwise
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	
	if target_nodes.is_empty():
		return false
	
	var first_node = target_nodes[0]
	if not first_node or not first_node.is_inside_tree():
		return false
	
	# Determine which increment to use based on modifiers
	var rotation_step: float
	if rotation_input.large_increment_modifier_held:
		rotation_step = settings.get("large_rotation_increment", 90.0)
	elif rotation_input.fine_increment_modifier_held:
		rotation_step = settings.get("fine_rotation_increment", 5.0)
	else:
		rotation_step = settings.get("rotation_increment", 15.0)
	
	# Apply reverse modifier
	if rotation_input.reverse_modifier_held:
		rotation_step = -rotation_step
	
	var first_original_rotation = original_transforms.get(first_node, Transform3D()).basis.get_euler()
	
	if rotation_input.x_pressed:
		RotationManager.apply_rotation_step(transform_state, first_node, "X", rotation_step, first_original_rotation, false)
		return true
	elif rotation_input.y_pressed:
		RotationManager.apply_rotation_step(transform_state, first_node, "Y", rotation_step, first_original_rotation, false)
		return true
	elif rotation_input.z_pressed:
		RotationManager.apply_rotation_step(transform_state, first_node, "Z", rotation_step, first_original_rotation, false)
		return true
	elif rotation_input.reset_pressed:
		RotationManager.reset_node_rotation(first_node)
		return true
	
	return false

## GROUP TRANSFORMATION

static func _apply_group_transformation(
	transform_data: Dictionary,
	transform_state: TransformState,
	new_center: Vector3,
	original_center: Vector3,
	settings: Dictionary,
	rotation_applied: bool
) -> void:
	"""Apply transformation to all nodes in the group
	
	Args:
		transform_data: Transform data dictionary
		transform_state: Transform state
		new_center: New center position from mouse/snapping
		original_center: Original center position when transform mode started
		settings: Settings dictionary
		rotation_applied: Whether rotation was applied this frame
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	var node_offsets = transform_data.get("node_offsets", {})
	var original_transforms = transform_data.get("original_transforms", {})
	var accumulated_y_delta = transform_data.get("accumulated_y_delta", 0.0)
	
	# Get the current rotation offset for group rotation around center
	var rotation_offset_euler = RotationManager.get_rotation_offset(transform_state)
	var rotation_basis = Basis.from_euler(rotation_offset_euler)
	
	# Check if smooth transforms are enabled
	var smooth_enabled = settings.get("smooth_transforms", true)
	
	# Apply transformations to ALL nodes using offset-based system
	for node in target_nodes:
		if not node or not node.is_inside_tree():
			continue
		
		# Get this node's original offset from center
		var original_offset = node_offsets.get(node, Vector3.ZERO)
		
		# STEP 1: Group Rotation - Rotate the node's position around the collective center
		var rotated_offset = rotation_basis * original_offset
		
		# STEP 2: Position - Base position + rotation orbit offset
		var target_position = Vector3()
		target_position.x = new_center.x + rotated_offset.x
		target_position.z = new_center.z + rotated_offset.z
		
		# Y position: follows ground or maintains original height
		if settings.get("snap_to_ground", false):
			target_position.y = new_center.y + rotated_offset.y + accumulated_y_delta
		else:
			target_position.y = original_center.y + rotated_offset.y + accumulated_y_delta
		
		# Apply position with or without smoothing
		if smooth_enabled:
			SmoothTransformManager.set_target_position(node, target_position)
		else:
			node.global_position = target_position
		
		# STEP 3: Individual Rotation - Apply rotation offset to node's original rotation
		if rotation_applied:
			var node_original_rotation = original_transforms.get(node, Transform3D()).basis.get_euler()
			RotationManager.apply_rotation_to_node(transform_state, node, node_original_rotation)
	
	# STEP 4: Scale - Apply scale multiplier to node's original scale
	for node in target_nodes:
		if node and node.is_inside_tree():
			var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
			_apply_scale_to_node(node, transform_state, node_original_scale, settings)

static func _apply_scale_to_node(
	node: Node3D,
	transform_state: TransformState,
	original_scale: Vector3,
	settings: Dictionary
) -> void:
	"""Apply the current scale multiplier to a single node
	
	Args:
		node: The node to scale
		transform_state: Transform state containing scale multiplier
		original_scale: Original scale of the node
		settings: Settings dictionary
	"""
	# Simply apply the current scale multiplier to the node
	# The scale multiplier has already been updated by _process_scale_for_group()
	ScaleManager.apply_uniform_scale_to_node(transform_state, node, original_scale)

## STATE HELPERS

static func get_transform_center(target_nodes: Array) -> Vector3:
	"""Calculate the center position of all target nodes
	
	Args:
		target_nodes: Array of Node3D objects
		
	Returns:
		Vector3: The center position of all valid nodes in tree
	"""
	var center = Vector3.ZERO
	var node_count = 0
	
	for node in target_nodes:
		if is_instance_valid(node) and node.is_inside_tree():
			center += node.global_position
			node_count += 1
	
	if node_count > 0:
		center /= node_count
	
	return center

static func capture_original_state(nodes: Array) -> Dictionary:
	"""Capture original transforms of all nodes
	
	Args:
		nodes: Array of Node3D objects
		
	Returns:
		Dictionary: Mapping of node -> original Transform3D
	"""
	var original_transforms = {}
	for node in nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
	return original_transforms

static func restore_original_state(transform_data: Dictionary) -> void:
	"""Restore all nodes to their original transforms
	
	Args:
		transform_data: Transform data dictionary
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	
	for node in target_nodes:
		if node and original_transforms.has(node):
			node.transform = original_transforms[node]

static func _calculate_node_offsets(nodes: Array, center: Vector3) -> Dictionary:
	"""Calculate each node's offset from the center
	
	Args:
		nodes: Array of Node3D objects
		center: Center position
		
	Returns:
		Dictionary: Mapping of node -> offset Vector3
	"""
	var offsets = {}
	for node in nodes:
		if node and node.is_inside_tree():
			offsets[node] = node.global_position - center
	return offsets

## OVERLAY UPDATE

static func update_overlays(transform_data: Dictionary) -> void:
	"""Update all overlays for transform mode
	
	Args:
		transform_data: Transform data dictionary
	"""
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	
	var target_node = target_nodes[0]
	if not target_node or not target_node.is_inside_tree():
		return
	
	OverlayManager.show_transform_overlay(
		2,  # TRANSFORM mode (compatible with both old and new enum)
		target_node.name,
		target_node.global_position,
		target_node.rotation,
		target_node.scale.x  # Assuming uniform scale
	)

## RESET MANAGEMENT

static func _reset_transforms_on_exit(transform_state: TransformState, settings: Dictionary) -> void:
	"""Reset transforms based on user settings when exiting transform mode
	
	Args:
		transform_state: Transform state to reset
		settings: Settings dictionary containing reset preferences
	"""
	if not transform_state:
		return
	
	# Reset height offset if enabled
	if settings.get("reset_height_on_exit", false):
		PositionManager.reset_height(transform_state)
	
	# Reset position offset if enabled
	if settings.get("reset_position_on_exit", false):
		PositionManager.reset_position(transform_state)
	
	# Reset scale if enabled
	if settings.get("reset_scale_on_exit", false):
		ScaleManager.reset_scale(transform_state)
	
	# Reset rotation if enabled
	if settings.get("reset_rotation_on_exit", false):
		RotationManager.reset_rotation(transform_state)
	
	# Always reset surface alignment when exiting modes
	RotationManager.reset_surface_alignment(transform_state)
