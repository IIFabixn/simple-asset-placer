@tool
extends RefCounted

class_name TransformationCoordinator

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const EditorFacade = preload("res://addons/simpleassetplacer/core/editor_facade.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const GridManager = preload("res://addons/simpleassetplacer/managers/grid_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")
const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")

var _services: ServiceRegistry
var _transform_state: TransformState
var _placement_service: PlacementStrategyService

func _init(services: ServiceRegistry) -> void:
	_services = services
	_transform_state = TransformState.new()
	if services and services.placement_strategy_service:
		_placement_service = services.placement_strategy_service
	else:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()


func _state() -> TransformState:
	"""Get or create unified state"""
	if not _transform_state:
		_transform_state = TransformState.new()
	return _transform_state


func _current_settings() -> Dictionary:
	var settings = _state().settings
	if settings.is_empty():
		return _services.settings_manager.get_combined_settings()
	return settings

func start_placement_mode(mesh: Mesh, meshlib, item_id, asset_path, placement_settings, dock_instance = null) -> void:
	exit_any_mode()
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.PLACEMENT):
		return

	# Reset control mode (deactivate modal) when entering placement mode
	if _services.control_mode_state:
		_services.control_mode_state.reset()

	var state := _state()
	state.begin_session(ModeStateMachine.Mode.PLACEMENT, placement_settings)
	state.dock_reference = dock_instance

	_ensure_undo_redo()
	
	# Initialize placement data
	state.session.placement_data = {
		"mesh": mesh,
		"meshlib": meshlib,
		"item_id": item_id,
		"asset_path": asset_path,
		"settings": placement_settings,
		"dock_reference": dock_instance,
		"undo_redo": _services.undo_redo
	}
	
	# Initialize overlays
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.PLACEMENT)
	
	# Setup preview mesh
	if mesh:
		_services.preview_manager.start_preview_mesh(mesh, placement_settings)
	elif meshlib and item_id >= 0:
		var preview_mesh = meshlib.get_item_mesh(item_id)
		if preview_mesh:
			_services.preview_manager.start_preview_mesh(preview_mesh, placement_settings)
	elif asset_path != "":
		_services.preview_manager.start_preview_asset(asset_path, placement_settings)
	
	# Configure managers
	_services.position_manager.configure(state, placement_settings)
	
	var smooth_enabled = placement_settings.get("smooth_transforms", true)
	var smooth_speed = placement_settings.get("smooth_transform_speed", 8.0)
	var smooth_config = {"smooth_enabled": smooth_enabled, "smooth_speed": smooth_speed}
	
	_services.preview_manager.configure(smooth_config)
	_services.smooth_transform_manager.configure(smooth_enabled, smooth_speed)
	_services.rotation_manager.configure(state, smooth_config)
	
	# Reset for new placement
	var reset_height = placement_settings.get("reset_height_on_exit", false)
	var reset_position = placement_settings.get("reset_position_on_exit", false)
	_services.position_manager.reset_for_new_placement(state, reset_height, reset_position)
	
	if not placement_settings.get("keep_rotation_between_placements", false):
		_services.rotation_manager.reset_all_rotation(state)

	# Initialize plane strategy for placement mode (starts at Y=0)
	if _services.placement_strategy_service:
		_services.placement_strategy_service.initialize_plane_for_placement()

	_services.grid_manager.reset_tracking()
	state.session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started placement mode")

func start_transform_mode(target_nodes: Variant, dock_instance = null) -> void:
	exit_any_mode()
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.TRANSFORM):
		return

	# Reset control mode (deactivate modal) when entering transform mode
	if _services.control_mode_state:
		_services.control_mode_state.reset()

	var combined_settings = _services.settings_manager.get_combined_settings()
	var state := _state()
	state.begin_session(ModeStateMachine.Mode.TRANSFORM, combined_settings)
	state.dock_reference = dock_instance

	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Transform mode settings loaded | snap_enabled:%s snap_step:%s snap_rot:%s step:%s snap_scale:%s step:%s" % [
		state.snap.snap_enabled,
		state.snap.snap_step,
		state.snap.snap_rotation_enabled,
		state.snap.snap_rotation_step,
		state.snap.snap_scale_enabled,
		state.snap.snap_scale_step
	])
	_ensure_undo_redo()
	
	# Validate and filter nodes
	var nodes_array = target_nodes if target_nodes is Array else [target_nodes] if target_nodes is Node3D else []
	if nodes_array.is_empty():
		return
	
	var valid_nodes = []
	for node in nodes_array:
		if node is Node3D and node.is_inside_tree():
			valid_nodes.append(node)
	
	if valid_nodes.is_empty():
		PluginLogger.warning("TransformationCoordinator", "No valid Node3D objects to transform")
		return
	
	# Store original transforms
	var original_transforms = {}
	var original_rotations = {}  # Store rotations separately to avoid euler conversion issues
	for node in valid_nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
			original_rotations[node] = node.rotation  # Store actual rotation directly
	
	# Calculate center position
	var center_pos = _calculate_transform_center(valid_nodes)
	
	# Initialize plane strategy
	if _services.placement_strategy_service:
		_services.placement_strategy_service.initialize_plane_from_position(center_pos)
		var plane_normal = _services.placement_strategy_service.get_current_plane_normal()
		if plane_normal != Vector3.ZERO:
			state.values.surface_normal = plane_normal
	
	# Configure position manager
	_services.position_manager.configure(state, combined_settings)
	
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
		"original_rotations": original_rotations,  # Store rotations separately
		"center_position": snapped_center,
		"original_center": center_pos,
		"node_offsets": node_offsets,
		"settings": combined_settings,
		"dock_reference": dock_instance,
		"undo_redo": _services.undo_redo
	}
	
	# Apply initial snap if needed
	if snapped_center != center_pos:
		_apply_transform_to_nodes(state)
	
	# Register nodes with smooth transform manager for interpolation
	if _services and _services.smooth_transform_manager:
		for node in valid_nodes:
			_services.smooth_transform_manager.register_object(node)
	
	# Initialize overlays
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.TRANSFORM)

	_services.grid_manager.reset_tracking()
	state.session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started transform mode for " + str(valid_nodes.size()) + " node(s)")

func exit_placement_mode() -> void:
	if not _services.mode_state_machine.is_placement_mode():
		return
	var state := _state()
	
	# Cleanup preview
	_services.preview_manager.cleanup_preview()
	
	# Call end callback if set
	if state.session.placement_end_callback.is_valid():
		state.session.placement_end_callback.call()
	
	# Reset transforms based on settings
	_reset_transforms_on_exit(state)
	
	# Cleanup overlays
	_services.overlay_manager.hide_transform_overlay()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.NONE)
	_services.overlay_manager.remove_grid_overlay()
	
	_services.mode_state_machine.clear_mode()
	state.end_session()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited placement mode")

