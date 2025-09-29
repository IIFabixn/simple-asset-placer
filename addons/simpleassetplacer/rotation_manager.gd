@tool
extends RefCounted

class_name RotationManager

# Class-level variables for enhanced rotation system
static var is_active: bool = false
static var current_preview_mesh: MeshInstance3D = null
static var settings_cache: Dictionary = {}
static var shift_held: bool = false

# Rotation state
static var current_rotation_x: float = 0.0  # Pitch rotation in degrees
static var current_rotation_y: float = 0.0  # Yaw rotation in degrees  
static var current_rotation_z: float = 0.0  # Roll rotation in degrees
static var last_rotation_axis: String = "Y"  # Track which axis was last used for mouse wheel

# UI overlay for rotation feedback
static var rotation_overlay: Control = null
static var rotation_label: Label = null

# Enhanced key state tracking for new rotation system
static var rotation_key_states: Dictionary = {}  # Track which rotation keys are currently held
static var mouse_start_position: Vector2 = Vector2.ZERO  # Mouse position when key was first pressed
static var rotation_start_values: Vector3 = Vector3.ZERO  # Rotation values when mouse motion started
static var active_rotation_axis: String = ""  # Which axis is currently being rotated
static var mouse_rotation_sensitivity: float = 0.5  # Degrees per pixel of mouse movement

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
	"""Get rotation display text with active axis and interaction mode"""
	var x_text = "X: %d°" % current_rotation_x
	var y_text = "Y: %d°" % current_rotation_y
	var z_text = "Z: %d°" % current_rotation_z
	
	# Highlight the currently active rotation axis
	if active_rotation_axis == "X":
		x_text = "[" + x_text + " - MOUSE]"
	elif active_rotation_axis == "Y":
		y_text = "[" + y_text + " - MOUSE]"
	elif active_rotation_axis == "Z":
		z_text = "[" + z_text + " - MOUSE]"
	else:
		# Highlight the last used axis if no active mouse rotation
		match last_rotation_axis:
			"X":
				x_text = "[" + x_text + "]"
			"Y":
				y_text = "[" + y_text + "]"
			"Z":
				z_text = "[" + z_text + "]"
	
	var base_text = "Rotation: %s %s %s" % [x_text, y_text, z_text]
	
	# Add control instructions for simplified system
	base_text += "\nControls: X/Y/Z keys for 15° rotation"
	base_text += "\nModifiers: Shift=reverse, Ctrl=90°"
	
	return base_text

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

static var _settings_cache = {}
static var _settings_loaded = false

static func clear_settings_cache():
	"""Clear the settings cache to force reload"""
	_settings_cache = {}
	_settings_loaded = false
	print("[ROTATION_MANAGER] Settings cache cleared")

static func handle_key_input(event: InputEventKey, dock_instance = null) -> bool:
	"""Enhanced rotation key input handling with mouse motion support"""
	print("[ROTATION_MANAGER] handle_key_input called - keycode: ", event.keycode, " (", OS.get_keycode_string(event.keycode), "), pressed: ", event.pressed)
	
	# Force fresh settings load for debugging (bypass cache temporarily)
	# Force X/Y/Z settings (dock settings are returning old W/Q/E values)
	print("[ROTATION_MANAGER] Forcing X/Y/Z settings to override dock's W/Q/E values")
	var settings = {
		"rotate_x_key": "X",
		"rotate_y_key": "Y", 
		"rotate_z_key": "Z",
		"reset_rotation_key": "T",
		"rotation_increment": 15.0,
		"large_rotation_increment": 90.0
	}
	
	# Get rotation keys from settings
	var key_x = string_to_keycode(settings.get("rotate_x_key", "X"))
	var key_y = string_to_keycode(settings.get("rotate_y_key", "Y"))
	var key_z = string_to_keycode(settings.get("rotate_z_key", "Z"))
	var key_reset = string_to_keycode(settings.get("reset_rotation_key", "T"))
	
	# Handle reset key (immediate action on press)
	if event.keycode == key_reset and event.pressed:
		print("[ROTATION_MANAGER] Reset rotation key pressed")
		reset_rotation()
		update_overlay()
		return true
	

	
	# Key press-based rotation system with modifier support
	if event.pressed and (event.keycode == key_x or event.keycode == key_y or event.keycode == key_z):
		var axis = ""
		if event.keycode == key_x:
			axis = "X"
		elif event.keycode == key_y:
			axis = "Y"
		elif event.keycode == key_z:
			axis = "Z"
		
		print("[ROTATION_MANAGER] Key detected for axis: ", axis)
		
		# Determine increment based on modifiers
		var base_increment = settings.get("rotation_increment", 15.0)
		var large_increment = settings.get("large_rotation_increment", 90.0)
		
		# Update modifier state tracking
		shift_held = Input.is_key_pressed(KEY_SHIFT)
		var alt_held = Input.is_key_pressed(KEY_ALT)
		
		var increment = large_increment if alt_held else base_increment
		var direction = -1.0 if shift_held else 1.0
		var final_increment = increment * direction
		
		print("[ROTATION_MANAGER] ", axis, "-axis rotation: ", final_increment, "° (Alt: ", alt_held, ", Shift: ", shift_held, ")")
		rotate_axis(axis, final_increment)
		update_overlay()
		return true
	else:
		print("[ROTATION_MANAGER] No key match or not pressed")
	
	return false

