@tool
extends RefCounted

class_name TransformationManager

"""
TRANSFORMATION COORDINATOR (CLEAN ARCHITECTURE)
===============================================

PURPOSE: Central coordinator for all placement and transform operations using specialist managers.

RESPONSIBILITIES:
- Coordinates between InputHandler, PositionManager, OverlayManager, and transformation managers
- Manages placement mode (preview mesh positioning and placement)
- Manages transform mode (selected object transformation)
- Handles mode switching and state management
- Delegates all specialized work to appropriate managers

ARCHITECTURE POSITION: Pure coordinator with no business logic
- Does NOT handle input detection (delegates to InputHandler)
- Does NOT handle positioning math (delegates to PositionManager) 
- Does NOT handle UI overlays (delegates to OverlayManager)
- Does NOT handle rotation/scale math (delegates to RotationManager/ScaleManager)

USED BY: Main plugin for all transformation operations
DELEGATES TO: InputHandler, PositionManager, OverlayManager, RotationManager, ScaleManager, PreviewManager, UtilityManager
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/plugin_constants.gd")

# Import specialized managers
const InputHandler = preload("res://addons/simpleassetplacer/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/overlay_manager.gd")

# Import focused managers
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const UtilityManager = preload("res://addons/simpleassetplacer/utility_manager.gd")

# === MODE ENUM ===

enum Mode {
	NONE,        # No active mode
	PLACEMENT,   # Placing new assets
	TRANSFORM    # Transforming selected objects
}

# === CORE STATE (Minimal) ===

# Current operation mode
static var current_mode: Mode = Mode.NONE

# Mode-specific data
static var placement_data: Dictionary = {}
static var transform_data: Dictionary = {}

# Grid overlay tracking
static var last_grid_center: Vector3 = Vector3.ZERO
static var last_grid_height: float = 0.0  # Track height offset for grid updates
static var grid_update_threshold: float = 5.0  # Only update grid when object moves this far

# Callbacks
static var placement_end_callback: Callable
static var mesh_placed_callback: Callable

# Settings reference
static var settings: Dictionary = {}

# Focus management
static var focus_grab_counter: int = 0  # Counter for repeated focus grabs

## MODE COORDINATION

static func start_placement_mode(mesh: Mesh = null, meshlib: MeshLibrary = null, item_id: int = -1, asset_path: String = "", placement_settings: Dictionary = {}, dock_instance = null):
	"""Coordinate starting placement mode"""
	# Exit any existing mode first
	exit_any_mode()
	
	# Set mode
	current_mode = Mode.PLACEMENT
	settings = placement_settings
	
	# Store placement data
	placement_data = {
		"mesh": mesh,
		"meshlib": meshlib,
		"item_id": item_id,
		"asset_path": asset_path,
		"settings": placement_settings,
		"dock_reference": dock_instance
	}
	
	# Initialize managers for placement mode
	OverlayManager.initialize_overlays()
	OverlayManager.set_mode(Mode.PLACEMENT)
	
	# Setup preview if we have something to place
	if mesh:
		PreviewManager.start_preview_mesh(mesh, placement_settings)
	elif meshlib and item_id >= 0:
		var preview_mesh = meshlib.get_item_mesh(item_id)
		if preview_mesh:
			PreviewManager.start_preview_mesh(preview_mesh, placement_settings)
	elif asset_path != "":
		PreviewManager.start_preview_asset(asset_path, placement_settings)
	
	# Configure position manager for placement
	PositionManager.configure(placement_settings)
	
	# Reset position manager for new placement
	# The first mouse update will set the initial position from raycast
	# Reset height and position offsets only if the corresponding settings are enabled
	var reset_height = placement_settings.get("reset_height_on_exit", false)
	var reset_position = placement_settings.get("reset_position_on_exit", false)
	PositionManager.reset_for_new_placement(reset_height, reset_position)
	
	# Reset rotation for new placement (unless user wants to keep rotation)
	if not settings.get("keep_rotation_between_placements", false):
		RotationManager.reset_all_rotation()
	
	# Reset grid tracking for new placement
	last_grid_center = Vector3.ZERO
	
	# Grab focus for the 3D viewport to ensure keyboard input works
	# Set counter to grab focus for next 3 frames to ensure it sticks
	focus_grab_counter = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started placement mode")

static func start_transform_mode(target_nodes, dock_instance = null):
	"""Coordinate starting transform mode for one or multiple nodes
	target_nodes: Node3D or Array of Node3D objects to transform together"""
	
	# Handle single node parameter - convert to array
	if target_nodes is Node3D:
		target_nodes = [target_nodes]
	elif not target_nodes is Array:
		return
	
	if target_nodes.is_empty():
		return
	
	# Filter to only Node3D objects
	var valid_nodes = []
	for node in target_nodes:
		if node is Node3D:
			valid_nodes.append(node)
	
	if valid_nodes.is_empty():
		return
	
	# Exit any existing mode first  
	exit_any_mode()
	
	# Set mode
	current_mode = Mode.TRANSFORM
	
	# Store transform data for all nodes
	var original_transforms = {}
	for node in valid_nodes:
		original_transforms[node] = node.transform
	
	# Calculate center position of all nodes for positioning reference
	var center_pos = Vector3.ZERO
	for node in valid_nodes:
		if node.is_inside_tree():
			center_pos += node.global_position
	center_pos /= valid_nodes.size()
	
	# Calculate each node's offset from the original center (store once, use every frame)
	var node_offsets = {}
	for node in valid_nodes:
		if node.is_inside_tree():
			node_offsets[node] = node.global_position - center_pos
	
	# Calculate snap offset ONCE at mode start to prevent jumping when snapping is enabled
	# This preserves the original position relative to the grid
	var snap_offset = Vector3.ZERO
	if PositionManager.snap_enabled:
		# Simulate what snapping would do to the center position
		var snapped_center = center_pos
		if PositionManager.snap_enabled:
			snapped_center = PositionManager._apply_grid_snap(center_pos)
		# Calculate offset needed to maintain original position
		snap_offset = center_pos - snapped_center
	
	transform_data = {
		"target_nodes": valid_nodes,  # Array of nodes
		"original_transforms": original_transforms,  # Dictionary mapping node to original transform
		"original_center": center_pos,  # Store the original center position
		"node_offsets": node_offsets,  # Store each node's offset from original center
		"dock_reference": dock_instance,
		"accumulated_xz_delta": Vector3.ZERO,  # Track accumulated WASD position adjustments
		"accumulated_y_delta": 0.0,  # Track accumulated height adjustments
		"snap_offset": snap_offset  # Offset to maintain position relative to snapped grid (calculated once at start)
	}
	
	# Initialize managers for transform mode
	OverlayManager.initialize_overlays()
	OverlayManager.set_mode(Mode.TRANSFORM)
	
	# Initialize position manager with center position
	PositionManager.set_position(center_pos)
	PositionManager.start_transform_positioning(valid_nodes[0])  # Use first node as reference
	
	# Reset grid tracking for new transform session
	last_grid_center = Vector3.ZERO
	
	# Grab focus for the 3D viewport to ensure keyboard input works
	# Set counter to grab focus for next 3 frames to ensure it sticks
	focus_grab_counter = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()

static func exit_placement_mode():
	"""Coordinate exiting placement mode"""
	if current_mode != Mode.PLACEMENT:
		return
	
	# Clean up preview
	PreviewManager.cleanup_preview()
	
	# Call end callback if set
	if placement_end_callback.is_valid():
		placement_end_callback.call()
	
	# Clear data
	placement_data.clear()
	
	# Reset transforms based on user settings
	_reset_transforms_on_exit()
	
	# Reset mode
	current_mode = Mode.NONE
	
	# Hide and cleanup overlays
	OverlayManager.hide_transform_overlay()
	OverlayManager.set_mode(Mode.NONE)
	OverlayManager.remove_grid_overlay()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited placement mode")

static func exit_transform_mode(confirm_changes: bool = true):
	"""Coordinate exiting transform mode"""
	if current_mode != Mode.TRANSFORM:
		return
	
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	
	if not confirm_changes:
		# Restore original transforms if not confirming changes
		for node in target_nodes:
			if node and original_transforms.has(node):
				node.transform = original_transforms[node]
	
	# Reset transforms based on user settings
	_reset_transforms_on_exit()
	
	# Clear data
	transform_data.clear()
	
	# Reset mode
	current_mode = Mode.NONE
	
	# Hide and cleanup overlays
	OverlayManager.hide_transform_overlay()
	OverlayManager.set_mode(Mode.NONE)
	OverlayManager.remove_grid_overlay()
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited transform mode (confirmed: " + str(confirm_changes) + ")")

static func exit_any_mode():
	"""Exit whatever mode is currently active"""
	match current_mode:
		Mode.PLACEMENT:
			exit_placement_mode()
		Mode.TRANSFORM:
			exit_transform_mode(false)

## GRID OVERLAY MANAGEMENT

static func _update_grid_overlay():
	"""Update or create grid overlay based on current settings and mode"""
	var show_grid = settings.get("show_grid", false)
	var snap_enabled = settings.get("snap_enabled", false)
	
	# Only show grid if both grid display and snapping are enabled
	if show_grid and snap_enabled and (current_mode == Mode.PLACEMENT or current_mode == Mode.TRANSFORM):
		var grid_size = settings.get("snap_step", 1.0)
		var offset = settings.get("snap_offset", Vector3.ZERO)
		var grid_extent_units = settings.get("grid_extent", 20.0)
		
		# Get center position based on current mode
		var center = Vector3.ZERO
		if current_mode == Mode.PLACEMENT:
			# Use base position (without height offset) for grid placement
			# This ensures the grid stays at ground level, not elevated with the object
			center = PositionManager.get_base_position()
		elif current_mode == Mode.TRANSFORM:
			# Use center of selected nodes
			var target_nodes = transform_data.get("target_nodes", [])
			if not target_nodes.is_empty():
				for node in target_nodes:
					if node and is_instance_valid(node) and node.is_inside_tree():
						center += node.global_position
				center /= target_nodes.size()
		
		# Calculate number of grid cells based on grid size and desired world extent
		var grid_extent = int(ceil(grid_extent_units / grid_size))
		grid_extent = clamp(grid_extent, 5, 100)  # Min 5, max 100 cells
		
		# Check if grid needs updating based on position, height, or existence
		var distance_from_last_center = center.distance_to(last_grid_center)
		var current_height = center.y
		var height_changed = abs(current_height - last_grid_height) > 0.01
		var needs_update = distance_from_last_center > grid_update_threshold or height_changed
		
		# Also check if grid overlay exists
		if not OverlayManager.grid_overlay or not is_instance_valid(OverlayManager.grid_overlay):
			needs_update = true
		
		if needs_update:
			OverlayManager.create_grid_overlay(center, grid_size, grid_extent, offset)
			last_grid_center = center
			last_grid_height = current_height
	else:
		# Hide/remove grid if disabled or not in active mode
		OverlayManager.remove_grid_overlay()
		last_grid_center = Vector3.ZERO  # Reset tracking
		last_grid_height = 0.0

## INPUT PROCESSING COORDINATION

static func process_frame_input(camera: Camera3D, input_settings: Dictionary = {}):
	"""Process input for the current frame - coordinate with InputHandler"""
	# Store current settings for TAB key and other operations
	settings = input_settings
	
	# Configure managers with current settings (important for both modes)
	# This ensures snap settings and other options are always up-to-date
	PositionManager.configure(input_settings)
	
	# Get the 3D viewport for proper mouse coordinate conversion
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	
	# Update input system with viewport context
	InputHandler.update_input_state(input_settings, viewport_3d)
	
	# Keep grabbing focus for the first few frames after mode starts
	if focus_grab_counter > 0:
		focus_grab_counter -= 1
		_grab_3d_viewport_focus()
	
	# Process mode-specific input
	match current_mode:
		Mode.PLACEMENT:
			_process_placement_input(camera)
		Mode.TRANSFORM:
			_process_transform_input(camera)
	
	# Update grid overlay AFTER position updates (so it follows the object)
	_update_grid_overlay()
	
	# Process global navigation input
	_process_navigation_input()

static func _process_placement_input(camera: Camera3D):
	"""Process input for placement mode"""
	if not camera:
		return
	
	var position_input = InputHandler.get_position_input()
	var rotation_input = InputHandler.get_rotation_input()
	var scale_input = InputHandler.get_scale_input()
	
	# Set half-step mode based on CTRL key state
	PositionManager.use_half_step = position_input.ctrl_held
	
	# Handle height adjustments with reverse modifier and increment size support
	var reverse_height = position_input.shift_held  # SHIFT = reverse direction
	
	# Determine height step based on modifiers (matching transform mode logic)
	var height_step = PositionManager.height_step_size  # Base step
	
	# Apply Y snap step if Y snapping is enabled
	if PositionManager.snap_y_enabled:
		height_step = PositionManager.snap_y_step
	
	# Apply modifier keys for increment size
	if position_input.ctrl_held:
		# CTRL = fine adjustment (10% of base step)
		height_step *= 0.1
	elif position_input.alt_held:
		# ALT = large adjustment (10x base step)
		height_step *= 10.0
	
	if position_input.height_up_pressed:
		var height_change = height_step if not reverse_height else -height_step
		PositionManager.adjust_height(height_change)
	elif position_input.height_down_pressed:
		var height_change = -height_step if not reverse_height else height_step
		PositionManager.adjust_height(height_change)
	elif position_input.reset_height_pressed:
		PositionManager.reset_height()
	
	# Handle position adjustments (WASD-style movement - camera relative)
	var position_delta = settings.get("position_increment", 0.1)
	if position_input.ctrl_held:
		position_delta = settings.get("fine_position_increment", 0.01)
	elif position_input.alt_held:
		position_delta = settings.get("large_position_increment", 1.0)
	
	# Get camera-relative directions snapped to nearest axis (same as transform mode)
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
		PositionManager.manual_position_offset -= camera_right * position_delta
	elif position_input.position_right_pressed:
		PositionManager.manual_position_offset += camera_right * position_delta
	
	if position_input.position_forward_pressed:
		PositionManager.manual_position_offset += camera_forward * position_delta
	elif position_input.position_backward_pressed:
		PositionManager.manual_position_offset -= camera_forward * position_delta
	
	# Handle position reset
	if position_input.reset_position_pressed:
		PositionManager.reset_position()
	
	# Update position from mouse AFTER processing WASD input
	# This ensures manual offsets are included in the same frame
	# Y position is controlled by base_height + height_offset (manual Q/E keys)
	# Manual WASD offsets are preserved via manual_position_offset in PositionManager
	var mouse_pos = position_input.mouse_position
	var world_pos = PositionManager.update_position_from_mouse(camera, mouse_pos, 1, true)
	
	# Get the updated position
	var preview_pos = PositionManager.get_current_position()
	
	# Update preview position
	PreviewManager.update_preview_position(preview_pos)
	
	# Update surface normal alignment if enabled, otherwise reset it
	if settings.get("align_with_normal", false):
		RotationManager.align_with_surface_normal(PositionManager.get_surface_normal())
	else:
		RotationManager.reset_surface_alignment()
	
	# Handle rotation input (this will be combined with surface alignment)
	# Don't rotate position offset - this makes rotation behave like transform mode (in-place)
	_process_rotation_input(rotation_input, PreviewManager.preview_mesh, false)
	
	# Apply the combined rotation (surface alignment + manual rotation) to the preview mesh
	if PreviewManager.preview_mesh:
		RotationManager.apply_rotation_to_node(PreviewManager.preview_mesh)
	
	# Handle scale input
	_process_scale_input(scale_input, PreviewManager.preview_mesh)
	
	# Handle placement action
	if position_input.left_clicked:
		place_at_preview_position()
	
	# Update overlays with current state
	_update_placement_overlays()

static func _process_transform_input(camera: Camera3D):
	"""Process input for transform mode"""
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty() or not camera:
		return
	
	var position_input = InputHandler.get_position_input()
	var rotation_input = InputHandler.get_rotation_input()
	var scale_input = InputHandler.get_scale_input()
	
	# Calculate center position of all nodes
	var center_y = 0.0
	var valid_node_count = 0
	for node in target_nodes:
		if node and node.is_inside_tree():
			center_y += node.global_position.y
			valid_node_count += 1
	
	if valid_node_count > 0:
		center_y /= valid_node_count
	
	# Get accumulated height delta from transform_data
	var accumulated_y_delta = transform_data.get("accumulated_y_delta", 0.0)
	
	# Handle height adjustments with reverse modifier and increment size support
	var reverse_height = position_input.shift_held  # SHIFT = reverse direction
	
	# Determine height step based on modifiers (matching placement mode logic)
	var height_step = PositionManager.height_step_size  # Base step
	
	# Apply Y snap step if Y snapping is enabled (same as placement mode)
	if PositionManager.snap_y_enabled:
		height_step = PositionManager.snap_y_step
	
	# Apply modifier keys for increment size
	if position_input.ctrl_held:
		# CTRL = fine adjustment (10% of base step)
		height_step *= 0.1
	elif position_input.alt_held:
		# ALT = large adjustment (10x base step)
		height_step *= 10.0
	
	if position_input.height_up_pressed:
		var height_change = height_step if not reverse_height else -height_step
		accumulated_y_delta += height_change
	elif position_input.height_down_pressed:
		var height_change = -height_step if not reverse_height else height_step
		accumulated_y_delta += height_change
	elif position_input.reset_height_pressed:
		# Reset accumulated height delta to 0
		accumulated_y_delta = 0.0
	
	# Store the accumulated height delta back to transform_data
	transform_data["accumulated_y_delta"] = accumulated_y_delta
	
	# Handle position adjustments (WASD-style movement) - this adds to XZ position
	var position_delta = settings.get("position_increment", 0.1)
	if position_input.ctrl_held:
		position_delta = settings.get("fine_position_increment", 0.01)
	elif position_input.alt_held:
		position_delta = settings.get("large_position_increment", 1.0)
	
	# Get accumulated delta from transform_data
	var accumulated_delta = transform_data.get("accumulated_xz_delta", Vector3.ZERO)
	
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
	
	# Handle position adjustments (WASD-style movement) - accumulate axis-aligned delta
	if position_input.position_left_pressed:
		accumulated_delta -= camera_right * position_delta  # Left is negative right
	elif position_input.position_right_pressed:
		accumulated_delta += camera_right * position_delta
	
	if position_input.position_forward_pressed:
		accumulated_delta += camera_forward * position_delta
	elif position_input.position_backward_pressed:
		accumulated_delta -= camera_forward * position_delta  # Backward is negative forward
	
	# Handle position reset
	if position_input.reset_position_pressed:
		accumulated_delta = Vector3.ZERO
	
	# Store back the accumulated delta
	transform_data["accumulated_xz_delta"] = accumulated_delta
	
	# Calculate XZ position using offset-from-center approach for proper grid snapping
	var mouse_pos = position_input.mouse_position
	
	# Set half-step mode based on CTRL key state
	PositionManager.use_half_step = position_input.ctrl_held
	
	# Get stored original center and node offsets (calculated once when transform mode started)
	var original_center = transform_data.get("original_center", Vector3.ZERO)
	var node_offsets = transform_data.get("node_offsets", {})
	var snap_offset = transform_data.get("snap_offset", Vector3.ZERO)
	
	# Update position from mouse (with snapping if enabled)
	PositionManager.update_position_from_mouse(camera, mouse_pos)
	var mouse_center = PositionManager.get_current_position()
	
	# Calculate new center position:
	# mouse_center (snapped) + snap_offset (preserves original grid alignment) + accumulated_delta (WASD movement)
	var new_center = mouse_center + snap_offset + accumulated_delta
	
	# Update surface normal alignment if enabled, otherwise reset it
	if settings.get("align_with_normal", false):
		RotationManager.align_with_surface_normal(PositionManager.get_surface_normal())
	else:
		RotationManager.reset_surface_alignment()
	
	# Handle rotation input - process ONCE for all nodes to avoid accumulation
	# Since RotationManager uses static state, we must not call it multiple times per frame
	var rotation_applied = false
	var original_transforms = transform_data.get("original_transforms", {})
	
	if not target_nodes.is_empty():
		var first_node = target_nodes[0]
		if first_node and first_node.is_inside_tree():
			var first_original_rotation = original_transforms.get(first_node, Transform3D()).basis.get_euler()
			_process_rotation_input(rotation_input, first_node, false, first_original_rotation)
			rotation_applied = true
	
	# Get the current rotation offset for group rotation around center
	var rotation_offset_euler = RotationManager.get_rotation_offset()
	var rotation_basis = Basis.from_euler(rotation_offset_euler)
	
	# Apply transformations to ALL nodes using offset-based system
	# Flow: base_position (mouse + snap) → apply rotation orbit → apply offsets (rotation, scale)
	for node in target_nodes:
		if not node or not node.is_inside_tree():
			continue
		
		# Get this node's original offset from center (calculated once at mode start)
		var original_offset = node_offsets.get(node, Vector3.ZERO)
		
		# STEP 1: Group Rotation - Rotate the node's position around the collective center
		# This makes nodes orbit around the center when rotating as a group
		var rotated_offset = rotation_basis * original_offset
		
		# STEP 2: Position - Base position (new_center) + rotation orbit offset
		# new_center = mouse_position (snapped) + snap_offset + accumulated_delta (WASD)
		node.global_position.x = new_center.x + rotated_offset.x
		node.global_position.z = new_center.z + rotated_offset.z
		
		# Y position: follows ground or maintains original height
		if settings.get("snap_to_ground", false):
			# Follow surface height from raycast + height offset
			node.global_position.y = new_center.y + rotated_offset.y + accumulated_y_delta
		else:
			# Maintain original Y + height offset
			node.global_position.y = original_center.y + rotated_offset.y + accumulated_y_delta
		
		# STEP 3: Individual Rotation - Apply rotation offset to node's original rotation
		# Rotation offset is applied on top of the node's original rotation
		if rotation_applied:
			var node_original_rotation = original_transforms.get(node, Transform3D()).basis.get_euler()
			RotationManager.apply_rotation_to_node(node, node_original_rotation)
	
	# STEP 4: Scale - Apply scale multiplier to node's original scale
	# final_scale = original_scale * scale_multiplier
	for node in target_nodes:
		if node and node.is_inside_tree():
			var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
			_process_scale_input(scale_input, node, node_original_scale)
	
	# Handle transform confirmation
	if position_input.left_clicked:
		exit_transform_mode(true)
	
	# Update overlays with current state (use first node as reference)
	if target_nodes.size() > 0 and target_nodes[0]:
		_update_transform_overlays(target_nodes[0])

static func _process_rotation_input(rotation_input: Dictionary, target_node: Node3D, rotate_position_offset: bool = false, original_rotation: Vector3 = Vector3.ZERO):
	"""Process rotation input for any target node
	
	Args:
		rotation_input: Input dictionary from InputHandler
		target_node: The node to apply rotation to
		rotate_position_offset: If true, also rotates manual position offset (for placement mode)
		original_rotation: The node's original rotation (from transform mode) or Vector3.ZERO for placement mode
	"""
	if not target_node:
		return
	
	# Handle rotation keys - use proper increment sizes and modifiers
	# Priority: ALT (large) > CTRL (fine) > Base
	# These should be mutually exclusive - only one size modifier at a time
	var rotation_step: float
	
	if rotation_input.alt_held and not rotation_input.ctrl_held:  # ALT only = large increment
		rotation_step = settings.get("large_rotation_increment", 90.0)
	elif rotation_input.ctrl_held and not rotation_input.alt_held:  # CTRL only = fine increment
		rotation_step = settings.get("fine_rotation_increment", 5.0)
	else:  # No modifier or both (default to base)
		rotation_step = settings.get("rotation_increment", 15.0)
	
	# Apply reverse direction modifier (SHIFT)
	if rotation_input.shift_held:  # SHIFT = reverse direction
		rotation_step = -rotation_step
	
	if rotation_input.x_pressed:
		RotationManager.apply_rotation_step(target_node, "X", rotation_step, original_rotation, rotate_position_offset)
	elif rotation_input.y_pressed:
		RotationManager.apply_rotation_step(target_node, "Y", rotation_step, original_rotation, rotate_position_offset)
	elif rotation_input.z_pressed:
		RotationManager.apply_rotation_step(target_node, "Z", rotation_step, original_rotation, rotate_position_offset)
	elif rotation_input.reset_pressed:
		RotationManager.reset_node_rotation(target_node)

static func _process_scale_input(scale_input: Dictionary, target_node: Node3D = null, original_scale: Vector3 = Vector3.ONE):
	"""Process scale input and apply to target node
	
	Args:
		scale_input: Input dictionary from InputHandler
		target_node: The node to apply scale to
		original_scale: The node's original scale (from transform mode) or Vector3.ONE for placement mode
	"""
	if not target_node:
		return
		
	var scale_step = settings.get("scale_increment", 0.1)  # Default
	var reverse_scale = scale_input.shift_held  # SHIFT = reverse direction
	
	# Apply modifier for increment size
	if scale_input.alt_held:  # ALT = large increment
		scale_step = settings.get("large_scale_increment", 0.5)
	
	if scale_input.up_pressed:
		if reverse_scale:
			ScaleManager.decrease_scale(scale_step)
		else:
			ScaleManager.increase_scale(scale_step)
		ScaleManager.apply_uniform_scale_to_node(target_node, original_scale)
	elif scale_input.down_pressed:
		if reverse_scale:
			ScaleManager.increase_scale(scale_step)
		else:
			ScaleManager.decrease_scale(scale_step)
		ScaleManager.apply_uniform_scale_to_node(target_node, original_scale)
	elif scale_input.reset_pressed:
		ScaleManager.reset_scale()
		ScaleManager.apply_uniform_scale_to_node(target_node, original_scale)

static func _process_navigation_input():
	"""Process navigation and mode control input"""
	var nav_input = InputHandler.get_navigation_input()
	
	# Handle TAB key for mode switching
	if nav_input.tab_just_pressed:
		handle_tab_key_activation()
	
	# Handle cancel/escape
	if nav_input.cancel_pressed or nav_input.escape_pressed:
		exit_any_mode()

## MOUSE WHEEL INPUT HANDLING

static func handle_mouse_wheel_input(event: InputEventMouseButton) -> bool:
	"""Process mouse wheel input using semantic data from InputHandler
	Returns true if the event was handled (should be consumed)"""
	
	# Get semantic wheel input interpretation from InputHandler
	var wheel_input = InputHandler.get_mouse_wheel_input(event)
	
	# If no action key is held, don't consume the event
	if wheel_input.is_empty():
		return false
	
	# Process the semantic action
	match wheel_input.get("action"):
		"height":
			_apply_height_adjustment(wheel_input)
		"scale":
			_apply_scale_adjustment(wheel_input)
		"rotation":
			_apply_rotation_adjustment(wheel_input)
		"position":
			_apply_position_adjustment(wheel_input)
	
	return true  # Event was handled

static func _apply_height_adjustment(wheel_input: Dictionary):
	"""Apply height adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	if reverse:
		direction = -direction
	
	# Mouse wheel uses fine adjustment by default (no large increment for height with mouse wheel currently)
	var step = settings.get("fine_height_increment", 0.01)
	
	if current_mode == Mode.PLACEMENT:
		# Apply fine increment for mouse wheel in placement mode
		if direction > 0:
			PositionManager.adjust_height(step)
		else:
			PositionManager.adjust_height(-step)
	elif current_mode == Mode.TRANSFORM:
		# In transform mode, update the accumulated height delta
		var accumulated_y_delta = transform_data.get("accumulated_y_delta", 0.0)
		accumulated_y_delta += step * direction
		transform_data["accumulated_y_delta"] = accumulated_y_delta
		
		# The actual position update will happen in _process_transform_input
		# This ensures consistency with keyboard height adjustments

