@tool
extends RefCounted

class_name OverlayManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

"""
CENTRALIZED UI OVERLAY SYSTEM  
=============================

PURPOSE: Manages all user interface overlays and visual feedback for the plugin.

RESPONSIBILITIES:
- Creates and manages UI overlays (rotation, scale, position status)
- Displays real-time transformation feedback to user
- Mode-aware overlay switching (placement vs transform mode)
- Status messages and user notifications
- Overlay positioning and styling
- Cleanup and lifecycle management of UI elements

ARCHITECTURE POSITION: Pure UI management with no business logic
- Does NOT handle input detection or processing
- Does NOT perform calculations (receives display data from other managers)
- Does NOT know about transformation math

USED BY: TransformationCoordinator for all UI feedback
DEPENDS ON: Godot UI system, EditorInterface for overlay containers
"""

# Preload the status overlay scene
const StatusOverlayScene = preload("res://addons/simpleassetplacer/ui/status_overlay.tscn")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === INSTANCE VARIABLES ===

# Overlay references
var _main_overlay: Control = null
var _status_overlay = null  # StatusOverlayControl instance (no type hint to avoid caching issues)
var _toolbar_buttons: Control = null
var _grid_overlay: Node3D = null
var _half_step_grid_overlay: Node3D = null

# Overlay state
var _overlays_initialized: bool = false
var _current_mode: int = 0
var _show_overlays: bool = true
var _status_message_timer: Timer = null  # Track active status message timer

## Getters

func get_grid_overlay() -> Node3D:
	"""Get the grid overlay node"""
	return _grid_overlay

func get_half_step_grid_overlay() -> Node3D:
	"""Get the half-step grid overlay node"""
	return _half_step_grid_overlay

## Core Overlay Management

func initialize_overlays():
	"""Initialize all overlay systems"""
	if _overlays_initialized:
		return
	
	cleanup_all_overlays()
	_create_main_overlay()
	_overlays_initialized = true

func _create_main_overlay():
	"""Create the main overlay container"""
	if NodeUtils.is_valid(_main_overlay):
		return
	
	_main_overlay = Control.new()
	_main_overlay.name = "AssetPlacerOverlay"
	_main_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add to editor viewport
	var editor_viewport = _services.editor_facade.get_editor_main_screen()
	if editor_viewport:
		editor_viewport.add_child(_main_overlay)
	
	# Load status overlay from scene
	_load_status_overlay_scene()

## Status Overlay

func _load_status_overlay_scene():
	"""Load status overlay from scene file"""
	if NodeUtils.is_valid(_status_overlay):
		return
	
	# Instance the status overlay scene (CanvasLayer)
	_status_overlay = StatusOverlayScene.instantiate()
	if _services and _services.placement_strategy_service and _status_overlay.has_method("set_placement_strategy_service"):
		_status_overlay.set_placement_strategy_service(_services.placement_strategy_service)
	if _status_overlay.has_method("set_services"):
		_status_overlay.set_services(_services)
	
	# Add to the 3D viewport specifically so it's positioned relative to viewport, not entire editor
	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if viewport_3d:
		viewport_3d.add_child(_status_overlay)
	
	# Set visible to false AFTER it's in the tree (deferred to ensure _ready() has run)
	_status_overlay.call_deferred("set_visible", false)

func set_placement_settings_reference(placement_settings: Node):
	"""Set the PlacementSettings reference for the status overlay"""
	if NodeUtils.is_valid(_status_overlay) and _status_overlay.has_method("set_placement_settings"):
		_status_overlay.set_placement_settings(placement_settings)

func set_toolbar_reference(toolbar: Control):
	"""Set the toolbar buttons reference"""
	_toolbar_buttons = toolbar