func exit_transform_mode(confirm_changes: bool = true) -> void:
	if not _services.mode_state_machine.is_transform_mode():
		return
	var state := _state()
	
	# Unregister nodes from smooth transform manager
	if state.session.transform_data and state.session.transform_data.has("target_nodes"):
		var nodes = state.session.transform_data["target_nodes"]
		if _services and _services.smooth_transform_manager:
			for node in nodes:
				if node and is_instance_valid(node):
					_services.smooth_transform_manager.unregister_object(node)
	
	# Commit or revert changes
	if confirm_changes:
		_register_transform_undo(state)
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

func exit_any_mode() -> void:
	var mode = _services.mode_state_machine.get_current_mode()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			exit_placement_mode()
		ModeStateMachine.Mode.TRANSFORM:
			exit_transform_mode(false)

func reset_transforms() -> void:
	"""Reset all transform offsets (rotation, scale, height, position)"""
	var state := _state()
	if not state:
		return

	var mode = _services.mode_state_machine.get_current_mode()

	if mode == ModeStateMachine.Mode.PLACEMENT:
		# Reset rotation
		_services.rotation_manager.reset_all_rotation(state)

		# Reset scale
		_services.scale_manager.reset_scale(state)

		# Reset offset along plane normal
		_services.position_manager.reset_offset_normal(state)

		# Reset manual position offset
		state.values.manual_position_offset = Vector3.ZERO

		# Show feedback
		if _services.overlay_manager:
			_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)

	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = state.session.transform_data
		var target_nodes = transform_payload.get("target_nodes", [])
		var original_transforms = transform_payload.get("original_transforms", {})

		# Reset rotation, scale, and update smooth transforms for all nodes
		for node in target_nodes:
			if node and node.is_inside_tree():
				# Reset rotation
				_services.rotation_manager.reset_node_rotation(node)

				# Reset scale to original
				var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
				node.scale = node_original_scale

				# Update smooth transform manager to prevent re-applying old targets
				_services.smooth_transform_manager.apply_transform_immediately(
					node,
					node.global_position,
					node.rotation,
					node.scale
				)

		# Reset scale state
		_services.scale_manager.reset_scale(state)

		# Reset offset along plane normal
		_services.position_manager.reset_offset_normal(state)

		# Reset manual position offset
		transform_payload["manual_position_offset"] = Vector3.ZERO

		# Update center position from base_position
		var center_pos = state.values.base_position
		state.values.position = center_pos
		transform_payload["center_position"] = center_pos

		# Show feedback
		if _services.overlay_manager:
			_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)

func process_frame_input(camera: Camera3D, input_settings: Dictionary = {}, delta: float = 1.0/60.0) -> void:
	if not camera or not is_instance_valid(camera):
		return
	
	var state := _state()
	
	# Update settings
	var previous_settings: Dictionary = {}
	if state.settings is Dictionary:
		previous_settings = state.settings.duplicate(true)
	
	if not input_settings.is_empty():
		state.settings = input_settings.duplicate(true)
	
	# Get viewport for input handling
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	# Update input state
	_services.input_handler.update_input_state(input_settings, viewport_3d)
	
	# Check UI focus
	var focus_owner: Control = get_current_focus_owner() if has_method("get_current_focus_owner") else null
	var ui_focus_locked := should_lock_input_to_ui(focus_owner) if has_method("should_lock_input_to_ui") else false
	state.session.ui_focus_locked = ui_focus_locked
	
	# Process navigation input (asset cycling, etc.)
	if _services and _services.input_handler:
		var nav_input = _services.input_handler.get_navigation_input()
		_process_navigation_input(nav_input, ui_focus_locked, focus_owner)
	
	# Get combined settings
	var combined_source = _services.settings_manager.get_combined_settings()
	var combined_settings = combined_source.duplicate(true)
	var settings_changed = previous_settings != combined_settings
	state.settings = combined_settings
	
	# Increment frame counter
	state.session.frames_since_mode_start += 1
	var is_first_frame = state.session.frames_since_mode_start == 1
	
	# Configure state if settings changed or first frame
	if state and (settings_changed or is_first_frame):
		if is_first_frame:
			PluginLogger.debug("TransformationCoordinator", "First frame - forcing configuration with snap_enabled: %s" % combined_settings.get("snap_enabled"))
		state.configure_from_settings(combined_settings)
		# Also update position_manager configuration when settings change or on first frame
		_services.position_manager.configure(state, combined_settings)
	
	# Configure smooth transforms
	_configure_smooth_transforms(combined_settings)
	
	# Handle focus grabbing for initial frames
	if state.session.focus_grab_frames > 0:
		state.session.focus_grab_frames -= 1
		_grab_3d_viewport_focus()
	
	# Process mode-specific input (if UI not locked)
	var mode = _services.mode_state_machine.get_current_mode()
	if not ui_focus_locked:
		match mode:
			ModeStateMachine.Mode.PLACEMENT:
				_process_placement_input(camera, state, combined_settings, delta)
				# Apply position/rotation/scale to preview mesh
				_update_preview_transform(state)
				# Update overlay with current state
				_update_overlay_display(mode, state)
				# Check for exit request
				if state.session.placement_data.get("_confirm_exit", false):
					state.session.placement_data.erase("_confirm_exit")
					exit_placement_mode()
					return
			
			ModeStateMachine.Mode.TRANSFORM:
				_process_transform_input(camera, state, combined_settings, delta)
				# Apply transforms to target nodes
				_update_transform_nodes(state)
				# Update overlay with current state
				_update_overlay_display(mode, state)
				# Check for exit request
				if state.session.transform_data.get("_confirm_exit", false):
					state.session.transform_data.erase("_confirm_exit")
					exit_transform_mode(true)
					return
	
	# Update visual systems (smooth transforms and grid)
	if _services.smooth_transform_manager:
		_services.smooth_transform_manager.update_smooth_transforms(delta)
	
	if mode != ModeStateMachine.Mode.NONE:
		var placement_center = _services.position_manager.get_base_position(state) if state else Vector3.ZERO
		var target_nodes = state.session.transform_data.get("target_nodes", []) if mode == ModeStateMachine.Mode.TRANSFORM else []
		_services.grid_manager.update_grid_overlay(mode, combined_settings, state, placement_center, target_nodes)

