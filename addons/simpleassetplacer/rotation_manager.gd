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

# Enhanced key state tracking for mouse motion rotation system
static var rotation_key_states: Dictionary = {}  # Track which rotation keys are currently held
static var mouse_start_position: Vector2 = Vector2.ZERO  # Mouse position when key was first pressed
static var mouse_motion_active: bool = false  # Whether mouse motion rotation is active
static var active_rotation_axis: String = ""  # Which axis is being rotated by mouse
static var rotation_start_values: Vector3 = Vector3.ZERO  # Rotation values when mouse motion started
static var mouse_rotation_sensitivity: float = 0.5  # Degrees per pixel of mouse movement

# Hold detection system for tap vs hold behavior  
static var hold_threshold_ms: float = 200.0  # Milliseconds to distinguish tap vs hold
static var key_press_start_time: Dictionary = {}  # When each key was first pressed
static var key_hold_processed: Dictionary = {}  # Whether we've already processed the hold for this key

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
	

	
	# Handle rotation keys for both press and release
	if event.keycode == key_x or event.keycode == key_y or event.keycode == key_z:
		var axis = ""
		if event.keycode == key_x:
			axis = "X"
		elif event.keycode == key_y:
			axis = "Y"
		elif event.keycode == key_z:
			axis = "Z"
		
		if event.pressed:
			# Key pressed - start mouse motion mode or apply instant rotation
			handle_rotation_key_press(axis, event)
		else:
			# Key released - end mouse motion mode or apply final rotation  
			handle_rotation_key_release(axis, event)
		
		return true
		
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
			var increment = settings.get("large_rotation_increment", 90.0) if Input.is_key_pressed(KEY_ALT) else settings.get("rotation_increment", 15.0)
			var direction = -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			var final_increment = increment * direction
			
			print("[ROTATION_MANAGER] ", axis, "-axis rotation key released - applying increment: ", final_increment, "° (Shift: ", Input.is_key_pressed(KEY_SHIFT), ", Alt: ", Input.is_key_pressed(KEY_ALT), ")")
			print("[ROTATION_MANAGER] Current rotation before: ", get_rotation())
			rotate_axis(axis, final_increment)
			print("[ROTATION_MANAGER] Current rotation after: ", get_rotation())
			
			# Clear active rotation if this was the active axis
			if active_rotation_axis == axis:
				active_rotation_axis = ""
			
			update_overlay()
		else:
			print("[ROTATION_MANAGER] Key released but no matching pressed state found for axis: ", axis)
	return false

static func handle_rotation_key_press(axis: String, event: InputEventKey):
	"""Handle when a rotation key is pressed - start tracking for tap vs hold"""
	print("[ROTATION_MANAGER] Key pressed for axis: ", axis)
	
	# Update modifier states
	shift_held = Input.is_key_pressed(KEY_SHIFT)
	var alt_held = Input.is_key_pressed(KEY_ALT)
	
	# Check if any modifiers are held - if so, apply instant rotation immediately
	if shift_held or alt_held:
		print("[ROTATION_MANAGER] Modifiers detected - applying instant rotation")
		# Use fallback settings since this is the old event system
		var fallback_settings = {
			"rotation_increment": 15.0,
			"large_rotation_increment": 90.0
		}
		apply_instant_rotation(axis, shift_held, alt_held, fallback_settings)
		return
	
	# If already in mouse motion mode for this axis - toggle it off
	if mouse_motion_active and active_rotation_axis == axis:
		print("[ROTATION_MANAGER] Ending mouse motion mode for ", axis)
		end_mouse_motion_rotation(axis)
		return
	
	# Record when this key was pressed and reset hold processing flag
	key_press_start_time[axis] = Time.get_ticks_msec()
	key_hold_processed[axis] = false
	print("[ROTATION_MANAGER] Started tracking key press time for axis: ", axis)