static func handle_rotation_key_event(event: InputEventKey, axis: String, settings: Dictionary) -> bool:
	"""Handle press/release events for rotation keys"""
	print("[ROTATION_MANAGER] handle_rotation_key_event called for axis: ", axis, ", pressed: ", event.pressed)
	
	if event.pressed:
		# Key pressed - start rotation mode for this axis
		rotation_key_states[axis] = true
		active_rotation_axis = axis
		mouse_start_position = DisplayServer.mouse_get_position()
		rotation_start_values = get_rotation()
		
		print("[ROTATION_MANAGER] ", axis, "-axis rotation key pressed - mouse motion mode active")
		update_overlay()
		return true
	else:
		# Key released - apply base rotation increment
		if rotation_key_states.get(axis, false):
			rotation_key_states[axis] = false
			
			# Determine rotation direction and increment
			var increment = settings.get("large_rotation_increment", 90.0) if Input.is_key_pressed(KEY_CTRL) else settings.get("rotation_increment", 15.0)
			var direction = -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			var final_increment = increment * direction
			
			print("[ROTATION_MANAGER] ", axis, "-axis rotation key released - applying increment: ", final_increment, "° (Shift: ", Input.is_key_pressed(KEY_SHIFT), ")")
			print("[ROTATION_MANAGER] Current rotation before: ", get_rotation())
			rotate_axis(axis, final_increment)
			print("[ROTATION_MANAGER] Current rotation after: ", get_rotation())
			
			# Clear active rotation if this was the active axis
			if active_rotation_axis == axis:
				active_rotation_axis = ""
			
			update_overlay()
		else:
			print("[ROTATION_MANAGER] Key released but no matching pressed state found for axis: ", axis)
		return true
	
	return false

static func handle_mouse_motion(event: InputEventMouseMotion, dock_instance = null) -> bool:
	"""Handle mouse motion for rotation when rotation keys are held"""
	if active_rotation_axis == "":
		return false
	
	# Cache settings
	var settings = _settings_cache if _settings_loaded else get_rotation_settings(dock_instance)
	if not _settings_loaded:
		_settings_cache = settings
		_settings_loaded = true
	
	# Calculate mouse delta from start position
	var current_mouse_pos = DisplayServer.mouse_get_position()
	var mouse_delta = current_mouse_pos - mouse_start_position
	
	# Use horizontal mouse movement for rotation (could be configurable)
	var rotation_delta = mouse_delta.x * mouse_rotation_sensitivity
	
	# Apply snapping if enabled
	var snap_enabled = settings.get("snap_enabled", false)
	var rotation_increment = settings.get("rotation_increment", 15.0)
	
	if snap_enabled:
		# Snap to nearest increment boundary
		var total_rotation = rotation_delta
		var snapped_rotation = round(total_rotation / rotation_increment) * rotation_increment
		rotation_delta = snapped_rotation
	
	# Calculate final rotation value
	var base_rotation = rotation_start_values
	var new_rotation = base_rotation
	
	match active_rotation_axis:
		"X":
			new_rotation.x = base_rotation.x + rotation_delta
		"Y":
			new_rotation.y = base_rotation.y + rotation_delta
		"Z":
			new_rotation.z = base_rotation.z + rotation_delta
	
	# Apply the rotation directly (temporary, will be finalized on key release)
	current_rotation_x = fmod(new_rotation.x, 360.0)
	current_rotation_y = fmod(new_rotation.y, 360.0)
	current_rotation_z = fmod(new_rotation.z, 360.0)
	
	# Update preview
	PreviewManager.update_rotation()
	update_overlay()
	
	return true

static func check_keys_direct(dock_instance = null):
	"""Legacy function - enhanced rotation now handled through events"""
	# This function is kept for compatibility but the new system
	# uses handle_key_input and handle_mouse_motion instead
	pass

static func get_rotation_settings(dock_instance) -> Dictionary:
	"""Get rotation settings from dock instance"""
	print("[ROTATION_MANAGER] get_rotation_settings called, dock_instance: ", dock_instance)
	
	if dock_instance:
		if dock_instance.has_method("get_placement_settings"):
			var settings = dock_instance.get_placement_settings()
			print("[ROTATION_MANAGER] Raw settings from dock: ", settings)
			print("[ROTATION_MANAGER] Successfully loaded settings from dock: rotate_x_key=", settings.get("rotate_x_key", "X"), 
			      ", rotate_y_key=", settings.get("rotate_y_key", "Y"),
			      ", rotate_z_key=", settings.get("rotate_z_key", "Z"),
			      ", reset_rotation_key=", settings.get("reset_rotation_key", "T"),
			      ", rotation_increment=", settings.get("rotation_increment", 15.0),
			      ", large_rotation_increment=", settings.get("large_rotation_increment", 90.0))
			return settings
		else:
			print("[ROTATION_MANAGER] Dock instance found but missing get_placement_settings method")
	else:
		print("[ROTATION_MANAGER] No dock instance provided, using fallback defaults")
	
	# Return fallback defaults if no dock instance or settings available
	print("[ROTATION_MANAGER] Using fallback defaults")
	return {
		"rotate_x_key": "X",
		"rotate_y_key": "Y", 
		"rotate_z_key": "Z",
		"reset_rotation_key": "T",
		"rotation_increment": 15.0,
		"large_rotation_increment": 90.0
	}

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