func show_transform_overlay(mode: int, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: float = 1.0, offset_y: float = 0.0, transform_state = null):
	"""Show unified transform overlay with all current transformation data"""
	if not _is_overlay_ready():
		return
	
	# Get control mode state from services
	var control_mode_state = _services.control_mode_state if _services else null

	var snap_state := {}
	if transform_state:
		snap_state = {
			"position": transform_state.snap.snap_enabled,
			"snap_y": transform_state.snap.snap_y_enabled,
			"rotation": transform_state.snap.snap_rotation_enabled,
			"scale": transform_state.snap.snap_scale_enabled,
			"half_step": transform_state.snap.use_half_step,
			"align": transform_state.placement.align_with_normal
		}
	else:
		# Fallback: read from settings when transform_state is not available
		var combined_settings: Dictionary = _services.settings_manager.get_combined_settings()
		snap_state = {
			"position": combined_settings.get("snap_enabled", false),
			"snap_y": combined_settings.get("snap_y_enabled", false),
			"rotation": combined_settings.get("snap_rotation_enabled", false),
			"scale": combined_settings.get("snap_scale_enabled", false),
			"half_step": false,  # Half-step is runtime only
			"align": combined_settings.get("align_with_normal", false)
		}
	
	# Always add cursor_warp from settings
	var combined_settings: Dictionary = _services.settings_manager.get_combined_settings()
	snap_state["cursor_warp"] = combined_settings.get("cursor_warp_enabled", true)

	var modifier_state := {}
	if _services and _services.input_handler:
		modifier_state = _services.input_handler.get_modifier_state()

	var smooth_enabled := false
	if _services and _services.smooth_transform_manager:
		smooth_enabled = _services.smooth_transform_manager.is_smooth_transforms_enabled()

	var extra_state := {
		"snap_state": snap_state,
		"modifier_state": modifier_state,
		"smooth_enabled": smooth_enabled
	}
	
	# Use the scene's controller method
	_status_overlay.show_transform_info(mode, node_name, position, rotation, scale, offset_y, control_mode_state, extra_state)
	_current_mode = mode

func refresh_overlay_buttons():
	"""Refresh the button states in the toolbar"""
	if NodeUtils.is_valid(_toolbar_buttons) and _toolbar_buttons.has_method("refresh_button_states"):
		_toolbar_buttons.refresh_button_states()

func show_status_message(message: String, color: Color = Color.GREEN, duration: float = 0.0):
	"""Show a temporary status message"""
	if not _is_overlay_ready():
		return
	
	# Cancel any existing status message timer
	if _status_message_timer and is_instance_valid(_status_message_timer):
		_status_message_timer.stop()
		_status_message_timer.queue_free()
		_status_message_timer = null
	
	# Use the scene's controller method
	_status_overlay.show_status_message(message, color)
	
	# Auto-hide after duration if specified
	if duration > 0.0:
		_status_message_timer = Timer.new()
		_status_message_timer.wait_time = duration
		_status_message_timer.one_shot = true
		_status_message_timer.timeout.connect(_on_status_message_timeout)
		Engine.get_main_loop().root.add_child(_status_message_timer)
		_status_message_timer.start()

func _on_status_message_timeout():
	"""Handle status message timer timeout"""
	if NodeUtils.is_valid(_status_overlay) and _current_mode == 0:  # Only hide if not in active mode (0 = NONE)
		_status_overlay.hide_overlay()
	elif not NodeUtils.is_valid(_status_overlay):
		_status_overlay = null  # Clear invalid reference
	
	# Clean up timer
	if _status_message_timer and is_instance_valid(_status_message_timer):
		_status_message_timer.queue_free()
		_status_message_timer = null

func hide_transform_overlay():
	"""Hide the unified transform overlay"""
	if NodeUtils.is_valid_and_ready(_status_overlay):
		_status_overlay.hide_overlay()
	_current_mode = 0  # NONE mode

## Mode-Specific Display

func set_mode(mode: int):
	"""Update the current mode for overlay context"""
	_current_mode = mode
	
	match mode:
		1:  # PLACEMENT mode
			PluginLogger.debug("OverlayManager", "Mode set to PLACEMENT")
		2:  # TRANSFORM mode
			PluginLogger.debug("OverlayManager", "Mode set to TRANSFORM")
		0:  # NONE mode
			PluginLogger.debug("OverlayManager", "Mode set to NONE")

## Overlay Utilities

func show_all_overlays():
	"""Show all relevant overlays for current mode"""
	_show_overlays = true
	_ensure_overlay_visible(true)

func hide_all_overlays():
	"""Hide all overlays"""
	_show_overlays = false
	hide_transform_overlay()