static func handle_rotation_key_release(axis: String, event: InputEventKey):
	"""Handle when a rotation key is released - apply base increment if it was a quick tap"""
	print("[ROTATION_MANAGER] Key released for axis: ", axis)
	
	if mouse_motion_active and active_rotation_axis == axis:
		# End mouse motion rotation that was already active
		end_mouse_motion_rotation(axis)
		return
	
	# Check if this was a quick tap (key released and hold wasn't processed)
	if key_press_start_time.has(axis) and not key_hold_processed.get(axis, false):
		var press_duration = Time.get_ticks_msec() - key_press_start_time[axis]
		if press_duration < hold_threshold_ms:
			print("[ROTATION_MANAGER] Quick tap detected (", press_duration, "ms) - applying base increment for axis: ", axis)
			var base_increment = 15.0
			var shift_held = Input.is_key_pressed(KEY_SHIFT)
			if shift_held:
				base_increment = -base_increment  # Reverse direction for shift
			rotate_axis(axis, base_increment)
	
	# Clean up tracking data
	key_press_start_time.erase(axis)
	key_hold_processed.erase(axis)

static func start_mouse_motion_rotation(axis: String):
	"""Start mouse motion rotation mode"""
	print("[ROTATION_MANAGER] start_mouse_motion_rotation called for axis: ", axis)
	var preview_mesh = PreviewManager.preview_mesh
	print("[ROTATION_MANAGER] PreviewManager.preview_mesh exists: ", preview_mesh != null)
	if not preview_mesh:
		print("[ROTATION_MANAGER] ❌ Cannot start mouse motion - no preview mesh!")
		return
		
	mouse_motion_active = true
	active_rotation_axis = axis
	mouse_start_position = get_mouse_position()
	
	# Store current rotation values
	rotation_start_values = Vector3(current_rotation_x, current_rotation_y, current_rotation_z)
	
	print("[ROTATION_MANAGER] 🎯 Started MOUSE MOTION rotation for ", axis, " axis - move mouse to rotate!")
	update_overlay()  # Update visual feedback

static func end_mouse_motion_rotation(axis: String):
	"""End mouse motion rotation mode"""
	mouse_motion_active = false
	active_rotation_axis = ""
	
	print("[ROTATION_MANAGER] ✅ Ended mouse motion rotation for ", axis, " axis")
	update_overlay()  # Update visual feedback

static func apply_instant_rotation(axis: String, reverse_held: bool, large_increment_held: bool, settings: Dictionary):
	"""Apply instant rotation with configurable modifiers"""
	var base_increment = settings.get("rotation_increment", 15.0)
	var large_increment = settings.get("large_rotation_increment", 90.0)
	
	var increment = large_increment if large_increment_held else base_increment
	var direction = -1.0 if reverse_held else 1.0
	var final_increment = increment * direction
	
	print("[ROTATION_MANAGER] ", axis, "-axis rotation: ", final_increment, "° (Large: ", large_increment_held, ", Reverse: ", reverse_held, ")")
	rotate_axis(axis, final_increment)

static func get_mouse_position() -> Vector2:
	"""Get current mouse position"""
	return DisplayServer.mouse_get_position()

static func handle_mouse_polling(current_mouse_pos: Vector2, dock_instance = null) -> bool:
	"""Handle mouse position updates from polling system for rotation"""
	# Check for hold detection on currently pressed keys
	check_for_key_holds()
	
	if not mouse_motion_active or active_rotation_axis == "":
		return false
	
	print("[ROTATION_MANAGER] 🖱️ Mouse polling - active axis: ", active_rotation_axis, ", mouse pos: ", current_mouse_pos)
	
	# Calculate mouse delta from start position
	var mouse_delta = current_mouse_pos - mouse_start_position
	
	# Use horizontal mouse movement for rotation
	var rotation_delta = mouse_delta.x * mouse_rotation_sensitivity
	
	# Calculate final rotation value
	var new_rotation_x = rotation_start_values.x
	var new_rotation_y = rotation_start_values.y  
	var new_rotation_z = rotation_start_values.z
	
	match active_rotation_axis:
		"X":
			new_rotation_x = rotation_start_values.x + rotation_delta
		"Y":
			new_rotation_y = rotation_start_values.y + rotation_delta
		"Z":
			new_rotation_z = rotation_start_values.z + rotation_delta
	
	# Apply the rotation
	current_rotation_x = fmod(new_rotation_x, 360.0)
	current_rotation_y = fmod(new_rotation_y, 360.0)
	current_rotation_z = fmod(new_rotation_z, 360.0)
	
	# Update preview
	PreviewManager.update_rotation()
	update_overlay()
	
	print("[ROTATION_MANAGER] Applied rotation - ", active_rotation_axis, ": ", rotation_delta, "°")
	return true

