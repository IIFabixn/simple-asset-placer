@tool
extends RefCounted

class_name ScaleManager

# Scale state
static var current_scale: float = 1.0  # Uniform scale multiplier
static var scale_step: float = 0.1  # Default scale increment
static var min_scale: float = 0.1  # Minimum scale
static var max_scale: float = 10.0  # Maximum scale

# UI overlay for scale feedback
static var scale_overlay: Control = null
static var scale_label: Label = null

static func reset_scale():
	"""Reset scale to 1.0 (original size)"""
	current_scale = 1.0
	
	# Notify that scale changed - handled by placement system
	_notify_scale_changed()

static func adjust_scale(delta: float):
	"""Adjust scale by the given delta"""
	current_scale += delta
	
	# Keep scale within reasonable bounds
	current_scale = clamp(current_scale, min_scale, max_scale)
	
	# Notify that scale changed - handled by placement system
	_notify_scale_changed()

static func multiply_scale(multiplier: float):
	"""Multiply current scale by a factor"""
	current_scale *= multiplier
	
	# Keep scale within reasonable bounds
	current_scale = clamp(current_scale, min_scale, max_scale)
	
	# Notify that scale changed - handled by placement system
	_notify_scale_changed()

static func _notify_scale_changed():
	"""Internal method to handle scale updates"""
	# This will be called by the placement system to update preview
	pass

static func get_scale() -> float:
	"""Get the current scale value"""
	return current_scale

static func apply_scale_to_node(node: Node3D):
	"""Apply the current scale to a 3D node"""
	if node:
		# Preserve the base scale and apply our multiplier
		var base_scale = node.get_meta("original_scale", Vector3.ONE)
		node.scale = base_scale * current_scale

static func get_display_text() -> String:
	"""Get formatted scale display text"""
	return "Scale: %.1fx" % current_scale

static func handle_key_input(event: InputEventKey, settings: Dictionary) -> bool:
	"""Handle scale keyboard input"""
	var scale_up_key = settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = settings.get("scale_down_key", "PAGE_DOWN")
	var scale_reset_key = settings.get("scale_reset_key", "HOME")
	
	var scale_increment = settings.get("scale_increment", 0.1)
	var large_scale_increment = settings.get("large_scale_increment", 0.5)
	
	# Convert string keys to keycodes
	var scale_up_keycode = string_to_keycode(scale_up_key)
	var scale_down_keycode = string_to_keycode(scale_down_key)
	var scale_reset_keycode = string_to_keycode(scale_reset_key)
	
	# Get modifier key settings
	var large_increment_key = settings.get("large_increment_modifier_key", "ALT")
	var reverse_key = settings.get("reverse_modifier_key", "SHIFT")
	
	# Check if modifiers are pressed (need to check Input directly since event doesn't have all modifiers)
	var large_increment_pressed = _is_modifier_pressed(large_increment_key)
	var reverse_pressed = _is_modifier_pressed(reverse_key)
	
	# Check for scale up
	if event.keycode == scale_up_keycode:
		var increment = large_scale_increment if large_increment_pressed else scale_increment
		# Apply reverse modifier (swap up/down behavior)
		var final_increment = increment if not reverse_pressed else -increment
		adjust_scale(final_increment)
		show_scale_overlay()
		return true
	
	# Check for scale down
	if event.keycode == scale_down_keycode:
		var increment = large_scale_increment if large_increment_pressed else scale_increment
		# Apply reverse modifier (swap up/down behavior)
		var final_increment = -increment if not reverse_pressed else increment
		adjust_scale(final_increment)
		show_scale_overlay()
		return true
	
	# Check for scale reset
	if event.keycode == scale_reset_keycode:
		reset_scale()
		show_scale_overlay()
		return true
	
	return false

static func string_to_keycode(key_string: String) -> Key:
	"""Convert string representation to Key enum"""
	match key_string.to_upper():
		"PAGE_UP": return KEY_PAGEUP
		"PAGE_DOWN": return KEY_PAGEDOWN
		"HOME": return KEY_HOME
		"END": return KEY_END
		"INSERT": return KEY_INSERT
		"DELETE": return KEY_DELETE
		"PLUS": return KEY_PLUS
		"MINUS": return KEY_MINUS
		"EQUAL": return KEY_EQUAL
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
		"0": return KEY_0
		"1": return KEY_1
		"2": return KEY_2
		"3": return KEY_3
		"4": return KEY_4
		"5": return KEY_5
		"6": return KEY_6
		"7": return KEY_7
		"8": return KEY_8
		"9": return KEY_9
		_: return KEY_NONE

static func show_scale_overlay():
	"""Show scale overlay with current scale value"""
	create_scale_overlay()
	
	if scale_overlay and scale_label:
		scale_label.text = get_display_text()
		scale_overlay.visible = true
		
		# Hide overlay after 2 seconds
		var viewport = EditorInterface.get_editor_viewport_3d(0)
		if viewport:
			viewport.get_tree().create_timer(2.0).timeout.connect(hide_scale_overlay)

static func hide_scale_overlay():
	"""Hide scale overlay"""
	if scale_overlay:
		scale_overlay.visible = false

static func create_scale_overlay():
	"""Create scale feedback overlay"""
	if scale_overlay:
		return
	
	var viewport = EditorInterface.get_editor_viewport_3d(0)
	if not viewport:
		return
	
	# Create overlay container
	scale_overlay = Control.new()
	scale_overlay.name = "ScaleOverlay"
	scale_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Create background panel
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(200, 60)
	panel.position = Vector2(20, 100)  # Position below rotation overlay
	
	# Create label
	scale_label = Label.new()
	scale_label.text = get_display_text()
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scale_label.add_theme_font_size_override("font_size", 14)
	scale_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	panel.add_child(scale_label)
	scale_overlay.add_child(panel)
	
	# Add to viewport
	viewport.add_child(scale_overlay)
	scale_overlay.visible = false

static func cleanup_overlay():
	"""Clean up scale overlay"""
	if scale_overlay and is_instance_valid(scale_overlay):
		scale_overlay.queue_free()
	
	scale_overlay = null
	scale_label = null

static func _is_modifier_pressed(modifier_key: String) -> bool:
	"""Check if a modifier key is currently pressed"""
	match modifier_key.to_upper():
		"SHIFT": return Input.is_key_pressed(KEY_SHIFT)
		"CTRL": return Input.is_key_pressed(KEY_CTRL)
		"ALT": return Input.is_key_pressed(KEY_ALT)
		"META": return Input.is_key_pressed(KEY_META)
		_: return false