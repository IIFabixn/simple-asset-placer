@tool
extends RefCounted

class_name OverlayManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")
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
var _status_overlay: CanvasLayer = null
var _toolbar_buttons: Control = null
var _grid_overlay: Node3D = null
var _half_step_grid_overlay: Node3D = null

# Overlay state
var _overlays_initialized: bool = false
var _current_mode: int = 0
var _show_overlays: bool = true

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

func show_transform_overlay(mode: int, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: float = 1.0, height_offset: float = 0.0):
	"""Show unified transform overlay with all current transformation data"""
	if not _is_overlay_ready():
		return
	
	# Use the scene's controller method
	_status_overlay.show_transform_info(mode, node_name, position, rotation, scale, height_offset)
	_current_mode = mode

func refresh_overlay_buttons():
	"""Refresh the button states in the toolbar"""
	if NodeUtils.is_valid(_toolbar_buttons) and _toolbar_buttons.has_method("refresh_button_states"):
		_toolbar_buttons.refresh_button_states()

func show_status_message(message: String, color: Color = Color.GREEN, duration: float = 0.0):
	"""Show a temporary status message"""
	if not _is_overlay_ready():
		return
	
	# Use the scene's controller method
	_status_overlay.show_status_message(message, color)
	
	# Auto-hide after duration if specified
	if duration > 0.0:
		await Engine.get_main_loop().create_timer(duration).timeout
		if NodeUtils.is_valid(_status_overlay) and _current_mode == 0:  # Only hide if not in active mode (0 = NONE)
			_status_overlay.hide_overlay()
		elif not NodeUtils.is_valid(_status_overlay):
			_status_overlay = null  # Clear invalid reference

func hide_transform_overlay():
	"""Hide the unified transform overlay"""
	if NodeUtils.is_valid_and_ready(_status_overlay):
		_status_overlay.hide_overlay()
	_current_mode = 0  # NONE mode

func hide_status_overlay():
	"""Hide status overlay (legacy compatibility)"""
	hide_transform_overlay()

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
	hide_status_overlay()

func cleanup_all_overlays():
	"""Clean up all overlay resources"""
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

func create_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO, show_half_step: bool = false):
	"""Create a 3D grid visualization in the world
	center: Center position of the grid
	grid_size: Size of each grid cell
	grid_extent: Number of cells in each direction from center
	offset: Grid offset from world origin
	show_half_step: If true, show a red half-step grid overlay"""
	
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
	
	# Calculate the range of grid lines to draw based on center position
	# We want grid lines at exact grid positions (accounting for offset)
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
		
		immediate_mesh.surface_add_vertex(Vector3(x_start, y, z))
		immediate_mesh.surface_add_vertex(Vector3(x_end, y, z))
	
	# Draw lines parallel to Z axis (running along X direction)
	for grid_x in range(start_grid_x, end_grid_x + 1):
		var x = grid_x * grid_size + offset.x
		var z_start = start_grid_z * grid_size + offset.z
		var z_end = end_grid_z * grid_size + offset.z
		
		immediate_mesh.surface_add_vertex(Vector3(x, y, z_start))
		immediate_mesh.surface_add_vertex(Vector3(x, y, z_end))
	
	immediate_mesh.surface_end()
	
	# Add main grid to scene
	editor_root.add_child(_grid_overlay)
	_grid_overlay.global_position = Vector3.ZERO  # Lines use absolute world coordinates
	
	# Create half-step grid if requested
	if show_half_step:
		_create_half_step_grid(center, grid_size * 0.5, grid_extent * 2, offset, editor_root)

func _create_half_step_grid(center: Vector3, half_grid_size: float, grid_extent: int, offset: Vector3, editor_root: Node):
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
	
	# Calculate grid positions for half-step grid
	var center_grid_x = round((center.x - offset.x) / half_grid_size)
	var center_grid_z = round((center.z - offset.z) / half_grid_size)
	
	var start_grid_x = center_grid_x - grid_extent
	var end_grid_x = center_grid_x + grid_extent
	var start_grid_z = center_grid_z - grid_extent
	var end_grid_z = center_grid_z + grid_extent
	
	var y = center.y + 0.01  # Slightly above main grid to prevent z-fighting
	
	# Draw lines parallel to X axis (running along Z direction)
	for grid_z in range(start_grid_z, end_grid_z + 1):
		var z = grid_z * half_grid_size + offset.z
		var x_start = start_grid_x * half_grid_size + offset.x
		var x_end = end_grid_x * half_grid_size + offset.x
		
		half_mesh.surface_add_vertex(Vector3(x_start, y, z))
		half_mesh.surface_add_vertex(Vector3(x_end, y, z))
	
	# Draw lines parallel to Z axis (running along X direction)
	for grid_x in range(start_grid_x, end_grid_x + 1):
		var x = grid_x * half_grid_size + offset.x
		var z_start = start_grid_z * half_grid_size + offset.z
		var z_end = end_grid_z * half_grid_size + offset.z
		
		half_mesh.surface_add_vertex(Vector3(x, y, z_start))
		half_mesh.surface_add_vertex(Vector3(x, y, z_end))
	
	half_mesh.surface_end()
	
	# Add half-step grid to scene
	editor_root.add_child(_half_step_grid_overlay)
	_half_step_grid_overlay.global_position = Vector3.ZERO

func update_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO, show_half_step: bool = false):
	"""Update existing grid or create new one"""
	create_grid_overlay(center, grid_size, grid_extent, offset, show_half_step)

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