static func handle_mouse_motion(event: InputEventMouseMotion, dock_instance = null) -> bool:
	"""Handle mouse motion for rotation when rotation keys are held (legacy - now using polling)"""
	print("[ROTATION_MANAGER] handle_mouse_motion called - mouse_motion_active: ", mouse_motion_active, ", active_rotation_axis: '", active_rotation_axis, "'")
	if not mouse_motion_active or active_rotation_axis == "":
		print("[ROTATION_MANAGER] Mouse motion not handled - not in rotation mode")
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
		"large_rotation_increment": 90.0,
		"reverse_modifier_key": "SHIFT",
		"large_increment_modifier_key": "ALT"
	}

static func get_modifier_keycodes(settings: Dictionary) -> Dictionary:
	"""Get modifier key codes from settings"""
	var reverse_key_string = settings.get("reverse_modifier_key", "SHIFT")
	var large_increment_key_string = settings.get("large_increment_modifier_key", "ALT")
	
	var reverse_keycode = KEY_SHIFT
	var large_increment_keycode = KEY_ALT
	
	# Convert strings to keycodes
	match reverse_key_string.to_upper():
		"SHIFT": reverse_keycode = KEY_SHIFT
		"CTRL": reverse_keycode = KEY_CTRL
		"ALT": reverse_keycode = KEY_ALT
		"META": reverse_keycode = KEY_META
	
	match large_increment_key_string.to_upper():
		"SHIFT": large_increment_keycode = KEY_SHIFT
		"CTRL": large_increment_keycode = KEY_CTRL
		"ALT": large_increment_keycode = KEY_ALT
		"META": large_increment_keycode = KEY_META
	
	return {
		"reverse": reverse_keycode,
		"large_increment": large_increment_keycode
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

# New state tracking variables for _process-based input
static var key_states: Dictionary = {}  # Track current key states for edge detection
static var key_press_times: Dictionary = {}  # Track when keys were pressed

static func process_key_input(delta: float, dock_instance = null):
	"""Handle rotation key input with precise timing in _process function"""
	# Get settings
	var settings = get_rotation_settings(dock_instance)
	var key_x = string_to_keycode(settings.get("rotate_x_key", "X"))
	var key_y = string_to_keycode(settings.get("rotate_y_key", "Y"))
	var key_z = string_to_keycode(settings.get("rotate_z_key", "Z"))
	var key_reset = string_to_keycode(settings.get("reset_rotation_key", "T"))
	
	var current_time = Time.get_ticks_msec()
	
	# Handle reset key
	if Input.is_key_pressed(key_reset):
		if not key_states.get("reset", false):  # Just pressed
			print("[ROTATION_MANAGER] Reset rotation key pressed")
			reset_rotation()
			update_overlay()
		key_states["reset"] = true
	else:
		key_states["reset"] = false
	
	# Handle rotation keys
	var rotation_keys = [
		{"key": key_x, "axis": "X"},
		{"key": key_y, "axis": "Y"},
		{"key": key_z, "axis": "Z"}
	]
	
	for key_info in rotation_keys:
		var keycode = key_info.key
		var axis = key_info.axis
		var is_pressed = Input.is_key_pressed(keycode)
		var was_pressed = key_states.get(axis, false)
		
		if is_pressed and not was_pressed:
			# Key just pressed
			handle_key_just_pressed(axis, current_time, settings)
		elif not is_pressed and was_pressed:
			# Key just released
			handle_key_just_released(axis, current_time, settings)
		elif is_pressed and was_pressed:
			# Key held - check for hold threshold
			check_key_hold_status(axis, current_time, settings)
		
		key_states[axis] = is_pressed
	
	# Update mouse motion if active
	if mouse_motion_active and active_rotation_axis != "":
		var current_mouse_pos = DisplayServer.mouse_get_position()
		handle_mouse_polling(current_mouse_pos, dock_instance)

static func handle_key_just_pressed(axis: String, current_time: float, settings: Dictionary):
	"""Handle when a rotation key is just pressed"""
	print("[ROTATION_MANAGER] Key just pressed for axis: ", axis)
	
	# Get configurable modifier keys
	var modifier_keys = get_modifier_keycodes(settings)
	
	# Check if any modifiers are held - if so, apply instant rotation immediately
	var reverse_held = Input.is_key_pressed(modifier_keys.reverse)
	var large_increment_held = Input.is_key_pressed(modifier_keys.large_increment)
	
	if reverse_held or large_increment_held:
		print("[ROTATION_MANAGER] Modifiers detected - applying instant rotation")
		apply_instant_rotation(axis, reverse_held, large_increment_held, settings)
		return
	
	# If already in mouse motion mode for this axis - toggle it off
	if mouse_motion_active and active_rotation_axis == axis:
		print("[ROTATION_MANAGER] Ending mouse motion mode for ", axis)
		end_mouse_motion_rotation(axis)
		return
	
	# Start tracking this key press
	key_press_times[axis] = current_time
	print("[ROTATION_MANAGER] Started tracking key press for axis: ", axis)

static func handle_key_just_released(axis: String, current_time: float, settings: Dictionary):
	"""Handle when a rotation key is just released"""
	print("[ROTATION_MANAGER] Key just released for axis: ", axis)
	
	if mouse_motion_active and active_rotation_axis == axis:
		# End active mouse motion rotation
		end_mouse_motion_rotation(axis)
		key_press_times.erase(axis)
		return
	
	# Check if this was a quick tap
	if key_press_times.has(axis):
		var press_duration = current_time - key_press_times[axis]
		if press_duration < hold_threshold_ms:
			print("[ROTATION_MANAGER] Quick tap detected (", press_duration, "ms) - applying base increment for axis: ", axis)
			
			# Get configurable settings
			var base_increment = settings.get("rotation_increment", 15.0)
			var modifier_keys = get_modifier_keycodes(settings)
			var reverse_held = Input.is_key_pressed(modifier_keys.reverse)
			
			if reverse_held:
				base_increment = -base_increment  # Reverse direction
			rotate_axis(axis, base_increment)
		
		key_press_times.erase(axis)

static func check_key_hold_status(axis: String, current_time: float, settings: Dictionary):
	"""Check if a held key has crossed the hold threshold"""
	if not key_press_times.has(axis):
		return
	
	var press_duration = current_time - key_press_times[axis]
	if press_duration >= hold_threshold_ms and not mouse_motion_active:
		print("[ROTATION_MANAGER] ⏱️ Hold threshold reached (", press_duration, "ms) - starting mouse motion for axis: ", axis)
		start_mouse_motion_rotation(axis)

static func check_for_key_holds():
	"""Check if any tracked keys have been held long enough to trigger mouse motion (legacy function)"""
	var current_time = Time.get_ticks_msec()
	
	for axis in key_press_start_time.keys():
		if key_hold_processed.get(axis, false):
			continue  # Already processed this key's hold
			
		var press_duration = current_time - key_press_start_time[axis]
		if press_duration >= hold_threshold_ms:
			# Key has been held long enough - start mouse motion
			print("[ROTATION_MANAGER] ⏱️ Hold detected (", press_duration, "ms) - starting mouse motion for axis: ", axis)
			start_mouse_motion_rotation(axis)
			key_hold_processed[axis] = true

static func hide_overlay():
	"""Hide the rotation overlay"""
	if rotation_overlay and is_instance_valid(rotation_overlay):
		rotation_overlay.queue_free()
	rotation_overlay = null
	rotation_label = null