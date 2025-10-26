@tool
extends RefCounted

class_name PlacementModeController

"""
PLACEMENT MODE CONTROLLER
=========================

PURPOSE: Handle all placement mode operations (placing new assets)

RESPONSIBILITIES:
- Start/exit placement mode
- Configure managers for placement
- Process placement input (WASD/QE, rotation, scale)
- Handle asset placement confirmation
- Update preview mesh transform

ARCHITECTURE: Focused controller extracted from TransformationCoordinator
- Single responsibility: placement mode
- Clean separation from transform mode
- No legacy code or backwards compatibility

USED BY: TransformationCoordinator (delegates placement operations)
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")
const TransformInputController = preload("res://addons/simpleassetplacer/core/transform_input_controller.gd")

var _services  # ServiceRegistry
var _input_controller: TransformInputController

func _init(services) -> void:
	_services = services
	_input_controller = TransformInputController.new(services)

## Mode Lifecycle

func start(mesh: Mesh, meshlib, item_id: int, asset_path: String, settings: Dictionary, dock_instance, state: TransformState) -> void:
	"""Start placement mode with the given asset"""
	if not _services.mode_state_machine.transition_to_mode(ModeStateMachine.Mode.PLACEMENT):
		return
	
	# Reset control mode when entering placement
	if _services.control_mode_state:
		_services.control_mode_state.reset()
	
	# Initialize session
	state.begin_session(ModeStateMachine.Mode.PLACEMENT, settings)
	state.dock_reference = dock_instance
	
	# Store placement data
	state.session.placement_data = {
		"mesh": mesh,
		"meshlib": meshlib,
		"item_id": item_id,
		"asset_path": asset_path,
		"settings": settings,
		"dock_reference": dock_instance,
		"undo_redo": _services.undo_redo
	}
	
	# Initialize overlays
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(ModeStateMachine.Mode.PLACEMENT)
	
	# Setup preview mesh
	_setup_preview(mesh, meshlib, item_id, asset_path, settings)
	
	# Configure managers
	_configure_managers(state, settings)
	
	# Initialize plane strategy
	if _services.placement_strategy_service:
		_services.placement_strategy_service.initialize_plane_for_placement()
	
	# Setup viewport focus
	_services.grid_manager.reset_tracking()
	state.session.focus_grab_frames = PluginConstants.FOCUS_GRAB_FRAMES
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started placement mode")

func exit(state: TransformState) -> void:
	"""Exit placement mode and cleanup"""
	if not _services.mode_state_machine.is_placement_mode():
		return
	
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

## Input Processing

func process_input(camera: Camera3D, state: TransformState, settings: Dictionary, delta: float) -> void:
	"""Process all placement mode input (delegates to TransformInputController)"""
	if not state or not camera:
		return
	
	# Process keyboard input through unified controller
	var changes = _input_controller.process_keyboard_input(camera, state, settings)
	
	# Check for placement confirmation
	if changes.get("confirm_action", false):
		state.session.placement_data["_confirm_exit"] = true

func update_preview_transform(state: TransformState) -> void:
	"""Apply current state transforms to the preview mesh"""
	var preview_mesh = _services.preview_manager.get_preview_mesh()
	if not preview_mesh or not is_instance_valid(preview_mesh):
		return
	
	# Calculate final transform
	var final_position = state.values.position + state.values.manual_position_offset
	var final_rotation = state.values.surface_alignment_rotation + state.values.manual_rotation_offset
	var final_scale = Vector3.ONE * state.values.scale_multiplier
	
	# Apply through smooth transform manager
	if _services.smooth_transform_manager:
		_services.smooth_transform_manager.set_target_transform(
			preview_mesh,
			final_position,
			final_rotation,
			final_scale
		)
	else:
		# Fallback: apply directly
		preview_mesh.global_position = final_position
		preview_mesh.rotation = final_rotation
		preview_mesh.scale = final_scale

## Helper Methods

func _setup_preview(mesh: Mesh, meshlib, item_id: int, asset_path: String, settings: Dictionary) -> void:
	"""Setup the preview mesh for placement"""
	if mesh:
		_services.preview_manager.start_preview_mesh(mesh, settings)
	elif meshlib and item_id >= 0:
		var preview_mesh = meshlib.get_item_mesh(item_id)
		if preview_mesh:
			_services.preview_manager.start_preview_mesh(preview_mesh, settings)
	elif asset_path != "":
		_services.preview_manager.start_preview_asset(asset_path, settings)

func _configure_managers(state: TransformState, settings: Dictionary) -> void:
	"""Configure all managers for placement mode"""
	_services.position_manager.configure(state, settings)
	
	var smooth_enabled = settings.get("smooth_transforms", true)
	var smooth_speed = settings.get("smooth_transform_speed", 8.0)
	var smooth_config = {"smooth_enabled": smooth_enabled, "smooth_speed": smooth_speed}
	
	_services.preview_manager.configure(smooth_config)
	_services.smooth_transform_manager.configure(smooth_enabled, smooth_speed)
	_services.rotation_manager.configure(state, smooth_config)
	
	# Reset for new placement
	var reset_height = settings.get("reset_height_on_exit", false)
	var reset_position = settings.get("reset_position_on_exit", false)
	_services.position_manager.reset_for_new_placement(state, reset_height, reset_position)
	
	if not settings.get("keep_rotation_between_placements", false):
		_services.rotation_manager.reset_all_rotation(state)

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
