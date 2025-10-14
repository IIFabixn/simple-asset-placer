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
const NumericInputManager = preload("res://addons/simpleassetplacer/managers/numeric_input_manager.gd")
const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")

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
	var smooth_config = {
		"smooth_enabled": smooth_enabled,
		"smooth_speed": smooth_speed
	}
	
	_services.preview_manager.configure(smooth_config)
	_services.smooth_transform_manager.configure(smooth_enabled, smooth_speed)
	_services.rotation_manager.configure(transform_state, smooth_config)
	
	# Reset position manager for new placement
	# Reset height and position offsets only if the corresponding settings are enabled
	var reset_height = settings.get("reset_height_on_exit", false)
	var reset_position = settings.get("reset_position_on_exit", false)
	if transform_state:
		_services.position_manager.reset_for_new_placement(transform_state, reset_height, reset_position)
	
	# Reset rotation for new placement (unless user wants to keep rotation)
	if transform_state and not settings.get("keep_rotation_between_placements", false):
		_services.rotation_manager.reset_all_rotation(transform_state)
	
	# Start in Position control mode (G) by default
	if _services.control_mode_state:
		_services.control_mode_state.switch_to_position_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Auto-activated Position control (G) on placement mode entry")
	
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
	
	# Process control mode transitions (G/R/L keys) and axis constraints (X/Y/Z keys)
	_process_control_mode_input(placement_data, transform_state)
	
	# Get control mode state to determine input routing
	var control_mode = _services.control_mode_state
	var modal_active = control_mode.is_modal_active() if control_mode else false
	
	# Get input dictionaries (InputHandler already suppresses numeric taps when modal active)
	var position_input = _services.input_handler.get_position_input()
	var rotation_input = _services.input_handler.get_rotation_input()
	var scale_input = _services.input_handler.get_scale_input()
	var numeric_input = _services.input_handler.get_numeric_input()
	var numeric_mgr = _services.numeric_input_manager
	
	# === INPUT ROUTING ===
	# Simple rule: If modal active (G/R/L pressed), skip keyboard input tracking
	# Otherwise, process keyboard input for numeric system and direct controls
	
	if not modal_active:
		# Check for numeric input confirmation and application
		if numeric_mgr.is_confirmed():
			_apply_numeric_input(placement_data, transform_state, settings)
			numeric_mgr.reset()
		
		# Track action key presses for numeric input system
		_track_action_for_numeric_input(rotation_input, scale_input, position_input)
	
	# Update numeric input overlay if active
	if numeric_mgr.is_active() and numeric_mgr.is_within_grace_period():
		var action_name = numeric_mgr.get_action_display_name()
		var input_string = numeric_mgr.get_input_string()
		_services.overlay_manager.show_numeric_input(action_name, input_string)
	
	# If numeric input is active, skip normal input processing (except mouse/position tracking)
	var skip_normal_input = numeric_mgr.is_active() and not numeric_mgr.is_confirmed()
	
	# Set half-step mode based on configured fine increment modifier
	var fine_modifier_held = position_input.fine_increment_modifier_held
	_services.position_manager.set_use_half_step(fine_modifier_held)
	transform_state.use_half_step = fine_modifier_held
	
	# Handle height adjustments (Q/E for quick vertical adjustments)
	if not skip_normal_input:
		_process_height_input(position_input, transform_state, settings)
	
	# Get mouse position and preview mesh
	var mouse_pos = position_input.mouse_position
	var preview_mesh = _services.preview_manager.get_preview_mesh()
	
	# IMPORTANT: Exclude preview mesh from collision detection to prevent self-collision
	var exclude_nodes = []
	if NodeUtils.is_valid(preview_mesh):
		exclude_nodes.append(preview_mesh)
	
	# === MODAL CONTROL PROCESSING ===
	# Process modal controls (G/R/L + mouse) when modal is active
	const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
	
	# Check if exclusive mode is enabled (modal_active already defined above)
	var modal_exclusive = settings.get("modal_control_exclusive", true)
	var should_lock_rotation = modal_active and modal_exclusive and control_mode.is_position_mode()
	
	if modal_active:
		match control_mode.get_control_mode():
			ControlModeState.ControlMode.POSITION:
				# Position mode: Mouse controls position
				# Store previous position for axis constraint
				var prev_pos = _services.position_manager.get_current_position(transform_state)
				
				# Calculate new position based on axis constraints
				var new_pos = Vector3.ZERO
				
				if control_mode.has_axis_constraint():
					# Use plane intersection for constrained movement
					new_pos = _calculate_constrained_position(camera, mouse_pos, prev_pos, control_mode)
				else:
					# No constraints: Use raycast for precise surface-based positioning
					# This gives better control by snapping to actual geometry
					new_pos = _services.position_manager.update_position_from_mouse(
						transform_state, camera, mouse_pos, 1, false, exclude_nodes
					)
				
				# Apply grid snapping if enabled (for modal G mode positioning)
				# Pass fine modifier state for half-step sub-grid
				if transform_state.snap_enabled or transform_state.snap_y_enabled:
					var use_half_step = position_input.fine_increment_modifier_held
					new_pos = TransformApplicator.apply_grid_snap(new_pos, transform_state, use_half_step)
				
				# Update transform state with new position
				transform_state.position = new_pos
				transform_state.target_position = new_pos
				
				# Update preview position
				if preview_mesh:
					preview_mesh.global_position = new_pos
				
				# Handle rotation updates based on modal state
				if should_lock_rotation:
					# G mode explicitly active with exclusive controls: Don't update rotation
					pass
				else:
					# Normal mode OR non-exclusive: Update surface normal alignment if enabled
					if settings.get("align_with_normal", false):
						_services.rotation_manager.align_with_surface_normal(transform_state, _services.position_manager.get_surface_normal(transform_state))
						# Apply rotation to preview
						if preview_mesh:
							TransformApplicator.apply_rotation_only(preview_mesh, transform_state)
					else:
						_services.rotation_manager.reset_surface_alignment(transform_state)
			
			ControlModeState.ControlMode.ROTATION:
				# R mode: Mouse controls rotation
				if not skip_normal_input:
					_process_mouse_rotation(camera, mouse_pos, transform_state, settings)
					
					# Apply rotation to preview mesh immediately (bypass smooth transforms)
					if preview_mesh:
						TransformApplicator.apply_rotation_only(preview_mesh, transform_state)
			
			ControlModeState.ControlMode.SCALE:
				# L mode: Mouse controls scale (vertical movement, per-axis or uniform)
				if not skip_normal_input:
					_process_mouse_scale(mouse_pos, transform_state, settings)
					
					# Apply scale to preview mesh immediately (bypass smooth transforms)
					if preview_mesh:
						var base_scale = transform_state.original_scale if transform_state.has("original_scale") else Vector3.ONE
						TransformApplicator.apply_scale_only(preview_mesh, transform_state, base_scale)
	
	# Handle asset cycling (always available)
	if not skip_normal_input:
		process_asset_cycling_input(placement_data)
	
	# Handle placement action
	if position_input.confirm_action:
		# If numeric input is active, confirm it instead of placing
		if numeric_mgr.is_active():
			numeric_mgr.confirm_action()
		else:
			place_at_current_position(placement_data, transform_state)
	
	# Update overlays with current state
	update_overlays(placement_data, transform_state)

