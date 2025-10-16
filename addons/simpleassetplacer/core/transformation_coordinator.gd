@tool
extends RefCounted

class_name TransformationCoordinator

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const TransformSession = preload("res://addons/simpleassetplacer/core/transform_session.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const EditorFacade = preload("res://addons/simpleassetplacer/core/editor_facade.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const GridManager = preload("res://addons/simpleassetplacer/managers/grid_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")
const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")
const FrameInputOrchestrator = preload("res://addons/simpleassetplacer/core/frame_input_orchestrator.gd")

var _services: ServiceRegistry
var _transform_session: TransformSession
var _frame_orchestrator: FrameInputOrchestrator
var _placement_service: PlacementStrategyService

func _init(services: ServiceRegistry) -> void:
	_services = services
	_transform_session = TransformSession.new()
	_frame_orchestrator = FrameInputOrchestrator.new(services, self)
	if services and services.placement_strategy_service:
		_placement_service = services.placement_strategy_service
	else:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()


func _session() -> TransformSession:
	if not _transform_session:
		_transform_session = TransformSession.new()
	return _transform_session


func _state() -> TransformState:
	return _session().transform_state


func _current_settings() -> Dictionary:
	var settings := _session().settings
	if settings.is_empty():
		return SettingsManager.get_combined_settings()
	return settings

func start_placement_mode(mesh: Mesh, meshlib, item_id, asset_path, placement_settings, dock_instance = null) -> void:
	exit_any_mode()
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.PLACEMENT):
		return

	# Reset control mode (deactivate modal) when entering placement mode
	if _services.control_mode_state:
		_services.control_mode_state.reset()

	var session := _session()
	session.begin(ModeStateMachine.Mode.PLACEMENT, placement_settings)
	session.dock_reference = dock_instance

	_ensure_undo_redo()
	var transform_state := session.transform_state
	session.placement_data = _services.placement_mode_handler.enter_placement_mode(mesh, meshlib, item_id, asset_path, placement_settings, transform_state, _services.undo_redo)
	if session.placement_data:
		session.placement_data["dock_reference"] = dock_instance

	_services.grid_manager.reset_tracking()
	session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()

func start_transform_mode(target_nodes: Variant, dock_instance = null) -> void:
	exit_any_mode()
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.TRANSFORM):
		return

	# Reset control mode (deactivate modal) when entering transform mode
	if _services.control_mode_state:
		_services.control_mode_state.reset()

	var combined_settings = SettingsManager.get_combined_settings()
	var session := _session()
	session.begin(ModeStateMachine.Mode.TRANSFORM, combined_settings)
	session.dock_reference = dock_instance

	var transform_state := session.transform_state
	PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Transform mode settings loaded | snap_rot:%s step:%s snap_scale:%s step:%s" % [
		transform_state.snap_rotation_enabled,
		transform_state.snap_rotation_step,
		transform_state.snap_scale_enabled,
		transform_state.snap_scale_step
	])
	_ensure_undo_redo()
	session.transform_data = _services.transform_mode_handler.enter_transform_mode(target_nodes, combined_settings, transform_state, _services.undo_redo)
	if session.transform_data:
		session.transform_data["dock_reference"] = dock_instance

	_services.grid_manager.reset_tracking()
	session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()

func exit_placement_mode() -> void:
	if not _services.mode_state_machine.is_placement_mode():
		return
	var session := _session()
	# Cancel any active numeric input
	if _services.numeric_input_controller:
		_services.numeric_input_controller.reset()
	elif _services.numeric_input_manager:
		_services.numeric_input_manager.reset()
	# Deactivate modal control
	if _services.control_mode_state:
		_services.control_mode_state.deactivate_modal()

	var state := session.transform_state
	var placement_data := session.placement_data
	var settings_snapshot := session.settings
	_services.placement_mode_handler.exit_placement_mode(placement_data, state, session.placement_end_callback, settings_snapshot)

	_services.mode_state_machine.clear_mode()
	session.reset()