func cleanup_all_overlays():
	"""Clean up all overlay resources"""
	# Clean up status message timer
	if _status_message_timer and is_instance_valid(_status_message_timer):
		_status_message_timer.stop()
		_status_message_timer.queue_free()
		_status_message_timer = null
	
	_status_overlay = NodeUtils.cleanup_and_null(_status_overlay)
	_grid_overlay = NodeUtils.cleanup_and_null(_grid_overlay)
	_half_step_grid_overlay = NodeUtils.cleanup_and_null(_half_step_grid_overlay)
	_main_overlay = NodeUtils.cleanup_and_null(_main_overlay)
	
	_overlays_initialized = false

## Consolidated Helper Functions

func _is_overlay_ready() -> bool:
	"""Check if overlays are properly initialized and ready for use"""
	return _show_overlays and NodeUtils.is_valid_and_ready(_status_overlay)

func _ensure_overlay_visible(visible: bool = true) -> void:
	"""Ensure status overlay has the specified visibility"""
	NodeUtils.safe_set_visible(_status_overlay, visible)

func _cleanup_grids() -> void:
	"""Clean up both main and half-step grid overlays"""
	_grid_overlay = NodeUtils.cleanup_and_null(_grid_overlay)
	_half_step_grid_overlay = NodeUtils.cleanup_and_null(_half_step_grid_overlay)

## Configuration

func set_overlay_visibility(visible: bool):
	"""Set global overlay visibility"""
	_show_overlays = visible
	
	if visible:
		show_all_overlays()
	else:
		hide_all_overlays()

func configure_overlay_positions(positions: Dictionary):
	"""Configure overlay positions"""	
	if positions.has("status") and _status_overlay:
		var label = _status_overlay.get_node("StatusLabel")
		if label:
			label.position = positions.status

## Grid Overlay

func create_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO, show_half_step: bool = false, plane_type: String = "XZ"):
	"""Create a 3D grid visualization in the world
	center: Center position of the grid
	grid_size: Size of each grid cell
	grid_extent: Number of cells in each direction from center
	offset: Grid offset from world origin
	show_half_step: If true, show a red half-step grid overlay
	plane_type: Which plane to draw the grid on ("XZ", "XY", or "YZ")"""
	
	# Clean up existing grids
	remove_grid_overlay()
	
	# Get the 3D editor viewport
	var editor_root = _services.editor_facade.get_edited_scene_root()
	if not editor_root:
		return
	
	# Create main grid node
	_grid_overlay = MeshInstance3D.new()
	_grid_overlay.name = "AssetPlacerGrid"
	
	# IMPORTANT: Set top_level = true to make grid independent of parent's transform
	# This prevents the grid from being affected by the scene root's rotation/scale
	# Without this, if the scene root is rotated (e.g., 180° Y rotation), the grid would be flipped
	_grid_overlay.top_level = true
	
	# Create grid mesh
	var immediate_mesh = ImmediateMesh.new()
	_grid_overlay.mesh = immediate_mesh
	
	# Create material for main grid lines
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.3)  # Light blue, semi-transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true  # Always visible
	material.disable_receive_shadows = true
	_grid_overlay.material_override = material
	
	# Draw main grid lines
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Draw grid based on plane type
	match plane_type:
		"XZ":  # Horizontal plane (Y is constant)
			_draw_xz_grid(immediate_mesh, center, grid_size, grid_extent, offset)
		"XY":  # Vertical plane facing Z (Z is constant)
			_draw_xy_grid(immediate_mesh, center, grid_size, grid_extent, offset)
		"YZ":  # Vertical plane facing X (X is constant)
			_draw_yz_grid(immediate_mesh, center, grid_size, grid_extent, offset)
		_:
			# Default to XZ plane
			_draw_xz_grid(immediate_mesh, center, grid_size, grid_extent, offset)
	
	immediate_mesh.surface_end()
	
	# Add main grid to scene
	editor_root.add_child(_grid_overlay)
	_grid_overlay.global_position = Vector3.ZERO  # Lines use absolute world coordinates
	
	# Create half-step grid if requested
	if show_half_step:
		_create_half_step_grid(center, grid_size * 0.5, grid_extent * 2, offset, editor_root, plane_type)