func handle_mouse_wheel_input(event: InputEventMouseButton) -> bool:
	var wheel_input = _services.input_handler.get_mouse_wheel_input(event)
	if wheel_input.is_empty():
		return false
	match wheel_input.get("action"):
		"height":
			_apply_height_adjustment(wheel_input)
		"scale":
			_apply_scale_adjustment(wheel_input)
		"scale_axis":
			_apply_scale_axis_adjustment(wheel_input)
		"rotation":
			_apply_rotation_adjustment(wheel_input)
		"position":
			_apply_position_adjustment(wheel_input)
		"position_axis":
			_apply_position_axis_adjustment(wheel_input)
	return true

func handle_mouse_motion(camera: Camera3D, mouse_position: Vector2) -> void:
	"""Handle mouse motion to update preview/transform position"""
	if not camera:
		return
	
	var state := _state()
	if not state:
		return
	
	var mode = _services.mode_state_machine.get_current_mode()
	
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			# Update position from mouse for placement mode
			var old_pos = state.values.position
			var old_offset = state.values.manual_position_offset
			_services.position_manager.update_position_from_mouse(state, camera, mouse_position)
			var new_pos = state.values.position
			var new_offset = state.values.manual_position_offset
			
			# Debug: Log if position or offset changed
			if old_pos.distance_to(new_pos) > 0.01 or old_offset.distance_to(new_offset) > 0.001:
				PluginLogger.debug("TransformationCoordinator", 
					"Mouse motion: pos %s->%s, offset %s->%s" % [old_pos, new_pos, old_offset, new_offset])
			
			# Apply updated position to preview
			_update_preview_transform(state)
			# Update overlay display
			_update_overlay_display(mode, state)
			
		ModeStateMachine.Mode.TRANSFORM:
			# Update position from mouse for transform mode (with node exclusions)
			var target_nodes = state.session.transform_data.get("target_nodes", [])
			var old_position = state.values.position  # Store old position before update
			_services.position_manager.update_position_from_mouse(state, camera, mouse_position, 1, false, target_nodes)
			var new_position = state.values.position  # Get new position after update
			
			# Calculate delta and apply to center_position (preserves manual_position_offset)
			var position_delta = new_position - old_position
			var current_center = state.session.transform_data.get("center_position", Vector3.ZERO)
			state.session.transform_data["center_position"] = current_center + position_delta
			
			# Apply updated position to nodes
			_update_transform_nodes(state)
			# Update overlay display
			_update_overlay_display(mode, state)


func handle_tab_key_activation(dock_instance = null, ignore_focus_lock: bool = false) -> void:
	if _services.mode_state_machine.is_any_mode_active():
		return
	if not ignore_focus_lock and not _is_3d_context_focused():
		return
	var selection = _services.editor_facade.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	if selected_nodes.is_empty():
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "No node selected. Select a Node3D and press TAB.")
		return
	var target_node3ds = []
	for node in selected_nodes:
		if node is Node3D:
			target_node3ds.append(node)
	if target_node3ds.is_empty():
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Selected node is not a Node3D. Select a Node3D and press TAB.")
		return
	var first_node = target_node3ds[0]
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if current_scene and (first_node.is_ancestor_of(current_scene) or current_scene == first_node or first_node.is_inside_tree()):
		start_transform_mode(target_node3ds, dock_instance)
		if target_node3ds.size() == 1:
			_services.overlay_manager.show_status_message("Transform mode: " + first_node.name, Color.GREEN, 2.0)
		else:
			_services.overlay_manager.show_status_message("Transform mode: " + str(target_node3ds.size()) + " nodes", Color.GREEN, 2.0)
	else:
		start_placement_from_node3d(first_node, dock_instance)

func start_placement_from_node3d(node: Node3D, dock_instance = null) -> void:
	var extracted_mesh = _services.utility_manager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		var session_settings = _state().settings
		var placement_settings = session_settings if not session_settings.is_empty() else _services.settings_manager.get_combined_settings()
		start_placement_mode(extracted_mesh, null, -1, "", placement_settings, dock_instance)
		_services.overlay_manager.show_status_message("Placement mode activated for: " + node.name, Color.GREEN, 2.0)
	else:
		_services.overlay_manager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)

func is_any_mode_active() -> bool:
	return _services.mode_state_machine.is_any_mode_active()

func is_placement_mode() -> bool:
	return _services.mode_state_machine.is_placement_mode()

func is_transform_mode() -> bool:
	return _services.mode_state_machine.is_transform_mode()

func get_current_mode() -> int:
	return _services.mode_state_machine.get_current_mode()

func get_current_mode_string() -> String:
	return _services.mode_state_machine.get_current_mode_string()

func get_current_scale() -> float:
	var state := _state()
	if state:
		return _services.scale_manager.get_scale(state)
	return 1.0

func set_placement_end_callback(callback: Callable) -> void:
	_state().placement_end_callback = callback

func set_mesh_placed_callback(callback: Callable) -> void:
	_state().mesh_placed_callback = callback

func set_dock_reference(dock_instance) -> void:
	_state().dock_reference = dock_instance

func cleanup_all() -> void:
	exit_any_mode()
	_services.overlay_manager.cleanup_all_overlays()
	_services.preview_manager.cleanup_preview()
	_services.grid_manager.cleanup_grid()

func cleanup() -> void:
	cleanup_all()

func update_settings(new_settings: Dictionary) -> void:
	var state := _state()
	state.settings = new_settings.duplicate(true)

func _ensure_undo_redo() -> void:
	if not _services.undo_redo:
		_services.undo_redo = _services.editor_facade.get_editor_interface().get_editor_undo_redo()

func _configure_smooth_transforms(settings_dict: Dictionary) -> void:
	var smooth_enabled = settings_dict.get("smooth_transforms", true)
	var smooth_speed = settings_dict.get("smooth_transform_speed", 8.0)
	
	# Configure smooth transforms through the unified configure() method
	var smooth_config = {
		"smooth_enabled": smooth_enabled,
		"smooth_speed": smooth_speed
	}
	
	_services.preview_manager.configure(smooth_config)
	_services.smooth_transform_manager.configure(smooth_enabled, smooth_speed)
	var state := _state()
	var config_state := state if state else TransformState.new()
	_services.rotation_manager.configure(config_state, smooth_config)
	_services.scale_manager.configure(config_state, smooth_config)

