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

# Import specialized managers
const InputHandler = preload("res://addons/simpleassetplacer/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/overlay_manager.gd")

# Import focused managers
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const UtilityManager = preload("res://addons/simpleassetplacer/utility_manager.gd")

# === CORE STATE (Minimal) ===

# Current operation mode
static var current_mode: String = ""  # "", "placement", "transform"

# Mode-specific data
static var placement_data: Dictionary = {}
static var transform_data: Dictionary = {}

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
	current_mode = "placement"
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
	OverlayManager.set_mode("placement")
	
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
	
	# Grab focus for the 3D viewport to ensure keyboard input works
	# Set counter to grab focus for next 3 frames to ensure it sticks
	focus_grab_counter = 3
	_grab_3d_viewport_focus()
	
	print("TransformationManager: Started placement mode")

static func start_transform_mode(target_node: Node3D, dock_instance = null):
	"""Coordinate starting transform mode"""
	if not target_node:
		return
	
	# Exit any existing mode first  
	exit_any_mode()
	
	# Set mode
	current_mode = "transform"
	
	# Store transform data
	transform_data = {
		"target_node": target_node,
		"original_transform": target_node.transform,
		"dock_reference": dock_instance
	}
	
	# Initialize managers for transform mode
	OverlayManager.initialize_overlays()
	OverlayManager.set_mode("transform")
	
	# Initialize position manager with node's current position
	PositionManager.start_transform_positioning(target_node)
	
	# Grab focus for the 3D viewport to ensure keyboard input works
	# Set counter to grab focus for next 3 frames to ensure it sticks
	focus_grab_counter = 3
	_grab_3d_viewport_focus()
	
	print("TransformationManager: Started transform mode for ", target_node.name)

static func exit_placement_mode():
	"""Coordinate exiting placement mode"""
	if current_mode != "placement":
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
	current_mode = ""
	
	# Hide and cleanup overlays
	OverlayManager.hide_transform_overlay()
	OverlayManager.set_mode("")
	
	print("TransformationManager: Exited placement mode")

static func exit_transform_mode(confirm_changes: bool = true):
	"""Coordinate exiting transform mode"""
	if current_mode != "transform":
		return
	
	var target_node = transform_data.get("target_node")
	
	if target_node and not confirm_changes:
		# Restore original transform if not confirming
		target_node.transform = transform_data.get("original_transform", Transform3D())
	
	# Reset transforms based on user settings
	_reset_transforms_on_exit()
	
	# Clear data
	transform_data.clear()
	
	# Reset mode
	current_mode = ""
	
	# Hide and cleanup overlays
	OverlayManager.hide_transform_overlay()
	OverlayManager.set_mode("")
	
	print("TransformationManager: Exited transform mode (confirmed: ", confirm_changes, ")")

static func exit_any_mode():
	"""Exit whatever mode is currently active"""
	match current_mode:
		"placement":
			exit_placement_mode()
		"transform":
			exit_transform_mode(false)

## INPUT PROCESSING COORDINATION

static func process_frame_input(camera: Camera3D, input_settings: Dictionary = {}):
	"""Process input for the current frame - coordinate with InputHandler"""
	# Store current settings for TAB key and other operations
	placement_settings = input_settings
	
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
		"placement":
			_process_placement_input(camera)
		"transform":
			_process_transform_input(camera)
	
	# Process global navigation input
	_process_navigation_input()

