@tool
extends RefCounted

class_name OverlayManager

# Forward reference to TransformationManager for Mode enum
const TransformationManager = preload("res://addons/simpleassetplacer/transformation_manager.gd")
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement_strategy_manager.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings_manager.gd")

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

USED BY: TransformationManager for all UI feedback
DEPENDS ON: Godot UI system, EditorInterface for overlay containers
"""

# Overlay references
static var main_overlay: Control = null
static var rotation_overlay: Control = null
static var scale_overlay: Control = null
static var position_overlay: Control = null
static var status_overlay: Control = null
static var grid_overlay: Node3D = null  # 3D grid visualization

# Overlay state
static var overlays_initialized: bool = false
static var current_mode: TransformationManager.Mode = TransformationManager.Mode.NONE
static var show_overlays: bool = true

## Core Overlay Management

static func initialize_overlays():
	"""Initialize all overlay systems"""
	if overlays_initialized:
		return
	
	cleanup_all_overlays()
	_create_main_overlay()
	overlays_initialized = true

static func _create_main_overlay():
	"""Create the main overlay container"""
	if main_overlay and is_instance_valid(main_overlay):
		return
	
	main_overlay = Control.new()
	main_overlay.name = "AssetPlacerOverlay"
	main_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add to editor viewport
	var editor_viewport = EditorInterface.get_editor_main_screen()
	if editor_viewport:
		editor_viewport.add_child(main_overlay)
	
	# Create unified status overlay
	_create_status_overlay()

## Rotation Overlay

static func _create_rotation_overlay():
	"""Create rotation feedback overlay"""
	if rotation_overlay and is_instance_valid(rotation_overlay):
		return
	
	rotation_overlay = Control.new()
	rotation_overlay.name = "RotationOverlay"
	rotation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create rotation display label
	var rotation_label = Label.new()
	rotation_label.name = "RotationLabel"
	rotation_label.text = "Rotation: X: 0° Y: 0° Z: 0°"
	rotation_label.add_theme_color_override("font_color", Color.WHITE)
	rotation_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	rotation_label.add_theme_constant_override("shadow_offset_x", 2)
	rotation_label.add_theme_constant_override("shadow_offset_y", 2)
	rotation_label.position = Vector2(20, 60)
	
	rotation_overlay.add_child(rotation_label)
	
	if main_overlay:
		main_overlay.add_child(rotation_overlay)
	
	rotation_overlay.visible = false

static func show_rotation_overlay(rotation: Vector3, message: String = ""):
	"""Show rotation overlay with current values"""
	if not show_overlays or not rotation_overlay:
		return
	
	var label = rotation_overlay.get_node("RotationLabel")
	if label:
		# Convert to degrees and normalize to 0-360 range for display
		var x_deg = fmod(rad_to_deg(rotation.x) + 360.0, 360.0)
		var y_deg = fmod(rad_to_deg(rotation.y) + 360.0, 360.0)
		var z_deg = fmod(rad_to_deg(rotation.z) + 360.0, 360.0)
		
		var text = "Rotation: X: %.1f° Y: %.1f° Z: %.1f°" % [x_deg, y_deg, z_deg]
		if message != "":
			text += "\n" + message
		label.text = text
	
	rotation_overlay.visible = true
	rotation_overlay.modulate.a = 1.0

static func hide_rotation_overlay():
	"""Hide rotation overlay"""
	if rotation_overlay:
		rotation_overlay.visible = false

## Scale Overlay

static func _create_scale_overlay():
	"""Create scale feedback overlay"""
	if scale_overlay and is_instance_valid(scale_overlay):
		return
	
	scale_overlay = Control.new()
	scale_overlay.name = "ScaleOverlay"
	scale_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create scale display label
	var scale_label = Label.new()
	scale_label.name = "ScaleLabel"
	scale_label.text = "Scale: 100%"
	scale_label.add_theme_color_override("font_color", Color.YELLOW)
	scale_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	scale_label.add_theme_constant_override("shadow_offset_x", 2)
	scale_label.add_theme_constant_override("shadow_offset_y", 2)
	scale_label.position = Vector2(20, 100)
	
	scale_overlay.add_child(scale_label)
	
	if main_overlay:
		main_overlay.add_child(scale_overlay)
	
	scale_overlay.visible = false

static func show_scale_overlay(scale_value: float, message: String = ""):
	"""Show scale overlay with current value"""
	if not show_overlays or not scale_overlay:
		return
	
	var label = scale_overlay.get_node("ScaleLabel")
	if label:
		var text = "Scale: %.1f%%" % (scale_value * 100.0)
		if message != "":
			text += " - " + message
		label.text = text
	
	scale_overlay.visible = true
	scale_overlay.modulate.a = 1.0

static func hide_scale_overlay():
	"""Hide scale overlay"""
	if scale_overlay:
		scale_overlay.visible = false

## Position Overlay

static func _create_position_overlay():
	"""Create position feedback overlay"""
	if position_overlay and is_instance_valid(position_overlay):
		return
	
	position_overlay = Control.new()
	position_overlay.name = "PositionOverlay"
	position_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create position display label
	var position_label = Label.new()
	position_label.name = "PositionLabel"
	position_label.text = "Position: X: 0.0 Y: 0.0 Z: 0.0"
	position_label.add_theme_color_override("font_color", Color.CYAN)
	position_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	position_label.add_theme_constant_override("shadow_offset_x", 2)
	position_label.add_theme_constant_override("shadow_offset_y", 2)
	position_label.position = Vector2(20, 140)
	
	position_overlay.add_child(position_label)
	
	if main_overlay:
		main_overlay.add_child(position_overlay)
	
	position_overlay.visible = false

static func show_position_overlay(position: Vector3, height_offset: float = 0.0):
	"""Show position overlay with current values"""
	if not show_overlays or not position_overlay:
		return
	
	var label = position_overlay.get_node("PositionLabel")
	if label:
		var text = "Position: X: %.2f Y: %.2f Z: %.2f" % [position.x, position.y, position.z]
		if height_offset != 0.0:
			text += "\nHeight Offset: %.2f" % height_offset
		label.text = text
	
	position_overlay.visible = true
	position_overlay.modulate.a = 1.0

static func hide_position_overlay():
	"""Hide position overlay"""
	if position_overlay:
		position_overlay.visible = false

## Status Overlay

static func _create_status_overlay():
	"""Create unified status overlay box in bottom center"""
	if status_overlay and is_instance_valid(status_overlay):
		return
	
	# Main container for the overlay box
	status_overlay = Control.new()
	status_overlay.name = "StatusOverlay"
	status_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_overlay.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	
	# Background panel for the overlay box
	var panel = Panel.new()
	panel.name = "StatusPanel"
	
	# Style the panel with dark background and border
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	style_box.border_color = Color(0.5, 0.5, 0.5, 0.9)
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	
	panel.add_theme_stylebox_override("panel", style_box)
	
	# Position panel in bottom center (wider to accommodate placement strategy)
	panel.size = Vector2(700, 120)
	panel.position = Vector2(-350, -130)  # Centered horizontally, 130 pixels from bottom
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	
	# Create main status label
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Asset Placer Ready"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.position = Vector2(10, 10)
	status_label.size = Vector2(680, 25)
	
	# Create transform info label
	var transform_label = Label.new()
	transform_label.name = "TransformLabel"
	transform_label.text = ""
	transform_label.add_theme_color_override("font_color", Color.CYAN)
	transform_label.add_theme_font_size_override("font_size", 12)
	transform_label.position = Vector2(10, 35)
	transform_label.size = Vector2(680, 75)
	transform_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transform_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	
	panel.add_child(status_label)
	panel.add_child(transform_label)
	status_overlay.add_child(panel)
	
	if main_overlay:
		main_overlay.add_child(status_overlay)
	
	status_overlay.visible = false

static func show_transform_overlay(mode: TransformationManager.Mode, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: float = 1.0, height_offset: float = 0.0):
	"""Show unified transform overlay with all current transformation data"""
	if not show_overlays or not status_overlay:
		return
	
	var status_label = status_overlay.get_node("StatusPanel/StatusLabel")
	var transform_label = status_overlay.get_node("StatusPanel/TransformLabel")
	
	if status_label and transform_label:
		# Get current placement strategy for display
		var strategy_name = PlacementStrategyManager.get_active_strategy_name()
		var strategy_icon = "🎯" if PlacementStrategyManager.get_active_strategy_type() == "collision" else "📐"
		
		# Set mode-specific status message with strategy indicator
		match mode:
			TransformationManager.Mode.PLACEMENT:
				status_label.text = "🎯 PLACEMENT MODE" + (" - " + node_name if node_name != "" else "") + "  |  " + strategy_icon + " " + strategy_name
				status_label.add_theme_color_override("font_color", Color.YELLOW)
			TransformationManager.Mode.TRANSFORM:
				status_label.text = "⚙️ TRANSFORM MODE" + (" - " + node_name if node_name != "" else "") + "  |  " + strategy_icon + " " + strategy_name
				status_label.add_theme_color_override("font_color", Color.CYAN)
			_:
				status_label.text = "🔧 Asset Placer Active  |  " + strategy_icon + " " + strategy_name
				status_label.add_theme_color_override("font_color", Color.GREEN)
		
		# Build transform info text
		var transform_text = ""
		transform_text += "Position: X: %.2f  Y: %.2f  Z: %.2f\n" % [position.x, position.y, position.z]
		transform_text += "Rotation: X: %.1f°  Y: %.1f°  Z: %.1f°\n" % [rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z)]
		transform_text += "Scale: %.1f%%  " % (scale * 100.0)
		
		if height_offset != 0.0:
			transform_text += "Height Offset: %.2f" % height_offset
		else:
			# Get actual keybinds from settings
			var settings = SettingsManager.get_combined_settings()
			var move_keys = "%s%s%s%s" % [
				settings.get("position_forward_key", "W"),
				settings.get("position_left_key", "A"),
				settings.get("position_back_key", "S"),
				settings.get("position_right_key", "D")
			]
			var height_up = settings.get("height_up_key", "Q")
			var height_down = settings.get("height_down_key", "E")
			var cycle_mode = settings.get("cycle_placement_mode_key", "P")
			
			# Show mode-specific keybinds with actual keys
			if mode == TransformationManager.Mode.PLACEMENT:
				transform_text += "%s (Move)  %s/%s (Height)  Mouse (Rotate)  PgUp/PgDn (Scale)  %s (Mode)" % [move_keys, height_up, height_down, cycle_mode]
			else:  # transform mode
				transform_text += "%s (Move)  %s/%s (Height)  Mouse+X/Y/Z (Rotate)  %s (Mode)  CTRL/ALT (Modifiers)" % [move_keys, height_up, height_down, cycle_mode]
		
		transform_label.text = transform_text
	
	status_overlay.visible = true
	current_mode = mode

static func show_status_message(message: String, color: Color = Color.GREEN, duration: float = 0.0):
	"""Show a temporary status message"""
	if not show_overlays or not status_overlay:
		return
	
	var status_label = status_overlay.get_node("StatusPanel/StatusLabel")
	var transform_label = status_overlay.get_node("StatusPanel/TransformLabel")
	
	if status_label and transform_label:
		status_label.text = message
		status_label.add_theme_color_override("font_color", color)
		transform_label.text = ""  # Clear transform info for simple messages
	
	status_overlay.visible = true
	
	# Auto-hide after duration if specified
	if duration > 0.0:
		await Engine.get_main_loop().create_timer(duration).timeout
		if status_overlay and current_mode == TransformationManager.Mode.NONE:  # Only hide if not in active mode
			status_overlay.visible = false

static func hide_transform_overlay():
	"""Hide the unified transform overlay"""
	if status_overlay:
		status_overlay.visible = false
		# Also hide it deferred to ensure it stays hidden
		status_overlay.call_deferred("set_visible", false)
	current_mode = TransformationManager.Mode.NONE

static func hide_status_overlay():
	"""Hide status overlay (legacy compatibility)"""
	hide_transform_overlay()

## Mode-Specific Display

static func set_mode(mode: TransformationManager.Mode):
	"""Set current mode and update displays accordingly"""
	current_mode = mode
	
	match mode:
		TransformationManager.Mode.PLACEMENT:
			# Mode will be properly displayed via show_transform_overlay calls
			pass
		TransformationManager.Mode.TRANSFORM:
			# Mode will be properly displayed via show_transform_overlay calls  
			pass
		TransformationManager.Mode.NONE:
			hide_transform_overlay()

static func update_mode_display(mode_data: Dictionary):
	"""Update all overlays based on current mode data"""
	if not show_overlays:
		return
	
	match current_mode:
		TransformationManager.Mode.PLACEMENT:
			if mode_data.has("position"):
				show_position_overlay(mode_data.position, mode_data.get("height_offset", 0.0))
			if mode_data.has("rotation"):
				show_rotation_overlay(mode_data.rotation)
			if mode_data.has("scale"):
				show_scale_overlay(mode_data.scale)
		
		TransformationManager.Mode.TRANSFORM:
			if mode_data.has("position"):
				show_position_overlay(mode_data.position)
			if mode_data.has("rotation"):
				show_rotation_overlay(mode_data.rotation, "Transforming...")

## Overlay Utilities

static func show_all_overlays():
	"""Show all relevant overlays for current mode"""
	show_overlays = true
	
	if rotation_overlay:
		rotation_overlay.visible = (current_mode in [TransformationManager.Mode.PLACEMENT, TransformationManager.Mode.TRANSFORM])
	if scale_overlay:
		scale_overlay.visible = (current_mode == TransformationManager.Mode.PLACEMENT)
	if position_overlay:
		position_overlay.visible = (current_mode in [TransformationManager.Mode.PLACEMENT, TransformationManager.Mode.TRANSFORM])
	if status_overlay:
		status_overlay.visible = true

static func hide_all_overlays():
	"""Hide all overlays"""
	show_overlays = false
	
	hide_rotation_overlay()
	hide_scale_overlay()
	hide_position_overlay()
	hide_status_overlay()

static func cleanup_all_overlays():
	"""Clean up all overlay resources"""
	if rotation_overlay and is_instance_valid(rotation_overlay):
		rotation_overlay.queue_free()
		rotation_overlay = null
	
	if scale_overlay and is_instance_valid(scale_overlay):
		scale_overlay.queue_free()
		scale_overlay = null
	
	if position_overlay and is_instance_valid(position_overlay):
		position_overlay.queue_free()
		position_overlay = null
	
	if status_overlay and is_instance_valid(status_overlay):
		status_overlay.queue_free()
		status_overlay = null
	
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.queue_free()
		grid_overlay = null
	
	if main_overlay and is_instance_valid(main_overlay):
		main_overlay.queue_free()
		main_overlay = null
	
	overlays_initialized = false

## Configuration

static func set_overlay_visibility(visible: bool):
	"""Set global overlay visibility"""
	show_overlays = visible
	
	if visible:
		show_all_overlays()
	else:
		hide_all_overlays()

static func configure_overlay_positions(positions: Dictionary):
	"""Configure overlay positions"""
	if positions.has("rotation") and rotation_overlay:
		var label = rotation_overlay.get_node("RotationLabel")
		if label:
			label.position = positions.rotation
	
	if positions.has("scale") and scale_overlay:
		var label = scale_overlay.get_node("ScaleLabel")
		if label:
			label.position = positions.scale
	
	if positions.has("position") and position_overlay:
		var label = position_overlay.get_node("PositionLabel")
		if label:
			label.position = positions.position
	
	if positions.has("status") and status_overlay:
		var label = status_overlay.get_node("StatusLabel")
		if label:
			label.position = positions.status

## Grid Overlay

static func create_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO):
	"""Create a 3D grid visualization in the world
	center: Center position of the grid
	grid_size: Size of each grid cell
	grid_extent: Number of cells in each direction from center
	offset: Grid offset from world origin"""
	
	# Clean up existing grid
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.queue_free()
	
	# Get the 3D editor viewport
	var editor_root = EditorInterface.get_edited_scene_root()
	if not editor_root:
		return
	
	# Create grid node
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "AssetPlacerGrid"
	
	# IMPORTANT: Set top_level = true to make grid independent of parent's transform
	# This prevents the grid from being affected by the scene root's rotation/scale
	# Without this, if the scene root is rotated (e.g., 180° Y rotation), the grid would be flipped
	grid_overlay.top_level = true
	
	# Create grid mesh
	var immediate_mesh = ImmediateMesh.new()
	grid_overlay.mesh = immediate_mesh
	
	# Create material for grid lines
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.3)  # Light blue, semi-transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true  # Always visible
	material.disable_receive_shadows = true
	grid_overlay.material_override = material
	
	# Draw grid lines
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
	
	# Add to scene
	editor_root.add_child(grid_overlay)
	grid_overlay.global_position = Vector3.ZERO  # Lines use absolute world coordinates

static func update_grid_overlay(center: Vector3, grid_size: float, grid_extent: int = 10, offset: Vector3 = Vector3.ZERO):
	"""Update existing grid or create new one"""
	create_grid_overlay(center, grid_size, grid_extent, offset)

static func hide_grid_overlay():
	"""Hide the grid overlay"""
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.visible = false

static func show_grid_overlay():
	"""Show the grid overlay"""
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.visible = true

static func remove_grid_overlay():
	"""Remove and cleanup grid overlay"""
	if grid_overlay and is_instance_valid(grid_overlay):
		grid_overlay.queue_free()
		grid_overlay = null

## Debug and Information

static func debug_print_overlay_state():
	"""Print current overlay state for debugging"""
	PluginLogger.debug("OverlayManager", "OverlayManager State:")
	PluginLogger.debug("OverlayManager", "  Initialized: " + str(overlays_initialized))
	PluginLogger.debug("OverlayManager", "  Show Overlays: " + str(show_overlays))
	PluginLogger.debug("OverlayManager", "  Current Mode: " + str(current_mode))
	PluginLogger.debug("OverlayManager", "  Main Overlay Valid: " + str(main_overlay != null and is_instance_valid(main_overlay)))
	PluginLogger.debug("OverlayManager", "  Rotation Overlay Valid: " + str(rotation_overlay != null and is_instance_valid(rotation_overlay)))
	PluginLogger.debug("OverlayManager", "  Scale Overlay Valid: " + str(scale_overlay != null and is_instance_valid(scale_overlay)))
	PluginLogger.debug("OverlayManager", "  Position Overlay Valid: " + str(position_overlay != null and is_instance_valid(position_overlay)))
	PluginLogger.debug("OverlayManager", "  Status Overlay Valid: " + str(status_overlay != null and is_instance_valid(status_overlay)))
	PluginLogger.debug("OverlayManager", "  Grid Overlay Valid: " + str(grid_overlay != null and is_instance_valid(grid_overlay)))