func _draw_xz_grid(mesh: ImmediateMesh, center: Vector3, grid_size: float, grid_extent: int, offset: Vector3):
	"""Draw grid on XZ plane (horizontal, Y is constant)"""
	var center_grid_x = round((center.x - offset.x) / grid_size)
	var center_grid_z = round((center.z - offset.z) / grid_size)
	
	var start_grid_x = center_grid_x - grid_extent
	var end_grid_x = center_grid_x + grid_extent
	var start_grid_z = center_grid_z - grid_extent
	var end_grid_z = center_grid_z + grid_extent
	
	var y = center.y  # Grid at object's height
	
	# Draw lines parallel to X axis (running along Z direction)
	for grid_z in range(start_grid_z, end_grid_z + 1):
		var z = grid_z * grid_size + offset.z
		var x_start = start_grid_x * grid_size + offset.x
		var x_end = end_grid_x * grid_size + offset.x
		
		mesh.surface_add_vertex(Vector3(x_start, y, z))
		mesh.surface_add_vertex(Vector3(x_end, y, z))
	
	# Draw lines parallel to Z axis (running along X direction)
	for grid_x in range(start_grid_x, end_grid_x + 1):
		var x = grid_x * grid_size + offset.x
		var z_start = start_grid_z * grid_size + offset.z
		var z_end = end_grid_z * grid_size + offset.z
		
		mesh.surface_add_vertex(Vector3(x, y, z_start))
		mesh.surface_add_vertex(Vector3(x, y, z_end))

func _draw_xy_grid(mesh: ImmediateMesh, center: Vector3, grid_size: float, grid_extent: int, offset: Vector3):
	"""Draw grid on XY plane (vertical, Z is constant)"""
	var center_grid_x = round((center.x - offset.x) / grid_size)
	var center_grid_y = round((center.y - offset.y) / grid_size)
	
	var start_grid_x = center_grid_x - grid_extent
	var end_grid_x = center_grid_x + grid_extent
	var start_grid_y = center_grid_y - grid_extent
	var end_grid_y = center_grid_y + grid_extent
	
	var z = center.z  # Grid at object's Z position
	
	# Draw lines parallel to X axis (running along Y direction)
	for grid_y in range(start_grid_y, end_grid_y + 1):
		var y = grid_y * grid_size + offset.y
		var x_start = start_grid_x * grid_size + offset.x
		var x_end = end_grid_x * grid_size + offset.x
		
		mesh.surface_add_vertex(Vector3(x_start, y, z))
		mesh.surface_add_vertex(Vector3(x_end, y, z))
	
	# Draw lines parallel to Y axis (running along X direction)
	for grid_x in range(start_grid_x, end_grid_x + 1):
		var x = grid_x * grid_size + offset.x
		var y_start = start_grid_y * grid_size + offset.y
		var y_end = end_grid_y * grid_size + offset.y
		
		mesh.surface_add_vertex(Vector3(x, y_start, z))
		mesh.surface_add_vertex(Vector3(x, y_end, z))

func _draw_yz_grid(mesh: ImmediateMesh, center: Vector3, grid_size: float, grid_extent: int, offset: Vector3):
	"""Draw grid on YZ plane (vertical, X is constant)"""
	var center_grid_y = round((center.y - offset.y) / grid_size)
	var center_grid_z = round((center.z - offset.z) / grid_size)
	
	var start_grid_y = center_grid_y - grid_extent
	var end_grid_y = center_grid_y + grid_extent
	var start_grid_z = center_grid_z - grid_extent
	var end_grid_z = center_grid_z + grid_extent
	
	var x = center.x  # Grid at object's X position
	
	# Draw lines parallel to Y axis (running along Z direction)
	for grid_z in range(start_grid_z, end_grid_z + 1):
		var z = grid_z * grid_size + offset.z
		var y_start = start_grid_y * grid_size + offset.y
		var y_end = end_grid_y * grid_size + offset.y
		
		mesh.surface_add_vertex(Vector3(x, y_start, z))
		mesh.surface_add_vertex(Vector3(x, y_end, z))
	
	# Draw lines parallel to Z axis (running along Y direction)
	for grid_y in range(start_grid_y, end_grid_y + 1):
		var y = grid_y * grid_size + offset.y
		var z_start = start_grid_z * grid_size + offset.z
		var z_end = end_grid_z * grid_size + offset.z
		
		mesh.surface_add_vertex(Vector3(x, y, z_start))
		mesh.surface_add_vertex(Vector3(x, y, z_end))

