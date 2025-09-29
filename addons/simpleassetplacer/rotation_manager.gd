@tool
extends RefCounted

class_name RotationManager

# Rotation state
static var current_rotation_x: float = 0.0  # Pitch rotation in degrees
static var current_rotation_y: float = 0.0  # Yaw rotation in degrees  
static var current_rotation_z: float = 0.0  # Roll rotation in degrees
static var last_rotation_axis: String = "Y"  # Track which axis was last used for mouse wheel

# UI overlay for rotation feedback
static var rotation_overlay: Control = null
static var rotation_label: Label = null

# Key state tracking for rotation
static var last_key_states: Dictionary = {}

static func reset_rotation():
	"""Reset all rotation values to zero"""
	current_rotation_x = 0.0
	current_rotation_y = 0.0
	current_rotation_z = 0.0
	last_rotation_axis = "Y"
	
	# Update preview to reflect rotation reset
	PreviewManager.update_rotation()

static func rotate_axis(axis: String, degrees: float):
	"""Rotate around the specified axis by the given degrees"""
	match axis:
		"X":
			current_rotation_x += degrees
		"Y":
			current_rotation_y += degrees
		"Z":
			current_rotation_z += degrees
	
	# Keep rotations within reasonable bounds
	current_rotation_x = fmod(current_rotation_x, 360.0)
	current_rotation_y = fmod(current_rotation_y, 360.0)
	current_rotation_z = fmod(current_rotation_z, 360.0)
	
	last_rotation_axis = axis
	
	# Update preview to reflect rotation change
	PreviewManager.update_rotation()

static func get_rotation() -> Vector3:
	"""Get the current rotation as a Vector3 in degrees"""
	return Vector3(current_rotation_x, current_rotation_y, current_rotation_z)

static func apply_rotation_to_node(node: Node3D):
	"""Apply the current rotation to a 3D node"""
	if node:
		node.rotation_degrees = get_rotation()

static func get_display_text() -> String:
	"""Get formatted rotation display text"""
	return "Rotation: X: %d° Y: %d° Z: %d°" % [current_rotation_x, current_rotation_y, current_rotation_z]

static func get_display_text_with_active() -> String:
	"""Get rotation display text with active axis highlighted"""
	var x_text = "X: %d°" % current_rotation_x
	var y_text = "Y: %d°" % current_rotation_y
	var z_text = "Z: %d°" % current_rotation_z
	
	# Highlight the last used axis
	match last_rotation_axis:
		"X":
			x_text = "[" + x_text + "]"
		"Y":
			y_text = "[" + y_text + "]"
		"Z":
			z_text = "[" + z_text + "]"
	
	return "Rotation: %s %s %s" % [x_text, y_text, z_text]

static func string_to_keycode(key_string: String) -> Key:
	"""Convert string representation to Key enum"""
	match key_string.to_upper():
		"A": return KEY_A
		"B": return KEY_B
		"C": return KEY_C
		"D": return KEY_D
		"E": return KEY_E
		"F": return KEY_F
		"G": return KEY_G
		"H": return KEY_H
		"I": return KEY_I
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"M": return KEY_M
		"N": return KEY_N
		"O": return KEY_O
		"P": return KEY_P
		"Q": return KEY_Q
		"R": return KEY_R
		"S": return KEY_S
		"T": return KEY_T
		"U": return KEY_U
		"V": return KEY_V
		"W": return KEY_W
		"X": return KEY_X
		"Y": return KEY_Y
		"Z": return KEY_Z
		_: return KEY_NONE

static func handle_key_input(event: InputEventKey, dock_instance = null) -> bool:
	"""Handle rotation key input events"""
	if not event.pressed:
		return false
	
	var settings = get_rotation_settings(dock_instance)
	
	# Get rotation keys from settings
	var key_x = string_to_keycode(settings.get("rotate_x_key", "X"))
	var key_y = string_to_keycode(settings.get("rotate_y_key", "R"))
	var key_z = string_to_keycode(settings.get("rotate_z_key", "Z"))
	var key_reset = string_to_keycode(settings.get("reset_rotation_key", "T"))
	
	# Choose increment based on Ctrl key
	var increment = settings.get("large_rotation_increment", 90.0) if event.ctrl_pressed else settings.get("rotation_increment", 15.0)
	
	if event.keycode == key_x:
		rotate_axis("X", increment)
		update_overlay()
		return true
	elif event.keycode == key_y:
		rotate_axis("Y", increment)
		update_overlay()
		return true
	elif event.keycode == key_z:
		rotate_axis("Z", increment)
		update_overlay()
		return true
	elif event.keycode == key_reset:
		reset_rotation()
		update_overlay()
		return true
	
	return false