func _process_placement_input(camera: Camera3D, state: TransformState, settings: Dictionary, delta: float) -> void:
	"""Process input for placement mode (WASD/QE movement, rotation, position updates)"""
	if not state or not camera:
		return
	
	# Get position input state
	var pos_input = _services.input_handler.get_position_input()
	
	# Process offset adjustments along plane normal (Q/E keys)
	if pos_input.height_up_pressed or pos_input.height_down_pressed:
		var step = settings.get("height_adjustment_step", 0.1)
		
		# Apply fine/large modifiers
		if pos_input.fine_increment_modifier_held:
			step = settings.get("fine_height_increment", 0.01)
		elif pos_input.large_increment_modifier_held:
			step = settings.get("large_height_increment", 1.0)
		
		var delta_normal = 0.0
		if pos_input.height_up_pressed:
			delta_normal = step  # Discrete increment, not frame-dependent
		elif pos_input.height_down_pressed:
			delta_normal = -step
		
		if delta_normal != 0.0:
			_services.position_manager.adjust_offset_normal(state, delta_normal)
	
	# Process offset reset (R key)
	if pos_input.reset_height_pressed:
		_services.position_manager.reset_offset_normal(state)
	
	# Process WASD position movement
	var position_delta := Vector3.ZERO
	var position_step = settings.get("position_adjustment_step", 0.1)
	
	# Apply fine/large modifiers
	if pos_input.fine_increment_modifier_held:
		position_step = settings.get("fine_position_increment", 0.01)
	elif pos_input.large_increment_modifier_held:
		position_step = settings.get("large_position_increment", 1.0)
	
	# Calculate movement direction in camera space, snapped to world axes
	if pos_input.position_forward_pressed or pos_input.position_backward_pressed or \
	   pos_input.position_left_pressed or pos_input.position_right_pressed:
		
		var camera_forward = -camera.global_transform.basis.z
		var camera_right = camera.global_transform.basis.x
		
		# Project to XZ plane (remove vertical component)
		camera_forward.y = 0
		camera_right.y = 0
		camera_forward = camera_forward.normalized()
		camera_right = camera_right.normalized()
		
		# Snap to nearest world axis for pure axis-aligned movement
		# This ensures movement is always along X or Z axis, not at an angle
		if abs(camera_forward.z) > abs(camera_forward.x):
			camera_forward = Vector3(0, 0, sign(camera_forward.z))
		else:
			camera_forward = Vector3(sign(camera_forward.x), 0, 0)
		
		if abs(camera_right.x) > abs(camera_right.z):
			camera_right = Vector3(sign(camera_right.x), 0, 0)
		else:
			camera_right = Vector3(0, 0, sign(camera_right.z))
		
		if pos_input.position_forward_pressed:
			position_delta += camera_forward * position_step
		if pos_input.position_backward_pressed:
			position_delta -= camera_forward * position_step
		if pos_input.position_right_pressed:
			position_delta += camera_right * position_step
		if pos_input.position_left_pressed:
			position_delta -= camera_right * position_step
		
		# Apply position delta
		if position_delta.length_squared() > 0.0:
			_services.position_manager.apply_position_delta(state, position_delta)
	
	# Process position reset
	if pos_input.reset_position_pressed:
		_services.position_manager.reset_position(state)
	
	# Process rotation input (X/Y/Z keys)
	var rot_input = _services.input_handler.get_rotation_input()
	
	if rot_input.x_pressed or rot_input.y_pressed or rot_input.z_pressed:
		var rotation_step = settings.get("rotation_step", 15.0)  # degrees
		
		# Apply fine/large modifiers
		if rot_input.fine_increment_modifier_held:
			rotation_step = settings.get("fine_rotation_increment", 1.0)
		elif rot_input.large_increment_modifier_held:
			rotation_step = settings.get("large_rotation_increment", 45.0)
		
		# Apply reverse modifier
		if rot_input.reverse_modifier_held:
			rotation_step = -rotation_step
		
		# Apply rotation as discrete increment (not frame-dependent)
		if rot_input.x_pressed:
			_services.rotation_manager.rotate_x(state, rotation_step)
		if rot_input.y_pressed:
			_services.rotation_manager.rotate_y(state, rotation_step)
		if rot_input.z_pressed:
			_services.rotation_manager.rotate_z(state, rotation_step)
	
	# Process rotation reset (T key)
	if rot_input.reset_pressed:
		_services.rotation_manager.reset_all_rotation(state)
	
	# Process scale input (Page Up/Page Down keys)
	var scale_input = _services.input_handler.get_scale_input()
	
	if scale_input.up_pressed or scale_input.down_pressed:
		var scale_step = settings.get("scale_increment", 0.1)
		
		# Apply fine/large modifiers
		if scale_input.fine_increment_modifier_held:
			scale_step = settings.get("fine_scale_increment", 0.01)
		elif scale_input.large_increment_modifier_held:
			scale_step = settings.get("large_scale_increment", 0.5)
		
		# Apply scale as discrete increment (not frame-dependent)
		if scale_input.up_pressed:
			_services.scale_manager.increase_scale(state, scale_step)
		elif scale_input.down_pressed:
			_services.scale_manager.decrease_scale(state, scale_step)
	
	# Process scale reset (Home key)
	if scale_input.reset_pressed:
		_services.scale_manager.reset_scale(state)
	
	# Process placement confirmation
	if pos_input.confirm_action:
		# Trigger placement
		state.session.placement_data["_confirm_exit"] = true