func _create_half_step_grid(center: Vector3, half_grid_size: float, grid_extent: int, offset: Vector3, editor_root: Node, plane_type: String = "XZ"):
	"""Create a red half-step grid overlay for fine snapping visualization"""
	
	# Create half-step grid node
	_half_step_grid_overlay = MeshInstance3D.new()
	_half_step_grid_overlay.name = "AssetPlacerHalfStepGrid"
	_half_step_grid_overlay.top_level = true
	
	# Create half-step grid mesh
	var half_mesh = ImmediateMesh.new()
	_half_step_grid_overlay.mesh = half_mesh
	
	# Create material for half-step grid lines (red, more transparent)
	var half_material = StandardMaterial3D.new()
	half_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	half_material.albedo_color = Color(1.0, 0.3, 0.3, 0.25)  # Red, semi-transparent
	half_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	half_material.no_depth_test = true  # Always visible
	half_material.disable_receive_shadows = true
	_half_step_grid_overlay.material_override = half_material
	
	# Draw half-step grid lines
	half_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Draw half-step grid based on plane type (slightly offset to prevent z-fighting)
	var offset_center = center
	match plane_type:
		"XZ":
			offset_center.y += 0.01
			_draw_xz_grid(half_mesh, offset_center, half_grid_size, grid_extent, offset)
		"XY":
			offset_center.z += 0.01
			_draw_xy_grid(half_mesh, offset_center, half_grid_size, grid_extent, offset)
		"YZ":
			offset_center.x += 0.01
			_draw_yz_grid(half_mesh, offset_center, half_grid_size, grid_extent, offset)
		_:
			offset_center.y += 0.01
			_draw_xz_grid(half_mesh, offset_center, half_grid_size, grid_extent, offset)
	
	half_mesh.surface_end()
	
	# Add half-step grid to scene
	editor_root.add_child(_half_step_grid_overlay)
	_half_step_grid_overlay.global_position = Vector3.ZERO

func update_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO, show_half_step: bool = false, plane_type: String = "XZ"):
	"""Update existing grid or create new one"""
	create_grid_overlay(center, grid_size, grid_extent, offset, show_half_step, plane_type)

func hide_grid_overlay():
	"""Hide the grid overlay"""
	NodeUtils.safe_set_visible(_grid_overlay, false)
	NodeUtils.safe_set_visible(_half_step_grid_overlay, false)

func show_grid_overlay():
	"""Show the grid overlay"""
	NodeUtils.safe_set_visible(_grid_overlay, true)
	NodeUtils.safe_set_visible(_half_step_grid_overlay, true)

func remove_grid_overlay():
	"""Remove and cleanup grid overlay"""
	_cleanup_grids()

## Debug and Information

func debug_print_overlay_state():
	"""Print current overlay state for debugging"""
	PluginLogger.debug("OverlayManager", "OverlayManager State:")
	PluginLogger.debug("OverlayManager", "  Initialized: " + str(_overlays_initialized))
	PluginLogger.debug("OverlayManager", "  Show Overlays: " + str(_show_overlays))
	PluginLogger.debug("OverlayManager", "  Current Mode: " + str(_current_mode))
	PluginLogger.debug("OverlayManager", "  Main Overlay Valid: " + str(NodeUtils.is_valid(_main_overlay)))
	PluginLogger.debug("OverlayManager", "  Status Overlay Valid: " + str(NodeUtils.is_valid(_status_overlay)))
	PluginLogger.debug("OverlayManager", "  Grid Overlay Valid: " + str(NodeUtils.is_valid(_grid_overlay)))
	PluginLogger.debug("OverlayManager", "  Half-Step Grid Overlay Valid: " + str(NodeUtils.is_valid(_half_step_grid_overlay)))