func exit_transform_mode(confirm_changes: bool = true) -> void:
	if not _services.mode_state_machine.is_transform_mode():
		return
	var session := _session()
	# Cancel any active numeric input
	if _services.numeric_input_controller:
		_services.numeric_input_controller.reset()
	elif _services.numeric_input_manager:
		_services.numeric_input_manager.reset()
	# Deactivate modal control
	if _services.control_mode_state:
		_services.control_mode_state.deactivate_modal()

	_services.transform_mode_handler.exit_transform_mode(session.transform_data, session.transform_state, confirm_changes, session.settings)

	_services.mode_state_machine.clear_mode()
	session.reset()

func exit_any_mode() -> void:
	var mode = _services.mode_state_machine.get_current_mode()
	# Cancel any active numeric input
	if _services.numeric_input_controller:
		_services.numeric_input_controller.reset()
	elif _services.numeric_input_manager:
		_services.numeric_input_manager.reset()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			exit_placement_mode()
		ModeStateMachine.Mode.TRANSFORM:
			exit_transform_mode(false)

func reset_transforms() -> void:
	"""Reset all transform offsets (rotation, scale, height, position)"""
	var session := _session()
	var state := session.transform_state
	if not state:
		return

	var mode = _services.mode_state_machine.get_current_mode()

	if mode == ModeStateMachine.Mode.PLACEMENT:
		# Reset rotation
		_services.rotation_manager.reset_all_rotation(state)

		# Reset scale
		_services.scale_manager.reset_scale(state)

		# Reset height offset
		_services.position_manager.reset_height(state)

		# Reset manual position offset
		state.manual_position_offset = Vector3.ZERO

		# Show feedback
		if _services.overlay_manager:
			_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)

	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = session.transform_data
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

		# Reset height offset
		_services.position_manager.reset_height(state)

		# Reset manual position offset
		transform_payload["manual_position_offset"] = Vector3.ZERO

		# Update center position to match new state
		var center_pos = Vector3(state.position.x, state.base_height + state.height_offset, state.position.z)
		state.position = center_pos
		transform_payload["center_position"] = center_pos

		# Show feedback
		if _services.overlay_manager:
			_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)

func process_frame_input(camera: Camera3D, input_settings: Dictionary = {}, delta: float = 1.0/60.0) -> void:
	var session := _session()
	_frame_orchestrator.process(session, camera, input_settings, delta)

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

func handle_tab_key_activation(dock_instance = null) -> void:
	if _services.mode_state_machine.is_any_mode_active():
		return
	if not _is_3d_context_focused():
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
		var session_settings = _session().settings
		var placement_settings = session_settings if not session_settings.is_empty() else SettingsManager.get_combined_settings()
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
	var state := _session().transform_state
	if state:
		return _services.scale_manager.get_scale(state)
	return 1.0

func set_placement_end_callback(callback: Callable) -> void:
	_session().placement_end_callback = callback

func set_mesh_placed_callback(callback: Callable) -> void:
	_session().mesh_placed_callback = callback

func set_dock_reference(dock_instance) -> void:
	_session().dock_reference = dock_instance

func cleanup_all() -> void:
	exit_any_mode()
	_services.overlay_manager.cleanup_all_overlays()
	_services.preview_manager.cleanup_preview()
	_services.grid_manager.cleanup_grid()

func cleanup() -> void:
	cleanup_all()

func update_settings(new_settings: Dictionary) -> void:
	var session := _session()
	session.settings = new_settings.duplicate(true)

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
	var state := _session().transform_state
	var config_state := state if state else TransformState.new()
	_services.rotation_manager.configure(config_state, smooth_config)
	_services.scale_manager.configure(config_state, smooth_config)

func _process_navigation_input() -> void:
	var input_handler = _services.input_handler if _services else null
	if not input_handler:
		return
	var control_state = _services.control_mode_state if _services else null
	if control_state and control_state.is_modal_active() and input_handler.is_mouse_button_just_pressed("right"):
		control_state.deactivate_modal()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Modal control deactivated via right-click")
		return

	var nav_input = input_handler.get_navigation_input()
	if nav_input.tab_just_pressed:
		handle_tab_key_activation(_session().dock_reference)
	if nav_input.cancel_pressed:
		if control_state and control_state.is_modal_active():
			control_state.deactivate_modal()
			PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Modal control deactivated via cancel key")
		else:
			exit_any_mode()
		return
	# Allow cycling placement strategy in both PLACEMENT and TRANSFORM modes
	if input_handler.should_cycle_placement_mode():
		if _services.mode_state_machine.is_any_mode_active():
			_cycle_placement_strategy()