func _process_transform_input(camera: Camera3D, state: TransformState, settings: Dictionary, delta: float) -> void:
	"""Process input for transform mode (WASD/QE movement for selected nodes)"""
	if not state or not camera:
		return
	
	if not state.session.transform_data or not state.session.transform_data.has("target_nodes"):
		return
	
	var nodes: Array = state.session.transform_data["target_nodes"]
	if nodes.is_empty():
		return
	
	# Get position input state
	var pos_input = _services.input_handler.get_position_input()
	
	# Get transform data
	var transform_data = state.session.transform_data
	var center_position: Vector3 = transform_data.get("center_position", state.values.position)
	
	# Process height adjustments (Q/E keys)
	if pos_input.height_up_pressed or pos_input.height_down_pressed:
		var step = settings.get("height_adjustment_step", 0.1)
		
		# Apply fine/large modifiers
		if pos_input.fine_increment_modifier_held:
			step = settings.get("fine_height_increment", 0.01)
		elif pos_input.large_increment_modifier_held:
			step = settings.get("large_height_increment", 1.0)
		
		var delta_height = 0.0
		if pos_input.height_up_pressed:
			delta_height = step  # Discrete increment, not frame-dependent
		elif pos_input.height_down_pressed:
			delta_height = -step
		
		if delta_height != 0.0:
			# Update center position height
			center_position.y += delta_height
			transform_data["center_position"] = center_position
			state.values.position = center_position
			state.values.base_position = center_position  # Update base position so plane tracking works
			
			# Update plane height so the plane follows the object's new height
			if _services.placement_strategy_service:
				_services.placement_strategy_service.update_plane_height(center_position)
	
	# Process WASD position movement
	var position_delta := Vector3.ZERO
	var position_step = settings.get("position_adjustment_step", 0.1)
	
	# Apply fine/large modifiers
	if pos_input.fine_increment_modifier_held:
		position_step = settings.get("fine_position_increment", 0.01)
	elif pos_input.large_increment_modifier_held:
		position_step = settings.get("large_position_increment", 1.0)
	
	# Calculate movement direction in camera space, snapped to world axes
	if pos_input.position_forward_pressed or pos_input.position_backward_pressed or \
	   pos_input.position_left_pressed or pos_input.position_right_pressed:
		
		var camera_forward = -camera.global_transform.basis.z
		var camera_right = camera.global_transform.basis.x
		
		# Project to XZ plane
		camera_forward.y = 0
		camera_right.y = 0
		camera_forward = camera_forward.normalized()
		camera_right = camera_right.normalized()
		
		# Snap to nearest world axis for pure axis-aligned movement
		# This ensures movement is always along X or Z axis, not at an angle
		if abs(camera_forward.z) > abs(camera_forward.x):
			camera_forward = Vector3(0, 0, sign(camera_forward.z))
		else:
			camera_forward = Vector3(sign(camera_forward.x), 0, 0)
		
		if abs(camera_right.x) > abs(camera_right.z):
			camera_right = Vector3(sign(camera_right.x), 0, 0)
		else:
			camera_right = Vector3(0, 0, sign(camera_right.z))
		
		if pos_input.position_forward_pressed:
			position_delta += camera_forward * position_step
		if pos_input.position_backward_pressed:
			position_delta -= camera_forward * position_step
		if pos_input.position_right_pressed:
			position_delta += camera_right * position_step
		if pos_input.position_left_pressed:
			position_delta -= camera_right * position_step
		
		# Apply position delta to manual_position_offset (not center directly)
		# This ensures the offset is preserved when the mouse moves
		if position_delta.length_squared() > 0.0:
			state.values.manual_position_offset += position_delta
	
	# Process rotation input (X/Y/Z keys)
	var rot_input = _services.input_handler.get_rotation_input()
	
	if rot_input.x_pressed or rot_input.y_pressed or rot_input.z_pressed:
		var rotation_step = settings.get("rotation_step", 15.0)  # degrees
		
		# Apply fine/large modifiers
		if rot_input.fine_increment_modifier_held:
			rotation_step = settings.get("fine_rotation_increment", 1.0)
		elif rot_input.large_increment_modifier_held:
			rotation_step = settings.get("large_rotation_increment", 45.0)
		
		# Apply reverse modifier
		if rot_input.reverse_modifier_held:
			rotation_step = -rotation_step
		
		# Apply rotation to state (not directly to nodes)
		# The smooth transform system will handle the actual node rotation
		if rot_input.x_pressed:
			_services.rotation_manager.rotate_x(state, rotation_step)
		if rot_input.y_pressed:
			_services.rotation_manager.rotate_y(state, rotation_step)
		if rot_input.z_pressed:
			_services.rotation_manager.rotate_z(state, rotation_step)
	
	# Process rotation reset (T key)
	if rot_input.reset_pressed:
		# Reset rotation offset in state (not directly on nodes)
		state.values.manual_rotation_offset = Vector3.ZERO
	
	# Process scale input (Page Up/Page Down keys)
	var scale_input = _services.input_handler.get_scale_input()
	
	if scale_input.up_pressed or scale_input.down_pressed:
		var scale_step = settings.get("scale_increment", 0.1)
		
		# Apply fine/large modifiers
		if scale_input.fine_increment_modifier_held:
			scale_step = settings.get("fine_scale_increment", 0.01)
		elif scale_input.large_increment_modifier_held:
			scale_step = settings.get("large_scale_increment", 0.5)
		
		# Apply scale as discrete increment (not frame-dependent) to all nodes
		for node in nodes:
			if not node or not node.is_inside_tree():
				continue
			
			if scale_input.up_pressed:
				node.scale *= (1.0 + scale_step)
			elif scale_input.down_pressed:
				node.scale *= (1.0 - scale_step)
	
	# Process scale reset (Home key)
	if scale_input.reset_pressed:
		var original_transforms = transform_data.get("original_transforms", {})
		for node in nodes:
			if not node or not node.is_inside_tree():
				continue
			if original_transforms.has(node):
				var original_scale = original_transforms[node].basis.get_scale()
				node.scale = original_scale
	
	# Process exit confirmation
	if pos_input.confirm_action:
		# Trigger transform mode exit
		state.session.transform_data["_confirm_exit"] = true

func _process_navigation_input(nav_input_override = null, ui_locked: bool = false, focus_owner: Control = null) -> void:
	var input_handler = _services.input_handler if _services else null
	if not input_handler:
		return

	var nav_input = nav_input_override
	if nav_input == null:
		nav_input = input_handler.get_navigation_input()
	if nav_input == null:
		return

	# Allow cycling placement strategy in both PLACEMENT and TRANSFORM modes, even when UI is locked
	# (cycling doesn't interfere with text input and should always be available)
	if input_handler.should_cycle_placement_mode():
		if _services.mode_state_machine.is_any_mode_active():
			_cycle_placement_strategy()
	
	if ui_locked:
		if nav_input.tab_just_pressed and _is_focus_in_plugin_ui(focus_owner):
			handle_tab_key_activation(_state().dock_reference, true)
		return

	var control_state = _services.control_mode_state if _services else null

	if nav_input.tab_just_pressed:
		handle_tab_key_activation(_state().dock_reference)
	if nav_input.cancel_pressed:
		# Modal system removed - cancel just exits mode
		exit_any_mode()
		return

func _cycle_placement_strategy() -> void:
	var new_strategy = _get_service().cycle_strategy()
	var state := _state()
	var settings = state.settings
	if settings.is_empty():
		settings = _services.settings_manager.get_combined_settings().duplicate(true)
		settings["placement_strategy"] = new_strategy
		state.settings = settings
	else:
		settings["placement_strategy"] = new_strategy
	_services.settings_manager.update_dock_settings({"placement_strategy": new_strategy})
	if state.dock_reference and state.dock_reference.has_method("update_placement_strategy_ui"):
		state.dock_reference.update_placement_strategy_ui(new_strategy)
	var strategy_name = _get_service().get_active_strategy_name()
	PluginLogger.info("TransformationCoordinator", "Placement mode: " + strategy_name)

func _is_focus_in_plugin_ui(focus_owner: Control) -> bool:
	if not focus_owner:
		return false
	var dock_instance = _state().dock_reference
	if dock_instance and focus_owner == dock_instance:
		return true
	if dock_instance and dock_instance is Control:
		var current: Node = focus_owner
		var depth := 0
		while current and depth < 32:
			if current == dock_instance:
				return true
			current = current.get_parent()
			depth += 1
	return false

