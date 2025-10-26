@tool
extends RefCounted

class_name TransformModeController

"""
TRANSFORM MODE CONTROLLER
=========================

PURPOSE: Handle all transform mode operations (modifying existing nodes)

RESPONSIBILITIES:
- Start/exit transform mode
- Configure managers for node transformation
- Process transform input (WASD/QE, rotation, scale)
- Handle transform confirmation/cancellation
- Update node transforms with undo/redo support

ARCHITECTURE: Focused controller extracted from TransformationCoordinator
- Single responsibility: transform mode
- Clean separation from placement mode
- No legacy code or backwards compatibility

USED BY: TransformationCoordinator (delegates transform operations)
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const TransformInputController = preload("res://addons/simpleassetplacer/core/transform_input_controller.gd")
const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")

var _services  # ServiceRegistry
var _input_controller: TransformInputController

func _init(services) -> void:
	_services = services
	_input_controller = TransformInputController.new(services)

## Mode Lifecycle

func start(target_nodes: Variant, dock_instance, state: TransformState) -> void:
	"""Start transform mode for the given nodes"""
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.TRANSFORM):
		return
	
	# Reset control mode when entering transform
	if _services.control_mode_state:
		_services.control_mode_state.reset()
	
	# Initialize session
	var settings = _services.settings_manager.get_combined_settings()
	state.begin_session(ModeStateMachine.Mode.TRANSFORM, settings)
	state.dock_reference = dock_instance
	
	# Validate and filter nodes
	var nodes_array = target_nodes if target_nodes is Array else [target_nodes] if target_nodes is Node3D else []
	if nodes_array.is_empty():
		return
	
	var valid_nodes = []
	for node in nodes_array:
		if node is Node3D and node.is_inside_tree():
			valid_nodes.append(node)
	
	if valid_nodes.is_empty():
		PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, "No valid Node3D objects to transform")
		return
	
	# Store original transforms
	var original_transforms = {}
	var original_rotations = {}
	for node in valid_nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
			original_rotations[node] = node.rotation
	
	# Calculate center position
	var center_pos = _calculate_center(valid_nodes)
	
	# Initialize plane strategy
	if _services.placement_strategy_service:
		_services.placement_strategy_service.initialize_plane_from_position(center_pos)
		var plane_normal = _services.placement_strategy_service.get_current_plane_normal()
		if plane_normal != Vector3.ZERO:
			state.values.surface_normal = plane_normal
	
	# Configure position manager
	_services.position_manager.configure(state, settings)
	
	# Apply initial grid snap
	var snapped_center = center_pos
	if state.snap.snap_enabled or state.snap.snap_y_enabled:
		snapped_center = TransformApplicator.apply_grid_snap(center_pos, state, false)
	
	# Calculate node offsets from snapped center
	var node_offsets = {}
	for node in valid_nodes:
		if node.is_inside_tree():
			node_offsets[node] = node.global_position - snapped_center
	
	# Initialize transform state
	state.values.position = snapped_center
	state.values.base_position = snapped_center
	state.values.manual_position_offset = Vector3.ZERO
	state.values.manual_rotation_offset = Vector3.ZERO
	state.values.surface_alignment_rotation = Vector3.ZERO
	_services.transform_operations.reset_scale(state)
	
	# Store transform data
	state.session.transform_data = {
		"target_nodes": valid_nodes,
		"original_transforms": original_transforms,
		"original_rotations": original_rotations,
		"center_position": snapped_center,
		"original_center": center_pos,
		"node_offsets": node_offsets,
		"settings": settings,
		"dock_reference": dock_instance,
		"undo_redo": _services.undo_redo
	}
	
	# Apply initial snap if needed
	if snapped_center != center_pos:
		update_node_transforms(state)
	
	# Register nodes with smooth transform manager
	if _services.smooth_transform_manager:
		for node in valid_nodes:
			_services.smooth_transform_manager.register_object(node)
	
	# Initialize overlays
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.TRANSFORM)
	
	_services.grid_manager.reset_tracking()
	state.session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started transform mode for %d node(s)" % valid_nodes.size())

func exit(confirm_changes: bool, state: TransformState) -> void:
	"""Exit transform mode and either confirm or cancel changes"""
	if not _services.mode_state_machine.is_transform_mode():
		return
	
	# Unregister nodes from smooth transform manager
	if state.session.transform_data and state.session.transform_data.has("target_nodes"):
		var nodes = state.session.transform_data["target_nodes"]
		if _services.smooth_transform_manager:
			for node in nodes:
				if node and is_instance_valid(node):
					_services.smooth_transform_manager.unregister_object(node)
	
	# Commit or revert changes
	if confirm_changes:
		_register_undo(state)
	else:
		_restore_original_transforms(state)
	
	# Reset transforms based on settings
	_reset_transforms_on_exit(state)
	
	# Cleanup overlays
	_services.overlay_manager.hide_transform_overlay()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.NONE)
	_services.overlay_manager.remove_grid_overlay()
	
	_services.mode_state_machine.clear_mode()
	state.end_session()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited transform mode")

## Input Processing

func process_input(camera: Camera3D, state: TransformState, settings: Dictionary, delta: float) -> void:
	"""Process all transform mode input (WASD/QE, rotation, scale)"""
	if not state or not camera:
		return
	
	if not state.session.transform_data or not state.session.transform_data.has("target_nodes"):
		return
	
	var nodes: Array = state.session.transform_data["target_nodes"]
	if nodes.is_empty():
		return
	
	# Process keyboard input through shared controller
	var changes = _input_controller.process_keyboard_input(camera, state, settings)
	
	# Check for exit confirmation
	if changes.get("confirm_action", false):
		state.session.transform_data["_confirm_exit"] = true
	
	# Handle scale reset (Home key)
	if changes.get("scale_reset", false):
		_reset_node_scales(nodes, state)

func update_node_transforms(state: TransformState) -> void:
	"""Apply current state transforms to the target nodes"""
	if not state.session.transform_data or not state.session.transform_data.has("target_nodes"):
		return
	
	var nodes: Array = state.session.transform_data["target_nodes"]
	var center_position: Vector3 = state.session.transform_data.get("center_position", state.values.position)
	var node_offsets: Dictionary = state.session.transform_data.get("node_offsets", {})
	var original_transforms: Dictionary = state.session.transform_data.get("original_transforms", {})
	var original_rotations: Dictionary = state.session.transform_data.get("original_rotations", {})
	
	# Calculate rotation basis for group rotation around center
	var rotation_basis = Basis.from_euler(state.values.manual_rotation_offset)
	
	# Apply transforms to each node
	for node in nodes:
		if not node or not node.is_inside_tree():
			continue
		
		# Get node's original offset from center
		var offset = node_offsets.get(node, Vector3.ZERO)
		
		# STEP 1: Group Rotation - Rotate the offset around the center
		# This makes nodes orbit around the collective center when rotating
		var rotated_offset = rotation_basis * offset
		
		# STEP 2: Calculate new position - center + rotated offset + manual position offset
		var new_position = center_position + rotated_offset + state.values.manual_position_offset
		
		# STEP 3: Calculate rotation - original + manual offset
		# Each node keeps its original rotation and adds the manual rotation
		var original_rotation = original_rotations.get(node, Vector3.ZERO)
		var new_rotation = original_rotation + state.values.manual_rotation_offset
		
		# STEP 4: Calculate scale - original + scale offset
		var original_transform = original_transforms.get(node, Transform3D())
		var original_scale = original_transform.basis.get_scale()
		var scale_offset = state.get_scale_vector() - Vector3.ONE
		var new_scale = original_scale + scale_offset
		
		# Apply through smooth transform manager
		if _services.smooth_transform_manager:
			var current_target_pos = _services.smooth_transform_manager.get_target_position(node)
			var current_target_rot = _services.smooth_transform_manager.get_target_rotation(node)
			var current_target_scale = _services.smooth_transform_manager.get_target_scale(node)
			
			var pos_changed = current_target_pos.distance_squared_to(new_position) > 0.00001
			var rot_changed = current_target_rot.distance_squared_to(new_rotation) > 0.00001
			var scale_changed = current_target_scale.distance_squared_to(new_scale) > 0.00001
			
			if pos_changed or rot_changed or scale_changed:
				_services.smooth_transform_manager.set_target_transform(node, new_position, new_rotation, new_scale)
		else:
			# Fallback: apply directly
			node.global_position = new_position
			node.rotation = new_rotation
			node.scale = new_scale

## Helper Methods

func _calculate_center(nodes: Array) -> Vector3:
	"""Calculate the center point of all nodes"""
	if nodes.is_empty():
		return Vector3.ZERO
	
	var center = Vector3.ZERO
	for node in nodes:
		if node is Node3D:
			center += node.global_position
	
	return center / nodes.size()

func _reset_node_scales(nodes: Array, state: TransformState) -> void:
	"""Reset all node scales to original"""
	var original_transforms = state.session.transform_data.get("original_transforms", {})
	for node in nodes:
		if not node or not node.is_inside_tree():
			continue
		if original_transforms.has(node):
			var original_scale = original_transforms[node].basis.get_scale()
			node.scale = original_scale

func _register_undo(state: TransformState) -> void:
	"""Register undo/redo action for transform changes"""
	if not state.session.transform_data:
		return
	
	var nodes: Array = state.session.transform_data.get("target_nodes", [])
	var original_transforms: Dictionary = state.session.transform_data.get("original_transforms", {})
	
	if nodes.is_empty() or not _services.undo_redo:
		return
	
	# Capture current transforms
	var current_transforms = {}
	for node in nodes:
		if node is Node3D:
			current_transforms[node] = node.global_transform
	
	# Check if anything changed
	var has_changes = false
	for node in nodes:
		if _transforms_different(original_transforms[node], current_transforms[node]):
			has_changes = true
			break
	
	if not has_changes:
		return
	
	# Create undo/redo action
	_services.undo_redo.create_action("Transform Nodes")
	
	for node in nodes:
		if not node is Node3D:
			continue
		_services.undo_redo.add_do_property(node, "global_transform", current_transforms[node])
		_services.undo_redo.add_undo_property(node, "global_transform", original_transforms[node])
	
	_services.undo_redo.commit_action()

func _restore_original_transforms(state: TransformState) -> void:
	"""Restore all nodes to original transforms"""
	if not state.session.transform_data:
		return
	
	var nodes: Array = state.session.transform_data.get("target_nodes", [])
	var original_transforms: Dictionary = state.session.transform_data.get("original_transforms", {})
	
	for node in nodes:
		if node is Node3D and original_transforms.has(node):
			node.global_transform = original_transforms[node]

func _transforms_different(a: Transform3D, b: Transform3D) -> bool:
	"""Check if two transforms are different"""
	const EPSILON = 0.0001
	return not (
		a.origin.distance_to(b.origin) < EPSILON and
		a.basis.x.distance_to(b.basis.x) < EPSILON and
		a.basis.y.distance_to(b.basis.y) < EPSILON and
		a.basis.z.distance_to(b.basis.z) < EPSILON
	)

func _reset_transforms_on_exit(state: TransformState) -> void:
	"""Reset transformations based on settings when exiting"""
	var settings = state.settings
	if settings.is_empty():
		return
	
	if settings.get("reset_height_on_exit", false):
		_services.position_manager.reset_offset_normal(state)
	
	if settings.get("reset_rotation_on_exit", false):
		_services.rotation_manager.reset_all_rotation(state)
	
	if settings.get("reset_scale_on_exit", false):
		_services.scale_manager.reset_scale(state)
	
	if settings.get("reset_position_on_exit", false):
		state.values.manual_position_offset = Vector3.ZERO
	
	if state.session.transform_data:
		state.session.transform_data.clear()