static func check_keys_direct(dock_instance = null):
	"""Check rotation keys using direct input polling"""
	var settings = get_rotation_settings(dock_instance)
	
	# Get rotation keys from settings
	var key_x = string_to_keycode(settings.get("rotate_x_key", "X"))
	var key_y = string_to_keycode(settings.get("rotate_y_key", "R"))
	var key_z = string_to_keycode(settings.get("rotate_z_key", "Z"))
	var key_reset = string_to_keycode(settings.get("reset_rotation_key", "T"))
	
	# Choose increment based on Ctrl key
	var increment = settings.get("large_rotation_increment", 90.0) if Input.is_key_pressed(KEY_CTRL) else settings.get("rotation_increment", 15.0)
	
	# Check each key and track state to prevent repeated triggering
	var current_states = {
		"x": Input.is_key_pressed(key_x),
		"y": Input.is_key_pressed(key_y),
		"z": Input.is_key_pressed(key_z),
		"reset": Input.is_key_pressed(key_reset)
	}
	
	# Only trigger on key press (transition from false to true)
	if current_states.x and not last_key_states.get("x", false):
		rotate_axis("X", increment)
		update_overlay()
	elif current_states.y and not last_key_states.get("y", false):
		rotate_axis("Y", increment)
		update_overlay()
	elif current_states.z and not last_key_states.get("z", false):
		rotate_axis("Z", increment)
		update_overlay()
	elif current_states.reset and not last_key_states.get("reset", false):
		reset_rotation()
		update_overlay()
	
	# Update last states
	last_key_states = current_states

static func handle_wheel_input(event: InputEventMouseButton, dock_instance = null) -> bool:
	"""Mouse wheel input disabled to avoid conflicts with camera zoom"""
	# Always return false to let camera zoom work normally
	return false

static func get_rotation_settings(dock_instance) -> Dictionary:
	"""Get rotation settings from dock instance"""
	if dock_instance and dock_instance.has_method("get_placement_settings"):
		return dock_instance.get_placement_settings()
	return {}

static func create_overlay():
	"""Create the rotation feedback overlay"""
	if rotation_overlay:
		return  # Already exists
	
	# Find the 3D viewport
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		print("RotationManager: Could not find 3D viewport")
		return
	
	# Create overlay container
	rotation_overlay = Control.new()
	rotation_overlay.name = "RotationOverlay"
	rotation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Create background panel
	var panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create main label for rotation values
	rotation_label = Label.new()
	rotation_label.text = get_display_text_with_active()
	rotation_label.add_theme_font_size_override("font_size", 14)
	rotation_label.add_theme_color_override("font_color", Color.WHITE)
	rotation_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	rotation_label.add_theme_constant_override("shadow_offset_x", 1)
	rotation_label.add_theme_constant_override("shadow_offset_y", 1)
	
	# Create instruction labels
	var instruction_label = Label.new()
	var key_info_label = Label.new()
	
	# Position overlay at bottom center
	var vbox = VBoxContainer.new()
	vbox.add_child(rotation_label)
	vbox.add_child(instruction_label)
	vbox.add_child(key_info_label)
	
	panel.add_child(vbox)
	rotation_overlay.add_child(panel)
	
	# Position at bottom center
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 80  # Move up from very bottom
	
	# Add to viewport
	viewport_3d.add_child(rotation_overlay)
	
	print("RotationManager: Rotation overlay created and added to 3D viewport")

static func update_overlay():
	"""Update the rotation overlay display"""
	if rotation_label:
		rotation_label.text = get_display_text_with_active()

static func hide_overlay():
	"""Hide the rotation overlay"""
	if rotation_overlay and is_instance_valid(rotation_overlay):
		rotation_overlay.queue_free()
	rotation_overlay = null
	rotation_label = null