func _get_service() -> PlacementStrategyService:
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	return _placement_service

func get_current_focus_owner() -> Control:
	var editor_interface = _services.editor_facade.get_editor_interface()
	if not editor_interface:
		return null
	var base_control = editor_interface.get_base_control()
	if not base_control:
		return null
	var viewport = base_control.get_viewport()
	if not viewport:
		return null
	return viewport.gui_get_focus_owner()

func should_lock_input_to_ui(focus_owner: Control) -> bool:
	if not focus_owner:
		return false
	if _is_spatial_editor_control(focus_owner):
		return false
	if _is_text_input_control(focus_owner):
		return true
	return false

func _wheel_modifiers(wheel_input: Dictionary) -> Dictionary:
	return {
		"reverse": wheel_input.get("reverse_modifier", false),
		"large": wheel_input.get("large_increment", false),
		"fine": wheel_input.get("fine_increment", false)
	}

func _resolve_increment(settings: Dictionary, base_key: String, fine_key: String, large_key: String, default_value: float, modifiers: Dictionary) -> float:
	var step := settings.get(base_key, default_value)
	if modifiers.get("large", false) and large_key != "":
		step = settings.get(large_key, step)
	elif modifiers.get("fine", false) and fine_key != "":
		step = settings.get(fine_key, step)
	return abs(step)

func _direction_with_modifiers(direction: int, modifiers: Dictionary) -> int:
	if direction == 0:
		return 0
	return -direction if modifiers.get("reverse", false) else direction

func _apply_height_adjustment(wheel_input: Dictionary) -> void:
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var settings := _current_settings()
	var step := _resolve_increment(settings, "height_adjustment_step", "fine_height_increment", "large_height_increment", 0.1, modifiers)
	var delta := step * direction
	
	# DEBUG: Log the actual values being used
	PluginLogger.debug("TransformationCoordinator", "Normal offset adjustment - step: %.4f, direction: %d, delta: %.4f, modifiers: %s" % [step, direction, delta, str(modifiers)])
	
	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var state := _state()
		if not state:
			return
		_services.position_manager.adjust_offset_normal(state, delta)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var state := _state()
		if not state:
			return
		var transform_payload = state.session.transform_data
		var center_position = transform_payload.get("center_position", state.values.position)
		
		# Update center position Y (same as keyboard Q/E but without frame delta multiplication)
		center_position.y += delta
		transform_payload["center_position"] = center_position
		state.values.position = center_position
		state.values.base_position = center_position  # Update base position so plane tracking works
		
		# Update plane height so the plane follows the object's new height
		if _services.placement_strategy_service:
			_services.placement_strategy_service.update_plane_height(center_position)

func _apply_scale_adjustment(wheel_input: Dictionary) -> void:
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var settings := _current_settings()
	var step := _resolve_increment(settings, "scale_increment", "fine_scale_increment", "large_scale_increment", 0.1, modifiers)
	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var state := _state()
		if not state:
			return
		if direction > 0:
			_services.scale_manager.increase_scale(state, step)
		else:
			_services.scale_manager.decrease_scale(state, step)
		# Transform will be applied smoothly via _update_preview_transform()
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var state := _state()
		if not state:
			return
		var transform_payload = _state().session.transform_data
		var target_nodes = transform_payload.get("target_nodes", [])
		if not target_nodes.is_empty():
			if direction > 0:
				_services.scale_manager.increase_scale(state, step)
			else:
				_services.scale_manager.decrease_scale(state, step)
			# Transforms will be applied smoothly via _update_transform_nodes()

func _apply_scale_axis_adjustment(wheel_input: Dictionary) -> void:
	"""Apply mouse wheel scale adjustments along constrained axes in L mode"""
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var axes = wheel_input.get("axes", {})  # Dictionary with X/Y/Z: bool
	var settings := _current_settings()
	var state := _state()
	if not state:
		return

	var step := _resolve_increment(settings, "scale_increment", "fine_scale_increment", "large_scale_increment", 0.1, modifiers)
	if not modifiers.get("fine", false) and not modifiers.get("large", false) and state.snap.snap_scale_enabled:
		step = settings.get("snap_scale_step", step)

	var current_scale = _services.scale_manager.get_scale_vector(state)
	var movement := Vector3.ZERO
	var axis_count := 0

	if axes.get("X", false):
		movement.x = direction
		axis_count += 1
	if axes.get("Y", false):
		movement.y = direction
		axis_count += 1
	if axes.get("Z", false):
		movement.z = direction
		axis_count += 1

	if axis_count == 0:
		return

	if axis_count > 1:
		movement = movement.normalized()

	movement *= step
	var new_scale = current_scale + movement
	new_scale.x = clamp(new_scale.x, 0.01, 100.0)
	new_scale.y = clamp(new_scale.y, 0.01, 100.0)
	new_scale.z = clamp(new_scale.z, 0.01, 100.0)
	
	# Update scale in transform state
	_services.scale_manager.set_non_uniform_multiplier(state, new_scale)
	
	# Transforms will be applied smoothly via _update_preview_transform() or _update_transform_nodes()

func _apply_rotation_adjustment(wheel_input: Dictionary) -> void:
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var axis = wheel_input.get("axis", "Y")
	var settings := _current_settings()
	var step := _resolve_increment(settings, "rotation_increment", "fine_rotation_increment", "large_rotation_increment", 15.0, modifiers) * direction
	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var state := _state()
		if not state:
			return
		_services.rotation_manager.rotate_axis(state, axis, step)
		# Transform will be applied smoothly via _update_preview_transform()
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var state := _state()
		if not state:
			return
		
		# Update rotation in state
		_services.rotation_manager.rotate_axis(state, axis, step)
		# Transforms will be applied smoothly via _update_transform_nodes()

func _apply_position_adjustment(wheel_input: Dictionary) -> void:
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var axis = wheel_input.get("axis", "forward")  # forward, backward, left, right
	var settings := _current_settings()
	var step := _resolve_increment(settings, "position_increment", "fine_position_increment", "large_position_increment", 0.1, modifiers)
	var mode = _services.mode_state_machine.get_current_mode()
	var camera = _services.editor_facade.get_editor_viewport_3d(0).get_camera_3d() if _services.editor_facade.get_editor_viewport_3d(0) else null
	if not camera:
		return
	
	# Calculate camera-relative directions snapped to nearest axis (same as mode handlers)
	var camera_forward = Vector3(0, 0, -1)
	var camera_right = Vector3(1, 0, 0)
	
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
	
	# Determine movement direction based on axis
	var movement = Vector3.ZERO
	match axis:
		"forward":
			movement = camera_forward * direction
		"backward":
			movement = -camera_forward * direction
		"left":
			movement = -camera_right * direction
		"right":
			movement = camera_right * direction
	
	movement *= step
	
	# Apply movement based on mode
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var state := _state()
		if not state:
			return
		# In placement mode, adjust manual_position_offset
		state.values.manual_position_offset += movement
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		# In transform mode, update the state directly (like keyboard handler does)
		var state = _state()
		if not state:
			return
		state.values.manual_position_offset += movement

