@tool
extends RefCounted

class_name TransformationCoordinator

"""
TRANSFORMATION COORDINATOR (SIMPLIFIED)
=======================================

PURPOSE: Coordinate transformation operations by delegating to focused controllers

RESPONSIBILITIES:
- Delegate to PlacementModeController for placement operations
- Delegate to TransformModeController for transform operations  
- Delegate to InputProcessor for input handling
- Manage frame updates and overlay display
- Provide public API for mode management

ARCHITECTURE: Simplified coordinator pattern
- No business logic - pure delegation
- Each controller has single responsibility
- Clean separation of concerns
- No legacy code or backwards compatibility

REFACTORED FROM: 1,610-line god object to ~450-line coordinator
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PlacementModeController = preload("res://addons/simpleassetplacer/core/placement_mode_controller.gd")
const TransformModeController = preload("res://addons/simpleassetplacer/core/transform_mode_controller.gd")
const InputProcessor = preload("res://addons/simpleassetplacer/core/input_processor.gd")

var _services  # ServiceRegistry
var _transform_state: TransformState

# Controllers
var _placement_controller: PlacementModeController
var _transform_controller: TransformModeController
var _input_processor: InputProcessor

func _init(services) -> void:
	_services = services
	_transform_state = TransformState.new()
	
	# Initialize controllers
	_placement_controller = PlacementModeController.new(services)
	_transform_controller = TransformModeController.new(services)
	_input_processor = InputProcessor.new(services)

## Public API - Mode Management

func start_placement_mode(mesh: Mesh, meshlib, item_id: int, asset_path: String, placement_settings: Dictionary, dock_instance = null) -> void:
	"""Start placement mode - delegates to PlacementModeController"""
	exit_any_mode()
	_ensure_undo_redo()
	_placement_controller.start(mesh, meshlib, item_id, asset_path, placement_settings, dock_instance, _state())

func start_transform_mode(target_nodes: Variant, dock_instance = null) -> void:
	"""Start transform mode - delegates to TransformModeController"""
	exit_any_mode()
	_ensure_undo_redo()
	_transform_controller.start(target_nodes, dock_instance, _state())

func exit_placement_mode(confirm_placement: bool = false) -> void:
	"""Exit placement mode - delegates to PlacementModeController"""
	_placement_controller.exit(_state(), confirm_placement)

func exit_transform_mode(confirm_changes: bool = true) -> void:
	"""Exit transform mode - delegates to TransformModeController"""
	_transform_controller.exit(confirm_changes, _state())

func exit_any_mode() -> void:
	"""Exit whatever mode is active"""
	var mode = _services.mode_state_machine.get_current_mode()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			exit_placement_mode()
		ModeStateMachine.Mode.TRANSFORM:
			exit_transform_mode(false)

## Public API - Input Handling

func process_frame_input(camera: Camera3D, input_settings: Dictionary = {}, delta: float = 1.0/60.0) -> void:
	"""Process all frame input - coordinates between controllers"""
	if not camera or not is_instance_valid(camera):
		return
	
	var state = _state()
	
	# Update settings
	if not input_settings.is_empty():
		state.settings = input_settings.duplicate(true)
	
	# Get viewport for input handling
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	# Update input state
	_services.input_handler.update_input_state(input_settings, viewport_3d)
	
	# Check UI focus
	var focus_owner = _get_current_focus_owner()
	var ui_focus_locked = _should_lock_input_to_ui(focus_owner)
	state.session.ui_focus_locked = ui_focus_locked
	
	# Process navigation input (asset cycling, Tab, ESC, P)
	if _services.input_handler:
		var nav_input = _services.input_handler.get_navigation_input()
		_input_processor.handle_navigation(nav_input, ui_focus_locked, focus_owner, state)
	
	# Get combined settings
	var combined_settings = _services.settings_manager.get_combined_settings()
	state.settings = combined_settings
	
	# Configure state if settings changed or first frame
	state.session.frames_since_mode_start += 1
	var is_first_frame = state.session.frames_since_mode_start == 1
	
	if is_first_frame:
		state.configure_from_settings(combined_settings)
		_services.position_manager.configure(state, combined_settings)
	
	# Configure smooth transforms
	_configure_smooth_transforms(combined_settings)
	
	# Handle focus grabbing
	if state.session.focus_grab_frames > 0:
		state.session.focus_grab_frames -= 1
		_grab_3d_viewport_focus()
	
	# Process mode-specific input (if UI not locked)
	var mode = _services.mode_state_machine.get_current_mode()
	if not ui_focus_locked:
		match mode:
			ModeStateMachine.Mode.PLACEMENT:
				_placement_controller.process_input(camera, state, combined_settings, delta)
				_placement_controller.update_preview_transform(state)
				_update_overlay_display(mode, state)
				
				# Check for placement confirmation
				if state.session.placement_data.get("_confirm_exit", false):
					state.session.placement_data.erase("_confirm_exit")
					_placement_controller.confirm_placement(state)
					return
			
			ModeStateMachine.Mode.TRANSFORM:
				_transform_controller.process_input(camera, state, combined_settings, delta)
				_transform_controller.update_node_transforms(state)
				_update_overlay_display(mode, state)
				
				# Check for exit
				if state.session.transform_data.get("_confirm_exit", false):
					state.session.transform_data.erase("_confirm_exit")
					exit_transform_mode(true)
					return
	
	# Update visual systems
	if _services.smooth_transform_manager:
		_services.smooth_transform_manager.update_smooth_transforms(delta)
	
	if mode != ModeStateMachine.Mode.NONE:
		var placement_center = _services.position_manager.get_base_position(state)
		var target_nodes = state.session.transform_data.get("target_nodes", []) if mode == ModeStateMachine.Mode.TRANSFORM else []
		_services.grid_manager.update_grid_overlay(mode, combined_settings, state, placement_center, target_nodes)

func handle_mouse_motion(camera: Camera3D, mouse_position: Vector2) -> void:
	"""Handle mouse motion - delegates to InputProcessor"""
	_input_processor.handle_mouse_motion(camera, mouse_position, _state())

func handle_mouse_wheel_input(event: InputEventMouseButton) -> bool:
	"""Handle mouse wheel - delegates to InputProcessor"""
	return _input_processor.handle_mouse_wheel(event)

func handle_tab_key_activation(dock_instance = null, ignore_focus_lock: bool = false) -> void:
	"""Handle Tab key activation"""
	_input_processor._handle_tab_activation(_state(), ignore_focus_lock)

## Public API - Status Queries

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
	var state = _state()
	return _services.scale_manager.get_scale(state) if state else 1.0

func refresh_overlay() -> void:
	"""Refresh the overlay display if a mode is active"""
	if not is_any_mode_active():
		return
	
	var state = _state()
	if state:
		var mode = get_current_mode()
		_update_overlay_display(mode, state)

## Public API - Configuration

func set_placement_end_callback(callback: Callable) -> void:
	_state().session.placement_end_callback = callback

func set_mesh_placed_callback(callback: Callable) -> void:
	_state().session.mesh_placed_callback = callback

func set_dock_reference(dock_instance) -> void:
	_state().dock_reference = dock_instance

func update_settings(new_settings: Dictionary) -> void:
	_state().settings = new_settings.duplicate(true)

## Public API - Cleanup

func cleanup_all() -> void:
	exit_any_mode()
	_services.overlay_manager.cleanup_all_overlays()
	_services.preview_manager.cleanup_preview()
	_services.grid_manager.cleanup_grid()

func cleanup() -> void:
	cleanup_all()

## Public API - Transform Resets

func reset_transforms() -> void:
	"""Reset all transform offsets"""
	var state = _state()
	if not state:
		return
	
	var mode = _services.mode_state_machine.get_current_mode()
	
	if mode == ModeStateMachine.Mode.PLACEMENT:
		_services.rotation_manager.reset_all_rotation(state)
		_services.scale_manager.reset_scale(state)
		_services.position_manager.reset_offset_normal(state)
		state.values.manual_position_offset = Vector3.ZERO
		_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)
	
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var target_nodes = state.session.transform_data.get("target_nodes", [])
		var original_transforms = state.session.transform_data.get("original_transforms", {})
		
		# Reset all nodes
		for node in target_nodes:
			if node and node.is_inside_tree():
				_services.rotation_manager.reset_node_rotation(node)
				var original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
				node.scale = original_scale
				_services.smooth_transform_manager.apply_transform_immediately(node, node.global_position, node.rotation, node.scale)
		
		_services.scale_manager.reset_scale(state)
		_services.position_manager.reset_offset_normal(state)
		state.values.manual_position_offset = Vector3.ZERO
		
		var center_pos = state.values.base_position
		state.values.position = center_pos
		state.session.transform_data["center_position"] = center_pos
		
		_services.overlay_manager.show_status_message("Reset all transforms", Color.GREEN, 1.5)

func start_placement_from_node3d(node: Node3D, dock_instance = null) -> void:
	"""Start placement mode from an existing Node3D"""
	var extracted_mesh = _services.utility_manager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		var settings = _state().settings
		if settings.is_empty():
			settings = _services.settings_manager.get_combined_settings()
		start_placement_mode(extracted_mesh, null, -1, "", settings, dock_instance)
		_services.overlay_manager.show_status_message("Placement mode: " + node.name, Color.GREEN, 2.0)
	else:
		_services.overlay_manager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)

## Internal Helpers

func _state() -> TransformState:
	"""Get or create unified state"""
	if not _transform_state:
		_transform_state = TransformState.new()
	return _transform_state

func _ensure_undo_redo() -> void:
	"""Ensure undo/redo manager is available"""
	if not _services.undo_redo:
		_services.undo_redo = _services.editor_facade.get_editor_interface().get_editor_undo_redo()

func _configure_smooth_transforms(settings: Dictionary) -> void:
	"""Configure smooth transform system"""
	var smooth_enabled = settings.get("smooth_transforms", true)
	var smooth_speed = settings.get("smooth_transform_speed", 8.0)
	var smooth_config = {
		"smooth_enabled": smooth_enabled, 
		"smooth_speed": smooth_speed,
		"fine_position_increment": settings.get("fine_position_increment", 0.01),
		"fine_rotation_increment": settings.get("fine_rotation_increment", 5.0),
		"fine_scale_increment": settings.get("fine_scale_increment", 0.01)
	}
	
	_services.preview_manager.configure(smooth_config)
	_services.smooth_transform_manager.configure(smooth_config)
	
	var state = _state()
	_services.rotation_manager.configure(state, smooth_config)
	_services.scale_manager.configure(state, smooth_config)

func _update_overlay_display(mode: int, state: TransformState) -> void:
	"""Update overlay with current transform information"""
	if not _services.overlay_manager or not state:
		return
	
	var node_name = ""
	var rotation = state.values.surface_alignment_rotation + state.values.manual_rotation_offset
	var position = state.values.position + state.values.manual_position_offset
	var scale_value = state.values.scale_multiplier
	
	if mode == ModeStateMachine.Mode.TRANSFORM:
		var nodes = state.session.transform_data.get("target_nodes", [])
		if nodes.size() == 1:
			node_name = nodes[0].name if nodes[0] else ""
			if nodes[0] and is_instance_valid(nodes[0]):
				rotation = nodes[0].rotation
				position = nodes[0].global_position  # Use actual node position in transform mode
				scale_value = nodes[0].scale.x  # Use actual node scale in transform mode
		elif nodes.size() > 1:
			node_name = "%d nodes" % nodes.size()
			if nodes[0] and is_instance_valid(nodes[0]):
				rotation = nodes[0].rotation
				position = nodes[0].global_position  # Use actual node position in transform mode
				scale_value = nodes[0].scale.x  # Use actual node scale in transform mode
	
	var plane_normal = Vector3.UP
	if _services.position_manager:
		plane_normal = _services.position_manager.get_plane_normal_direction(state)
	var normal_offset = state.values.manual_position_offset.dot(plane_normal)
	
	_services.overlay_manager.show_transform_overlay(mode, node_name, position, rotation, scale_value, normal_offset, state)

func _grab_3d_viewport_focus() -> void:
	"""Attempt to grab focus for 3D viewport"""
	var focus_owner = _get_current_focus_owner()
	if _should_lock_input_to_ui(focus_owner):
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
	"""Find the spatial editor control"""
	if node and node.get_class() == "Node3DEditor":
		return node if node is Control else null
	
	if node:
		for child in node.get_children():
			var result = _find_spatial_editor(child)
			if result:
				return result
	
	return null

func _get_current_focus_owner() -> Control:
	"""Get the currently focused control"""
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

func _should_lock_input_to_ui(focus_owner: Control) -> bool:
	"""Check if input should be locked to UI (text editing, etc.)"""
	if not focus_owner:
		return false
	
	if _is_spatial_editor_control(focus_owner):
		return false
	
	if _is_text_input_control(focus_owner):
		return true
	
	return false

func _is_spatial_editor_control(control: Control) -> bool:
	"""Check if control is part of spatial editor"""
	var current: Node = control
	var depth = 0
	while current and depth < 8:
		if current.get_class() == "Node3DEditor":
			return true
		current = current.get_parent()
		depth += 1
	return false

func _is_text_input_control(control: Control) -> bool:
	"""Check if control is text input (LineEdit, TextEdit, SpinBox)"""
	if control is LineEdit or control is TextEdit:
		return true
	if control.get_class() == "SpinBox":
		return true
	
	var current: Node = control.get_parent()
	var depth = 0
	while current and depth < 5:
		if current is LineEdit or current is TextEdit:
			return true
		if current.get_class() == "SpinBox":
			return true
		current = current.get_parent()
		depth += 1
	
	return false