static func _apply_scale_adjustment(wheel_input: Dictionary):
	"""Apply scale adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var large_increment = wheel_input.get("large_increment", false)
	
	# Mouse wheel uses fine adjustment by default, unless ALT is held for large increment
	var step = settings.get("fine_scale_increment", 0.01)
	if large_increment:
		step = settings.get("large_scale_increment", 0.5)
	
	if current_mode == Mode.PLACEMENT:
		var target_node = PreviewManager.preview_mesh
		if target_node:
			if direction > 0:
				ScaleManager.increase_scale(step)
			else:
				ScaleManager.decrease_scale(step)
			ScaleManager.apply_uniform_scale_to_node(target_node, Vector3.ONE)  # Placement mode starts at scale 1.0
	elif current_mode == Mode.TRANSFORM:
		# Apply scale multiplier adjustment to ALL nodes in transform mode (using their original scales)
		var target_nodes = transform_data.get("target_nodes", [])
		var original_transforms = transform_data.get("original_transforms", {})
		if not target_nodes.is_empty():
			if direction > 0:
				ScaleManager.increase_scale(step)
			else:
				ScaleManager.decrease_scale(step)
			# Apply to all nodes with their original scales
			for node in target_nodes:
				if node and node.is_inside_tree():
					var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
					ScaleManager.apply_uniform_scale_to_node(node, node_original_scale)

static func _apply_rotation_adjustment(wheel_input: Dictionary):
	"""Apply rotation adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var axis = wheel_input.get("axis", "Y")
	var large_increment = wheel_input.get("large_increment", false)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	# Mouse wheel: ALT = large increment, otherwise fine adjustment
	# Use explicit if/else to prevent accidental addition of increments
	var step: float
	if large_increment:
		step = settings.get("large_rotation_increment", 90.0)
	else:
		step = settings.get("fine_rotation_increment", 5.0)
	
	if reverse:
		direction = -direction
	
	if current_mode == Mode.PLACEMENT:
		var target_node = PreviewManager.preview_mesh
		if target_node:
			RotationManager.apply_rotation_step(target_node, axis, step * direction, Vector3.ZERO, false)
	elif current_mode == Mode.TRANSFORM:
		# Apply rotation offset to ALL nodes in transform mode (using their original rotations)
		var target_nodes = transform_data.get("target_nodes", [])
		var original_transforms = transform_data.get("original_transforms", {})
		for node in target_nodes:
			if node and node.is_inside_tree():
				var node_original_rotation = original_transforms.get(node, Transform3D()).basis.get_euler()
				RotationManager.apply_rotation_step(node, axis, step * direction, node_original_rotation, false)