func _apply_position_axis_adjustment(wheel_input: Dictionary) -> void:
	"""Apply mouse wheel position adjustments along constrained axes in G mode"""
	var modifiers := _wheel_modifiers(wheel_input)
	var direction := _direction_with_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	var axes = wheel_input.get("axes", {})  # Dictionary with X/Y/Z: bool
	var state := _state()
	if not state:
		return
	var settings := _current_settings()

	var step := _resolve_increment(settings, "position_increment", "fine_position_increment", "large_position_increment", 0.1, modifiers)
	if not modifiers.get("fine", false) and not modifiers.get("large", false) and state.snap.snap_enabled:
		step = state.snap.snap_step

	var movement = Vector3.ZERO
	var axis_count = 0

	if axes.get("X", false):
		movement.x = direction
		axis_count += 1
	if axes.get("Y", false):
		movement.y = direction
		axis_count += 1
	if axes.get("Z", false):
		movement.z = direction
		axis_count += 1

	if axis_count == 0:
		return

	if axis_count > 1:
		movement = movement.normalized()

	movement *= step

	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		state.values.position += movement
		state.target_position += movement
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = _state().session.transform_data
		var center_pos = transform_payload.get("center_position", state.values.position)
		center_pos += movement
		transform_payload["center_position"] = center_pos
		state.values.position = center_pos

func _grab_3d_viewport_focus() -> void:
	var focus_owner = get_current_focus_owner()
	if should_lock_input_to_ui(focus_owner):
		return
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	var base_control = _services.editor_facade.get_editor_interface().get_base_control()
	if not base_control:
		return
	var spatial_editor = _find_spatial_editor(base_control)
	if spatial_editor:
		if spatial_editor.focus_mode == Control.FOCUS_NONE:
			spatial_editor.focus_mode = Control.FOCUS_ALL
		spatial_editor.grab_focus()
		spatial_editor.call_deferred("grab_focus")

func _find_spatial_editor(node: Node) -> Control:
	if node and node.get_class() == "Node3DEditor":
		if node is Control:
			return node
	if node:
		for child in node.get_children():
			var result = _find_spatial_editor(child)
			if result:
				return result
	return null

func _is_spatial_editor_control(control: Control) -> bool:
	var current: Node = control
	var depth := 0
	while current and depth < 8:
		if current.get_class() == "Node3DEditor":
			return true
		current = current.get_parent()
		depth += 1
	return false

func _is_text_input_control(control: Control) -> bool:
	if control is LineEdit or control is TextEdit:
		return true
	if control.get_class() == "SpinBox":
		return true
	var current: Node = control.get_parent()
	var depth := 0
	while current and depth < 5:
		if current is LineEdit or current is TextEdit:
			return true
		if current.get_class() == "SpinBox":
			return true
		current = current.get_parent()
		depth += 1
	return false

func _is_3d_context_focused() -> bool:
	var edited_scene = _services.editor_facade.get_edited_scene_root()
	if not edited_scene:
		return false
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return false
	var camera = viewport_3d.get_camera_3d()
	if not camera:
		return false
	var base_control = _services.editor_facade.get_editor_interface().get_base_control()
	if base_control:
		var focused_control = base_control.get_viewport().gui_get_focus_owner()
		if focused_control:
			if should_lock_input_to_ui(focused_control):
				return false
			var current = focused_control
			var depth = 0
			while current and depth < 20:
				var control_class = current.get_class()
				var control_name = current.name if current.name else ""
				if "Inspector" in control_class or "Inspector" in control_name or "EditorProperty" in control_class:
					return false
				current = current.get_parent()
				depth += 1
	return true


func _calculate_transform_center(nodes: Array) -> Vector3:
	"""Calculate the center point of all selected nodes."""
	if nodes.is_empty():
		return Vector3.ZERO
	
	var center := Vector3.ZERO
	for node in nodes:
		if node is Node3D:
			center += node.global_position
	
	return center / nodes.size()


func _apply_transform_to_nodes(state: TransformState) -> void:
	"""Apply the current transformation to all nodes being transformed."""
	if not state.session.transform_data or not state.session.transform_data.has("nodes"):
		return
	
	var nodes: Array = state.session.transform_data["nodes"]
	var center: Vector3 = state.session.transform_data["center"]
	
	for node in nodes:
		if not node is Node3D:
			continue
		
		var original_transform: Transform3D = state.session.transform_data["original_transforms"][node]
		var relative_pos := original_transform.origin - center
		
		# Apply rotation around center
		var rotated_offset := Basis.from_euler(state.rotation) * relative_pos
		
		# Apply position offset and scale
		node.global_position = center + state.values.position + (rotated_offset * state.scale)
		node.global_rotation = original_transform.basis.get_euler() + state.rotation


func _reset_transforms_on_exit(state: TransformState) -> void:
	"""Reset transformations when exiting transform mode."""
	state.values.position = Vector3.ZERO
	state.values.manual_rotation_offset = Vector3.ZERO
	state.values.scale_multiplier = 1.0
	state.values.manual_position_offset = Vector3.ZERO
	
	if state.session.transform_data:
		state.session.transform_data.clear()


func _register_transform_undo(state: TransformState) -> void:
	"""Register an undo/redo action for the transformation."""
	if not state.session.transform_data or not state.session.transform_data.has("nodes"):
		return
	
	var undo_redo: EditorUndoRedoManager = _services.undo_redo_manager
	if not undo_redo:
		return
	
	var nodes: Array = state.session.transform_data["nodes"]
	var original_transforms: Dictionary = state.session.transform_data["original_transforms"]
	
	# Capture current transforms
	var current_transforms := {}
	for node in nodes:
		if node is Node3D:
			current_transforms[node] = node.global_transform
	
	# Only create undo if transforms actually changed
	var has_changes := false
	for node in nodes:
		if _transforms_different(original_transforms[node], current_transforms[node]):
			has_changes = true
			break
	
	if not has_changes:
		return
	
	undo_redo.create_action("Transform Nodes")
	
	for node in nodes:
		if not node is Node3D:
			continue
		undo_redo.add_do_property(node, "global_transform", current_transforms[node])
		undo_redo.add_undo_property(node, "global_transform", original_transforms[node])
	
	undo_redo.commit_action()