## CONTROL MODE MANAGEMENT

func _process_control_mode_input(placement_data: Dictionary, transform_state: TransformState) -> void:
	"""Process control mode transitions (G/R/L) and axis constraints (X/Y/Z)
	
	This handles Blender-style modal controls:
	- G = Position control mode
	- R = Rotation control mode
	- L = Scale control mode
	- X/Y/Z = Axis constraint toggle (double-tap to disable)
	"""
	var control_input = _services.input_handler.get_control_mode_input()
	var control_mode = _services.control_mode_state
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle control mode transitions
	if control_input.position_control_pressed:
		control_mode.switch_to_position_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Position control (G)")
	elif control_input.rotation_control_pressed:
		control_mode.switch_to_rotation_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Rotation control (R)")
	elif control_input.scale_control_pressed:
		control_mode.switch_to_scale_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Scale control (L)")
	
	# Handle axis constraints (X/Y/Z keys)
	# Pass current position so it can be stored as constraint origin
	var current_pos = transform_state.position
	if control_input.axis_x_pressed:
		control_mode.process_axis_key_press("X", current_time, current_pos)
	elif control_input.axis_y_pressed:
		control_mode.process_axis_key_press("Y", current_time, current_pos)
	elif control_input.axis_z_pressed:
		control_mode.process_axis_key_press("Z", current_time, current_pos)

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

