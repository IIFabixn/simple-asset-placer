@tool
extends RefCounted

class_name PlacementModeHandler

"""
PLACEMENT MODE HANDLER (FULLY INSTANCE-BASED)
==============================================

PURPOSE: Handles all placement mode logic (preview mesh, input, placement)

RESPONSIBILITIES:
- Preview mesh initialization and management
- Placement mode input processing
- Position updates from mouse raycast
- Rotation and scale adjustments
- Asset cycling
- Actual placement operation
- Placement mode overlay updates

ARCHITECTURE: Fully instance-based with dependency injection
- Called by TransformationCoordinator when in placement mode
- Manages placement_data dictionary
- Receives injected manager instances via ServiceRegistry
- NO static methods

USED BY: TransformationCoordinator
USES: PreviewManager, PositionManager, RotationManager, ScaleManager, OverlayManager,
      InputHandler, UtilityManager, SmoothTransformManager (all via ServiceRegistry)
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

# Dependencies (injected via ServiceRegistry)
var _services: ServiceRegistry

## Initialization

func _init(services: ServiceRegistry) -> void:
	"""Initialize with service registry
	
	Args:
		services: ServiceRegistry containing all manager instances
	"""
	_services = services

## MODE ENTRY/EXIT

func enter_placement_mode(
	mesh: Mesh = null,
	meshlib: MeshLibrary = null,
	item_id: int = -1,
	asset_path: String = "",
	settings: Dictionary = {},
	transform_state: TransformState = null,
	undo_redo: EditorUndoRedoManager = null
) -> Dictionary:
	"""Initialize placement mode and return placement data
	
	Args:
		mesh: Direct mesh to place
		meshlib: MeshLibrary containing the item
		item_id: ID of item in MeshLibrary
		asset_path: Path to scene/asset to place
		settings: Placement settings dictionary
		transform_state: Transform state to configure
		undo_redo: EditorUndoRedoManager for undo/redo support
		
	Returns:
		Dictionary: placement_data containing all placement state
	"""
	# Store placement data
	var placement_data = {
		"mesh": mesh,
		"meshlib": meshlib,
		"item_id": item_id,
		"asset_path": asset_path,
		"settings": settings,
		"dock_reference": null,
		"undo_redo": undo_redo
	}
	
	# Initialize managers for placement mode
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(1)  # PLACEMENT mode (compatible with both old and new enum)
	
	# Setup preview if we have something to place
	if mesh:
		_services.preview_manager.start_preview_mesh(mesh, settings)
	elif meshlib and item_id >= 0:
		var preview_mesh = meshlib.get_item_mesh(item_id)
		if preview_mesh:
			_services.preview_manager.start_preview_mesh(preview_mesh, settings)
	elif asset_path != "":
		_services.preview_manager.start_preview_asset(asset_path, settings)
	
	# Configure position manager for placement
	if transform_state:
		_services.position_manager.configure(transform_state, settings)
	
	# Configure smooth transformations
	var smooth_enabled = settings.get("smooth_transforms", true)
	var smooth_speed = settings.get("smooth_transform_speed", 8.0)
	_services.preview_manager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	_services.smooth_transform_manager.configure(smooth_enabled, smooth_speed)
	_services.rotation_manager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	# Note: ScaleManager is static and doesn't need smooth transform configuration
	
	# Reset position manager for new placement
	# Reset height and position offsets only if the corresponding settings are enabled
	var reset_height = settings.get("reset_height_on_exit", false)
	var reset_position = settings.get("reset_position_on_exit", false)
	if transform_state:
		_services.position_manager.reset_for_new_placement(transform_state, reset_height, reset_position)
	
	# Reset rotation for new placement (unless user wants to keep rotation)
	if transform_state and not settings.get("keep_rotation_between_placements", false):
		_services.rotation_manager.reset_all_rotation(transform_state)
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started placement mode")
	
	return placement_data

func exit_placement_mode(
	placement_data: Dictionary,
	transform_state: TransformState,
	end_callback: Callable,
	settings: Dictionary
) -> void:
	"""Clean up placement mode
	
	Args:
		placement_data: Placement data dictionary
		transform_state: Transform state to reset
		end_callback: Callback to call when placement ends
		settings: Settings dictionary for reset behavior
	"""
	# Clean up preview (this also unregisters from smooth transforms)
	_services.preview_manager.cleanup_preview()
	
	# Call end callback if set
	if end_callback.is_valid():
		end_callback.call()
	
	# Reset transforms based on user settings
	_reset_transforms_on_exit(transform_state, settings)
	
	# Hide and cleanup overlays
	_services.overlay_manager.hide_transform_overlay()
	_services.overlay_manager.set_mode(0)  # NONE mode (compatible with both old and new enum)
	_services.overlay_manager.remove_grid_overlay()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited placement mode")

## INPUT PROCESSING

func process_input(
	camera: Camera3D,
	placement_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary,
	delta: float
) -> void:
	"""Process input for placement mode
	
	Args:
		camera: The 3D camera for raycasting
		placement_data: Placement data dictionary
		transform_state: Current transform state
		settings: Current settings dictionary
		delta: Frame delta time
	"""
	if not camera:
		return
	
	var position_input = _services.input_handler.get_position_input()
	var rotation_input = _services.input_handler.get_rotation_input()
	var scale_input = _services.input_handler.get_scale_input()
	
	# Set half-step mode based on configured fine increment modifier
	_services.position_manager.set_use_half_step(position_input.fine_increment_modifier_held)
	
	# Handle height adjustments
	_process_height_input(position_input, transform_state, settings)
	
	# Handle position adjustments (WASD-style movement)
	_process_position_input(camera, position_input, transform_state, settings)
	
	# Update position from mouse AFTER processing WASD input
	var mouse_pos = position_input.mouse_position
	
	# IMPORTANT: Exclude preview mesh from collision detection to prevent self-collision
	var exclude_nodes = []
	var preview_mesh = _services.preview_manager.get_preview_mesh()
	if NodeUtils.is_valid(preview_mesh):
		exclude_nodes.append(preview_mesh)
	
	_services.position_manager.update_position_from_mouse(transform_state, camera, mouse_pos, 1, true, exclude_nodes)
	
	# Get the updated position
	var preview_pos = _services.position_manager.get_current_position(transform_state)
	
	# Update preview position
	_services.preview_manager.update_preview_position(preview_pos)
	
	# Update surface normal alignment if enabled, otherwise reset it
	if settings.get("align_with_normal", false):
		_services.rotation_manager.align_with_surface_normal(transform_state, _services.position_manager.get_surface_normal(transform_state))
	else:
		_services.rotation_manager.reset_surface_alignment(transform_state)
	
	# Handle rotation input (this will be combined with surface alignment)
	# Don't rotate position offset - this makes rotation behave like transform mode (in-place)
	# Reuse preview_mesh variable from above
	_process_rotation_input(rotation_input, preview_mesh, transform_state, settings, false)
	
	# Apply the combined rotation (surface alignment + manual rotation) to the preview mesh
	if preview_mesh:
		_services.rotation_manager.apply_rotation_to_node(transform_state, preview_mesh)
	
	# Handle scale input
	_process_scale_input(scale_input, preview_mesh, transform_state, settings)
	
	# Handle asset cycling
	process_asset_cycling_input(placement_data)
	
	# Handle placement action
	if position_input.confirm_action:
		place_at_current_position(placement_data, transform_state)
	
	# Update overlays with current state
	update_overlays(placement_data, transform_state)

## INPUT HELPERS

func _process_height_input(
	position_input: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process height adjustment input
	
	Args:
		position_input: Position input dictionary from InputHandler
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	var reverse_height = position_input.reverse_modifier_held
	
	# Determine height step based on modifiers
	var height_step = _services.position_manager.get_height_step_size()
	
	# Apply Y snap step if Y snapping is enabled
	if transform_state.snap_y_enabled:
		height_step = transform_state.snap_y_step
	
	# Apply modifier keys for increment size
	if position_input.fine_increment_modifier_held:
		height_step *= 0.1
	elif position_input.large_increment_modifier_held:
		height_step *= 10.0
	
	if position_input.height_up_pressed:
		var height_change = height_step if not reverse_height else -height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	elif position_input.height_down_pressed:
		var height_change = -height_step if not reverse_height else height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	elif position_input.reset_height_pressed:
		_services.position_manager.reset_height(transform_state)

func _process_position_input(
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
	
	# Handle position adjustments (WASD-style movement) - directly modify manual offset
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
		_services.position_manager.reset_position(transform_state)

func _process_rotation_input(
	rotation_input: Dictionary,
	target_node: Node3D,
	transform_state: TransformState,
	settings: Dictionary,
	rotate_position_offset: bool = false
) -> void:
	"""Process rotation input for preview mesh
	
	Args:
		rotation_input: Rotation input dictionary from InputHandler
		target_node: The node to apply rotation to
		transform_state: Transform state to modify
		settings: Settings dictionary
		rotate_position_offset: If true, also rotates manual position offset
	"""
	if not target_node:
		return
	
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
	
	if rotation_input.x_pressed:
		_services.rotation_manager.apply_rotation_step(transform_state, target_node, "X", rotation_step, Vector3.ZERO, rotate_position_offset)
	elif rotation_input.y_pressed:
		_services.rotation_manager.apply_rotation_step(transform_state, target_node, "Y", rotation_step, Vector3.ZERO, rotate_position_offset)
	elif rotation_input.z_pressed:
		_services.rotation_manager.apply_rotation_step(transform_state, target_node, "Z", rotation_step, Vector3.ZERO, rotate_position_offset)
	elif rotation_input.reset_pressed:
		_services.rotation_manager.reset_node_rotation(target_node)

func _process_scale_input(
	scale_input: Dictionary,
	target_node: Node3D,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process scale input for preview mesh
	
	Args:
		scale_input: Scale input dictionary from InputHandler
		target_node: The node to apply scale to
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	if not target_node:
		return
	
	# Determine which increment to use based on modifiers
	var scale_step: float
	if scale_input.large_increment_modifier_held:
		scale_step = settings.get("large_scale_increment", 0.5)
	elif scale_input.fine_increment_modifier_held:
		scale_step = settings.get("fine_scale_increment", 0.01)
	else:
		scale_step = settings.get("scale_increment", 0.1)
	
	if scale_input.up_pressed:
		_services.scale_manager.increase_scale(transform_state, scale_step)
		var new_scale = _services.scale_manager.get_scale_vector(transform_state)
		_services.preview_manager.update_preview_scale(new_scale)
	elif scale_input.down_pressed:
		_services.scale_manager.decrease_scale(transform_state, scale_step)
		var new_scale = _services.scale_manager.get_scale_vector(transform_state)
		_services.preview_manager.update_preview_scale(new_scale)
	elif scale_input.reset_pressed:
		_services.scale_manager.reset_scale(transform_state)
		var new_scale = _services.scale_manager.get_scale_vector(transform_state)
		_services.preview_manager.update_preview_scale(new_scale)

## ASSET CYCLING

func process_asset_cycling_input(placement_data: Dictionary) -> void:
	"""Process asset cycling input during placement mode
	
	Args:
		placement_data: Placement data dictionary containing dock reference
	"""
	# Get the dock reference to call cycling methods
	var dock = placement_data.get("dock_reference", null)
	if not dock:
		return
	
	# Check for cycling input
	if _services.input_handler.should_cycle_next_asset():
		if dock.has_method("cycle_next_asset"):
			dock.cycle_next_asset()
	elif _services.input_handler.should_cycle_previous_asset():
		if dock.has_method("cycle_previous_asset"):
			dock.cycle_previous_asset()

## PLACEMENT

func place_at_current_position(
	placement_data: Dictionary,
	transform_state: TransformState,
	placed_callback: Callable = Callable()
) -> Node3D:
	"""Place object at current preview position
	
	Args:
		placement_data: Placement data dictionary (must contain undo_redo if undo is needed)
		transform_state: Transform state containing placement transform
		placed_callback: Optional callback to call when placement succeeds
		
	Returns:
		Node3D: The placed node, or null if placement failed
	"""
	var position = _services.position_manager.get_current_position(transform_state)
	var placed_node = null
	
	# Debug: Log transform state scale
	if transform_state:
		PluginLogger.info("PlacementModeHandler", "Placing with scale multiplier: " + str(transform_state.scale_multiplier))
	
	# Use internal placement functions
	var mesh = placement_data.get("mesh")
	var meshlib = placement_data.get("meshlib")
	var item_id = placement_data.get("item_id", -1)
	var asset_path = placement_data.get("asset_path", "")
	var settings = placement_data.get("settings", {})
	
	if meshlib and item_id >= 0:
		placed_node = _services.utility_manager.place_meshlib_item_in_scene(
			meshlib,
			item_id,
			position,
			settings,
			transform_state
		)
	elif asset_path != "":
		placed_node = _services.utility_manager.place_asset_in_scene(
			asset_path,
			position,
			settings,
			transform_state
		)
	elif mesh:
		placed_node = _services.utility_manager.place_mesh_in_scene(
			mesh,
			position,
			settings,
			transform_state
		)
	
	# Create undo/redo action if placement succeeded
	if placed_node:
		var undo_redo = placement_data.get("undo_redo")
		if undo_redo:
			# Generate action name based on what was placed
			var action_name = ""
			if meshlib and item_id >= 0:
				action_name = "Place " + meshlib.get_item_name(item_id)
			else:
				action_name = "Place " + placed_node.name
			
			# Create undo action
			if _services and _services.undo_redo_helper:
				var success = _services.undo_redo_helper.create_placement_undo(undo_redo, placed_node, action_name)
				if not success:
					PluginLogger.warning("PlacementModeHandler", "Failed to create undo action for placement")
	
	# Call placement callback
	if placed_node and placed_callback.is_valid():
		placed_callback.call(placed_node)
	
	# Show feedback
	if placed_node:
		_services.overlay_manager.show_status_message("Placed: " + placed_node.name, Color.GREEN, 1.0)
	
	return placed_node

## NODE3D PLACEMENT

func start_from_node3d(node: Node3D, settings: Dictionary) -> Dictionary:
	"""Start placement mode from a Node3D by extracting its mesh
	
	Args:
		node: The Node3D to extract mesh from
		settings: Settings dictionary
		
	Returns:
		Dictionary: placement_data if successful, empty dict if failed
	"""
	var extracted_mesh = _services.utility_manager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		_services.overlay_manager.show_status_message("Placement mode activated for: " + node.name, Color.GREEN, 2.0)
		# Return minimal placement data - coordinator will call enter_placement_mode
		return {
			"mesh": extracted_mesh,
			"meshlib": null,
			"item_id": -1,
			"asset_path": "",
			"settings": settings
		}
	else:
		_services.overlay_manager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)
		return {}

## OVERLAY UPDATE

func update_overlays(placement_data: Dictionary, transform_state: TransformState) -> void:
	"""Update all overlays for placement mode
	
	Args:
		placement_data: Placement data dictionary
		transform_state: Transform state containing current transform
	"""
	var asset_path = placement_data.get("asset_path", "")
	var current_asset_name = asset_path.get_file().get_basename() if asset_path != "" else "Mesh"
	
	_services.overlay_manager.show_transform_overlay(
		1,  # PLACEMENT mode (compatible with both old and new enum)
		current_asset_name,
		_services.position_manager.get_current_position(transform_state),
		_services.preview_manager.get_preview_rotation(),
		_services.scale_manager.get_scale(transform_state),
		_services.position_manager.get_height_offset(transform_state)
	)

## RESET MANAGEMENT

func _reset_transforms_on_exit(transform_state: TransformState, settings: Dictionary) -> void:
	"""Reset transforms based on user settings when exiting placement mode
	
	Args:
		transform_state: Transform state to reset
		settings: Settings dictionary containing reset preferences
	"""
	if not transform_state:
		return
	
	# Reset height offset if enabled
	if settings.get("reset_height_on_exit", false):
		_services.position_manager.reset_height(transform_state)
	
	# Reset position offset if enabled
	if settings.get("reset_position_on_exit", false):
		_services.position_manager.reset_position(transform_state)
	
	# Reset scale if enabled
	if settings.get("reset_scale_on_exit", false):
		_services.scale_manager.reset_scale(transform_state)
	
	# Reset rotation if enabled
	if settings.get("reset_rotation_on_exit", false):
		_services.rotation_manager.reset_rotation(transform_state)
	
	# Always reset surface alignment when exiting modes
	_services.rotation_manager.reset_surface_alignment(transform_state)