static func _apply_position_adjustment(wheel_input: Dictionary):
	"""Apply position adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var axis = wheel_input.get("axis", "forward")
	var reverse = wheel_input.get("reverse_modifier", false)
	
	# Mouse wheel uses fine adjustment by default
	var step = settings.get("fine_position_increment", 0.01)
	
	if reverse:
		direction = -direction
	
	# Calculate the actual movement delta based on axis
	var movement_delta = step * direction
	
	if current_mode == Mode.PLACEMENT:
		# Use PositionManager functions to properly update manual_position_offset
		var camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		match axis:
			"forward":
				PositionManager.move_forward(movement_delta, camera)
			"backward":
				PositionManager.move_backward(movement_delta, camera)
			"left":
				PositionManager.move_left(movement_delta, camera)
			"right":
				PositionManager.move_right(movement_delta, camera)
		
		# Update preview position with the new offset
		var preview_pos = PositionManager.get_current_position()
		PreviewManager.update_preview_position(preview_pos)
	
	elif current_mode == Mode.TRANSFORM:
		# Apply position adjustment to ALL nodes in transform mode
		var target_nodes = transform_data.get("target_nodes", [])
		if not target_nodes.is_empty():
			# Get current camera for relative movement
			var camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
			if camera:
				# Get accumulated delta
				var accumulated_delta = transform_data.get("accumulated_xz_delta", Vector3.ZERO)
				
				# Calculate camera-relative directions (snapped to axes like keyboard input)
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
				
				# Add to accumulated delta based on axis
				match axis:
					"forward":
						accumulated_delta += camera_forward * movement_delta
					"backward":
						accumulated_delta -= camera_forward * movement_delta
					"left":
						accumulated_delta -= camera_right * movement_delta
					"right":
						accumulated_delta += camera_right * movement_delta
				
				# Store back the accumulated delta
				transform_data["accumulated_xz_delta"] = accumulated_delta

## TAB KEY COORDINATION

static func _grab_3d_viewport_focus():
	"""Grab keyboard focus for the 3D viewport to ensure input works during transform mode"""
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	var base_control = EditorInterface.get_base_control()
	if not base_control:
		return
	
	# Find the 3D editor control area
	var spatial_editor = _find_spatial_editor(base_control)
	if spatial_editor:
		# Enable focus mode on the spatial editor so it can receive focus
		if spatial_editor.focus_mode == Control.FOCUS_NONE:
			spatial_editor.focus_mode = Control.FOCUS_ALL
		
		# Grab focus immediately first
		spatial_editor.grab_focus()
		# Then grab it again deferred to override anything that steals it
		spatial_editor.call_deferred("grab_focus")

static func _find_spatial_editor(node: Node) -> Control:
	"""Find the Node3DEditor (spatial editor) control"""
	if node and node.get_class() == "Node3DEditor":
		if node is Control:
			return node
	
	if node:
		for child in node.get_children():
			var result = _find_spatial_editor(child)
			if result:
				return result
	
	return null

static func _is_3d_context_focused() -> bool:
	"""Check if 3D viewport or scene tree has focus (contexts where transform mode should work)"""
	# Instead of checking keyboard focus, check if we're editing a 3D scene
	# and have a valid camera (which means a 3D viewport is active)
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return false
	
	# Check if we can get a 3D viewport camera (means 3D editor is active)
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return false
	
	var camera = viewport_3d.get_camera_3d()
	if not camera:
		return false
	
	# Get the currently focused control to check if we're NOT in specific UI elements
	var base_control = EditorInterface.get_base_control()
	if base_control:
		var focused_control = base_control.get_viewport().gui_get_focus_owner()
		if focused_control:
			# Check if focus is in Inspector - we want to block TAB there
			var current = focused_control
			var depth = 0
			while current and depth < 20:
				var control_class = current.get_class()
				var control_name = current.name if current.name else ""
				
				# Block TAB if we're in Inspector property fields
				if "Inspector" in control_class or "Inspector" in control_name or "EditorProperty" in control_class:
					return false
				
				current = current.get_parent()
				depth += 1
	
	# We have a 3D scene open with a viewport, and we're not in Inspector
	return true

static func handle_tab_key_activation(dock_instance = null):
	"""Handle TAB key activation - coordinate between placement and transform modes"""
	# Don't handle TAB if already in a mode
	if is_any_mode_active():
		return
	
	# Check if 3D viewport or scene tree has focus before activating transform mode
	# This prevents TAB from activating when user is in Inspector or other UI elements
	if not _is_3d_context_focused():
		# Not in 3D context - don't intercept TAB key
		return
	
	var selection = EditorInterface.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	
	if selected_nodes.is_empty():
		OverlayManager.show_status_message("No node selected. Select a Node3D and press TAB.", Color.YELLOW, 3.0)
		return
	
	# Find ALL Node3D nodes in selection
	var target_node3ds = []
	for node in selected_nodes:
		if node is Node3D:
			target_node3ds.append(node)
	
	if target_node3ds.is_empty():
		OverlayManager.show_status_message("Selected node is not a Node3D. Select a Node3D and press TAB.", Color.YELLOW, 3.0)
		return
	
	# Determine mode based on node context (check first node)
	var first_node = target_node3ds[0]
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene and (first_node.is_ancestor_of(current_scene) or current_scene == first_node or first_node.is_inside_tree()):
		# Nodes are in scene - start transform mode for all selected nodes
		start_transform_mode(target_node3ds, dock_instance)
		if target_node3ds.size() == 1:
			OverlayManager.show_status_message("Transform mode: " + first_node.name, Color.GREEN, 2.0)
		else:
			OverlayManager.show_status_message("Transform mode: " + str(target_node3ds.size()) + " nodes", Color.GREEN, 2.0)
	else:
		# Node is external - start placement mode (only uses first node)
		start_placement_from_node3d(first_node, dock_instance)

static func start_placement_from_node3d(node: Node3D, dock_instance = null):
	"""Start placement mode from a Node3D by extracting its mesh"""
	var extracted_mesh = UtilityManager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		# Use current settings (includes dock settings from process_frame_input)
		start_placement_mode(extracted_mesh, null, -1, "", settings, dock_instance)
		OverlayManager.show_status_message("Placement mode activated for: " + node.name, Color.GREEN, 2.0)
	else:
		OverlayManager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)

## OVERLAY UPDATE COORDINATION

static func _update_placement_overlays():
	"""Update all overlays for placement mode"""
	var current_asset_name = placement_data.get("asset_path", "").get_file().get_basename() if placement_data.get("asset_path", "") != "" else "Mesh"
	
	OverlayManager.show_transform_overlay(
		Mode.PLACEMENT,
		current_asset_name,
		PositionManager.get_current_position(),
		PreviewManager.get_preview_rotation(),
		ScaleManager.get_scale(),
		PositionManager.get_height_offset()
	)

static func _update_transform_overlays(target_node: Node3D):
	"""Update all overlays for transform mode"""
	if not target_node:
		return
	
	if target_node.is_inside_tree():
		OverlayManager.show_transform_overlay(
			Mode.TRANSFORM,
			target_node.name,
			target_node.global_position,
			target_node.rotation,
			target_node.scale.x  # Assuming uniform scale
		)

## PLACEMENT COORDINATION

static func place_at_preview_position():
	"""Coordinate placing object at current preview position"""
	if current_mode != Mode.PLACEMENT:
		return
	
	var position = PositionManager.get_current_position()
	var placed_node = null
	
	# Use internal placement functions
	if placement_data.get("meshlib") and placement_data.get("item_id", -1) >= 0:
		placed_node = UtilityManager.place_meshlib_item_in_scene(
			placement_data.meshlib, 
			placement_data.item_id, 
			position, 
			placement_data.get("settings", {})
		)
	elif placement_data.get("asset_path", "") != "":
		placed_node = UtilityManager.place_asset_in_scene(
			placement_data.asset_path,
			position,
			placement_data.get("settings", {})
		)
	elif placement_data.get("mesh"):
		placed_node = UtilityManager.place_mesh_in_scene(
			placement_data.mesh,
			position,
			placement_data.get("settings", {})
		)
	
	# Call placement callback
	if placed_node and mesh_placed_callback.is_valid():
		mesh_placed_callback.call(placed_node)
	
	# Show feedback
	if placed_node:
		OverlayManager.show_status_message("Placed: " + placed_node.name, Color.GREEN, 1.0)

## STATE QUERIES

static func is_any_mode_active() -> bool:
	"""Check if any transformation mode is currently active"""
	return current_mode != Mode.NONE

static func is_placement_mode() -> bool:
	"""Check if placement mode is active"""
	return current_mode == Mode.PLACEMENT

static func is_transform_mode() -> bool:
	"""Check if transform mode is active"""
	return current_mode == Mode.TRANSFORM

static func get_current_mode() -> Mode:
	"""Get the current mode (returns Mode enum)"""
	return current_mode

static func get_current_mode_string() -> String:
	"""Get the current mode as a string (for display/logging purposes)"""
	match current_mode:
		Mode.NONE:
			return "none"
		Mode.PLACEMENT:
			return "placement"
		Mode.TRANSFORM:
			return "transform"
		_:
			return "unknown"

static func get_current_scale() -> float:
	"""Get current scale multiplier"""
	return ScaleManager.get_scale()

## CLEANUP

static func cleanup():
	"""Clean up all manager resources"""
	exit_any_mode()
	OverlayManager.cleanup_all_overlays()
	PreviewManager.cleanup_preview()
	placement_data.clear()
	transform_data.clear()
	settings.clear()
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Cleanup completed")

## RESET MANAGEMENT

static func _reset_transforms_on_exit():
	"""Reset transforms based on user settings when exiting modes"""
	# Reset height offset if enabled
	if settings.get("reset_height_on_exit", false):
		PositionManager.reset_height()
	
	# Reset position offset if enabled
	if settings.get("reset_position_on_exit", false):
		PositionManager.reset_position()
	
	# Reset scale if enabled
	if settings.get("reset_scale_on_exit", false):
		ScaleManager.reset_scale()
	
	# Reset rotation if enabled
	if settings.get("reset_rotation_on_exit", false):
		RotationManager.reset_rotation()
	
	# Always reset surface alignment when exiting modes
	RotationManager.reset_surface_alignment()