func _restore_original_transforms(state: TransformState) -> void:
	"""Restore nodes to their original transforms."""
	if not state.session.transform_data or not state.session.transform_data.has("nodes"):
		return
	
	var nodes: Array = state.session.transform_data["nodes"]
	var original_transforms: Dictionary = state.session.transform_data["original_transforms"]
	
	for node in nodes:
		if node is Node3D and original_transforms.has(node):
			node.global_transform = original_transforms[node]


func _transforms_different(a: Transform3D, b: Transform3D) -> bool:
	"""Check if two transforms are different (with tolerance for floating point errors)."""
	const EPSILON = 0.0001
	return not (
		a.origin.distance_to(b.origin) < EPSILON and
		a.basis.x.distance_to(b.basis.x) < EPSILON and
		a.basis.y.distance_to(b.basis.y) < EPSILON and
		a.basis.z.distance_to(b.basis.z) < EPSILON
	)


func _update_preview_transform(state: TransformState) -> void:
	"""Apply current state transforms to the preview mesh"""
	var preview_mesh = _services.preview_manager.get_preview_mesh()
	if not preview_mesh or not is_instance_valid(preview_mesh):
		PluginLogger.debug("TransformationCoordinator", "No valid preview mesh to update")
		return
	
	# Calculate final position: base + height offset + manual offset
	var final_position = state.values.position + state.values.manual_position_offset
	
	# Debug: Log when manual offset is applied
	if state.values.manual_position_offset.length_squared() > 0.001:
		PluginLogger.debug("TransformationCoordinator", "Updating preview: position=%s, offset=%s, final=%s" % [
			state.values.position, state.values.manual_position_offset, final_position])
	
	# Get rotation and scale from state
	var final_rotation = state.values.surface_alignment_rotation + state.values.manual_rotation_offset
	var final_scale = Vector3.ONE * state.values.scale_multiplier
	
	# Apply through SmoothTransformManager for proper interpolation
	# If smooth transforms are disabled, it will apply directly
	if _services.smooth_transform_manager:
		_services.smooth_transform_manager.set_target_transform(
			preview_mesh, 
			final_position, 
			final_rotation, 
			final_scale
		)
	else:
		# Fallback: apply directly if smooth transform manager not available
		preview_mesh.global_position = final_position
		preview_mesh.rotation = final_rotation
		preview_mesh.scale = final_scale


func _update_transform_nodes(state: TransformState) -> void:
	"""Apply current state transforms to the target nodes in transform mode"""
	if not state.session.transform_data or not state.session.transform_data.has("target_nodes"):
		return
	
	var nodes: Array = state.session.transform_data["target_nodes"]
	var center_position: Vector3 = state.session.transform_data.get("center_position", state.values.position)
	var node_offsets: Dictionary = state.session.transform_data.get("node_offsets", {})
	var original_transforms: Dictionary = state.session.transform_data.get("original_transforms", {})
	var original_rotations: Dictionary = state.session.transform_data.get("original_rotations", {})
	
	# Apply transforms to each node
	for node in nodes:
		if not node or not node.is_inside_tree():
			continue
		
		# Get node's offset from center
		var offset = node_offsets.get(node, Vector3.ZERO)
		
		# Calculate new position: center + offset + manual offset
		var new_position = center_position + offset + state.values.manual_position_offset
		
		# Calculate rotation: use stored original rotation + manual offset
		# This avoids euler conversion issues from basis.get_euler()
		var original_rotation = original_rotations.get(node, Vector3.ZERO)
		var new_rotation = original_rotation + state.values.manual_rotation_offset
		
		# Calculate scale: original + scale offset (additive scaling)
		var original_transform = original_transforms.get(node, Transform3D())
		var original_scale = original_transform.basis.get_scale()
		var scale_offset = state.get_scale_vector() - Vector3.ONE
		var new_scale = original_scale + scale_offset
		
		# Apply through SmoothTransformManager for proper interpolation
		# If smooth transforms are disabled, it will apply directly
		if _services.smooth_transform_manager:
			# Check if we actually need to update (avoid unnecessary target updates)
			var current_target_pos = _services.smooth_transform_manager.get_target_position(node)
			var current_target_rot = _services.smooth_transform_manager.get_target_rotation(node)
			var current_target_scale = _services.smooth_transform_manager.get_target_scale(node)
			
			var pos_changed = current_target_pos.distance_squared_to(new_position) > 0.00001
			var rot_changed = current_target_rot.distance_squared_to(new_rotation) > 0.00001
			var scale_changed = current_target_scale.distance_squared_to(new_scale) > 0.00001
			
			# Only update if something actually changed
			if pos_changed or rot_changed or scale_changed:
				_services.smooth_transform_manager.set_target_transform(
					node,
					new_position,
					new_rotation,
					new_scale
				)
		else:
			# Fallback: apply directly if smooth transform manager not available
			node.global_position = new_position
			node.rotation = new_rotation
			node.scale = new_scale


func _update_overlay_display(mode: int, state: TransformState) -> void:
	"""Update the overlay with current transform information"""
	if not _services.overlay_manager or not state:
		return
	
	# Get node name for display
	var node_name := ""
	var rotation := state.values.surface_alignment_rotation + state.values.manual_rotation_offset
	
	if mode == ModeStateMachine.Mode.TRANSFORM:
		var nodes = state.session.transform_data.get("target_nodes", [])
		if nodes.size() == 1:
			node_name = nodes[0].name if nodes[0] else ""
			# For single node in transform mode, show actual current rotation
			if nodes[0] and is_instance_valid(nodes[0]):
				rotation = nodes[0].rotation
		elif nodes.size() > 1:
			node_name = str(nodes.size()) + " nodes"
			# For multiple nodes, show the first node's rotation as representative
			if nodes[0] and is_instance_valid(nodes[0]):
				rotation = nodes[0].rotation
	
	# Get current transform values
	var position := state.values.position + state.values.manual_position_offset
	var scale_value := state.values.scale_multiplier
	
	# Calculate offset along plane normal for display
	var plane_normal: Vector3 = Vector3.UP
	if _services.position_manager:
		plane_normal = _services.position_manager.get_plane_normal_direction(state)
	var normal_offset := state.values.manual_position_offset.dot(plane_normal)
	
	# Update overlay
	_services.overlay_manager.show_transform_overlay(
		mode,
		node_name,
		position,
		rotation,
		scale_value,
		normal_offset,
		state
	)
