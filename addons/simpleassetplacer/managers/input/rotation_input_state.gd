@tool
extends RefCounted

class_name RotationInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var x_pressed: bool
var y_pressed: bool
var z_pressed: bool
var reset_pressed: bool
var reverse_modifier_held: bool
var large_increment_modifier_held: bool
var fine_increment_modifier_held: bool
var x_tapped: bool
var y_tapped: bool
var z_tapped: bool

func _init(snapshot: RawInputSnapshot) -> void:
	var right_mouse_held: bool = snapshot.is_mouse_button_pressed("right")
	x_pressed = (snapshot.is_key_just_pressed("rotate_x") or snapshot.is_action_key_held_with_repeat("rotate_x", "rotation")) and not right_mouse_held
	y_pressed = (snapshot.is_key_just_pressed("rotate_y") or snapshot.is_action_key_held_with_repeat("rotate_y", "rotation")) and not right_mouse_held
	z_pressed = (snapshot.is_key_just_pressed("rotate_z") or snapshot.is_action_key_held_with_repeat("rotate_z", "rotation")) and not right_mouse_held
	reset_pressed = snapshot.is_key_just_pressed("reset_rotation") and not right_mouse_held
	reverse_modifier_held = snapshot.is_reverse_modifier_held()
	large_increment_modifier_held = snapshot.is_large_increment_modifier_held()
	fine_increment_modifier_held = snapshot.is_fine_increment_modifier_held()
	x_tapped = snapshot.key_edge_pressed("rotate_x") and not right_mouse_held
	y_tapped = snapshot.key_edge_pressed("rotate_y") and not right_mouse_held
	z_tapped = snapshot.key_edge_pressed("rotate_z") and not right_mouse_held

func to_dictionary() -> Dictionary:
	return {
		"x_pressed": x_pressed,
		"y_pressed": y_pressed,
		"z_pressed": z_pressed,
		"reset_pressed": reset_pressed,
		"reverse_modifier_held": reverse_modifier_held,
		"large_increment_modifier_held": large_increment_modifier_held,
		"fine_increment_modifier_held": fine_increment_modifier_held,
		"x_tapped": x_tapped,
		"y_tapped": y_tapped,
		"z_tapped": z_tapped
	}
