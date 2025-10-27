@tool
extends RefCounted

class_name InputProcessor

"""
INPUT PROCESSOR
===============

PURPOSE: Process mouse and wheel input for both placement and transform modes

RESPONSIBILITIES:
- Handle mouse motion (position updates)
- Handle mouse wheel (height/rotation/scale adjustments)
- Process keyboard navigation (Tab, ESC, P)
- Apply modifiers (CTRL/ALT/SHIFT)
- Calculate increments with modifiers

ARCHITECTURE: Focused input processor extracted from TransformationCoordinator
- Delegates to appropriate mode controllers
- No mode-specific logic, just input routing
- No legacy code or backwards compatibility

USED BY: TransformationCoordinator
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

var _services  # ServiceRegistry

func _init(services) -> void:
	_services = services

## Mouse Input

func handle_mouse_motion(camera: Camera3D, mouse_position: Vector2, state: TransformState) -> void:
	"""Handle mouse motion to update position"""
	if not camera or not state:
		return
	
	var mode = _services.mode_state_machine.get_current_mode()
	
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			_handle_placement_mouse_motion(camera, mouse_position, state)
		
		ModeStateMachine.Mode.TRANSFORM:
			_handle_transform_mouse_motion(camera, mouse_position, state)

func handle_mouse_wheel(event: InputEventMouseButton) -> bool:
	"""Handle mouse wheel input for adjustments"""
	var wheel_input = _services.input_handler.get_mouse_wheel_input(event)
	if wheel_input.is_empty():
		return false
	
	match wheel_input.get("action"):
		"height":
			_apply_height_adjustment(wheel_input)
		"scale":
			_apply_scale_adjustment(wheel_input)
		"rotation":
			_apply_rotation_adjustment(wheel_input)
		"position":
			_apply_position_adjustment(wheel_input)
	
	return true

## Navigation Input

func handle_navigation(nav_input, ui_locked: bool, focus_owner: Control, state: TransformState) -> void:
	"""Handle navigation keys (Tab, ESC, P, [ / ])"""
	if not nav_input:
		return
	
	# Cycle placement strategy (P key) - allowed even when UI locked
	if _services.input_handler.should_cycle_placement_mode():
		if _services.mode_state_machine.is_any_mode_active():
			_cycle_placement_strategy(state)
	
	# Handle asset cycling ([ / ] keys) - only works in placement mode
	if _services.mode_state_machine.is_placement_mode():
		_handle_asset_cycling(nav_input, state)
	
	# Other navigation requires UI not locked
	if ui_locked:
		# Allow Tab if focus is in plugin UI
		if nav_input.tab_just_pressed and _is_focus_in_plugin_ui(focus_owner, state):
			_handle_tab_activation(state, true)
		return
	
	# Handle Tab key (enter transform mode)
	if nav_input.tab_just_pressed:
		_handle_tab_activation(state, false)
	
	# Handle ESC (cancel/exit mode)
	if nav_input.cancel_pressed:
		if _services.mode_state_machine.is_placement_mode():
			_services.transformation_coordinator.exit_placement_mode()
		elif _services.mode_state_machine.is_transform_mode():
			_services.transformation_coordinator.exit_transform_mode(false)

## Mouse Motion Handlers

func _handle_placement_mouse_motion(camera: Camera3D, mouse_position: Vector2, state: TransformState) -> void:
	"""Update position from mouse in placement mode"""
	# Skip position updates during camera fly mode (right mouse button held)
	# This prevents unwanted position changes while navigating the viewport
	if _services.input_handler and _services.input_handler.is_mouse_button_pressed("right"):
		return
	
	# Get preview mesh to exclude from raycast (prevents self-collision)
	var exclude_nodes = []
	if _services.preview_manager and _services.preview_manager.has_preview():
		var preview_mesh = _services.preview_manager.get_preview_mesh()
		if preview_mesh:
			exclude_nodes.append(preview_mesh)
	
	_services.position_manager.update_position_from_mouse(state, camera, mouse_position, 1, false, exclude_nodes)

func _handle_transform_mouse_motion(camera: Camera3D, mouse_position: Vector2, state: TransformState) -> void:
	"""Update position from mouse in transform mode"""
	# Skip position updates during camera fly mode (right mouse button held)
	# This prevents unwanted position changes while navigating the viewport
	if _services.input_handler and _services.input_handler.is_mouse_button_pressed("right"):
		return
	
	var target_nodes = state.session.transform_data.get("target_nodes", [])
	var current_center = state.session.transform_data.get("center_position", Vector3.ZERO)
	
	# Get the plane normal direction (perpendicular to the active plane)
	# - XZ plane (horizontal): normal = Y axis (up/down)
	# - XY plane (vertical): normal = Z axis (forward/back)
	# - YZ plane (vertical): normal = X axis (left/right)
	var plane_normal = _services.position_manager.get_plane_normal_direction(state)
	
	# Store the component along the plane normal to preserve height adjustments
	var preserved_normal_offset = current_center.dot(plane_normal)
	
	var old_position = state.values.position
	
	# Update with node exclusions to avoid self-collision
	_services.position_manager.update_position_from_mouse(state, camera, mouse_position, 1, false, target_nodes)
	
	var new_position = state.values.position
	var position_delta = new_position - old_position
	
	# Apply the position delta to center
	current_center += position_delta
	
	# Check if we're using collision placement strategy - if so, allow surface snapping
	var settings = _get_current_settings()
	var placement_strategy = settings.get("placement_strategy", "collision")
	
	# Only restore plane normal component if using plane placement strategy
	# With collision strategy, allow objects to snap to surfaces below
	if placement_strategy == "plane":
		# Restore the component along the plane normal (preserve height offset from Q/E keys)
		# This ensures mouse motion only moves along the plane, not perpendicular to it
		var new_normal_component = current_center.dot(plane_normal)
		current_center += plane_normal * (preserved_normal_offset - new_normal_component)
		
	state.session.transform_data["center_position"] = current_center

## Mouse Wheel Handlers

func _apply_height_adjustment(wheel_input: Dictionary) -> void:
	"""Apply height adjustment from mouse wheel (Q/E equivalent)"""
	var modifiers = _extract_modifiers(wheel_input)
	var direction = _apply_direction_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	
	var settings = _get_current_settings()
	var step = _calculate_step(settings, "height_adjustment_step", "fine_height_increment", "large_height_increment", 0.1, modifiers)
	var delta = step * direction
	
	var mode = _services.mode_state_machine.get_current_mode()
	var state = _services.transformation_coordinator._state()
	
	if mode == ModeStateMachine.Mode.PLACEMENT:
		_services.position_manager.adjust_offset_normal(state, delta)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var center_position = state.session.transform_data.get("center_position", state.values.position)
		center_position.y += delta
		state.session.transform_data["center_position"] = center_position
		state.values.position = center_position
		state.values.base_position = center_position
		
		if _services.placement_strategy_service:
			_services.placement_strategy_service.update_plane_height(center_position)

func _apply_scale_adjustment(wheel_input: Dictionary) -> void:
	"""Apply scale adjustment from mouse wheel (Page Up/Down equivalent)"""
	var modifiers = _extract_modifiers(wheel_input)
	var direction = _apply_direction_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	
	var settings = _get_current_settings()
	var step = _calculate_step(settings, "scale_increment", "fine_scale_increment", "large_scale_increment", 0.1, modifiers)
	
	var mode = _services.mode_state_machine.get_current_mode()
	var state = _services.transformation_coordinator._state()
	
	if direction > 0:
		_services.scale_manager.increase_scale(state, step)
	else:
		_services.scale_manager.decrease_scale(state, step)

func _apply_rotation_adjustment(wheel_input: Dictionary) -> void:
	"""Apply rotation adjustment from mouse wheel (X/Y/Z equivalent)"""
	var modifiers = _extract_modifiers(wheel_input)
	var direction = _apply_direction_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	
	var axis = wheel_input.get("axis", "Y")
	var settings = _get_current_settings()
	var step = _calculate_step(settings, "rotation_increment", "fine_rotation_increment", "large_rotation_increment", 15.0, modifiers) * direction
	
	var state = _services.transformation_coordinator._state()
	_services.rotation_manager.rotate_axis(state, axis, step)

func _apply_position_adjustment(wheel_input: Dictionary) -> void:
	"""Apply position adjustment from mouse wheel (WASD equivalent)"""
	var modifiers = _extract_modifiers(wheel_input)
	var direction = _apply_direction_modifiers(wheel_input.get("direction", 0), modifiers)
	if direction == 0:
		return
	
	var axis = wheel_input.get("axis", "forward")
	var settings = _get_current_settings()
	var step = _calculate_step(settings, "position_increment", "fine_position_increment", "large_position_increment", 0.1, modifiers)
	
	var camera = _get_current_camera()
	if not camera:
		return
	
	var state = _services.transformation_coordinator._state()
	
	# Use plane-aware movement functions instead of hardcoded XZ projection
	# This ensures intuitive controls on all plane orientations
	match axis:
		"forward":
			if direction > 0:
				_services.position_manager.move_forward(state, step, camera)
			else:
				_services.position_manager.move_backward(state, step, camera)
		"backward":
			if direction > 0:
				_services.position_manager.move_backward(state, step, camera)
			else:
				_services.position_manager.move_forward(state, step, camera)
		"left":
			if direction > 0:
				_services.position_manager.move_left(state, step, camera)
			else:
				_services.position_manager.move_right(state, step, camera)
		"right":
			if direction > 0:
				_services.position_manager.move_right(state, step, camera)
			else:
				_services.position_manager.move_left(state, step, camera)

## Helper Methods

func _extract_modifiers(input_dict: Dictionary) -> Dictionary:
	"""Extract modifier keys from input dictionary"""
	return {
		"reverse": input_dict.get("reverse_modifier", false),
		"large": input_dict.get("large_increment", false),
		"fine": input_dict.get("fine_increment", false)
	}

func _apply_direction_modifiers(direction: int, modifiers: Dictionary) -> int:
	"""Apply reverse modifier to direction"""
	if direction == 0:
		return 0
	return -direction if modifiers.get("reverse", false) else direction

func _calculate_step(settings: Dictionary, base_key: String, fine_key: String, large_key: String, default: float, modifiers: Dictionary) -> float:
	"""Calculate step size with modifiers applied"""
	var step = settings.get(base_key, default)
	
	if modifiers.get("large", false):
		step = settings.get(large_key, step)
	elif modifiers.get("fine", false):
		step = settings.get(fine_key, step)
	
	return abs(step)

func _cycle_placement_strategy(state: TransformState) -> void:
	"""Cycle between placement strategies (collision/plane)"""
	var placement_service = _services.placement_strategy_service
	if not placement_service:
		return
	
	var new_strategy = placement_service.cycle_strategy()
	
	# Update settings
	var settings = state.settings if not state.settings.is_empty() else _get_current_settings().duplicate(true)
	settings["placement_strategy"] = new_strategy
	state.settings = settings
	
	_services.settings_manager.update_dock_settings({"placement_strategy": new_strategy})
	
	# Update UI if dock available
	if state.dock_reference and state.dock_reference.has_method("update_placement_strategy_ui"):
		state.dock_reference.update_placement_strategy_ui(new_strategy)
	
	var strategy_name = placement_service.get_active_strategy_name()
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Placement mode: " + strategy_name)

func _handle_asset_cycling(nav_input, state: TransformState) -> void:
	"""Handle asset cycling input ([ / ] keys) during placement mode"""
	if not nav_input:
		return
	
	# Get the dock reference to call cycling methods
	var dock = state.session.placement_data.get("dock_reference", null)
	if not dock:
		dock = state.dock_reference
	
	if not dock:
		return
	
	# Check for cycling input
	var cycled = false
	if nav_input.cycle_next_asset:
		if dock.has_method("cycle_next_asset"):
			cycled = dock.cycle_next_asset()
	elif nav_input.cycle_previous_asset:
		if dock.has_method("cycle_previous_asset"):
			cycled = dock.cycle_previous_asset()
	
	# If we cycled to a new asset, update the position immediately
	# This prevents the preview from staying at the old position until the mouse moves
	if cycled:
		_update_position_after_asset_cycle(state)

func _handle_tab_activation(state: TransformState, ignore_focus_lock: bool) -> void:
	"""Handle Tab key to enter transform mode"""
	if _services.mode_state_machine.is_any_mode_active():
		return
	
	if not ignore_focus_lock and not _is_3d_context_focused():
		return
	
	var selection = _services.editor_facade.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	if selected_nodes.is_empty():
		return
	
	# Filter to Node3D objects
	var target_nodes = []
	for node in selected_nodes:
		if node is Node3D:
			target_nodes.append(node)
	
	if target_nodes.is_empty():
		return
	
	# Start transform mode
	var first_node = target_nodes[0]
	var current_scene = _services.editor_facade.get_edited_scene_root()
	
	if current_scene and (first_node.is_ancestor_of(current_scene) or current_scene == first_node or first_node.is_inside_tree()):
		_services.transformation_coordinator.start_transform_mode(target_nodes, state.dock_reference)
		
		if target_nodes.size() == 1:
			_services.overlay_manager.show_status_message("Transform mode: " + first_node.name, Color.GREEN, 2.0)
		else:
			_services.overlay_manager.show_status_message("Transform mode: %d nodes" % target_nodes.size(), Color.GREEN, 2.0)

func _is_focus_in_plugin_ui(focus_owner: Control, state: TransformState) -> bool:
	"""Check if focus is within plugin UI"""
	if not focus_owner:
		return false
	
	var dock_instance = state.dock_reference
	if not dock_instance:
		return false
	
	if focus_owner == dock_instance:
		return true
	
	if dock_instance is Control:
		var current: Node = focus_owner
		var depth = 0
		while current and depth < 32:
			if current == dock_instance:
				return true
			current = current.get_parent()
			depth += 1
	
	return false

func _is_3d_context_focused() -> bool:
	"""Check if 3D editor context is focused"""
	var edited_scene = _services.editor_facade.get_edited_scene_root()
	if not edited_scene:
		return false
	
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return false
	
	var camera = viewport_3d.get_camera_3d()
	if not camera:
		return false
	
	return true

func _apply_transform_mode_grid_snap(state: TransformState, pos: Vector3) -> Vector3:
	"""Apply grid snapping for transform mode (similar to position_manager logic)"""
	if not state.snap.snap_enabled and not state.snap.snap_y_enabled:
		return pos
	
	# Use position manager's grid snapping logic
	if _services.position_manager:
		# Temporarily update target position and apply grid snap
		var original_target = state.values.target_position
		state.values.target_position = pos
		
		if state.snap.snap_y_enabled:
			# Apply full grid snap (XYZ)
			state.values.target_position = _services.position_manager._apply_grid_snap(state, state.values.target_position)
		else:
			# Apply XZ-only grid snap (preserve Y from collision detection)
			state.values.target_position = _services.position_manager._apply_grid_snap_xz_only(state, state.values.target_position)
		
		var snapped_pos = state.values.target_position
		state.values.target_position = original_target  # Restore original
		return snapped_pos
	
	return pos

func _get_current_settings() -> Dictionary:
	"""Get current settings"""
	return _services.settings_manager.get_combined_settings()

func _get_current_camera() -> Camera3D:
	"""Get current editor camera"""
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	return viewport.get_camera_3d() if viewport else null

func _update_position_after_asset_cycle(state: TransformState) -> void:
	"""Update position immediately after cycling to a new asset to prevent preview lag"""
	# Get current mouse position
	var mouse_pos = _services.input_handler.get_mouse_position()
	
	# Get camera
	var camera = _get_current_camera()
	if not camera:
		return
	
	# Get preview mesh to exclude from raycast (prevents self-collision)
	var exclude_nodes = []
	if _services.preview_manager and _services.preview_manager.has_preview():
		var preview_mesh = _services.preview_manager.get_preview_mesh()
		if preview_mesh:
			exclude_nodes.append(preview_mesh)
	
	# Update position from current mouse location
	_services.position_manager.update_position_from_mouse(state, camera, mouse_pos, 1, false, exclude_nodes)