func _cycle_placement_strategy() -> void:
	var new_strategy = _get_service().cycle_strategy()
	var session := _session()
	var settings := session.settings
	if settings.is_empty():
		settings = SettingsManager.get_combined_settings().duplicate(true)
		settings["placement_strategy"] = new_strategy
		session.settings = settings
	else:
		settings["placement_strategy"] = new_strategy
	SettingsManager.update_dock_settings({"placement_strategy": new_strategy})
	if session.dock_reference and session.dock_reference.has_method("update_placement_strategy_ui"):
		session.dock_reference.update_placement_strategy_ui(new_strategy)
	var strategy_name = _get_service().get_active_strategy_name()
	PluginLogger.info("TransformationCoordinator", "Placement mode: " + strategy_name)

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
	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var state := _state()
		if not state:
			return
		_services.position_manager.adjust_height(state, delta)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = _session().transform_data
		var accumulated_y_delta = transform_payload.get("accumulated_y_delta", 0.0)
		accumulated_y_delta += delta
		transform_payload["accumulated_y_delta"] = accumulated_y_delta

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
		var target_node = _services.preview_manager.get_preview_mesh()
		if target_node:
			if direction > 0:
				_services.scale_manager.increase_scale(state, step)
			else:
				_services.scale_manager.decrease_scale(state, step)
			TransformApplicator.apply_scale_only(target_node, state)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var state := _state()
		if not state:
			return
		var transform_payload = _session().transform_data
		var target_nodes = transform_payload.get("target_nodes", [])
		var original_transforms = transform_payload.get("original_transforms", {})
		if not target_nodes.is_empty():
			if direction > 0:
				_services.scale_manager.increase_scale(state, step)
			else:
				_services.scale_manager.decrease_scale(state, step)
			for node in target_nodes:
				if node and node.is_inside_tree():
					var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
					TransformApplicator.apply_scale_only(node, state, node_original_scale)

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
	if not modifiers.get("fine", false) and not modifiers.get("large", false) and state.snap_scale_enabled:
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
	
	# Apply to nodes based on mode
	var mode = _services.mode_state_machine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var target_node = _services.preview_manager.get_preview_mesh()
		if target_node:
			var base_scale = state.get_meta("original_scale") if state.has_meta("original_scale") else Vector3.ONE
			TransformApplicator.apply_scale_only(target_node, state, base_scale)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = _session().transform_data
		var target_nodes = transform_payload.get("target_nodes", [])
		var original_transforms = transform_payload.get("original_transforms", {})
		for node in target_nodes:
			if node and node.is_inside_tree():
				var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
				TransformApplicator.apply_scale_only(node, state, node_original_scale)

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
		var target_node = _services.preview_manager.get_preview_mesh()
		if target_node:
			_services.rotation_manager.rotate_axis(state, axis, step)
			TransformApplicator.apply_rotation_only(target_node, state)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		# For transform mode with multiple nodes, rotate around the group center
		var state := _state()
		if not state:
			return
		_services.transform_mode_handler.rotate_group_by_step(axis, step, _session().transform_data, state)

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
		state.manual_position_offset += movement
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		# In transform mode, adjust manual_position_offset in transform_data
		var transform_payload = _session().transform_data
		var manual_offset = transform_payload.get("manual_position_offset", Vector3.ZERO)
		manual_offset += movement
		transform_payload["manual_position_offset"] = manual_offset

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
	if not modifiers.get("fine", false) and not modifiers.get("large", false) and state.snap_enabled:
		step = state.snap_step

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
		state.position += movement
		state.target_position += movement
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var transform_payload = _session().transform_data
		var center_pos = transform_payload.get("center_position", state.position)
		center_pos += movement
		transform_payload["center_position"] = center_pos
		state.position = center_pos

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