func _process_mouse_rotation(
	camera: Camera3D,
	mouse_pos: Vector2,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process mouse movement for rotation control (R mode)
	
	Uses horizontal mouse movement to rotate around the constrained axis,
	or around Y-axis if no constraint is active.
	
	Args:
		camera: The 3D camera
		mouse_pos: Current mouse position in viewport
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	if not camera:
		return
	
	# Get viewport for delta calculation and cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport:
		return
	
	# Store previous mouse position for delta calculation
	if not transform_state.has("_prev_mouse_pos"):
		transform_state.set("_prev_mouse_pos", mouse_pos)
		return
	
	var prev_mouse_pos = transform_state.get("_prev_mouse_pos")
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Cursor warping: If mouse is near screen edges, warp to center
	# This allows infinite rotation without hitting screen boundaries
	var viewport_rect = viewport.get_visible_rect()
	var viewport_size = viewport_rect.size
	var warp_margin = 50  # pixels from edge before warping
	var should_warp = false
	var warp_target_local = mouse_pos  # Target in viewport-local space
	
	# Check if we need to warp (using viewport-local coordinates)
	if mouse_pos.x < warp_margin or mouse_pos.x > viewport_size.x - warp_margin:
		warp_target_local.x = viewport_size.x / 2
		should_warp = true
	if mouse_pos.y < warp_margin or mouse_pos.y > viewport_size.y - warp_margin:
		warp_target_local.y = viewport_size.y / 2
		should_warp = true
	
	if should_warp:
		# Convert viewport-local position to global screen position
		# SubViewport doesn't have get_screen_position(), so we use get_screen_transform()
		var viewport_screen_transform = viewport.get_screen_transform()
		var warp_target_global = viewport_screen_transform * warp_target_local
		
		# Warp cursor using global screen coordinates
		Input.warp_mouse(warp_target_global)
		
		# Update tracking to new position (prevents jump in delta)
		transform_state.set("_prev_mouse_pos", warp_target_local)
	else:
		transform_state.set("_prev_mouse_pos", mouse_pos)
	
	# Determine which axis to rotate around
	# In rotation mode, axis constraints specify which axis to rotate around
	# If multiple axes are constrained, use the first one (X > Y > Z priority)
	# If no constraint, rotate around camera Y axis (Blender default)
	var control_mode = _services.control_mode_state
	var rotate_around_axis = ""
	
	if control_mode.has_axis_constraint():
		# Priority: X > Y > Z (if multiple constraints, use first one)
		if control_mode.is_x_constrained():
			rotate_around_axis = "X"
		elif control_mode.is_y_constrained():
			rotate_around_axis = "Y"
		elif control_mode.is_z_constrained():
			rotate_around_axis = "Z"
	else:
		# No constraint: Rotate around Y axis (default)
		rotate_around_axis = "Y"
	
	# Calculate rotation based on horizontal mouse movement
	# Sensitivity: pixels to degrees
	var rotation_sensitivity = settings.get("mouse_rotation_sensitivity", 0.5)
	var rotation_amount = -mouse_delta.x * rotation_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler.is_fine_increment_modifier_held():
		# Fine modifier: More precise control (default 0.1x)
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= fine_multiplier
	elif input_handler.is_large_increment_modifier_held():
		# Large modifier: Faster control (default 2.0x)
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= large_multiplier
	
	# Apply rotation snapping if enabled
	if transform_state.snap_rotation_enabled:
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Rotation snapping ACTIVE - step: %s, half_step: %s" % [transform_state.snap_rotation_step, transform_state.use_half_step])
		# Get current rotation in degrees for the target axis
		var current_rotation_deg = 0.0
		match rotate_around_axis:
			"X":
				current_rotation_deg = rad_to_deg(transform_state.manual_rotation_offset.x)
			"Y":
				current_rotation_deg = rad_to_deg(transform_state.manual_rotation_offset.y)
			"Z":
				current_rotation_deg = rad_to_deg(transform_state.manual_rotation_offset.z)
		
		# Add the rotation amount (in degrees)
		var new_rotation_deg = current_rotation_deg + rotation_amount
		
		# Apply snapping with half-step support
		var snap_step = transform_state.snap_rotation_step
		if transform_state.use_half_step:
			snap_step = snap_step / 2.0
		
		# Snap to nearest increment
		new_rotation_deg = round(new_rotation_deg / snap_step) * snap_step
		
		# Set the snapped rotation (convert back to radians)
		match rotate_around_axis:
			"X":
				transform_state.manual_rotation_offset.x = deg_to_rad(new_rotation_deg)
			"Y":
				transform_state.manual_rotation_offset.y = deg_to_rad(new_rotation_deg)
			"Z":
				transform_state.manual_rotation_offset.z = deg_to_rad(new_rotation_deg)
	else:
		# No snapping - apply rotation directly
		# Convert to radians
		rotation_amount = deg_to_rad(rotation_amount)
		
		# Apply rotation to transform state
		match rotate_around_axis:
			"X":
				transform_state.manual_rotation_offset.x += rotation_amount
			"Y":
				transform_state.manual_rotation_offset.y += rotation_amount
			"Z":
				transform_state.manual_rotation_offset.z += rotation_amount

func _process_mouse_scale(
	mouse_pos: Vector2,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process mouse movement for scale control (L mode)
	
	Uses vertical mouse movement to adjust scale.
	
	Args:
		mouse_pos: Current mouse position in viewport
		transform_state: Transform state to modify
		settings: Settings dictionary
	"""
	# Get viewport for cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	
	# Store previous mouse position for delta calculation
	if not transform_state.has("_prev_mouse_pos_scale"):
		transform_state.set("_prev_mouse_pos_scale", mouse_pos)
		return
	
	var prev_mouse_pos = transform_state.get("_prev_mouse_pos_scale")
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Cursor warping: If mouse is near screen edges, warp to center
	# This allows infinite scaling without hitting screen boundaries
	if viewport:
		var viewport_rect = viewport.get_visible_rect()
		var viewport_size = viewport_rect.size
		var warp_margin = 50  # pixels from edge before warping
		var should_warp = false
		var warp_target_local = mouse_pos
		
		if mouse_pos.x < warp_margin or mouse_pos.x > viewport_size.x - warp_margin:
			warp_target_local.x = viewport_size.x / 2
			should_warp = true
		if mouse_pos.y < warp_margin or mouse_pos.y > viewport_size.y - warp_margin:
			warp_target_local.y = viewport_size.y / 2
			should_warp = true
		
		if should_warp:
			# Convert viewport-local position to global screen position
			# SubViewport doesn't have get_screen_position(), so we use get_screen_transform()
			var viewport_screen_transform = viewport.get_screen_transform()
			var warp_target_global = viewport_screen_transform * warp_target_local
			
			# Warp cursor using global screen coordinates
			Input.warp_mouse(warp_target_global)
			
			transform_state.set("_prev_mouse_pos_scale", warp_target_local)
		else:
			transform_state.set("_prev_mouse_pos_scale", mouse_pos)
	else:
		transform_state.set("_prev_mouse_pos_scale", mouse_pos)
	
	# Calculate scale change based on vertical mouse movement
	# Sensitivity: pixels to scale factor
	var scale_sensitivity = settings.get("mouse_scale_sensitivity", 0.01)
	var scale_delta = -mouse_delta.y * scale_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler.is_fine_increment_modifier_held():
		# Fine modifier: More precise control (default 0.1x)
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		scale_delta *= fine_multiplier
	elif input_handler.is_large_increment_modifier_held():
		# Large modifier: Faster control (default 2.0x)
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		scale_delta *= large_multiplier
	
	# Check for axis constraints (L + X/Y/Z for per-axis scaling)
	var control_mode = _services.control_mode_state
	var has_constraint = control_mode.has_axis_constraint()
	
	if has_constraint:
		# Per-axis scaling: Apply delta only to constrained axes
		var current_scale_vector = _services.scale_manager.get_scale_vector(transform_state)
		var new_scale_vector = current_scale_vector
		
		if control_mode.is_x_constrained():
			new_scale_vector.x = current_scale_vector.x + scale_delta
		if control_mode.is_y_constrained():
			new_scale_vector.y = current_scale_vector.y + scale_delta
		if control_mode.is_z_constrained():
			new_scale_vector.z = current_scale_vector.z + scale_delta
		
		# Apply scale snapping if enabled (per-axis)
		if transform_state.snap_scale_enabled:
			var snap_step = transform_state.snap_scale_step
			if transform_state.use_half_step:
				snap_step = snap_step / 2.0
			
			if control_mode.is_x_constrained():
				new_scale_vector.x = round(new_scale_vector.x / snap_step) * snap_step
			if control_mode.is_y_constrained():
				new_scale_vector.y = round(new_scale_vector.y / snap_step) * snap_step
			if control_mode.is_z_constrained():
				new_scale_vector.z = round(new_scale_vector.z / snap_step) * snap_step
		
		# Clamp to reasonable values
		new_scale_vector.x = clamp(new_scale_vector.x, 0.01, 100.0)
		new_scale_vector.y = clamp(new_scale_vector.y, 0.01, 100.0)
		new_scale_vector.z = clamp(new_scale_vector.z, 0.01, 100.0)
		
		_services.scale_manager.set_non_uniform_multiplier(transform_state, new_scale_vector)
	else:
		# Uniform scaling: Apply delta to all axes equally
		var current_scale = _services.scale_manager.get_scale(transform_state)
		var new_scale = current_scale + scale_delta
		
		# Apply scale snapping if enabled (uniform)
		if transform_state.snap_scale_enabled:
			PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Scale snapping ACTIVE - step: %s, half_step: %s" % [transform_state.snap_scale_step, transform_state.use_half_step])
			var snap_step = transform_state.snap_scale_step
			if transform_state.use_half_step:
				snap_step = snap_step / 2.0
			
			# Snap to nearest increment
			new_scale = round(new_scale / snap_step) * snap_step
		
		# Clamp scale to reasonable values
		new_scale = clamp(new_scale, 0.01, 100.0)
		
		_services.scale_manager.set_scale_multiplier(transform_state, new_scale)

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

## Numeric Input Integration

func _track_action_for_numeric_input(rotation_input: Dictionary, scale_input: Dictionary, position_input: Dictionary) -> void:
	"""Track when action keys are TAPPED (not held) to set context for numeric input.
	The numeric input will only activate when user actually types a number.
	
	IMPORTANT CONTEXT-AWARE ROUTING:
	- In Position mode (G): X/Y/Z are axis constraints ONLY (no numeric input)
	- In Rotation mode (R): X/Y/Z trigger numeric rotation input (+ axis constraints)
	- In Scale mode (L): X/Y/Z trigger numeric scale input (+ axis constraints)
	- When no modal active: X/Y/Z trigger rotation numeric input
	"""
	var numeric_mgr = _services.numeric_input_manager
	if not numeric_mgr:
		return
	
	# Check current control mode to determine X/Y/Z behavior
	var control_mode = _services.control_mode_state
	var is_position_mode = control_mode.is_position_mode() if control_mode else false
	
	var ActionType = NumericInputManager.ActionType
	
	# Track rotation actions (only on tap, not on hold/repeat)
	# X/Y/Z keys for numeric input - BUT skip in Position mode (they're pure axis constraints there)
	if not is_position_mode:
		if rotation_input.get("x_tapped", false):
			numeric_mgr.set_action_context(ActionType.ROTATE_X)
		elif rotation_input.get("y_tapped", false):
			numeric_mgr.set_action_context(ActionType.ROTATE_Y)
		elif rotation_input.get("z_tapped", false):
			numeric_mgr.set_action_context(ActionType.ROTATE_Z)
	
	# Track scale actions (only on tap, not on hold/repeat)
	elif scale_input.get("up_tapped", false) or scale_input.get("down_tapped", false):
		numeric_mgr.set_action_context(ActionType.SCALE)
	
	# Track height actions (only on tap, not on hold/repeat)
	elif position_input.get("height_up_tapped", false) or position_input.get("height_down_tapped", false):
		numeric_mgr.set_action_context(ActionType.HEIGHT)
	
	# Track position actions (only on tap, not on hold/repeat)
	elif position_input.get("position_forward_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_FORWARD)
	elif position_input.get("position_backward_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_BACKWARD)
	elif position_input.get("position_left_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_LEFT)
	elif position_input.get("position_right_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_RIGHT)

func _apply_numeric_input(placement_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	"""Apply the confirmed numeric input value to the transformation"""
	var numeric_mgr = _services.numeric_input_manager
	if not numeric_mgr or not numeric_mgr.is_active():
		return
	
	var action = numeric_mgr.get_active_action()
	var ActionType = NumericInputManager.ActionType
	var preview_mesh = _services.preview_manager.get_preview_mesh()
	
	match action:
		ActionType.ROTATE_X, ActionType.ROTATE_Y, ActionType.ROTATE_Z:
			_apply_numeric_rotation(action, numeric_mgr, preview_mesh, transform_state)
		
		ActionType.SCALE:
			_apply_numeric_scale(numeric_mgr, preview_mesh, transform_state)
		
		ActionType.HEIGHT:
			_apply_numeric_height(numeric_mgr, transform_state)
		
		ActionType.POSITION_FORWARD, ActionType.POSITION_BACKWARD, ActionType.POSITION_LEFT, ActionType.POSITION_RIGHT:
			_apply_numeric_position(action, numeric_mgr, transform_state)

func _apply_numeric_rotation(action, numeric_mgr, preview_mesh: Node3D, transform_state: TransformState) -> void:
	"""Apply numeric input to rotation"""
	if not preview_mesh:
		return
	
	var ActionType = NumericInputManager.ActionType
	var axis = ""
	match action:
		ActionType.ROTATE_X:
			axis = "X"
		ActionType.ROTATE_Y:
			axis = "Y"
		ActionType.ROTATE_Z:
			axis = "Z"
	
	if axis == "":
		return
	
	# Get current rotation
	var current_rotation_deg = rad_to_deg(preview_mesh.rotation[axis.to_lower()])
	
	# Apply numeric value
	var new_rotation_deg = numeric_mgr.apply_to_value(current_rotation_deg)
	var rotation_step = new_rotation_deg - current_rotation_deg
	
	# Apply the rotation
	_services.rotation_manager.rotate_axis(transform_state, axis, rotation_step)
	if preview_mesh:
		TransformApplicator.apply_rotation_only(preview_mesh, transform_state)

func _apply_numeric_scale(numeric_mgr, preview_mesh: Node3D, transform_state: TransformState) -> void:
	"""Apply numeric input to scale"""
	var current_scale = _services.scale_manager.get_scale(transform_state)
	var new_scale = numeric_mgr.apply_to_value(current_scale)
	
	# Set the scale directly
	_services.scale_manager.set_scale_multiplier(transform_state, new_scale)
	
	# Apply to preview mesh
	if preview_mesh:
		TransformApplicator.apply_scale_only(preview_mesh, transform_state)

func _apply_numeric_height(numeric_mgr, transform_state: TransformState) -> void:
	"""Apply numeric input to height"""
	var current_height = transform_state.height_offset
	var new_height = numeric_mgr.apply_to_value(current_height)
	
	# Set height offset directly
	transform_state.height_offset = new_height

func _apply_numeric_position(action, numeric_mgr, transform_state: TransformState) -> void:
	"""Apply numeric input to position offset"""
	var ActionType = NumericInputManager.ActionType
	
	var value = numeric_mgr.get_numeric_value()
	if numeric_mgr.get_prefix_mode() == NumericInputManager.PrefixMode.ABSOLUTE:
		# Absolute positioning
		match action:
			ActionType.POSITION_FORWARD, ActionType.POSITION_BACKWARD:
				transform_state.manual_position_offset.z = -value if action == ActionType.POSITION_FORWARD else value
			ActionType.POSITION_LEFT, ActionType.POSITION_RIGHT:
				transform_state.manual_position_offset.x = -value if action == ActionType.POSITION_LEFT else value
	else:
		# Relative positioning
		var delta = value
		if numeric_mgr.get_prefix_mode() == NumericInputManager.PrefixMode.RELATIVE_SUB:
			delta = -delta
		
		match action:
			ActionType.POSITION_FORWARD:
				transform_state.manual_position_offset.z -= delta
			ActionType.POSITION_BACKWARD:
				transform_state.manual_position_offset.z += delta
			ActionType.POSITION_LEFT:
				transform_state.manual_position_offset.x -= delta
			ActionType.POSITION_RIGHT:
				transform_state.manual_position_offset.x += delta

## AXIS CONSTRAINT HELPERS

func _calculate_constrained_position(camera: Camera3D, mouse_pos: Vector2, current_pos: Vector3, control_mode) -> Vector3:
	"""Calculate position with axis constraints using plane intersection
	
	Projects the mouse ray onto a plane/line defined by the constrained axes.
	Uses the constraint origin (position when first axis was activated) as the reference point.
	
	Args:
		camera: The 3D camera
		mouse_pos: Mouse position in viewport
		current_pos: Current object position (fallback if no constraint origin)
		control_mode: ControlModeState with axis constraints
		
	Returns:
		New constrained position
	"""
	# Use constraint origin if available, otherwise fall back to current position
	var constraint_origin = current_pos
	if control_mode.has_constraint_origin():
		constraint_origin = control_mode.get_constraint_origin()
	
	# Create ray from camera through mouse
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# Validate ray direction
	if ray_direction.length_squared() < 0.0001:
		PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, "Invalid ray direction in constraint calculation")
		return constraint_origin
	
	var x_constrained = control_mode.is_x_constrained()
	var y_constrained = control_mode.is_y_constrained()
	var z_constrained = control_mode.is_z_constrained()
	
	# Count constrained axes
	var constraint_count = 0
	if x_constrained: constraint_count += 1
	if y_constrained: constraint_count += 1
	if z_constrained: constraint_count += 1
	
	var result_pos = constraint_origin
	
	if constraint_count == 0:
		# No constraints - shouldn't happen, but return constraint origin
		result_pos = constraint_origin
	elif constraint_count == 1:
		# Single axis constraint - use line projection
		result_pos = _project_to_line(ray_origin, ray_direction, constraint_origin, x_constrained, y_constrained, z_constrained)
	elif constraint_count == 2:
		# Two axes constrained - use plane intersection
		# Plane normal is the axis that's NOT constrained
		var plane_normal = Vector3.ZERO
		if not x_constrained:
			plane_normal = Vector3.RIGHT  # YZ plane (normal points along X)
		elif not y_constrained:
			plane_normal = Vector3.UP  # XZ plane (normal points along Y)
		else:  # not z_constrained
			plane_normal = Vector3.FORWARD  # XY plane (normal points along Z) - Changed from BACK
		
		# Check if ray is nearly parallel to plane (dot product near 0)
		var ray_plane_dot = abs(ray_direction.dot(plane_normal))
		if ray_plane_dot < 0.0001:
			# Ray is parallel to plane, can't intersect properly
			return constraint_origin
		
		# Intersect ray with plane
		var plane = Plane(plane_normal, constraint_origin.dot(plane_normal))
		var intersection = plane.intersects_ray(ray_origin, ray_direction)
		
		if intersection != null:
			result_pos = intersection
		else:
			result_pos = constraint_origin
	else:
		# All three axes constrained - no movement possible
		result_pos = constraint_origin
	
	# Safety check: Ensure result is reasonable distance from constraint origin
	# This prevents extreme values from calculation errors
	var max_distance = 100000.0  # Maximum total allowed distance from origin
	var distance = result_pos.distance_to(constraint_origin)
	if distance > max_distance:
		PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, 
			"Constraint calculation produced extreme value (distance from origin: %.2f), clamping" % distance)
		# Clamp to max distance from origin
		var direction = (result_pos - constraint_origin).normalized()
		result_pos = constraint_origin + direction * max_distance
	
	return result_pos

func _project_to_line(ray_origin: Vector3, ray_direction: Vector3, line_point: Vector3, x_axis: bool, y_axis: bool, z_axis: bool) -> Vector3:
	"""Project mouse ray onto a constrained line (single axis)
	
	Args:
		ray_origin: Ray origin from camera
		ray_direction: Ray direction
		line_point: Point on the line (current position)
		x_axis: True if X is the constrained axis
		y_axis: True if Y is the constrained axis
		z_axis: True if Z is the constrained axis
		
	Returns:
		Closest point on the line to the ray
	"""
	# Determine line direction based on constrained axis
	# Note: Using Godot's standard axis directions
	# X = RIGHT (1, 0, 0) → Positive X is to the right
	# Y = UP (0, 1, 0) → Positive Y is up
	# Z = FORWARD (0, 0, -1) → Positive Z is away from camera (Godot uses -Z as forward)
	var line_direction = Vector3.ZERO
	if x_axis:
		line_direction = Vector3.RIGHT  # (1, 0, 0)
	elif y_axis:
		line_direction = Vector3.UP  # (0, 1, 0)
	else:  # z_axis
		line_direction = Vector3.FORWARD  # (0, 0, -1) - Changed from BACK to FORWARD
	
	# Simpler approach: Find where ray intersects a plane perpendicular to constraint axis,
	# then project that point onto the constraint line
	
	# Create two perpendicular vectors to the line direction (for the perpendicular plane)
	# We'll use the plane that the camera ray is most aligned with
	var perp1 = Vector3.ZERO
	var perp2 = Vector3.ZERO
	
	if abs(line_direction.x) < 0.9:
		perp1 = Vector3.RIGHT.cross(line_direction).normalized()
	else:
		perp1 = Vector3.UP.cross(line_direction).normalized()
	perp2 = line_direction.cross(perp1).normalized()
	
	# Choose the perpendicular vector most aligned with the ray direction
	var plane_normal = perp1 if abs(ray_direction.dot(perp1)) > abs(ray_direction.dot(perp2)) else perp2
	
	# Check if ray is nearly parallel to our perpendicular plane
	var ray_plane_dot = abs(ray_direction.dot(plane_normal))
	if ray_plane_dot < 0.01:
		# Ray is parallel, can't get good intersection
		return line_point
	
	# Intersect ray with plane perpendicular to constraint axis
	var plane = Plane(plane_normal, line_point.dot(plane_normal))
	var intersection = plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection == null:
		return line_point
	
	# Project the intersection point onto the constraint line
	# This is simple: just take the component along the line direction
	var offset_from_origin = intersection - line_point
	var distance_along_line = offset_from_origin.dot(line_direction)
	
	# Safety check: Clamp to reasonable values
	var max_distance = 100000.0
	if abs(distance_along_line) > max_distance:
		distance_along_line = clamp(distance_along_line, -max_distance, max_distance)
	
	var result = line_point + line_direction * distance_along_line
	
	# Additional safety: Ensure result is reasonable
	# If result is astronomically far, return current position (silent fallback)
	if result.length() > 1000000.0:  # More than 1 million units from origin
		return line_point
	
	return result