static func _process_placement_input(camera: Camera3D):
	"""Process input for placement mode"""
	if not camera:
		return
	
	var position_input = InputHandler.get_position_input()
	var rotation_input = InputHandler.get_rotation_input()
	var scale_input = InputHandler.get_scale_input()
	
	# Update position from mouse
	var mouse_pos = position_input.mouse_position
	var world_pos = PositionManager.update_position_from_mouse(camera, mouse_pos)
	
	# Handle height adjustments with reverse modifier support
	var reverse_height = position_input.shift_held  # SHIFT = reverse direction
	if position_input.height_up_pressed:
		if reverse_height:
			PositionManager.decrease_height()
		else:
			PositionManager.increase_height()
	elif position_input.height_down_pressed:
		if reverse_height:
			PositionManager.increase_height()
		else:
			PositionManager.decrease_height()
	
	# Update preview position
	PreviewManager.update_preview_position(PositionManager.get_current_position())
	
	# Apply surface normal alignment if enabled
	if placement_settings.get("align_with_normal", false):
		RotationManager.align_with_surface_normal(PositionManager.get_surface_normal())
		RotationManager.apply_rotation_to_node(PreviewManager.preview_mesh)
	
	# Handle rotation input
	_process_rotation_input(rotation_input, PreviewManager.preview_mesh)
	
	# Handle scale input
	_process_scale_input(scale_input, PreviewManager.preview_mesh)
	
	# Handle placement action
	if position_input.left_clicked:
		place_at_preview_position()
	
	# Update overlays with current state
	_update_placement_overlays()

static func _process_transform_input(camera: Camera3D):
	"""Process input for transform mode"""
	var target_node = transform_data.get("target_node")
	if not target_node or not camera:
		return
	
	var position_input = InputHandler.get_position_input()
	var rotation_input = InputHandler.get_rotation_input()
	var scale_input = InputHandler.get_scale_input()
	
	# Store current Y position before mouse update (only if node is in tree)
	var current_y = target_node.global_position.y if target_node.is_inside_tree() else 0.0
	
	# Handle height adjustments first with reverse modifier support
	var height_step = placement_settings.get("height_adjustment_step", 0.1)
	var reverse_height = position_input.shift_held  # SHIFT = reverse direction
	
	if position_input.height_up_pressed:
		current_y += height_step if not reverse_height else -height_step
	elif position_input.height_down_pressed:
		current_y -= height_step if not reverse_height else -height_step
	
	# Always update position from mouse (for XZ movement)
	var mouse_pos = position_input.mouse_position
	PositionManager.update_transform_node_position(target_node, camera, mouse_pos)
	
	# Restore the adjusted Y position (overriding the mouse raycast Y)
	if target_node.is_inside_tree():
		target_node.global_position.y = current_y
	
	# Apply surface normal alignment if enabled
	if placement_settings.get("align_with_normal", false):
		RotationManager.align_with_surface_normal(PositionManager.get_surface_normal())
		RotationManager.apply_rotation_to_node(target_node)
	
	# Handle rotation input
	_process_rotation_input(rotation_input, target_node)
	
	# Handle scale input
	_process_scale_input(scale_input, target_node)
	
	# Handle transform confirmation
	if position_input.left_clicked:
		exit_transform_mode(true)
	
	# Update overlays with current state
	_update_transform_overlays(target_node)

static func _process_rotation_input(rotation_input: Dictionary, target_node: Node3D):
	"""Process rotation input for any target node"""
	if not target_node:
		return
	
	# Handle rotation keys - use proper increment sizes and modifiers
	var rotation_step = placement_settings.get("rotation_increment", 15.0)  # Default
	
	# Apply modifier for increment size
	if rotation_input.alt_held:  # ALT = large increment
		rotation_step = placement_settings.get("large_rotation_increment", 90.0)
	elif rotation_input.ctrl_held:  # CTRL = fine increment
		rotation_step = placement_settings.get("fine_rotation_increment", 5.0)
	
	# Apply reverse direction modifier
	if rotation_input.shift_held:  # SHIFT = reverse direction
		rotation_step = -rotation_step
	
	if rotation_input.x_pressed:
		RotationManager.apply_rotation_step(target_node, "X", rotation_step)
	elif rotation_input.y_pressed:
		RotationManager.apply_rotation_step(target_node, "Y", rotation_step)
	elif rotation_input.z_pressed:
		RotationManager.apply_rotation_step(target_node, "Z", rotation_step)
	elif rotation_input.reset_pressed:
		RotationManager.reset_node_rotation(target_node)

