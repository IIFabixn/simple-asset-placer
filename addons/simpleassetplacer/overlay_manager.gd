@tool
extends RefCounted

class_name OverlayManager

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

# Overlay state
static var overlays_initialized: bool = false
static var current_mode: String = ""
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
		var text = "Rotation: X: %.1f° Y: %.1f° Z: %.1f°" % [
			rad_to_deg(rotation.x),
			rad_to_deg(rotation.y), 
			rad_to_deg(rotation.z)
		]
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
	
	# Position panel in bottom center
	panel.size = Vector2(400, 120)
	panel.position = Vector2(-200, -130)  # Centered horizontally, 130 pixels from bottom
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
	status_label.size = Vector2(380, 25)
	
	# Create transform info label
	var transform_label = Label.new()
	transform_label.name = "TransformLabel"
	transform_label.text = ""
	transform_label.add_theme_color_override("font_color", Color.CYAN)
	transform_label.add_theme_font_size_override("font_size", 12)
	transform_label.position = Vector2(10, 35)
	transform_label.size = Vector2(380, 75)
	transform_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transform_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	
	panel.add_child(status_label)
	panel.add_child(transform_label)
	status_overlay.add_child(panel)
	
	if main_overlay:
		main_overlay.add_child(status_overlay)
	
	status_overlay.visible = false

static func show_transform_overlay(mode: String, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: float = 1.0, height_offset: float = 0.0):
	"""Show unified transform overlay with all current transformation data"""
	if not show_overlays or not status_overlay:
		return
	
	var status_label = status_overlay.get_node("StatusPanel/StatusLabel")
	var transform_label = status_overlay.get_node("StatusPanel/TransformLabel")
	
	if status_label and transform_label:
		# Set mode-specific status message
		match mode:
			"placement":
				status_label.text = "🎯 PLACEMENT MODE" + (" - " + node_name if node_name != "" else "")
				status_label.add_theme_color_override("font_color", Color.YELLOW)
			"transform":
				status_label.text = "⚙️ TRANSFORM MODE" + (" - " + node_name if node_name != "" else "")
				status_label.add_theme_color_override("font_color", Color.CYAN)
			_:
				status_label.text = "🔧 Asset Placer Active"
				status_label.add_theme_color_override("font_color", Color.GREEN)
		
		# Build transform info text
		var transform_text = ""
		transform_text += "Position: X: %.2f  Y: %.2f  Z: %.2f\n" % [position.x, position.y, position.z]
		transform_text += "Rotation: X: %.1f°  Y: %.1f°  Z: %.1f°\n" % [rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z)]
		transform_text += "Scale: %.1f%%  " % (scale * 100.0)
		
		if height_offset != 0.0:
			transform_text += "Height Offset: %.2f" % height_offset
		else:
			transform_text += "Keys: O/P (Height)  L/K (Scale)  Mouse (Rotate)"
		
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
		if status_overlay and current_mode == "":  # Only hide if not in active mode
			status_overlay.visible = false

static func hide_transform_overlay():
	"""Hide the unified transform overlay"""
	if status_overlay:
		status_overlay.visible = false
	current_mode = ""

static func hide_status_overlay():
	"""Hide status overlay (legacy compatibility)"""
	hide_transform_overlay()

## Mode-Specific Display

static func set_mode(mode: String):
	"""Set current mode and update displays accordingly"""
	current_mode = mode
	
	match mode:
		"placement":
			# Mode will be properly displayed via show_transform_overlay calls
			pass
		"transform":
			# Mode will be properly displayed via show_transform_overlay calls  
			pass
		"":
			hide_transform_overlay()

static func update_mode_display(mode_data: Dictionary):
	"""Update all overlays based on current mode data"""
	if not show_overlays:
		return
	
	match current_mode:
		"placement":
			if mode_data.has("position"):
				show_position_overlay(mode_data.position, mode_data.get("height_offset", 0.0))
			if mode_data.has("rotation"):
				show_rotation_overlay(mode_data.rotation)
			if mode_data.has("scale"):
				show_scale_overlay(mode_data.scale)
		
		"transform":
			if mode_data.has("position"):
				show_position_overlay(mode_data.position)
			if mode_data.has("rotation"):
				show_rotation_overlay(mode_data.rotation, "Transforming...")

## Overlay Utilities

static func show_all_overlays():
	"""Show all relevant overlays for current mode"""
	show_overlays = true
	
	if rotation_overlay:
		rotation_overlay.visible = (current_mode in ["placement", "transform"])
	if scale_overlay:
		scale_overlay.visible = (current_mode == "placement")
	if position_overlay:
		position_overlay.visible = (current_mode in ["placement", "transform"])
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

## Debug and Information

static func debug_print_overlay_state():
	"""Print current overlay state for debugging"""
	print("OverlayManager State:")
	print("  Initialized: ", overlays_initialized)
	print("  Show Overlays: ", show_overlays)
	print("  Current Mode: ", current_mode)
	print("  Main Overlay Valid: ", main_overlay != null and is_instance_valid(main_overlay))
	print("  Rotation Overlay Valid: ", rotation_overlay != null and is_instance_valid(rotation_overlay))
	print("  Scale Overlay Valid: ", scale_overlay != null and is_instance_valid(scale_overlay))
	print("  Position Overlay Valid: ", position_overlay != null and is_instance_valid(position_overlay))
	print("  Status Overlay Valid: ", status_overlay != null and is_instance_valid(status_overlay))