static func _process_scale_input(scale_input: Dictionary, target_node: Node3D = null):
	"""Process scale input and apply to target node"""
	if not target_node:
		return
		
	var scale_step = placement_settings.get("scale_increment", 0.1)  # Default
	
	# Apply modifier for increment size
	if scale_input.alt_held:  # ALT = large increment
		scale_step = placement_settings.get("large_scale_increment", 0.5)
	
	if scale_input.up_pressed:
		ScaleManager.increase_scale(scale_step)
		ScaleManager.apply_uniform_scale_to_node(target_node)
	elif scale_input.down_pressed:
		ScaleManager.decrease_scale(scale_step)
		ScaleManager.apply_uniform_scale_to_node(target_node)
	elif scale_input.reset_pressed:
		ScaleManager.reset_scale()
		ScaleManager.apply_uniform_scale_to_node(target_node)

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
	
	return true  # Event was handled

static func _apply_height_adjustment(wheel_input: Dictionary):
	"""Apply height adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	if reverse:
		direction = -direction
	
	# Mouse wheel uses fine adjustment by default (no large increment for height with mouse wheel currently)
	var step = placement_settings.get("fine_height_increment", 0.01)
	
	if current_mode == "placement":
		if direction > 0:
			PositionManager.increase_height()
		else:
			PositionManager.decrease_height()
	elif current_mode == "transform":
		var target_node = transform_data.get("target_node")
		if target_node and target_node.is_inside_tree():
			target_node.global_position.y += step * direction

static func _apply_scale_adjustment(wheel_input: Dictionary):
	"""Apply scale adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var large_increment = wheel_input.get("large_increment", false)
	
	# Mouse wheel uses fine adjustment by default, unless ALT is held for large increment
	var step = placement_settings.get("fine_scale_increment", 0.01)
	if large_increment:
		step = placement_settings.get("large_scale_increment", 0.5)
	
	var target_node = null
	if current_mode == "placement":
		target_node = PreviewManager.preview_mesh
	elif current_mode == "transform":
		target_node = transform_data.get("target_node")
	
	if target_node:
		if direction > 0:
			ScaleManager.increase_scale(step)
		else:
			ScaleManager.decrease_scale(step)
		ScaleManager.apply_uniform_scale_to_node(target_node)

static func _apply_rotation_adjustment(wheel_input: Dictionary):
	"""Apply rotation adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var axis = wheel_input.get("axis", "Y")
	var large_increment = wheel_input.get("large_increment", false)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	# Mouse wheel uses fine adjustment by default, unless ALT is held for large increment
	var step = placement_settings.get("fine_rotation_increment", 5.0)
	if large_increment:
		step = placement_settings.get("large_rotation_increment", 90.0)
	
	if reverse:
		direction = -direction
	
	var target_node = null
	if current_mode == "placement":
		target_node = PreviewManager.preview_mesh
	elif current_mode == "transform":
		target_node = transform_data.get("target_node")
	
	if target_node:
		RotationManager.apply_rotation_step(target_node, axis, step * direction)

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
	
	# Find first Node3D in selection
	var target_node3d = null
	for node in selected_nodes:
		if node is Node3D:
			target_node3d = node
			break
	
	if not target_node3d:
		OverlayManager.show_status_message("Selected node is not a Node3D. Select a Node3D and press TAB.", Color.YELLOW, 3.0)
		return
	
	# Determine mode based on node context
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene and (target_node3d.is_ancestor_of(current_scene) or current_scene == target_node3d or target_node3d.is_inside_tree()):
		# Node is in scene - start transform mode
		start_transform_mode(target_node3d, dock_instance)
	else:
		# Node is external - start placement mode
		start_placement_from_node3d(target_node3d, dock_instance)

static func start_placement_from_node3d(node: Node3D, dock_instance = null):
	"""Start placement mode from a Node3D by extracting its mesh"""
	var extracted_mesh = UtilityManager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		# Use current placement settings (includes dock settings from process_frame_input)
		start_placement_mode(extracted_mesh, null, -1, "", placement_settings, dock_instance)
		OverlayManager.show_status_message("Placement mode activated for: " + node.name, Color.GREEN, 2.0)
	else:
		OverlayManager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)

## OVERLAY UPDATE COORDINATION

static func _update_placement_overlays():
	"""Update all overlays for placement mode"""
	var current_asset_name = placement_data.get("asset_path", "").get_file().get_basename() if placement_data.get("asset_path", "") != "" else "Mesh"
	
	OverlayManager.show_transform_overlay(
		"placement",
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
			"transform",
			target_node.name,
			target_node.global_position,
			target_node.rotation,
			target_node.scale.x  # Assuming uniform scale
		)

## PLACEMENT COORDINATION

static func place_at_preview_position():
	"""Coordinate placing object at current preview position"""
	if current_mode != "placement":
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
	return current_mode != ""

static func is_placement_mode() -> bool:
	"""Check if placement mode is active"""
	return current_mode == "placement"

static func is_transform_mode() -> bool:
	"""Check if transform mode is active"""
	return current_mode == "transform"

static func get_current_mode() -> String:
	"""Get the current mode"""
	return current_mode

static func get_current_scale() -> float:
	"""Get current scale multiplier"""
	return ScaleManager.get_scale()

## LEGACY COMPATIBILITY (Static data access for external consumers)

static var placement_mode: bool = false:
	get: return current_mode == "placement"
	set(value): 
		if value and current_mode != "placement":
			# This is a legacy call - show warning
			print("Warning: Using legacy placement_mode setter. Use start_placement_mode() instead.")

static var transform_mode: bool = false:
	get: return current_mode == "transform"
	set(value):
		if value and current_mode != "transform":
			print("Warning: Using legacy transform_mode setter. Use start_transform_mode() instead.")

# Legacy state properties (delegated to appropriate managers)
static var placement_mesh: Mesh = null:
	get: return placement_data.get("mesh")
	set(value): placement_data["mesh"] = value

static var placement_meshlib: MeshLibrary = null:
	get: return placement_data.get("meshlib")
	set(value): placement_data["meshlib"] = value

static var placement_item_id: int = -1:
	get: return placement_data.get("item_id", -1)
	set(value): placement_data["item_id"] = value

static var placement_asset_path: String = "":
	get: return placement_data.get("asset_path", "")
	set(value): placement_data["asset_path"] = value

static var is_meshlib_placement: bool = false:
	get: return placement_data.has("meshlib") and placement_data.get("item_id", -1) >= 0

static var placement_settings: Dictionary = {}:
	get: return placement_data.get("settings", {})
	set(value): placement_data["settings"] = value

static var dock_reference = null:
	get: return placement_data.get("dock_reference") if current_mode == "placement" else transform_data.get("dock_reference")
	set(value): 
		if current_mode == "placement":
			placement_data["dock_reference"] = value
		elif current_mode == "transform":
			transform_data["dock_reference"] = value

static var transform_node: Node3D = null:
	get: return transform_data.get("target_node")
	set(value): transform_data["target_node"] = value

static var original_transform: Transform3D = Transform3D():
	get: return transform_data.get("original_transform", Transform3D())
	set(value): transform_data["original_transform"] = value

static var transform_start_position: Vector3 = Vector3.ZERO:
	get: return PositionManager.get_current_position()
	set(value): PositionManager.set_position(value)

static var transform_mode_active: bool = false:
	get: return current_mode == "transform"

static var update_timer: Timer = null:
	get: return null  # Deprecated - no longer used
	set(value): pass  # Ignore - no longer used

static var left_was_pressed: bool = false:
	get: return InputHandler.is_mouse_button_pressed("left")
	set(value): pass  # Read-only through InputHandler

## CLEANUP

static func cleanup():
	"""Clean up all manager resources"""
	exit_any_mode()
	OverlayManager.cleanup_all_overlays()
	PreviewManager.cleanup_preview()
	placement_data.clear()
	transform_data.clear()
	settings.clear()
	print("TransformationManager: Cleanup completed")

## RESET MANAGEMENT

static func _reset_transforms_on_exit():
	"""Reset transforms based on user settings when exiting modes"""
	# Reset height offset if enabled
	if settings.get("reset_height_on_exit", false):
		PositionManager.reset_height()
	
	# Reset scale if enabled
	if settings.get("reset_scale_on_exit", false):
		ScaleManager.reset_scale()
	
	# Reset rotation if enabled
	if settings.get("reset_rotation_on_exit", false):
		RotationManager.reset_rotation()