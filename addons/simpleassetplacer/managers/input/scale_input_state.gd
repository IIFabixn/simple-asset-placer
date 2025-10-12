@tool
extends RefCounted

class_name ScaleInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var up_pressed: bool
var down_pressed: bool
var reset_pressed: bool
var reverse_modifier_held: bool
var large_increment_modifier_held: bool
var fine_increment_modifier_held: bool
var up_tapped: bool
var down_tapped: bool

func _init(snapshot: RawInputSnapshot) -> void:
	var right_mouse_held: bool = snapshot.is_mouse_button_pressed("right")
	up_pressed = (snapshot.is_key_just_pressed("scale_up") or snapshot.is_action_key_held_with_repeat("scale_up", "scale")) and not right_mouse_held
	down_pressed = (snapshot.is_key_just_pressed("scale_down") or snapshot.is_action_key_held_with_repeat("scale_down", "scale")) and not right_mouse_held
	reset_pressed = snapshot.is_key_just_pressed("reset_scale") and not right_mouse_held
	reverse_modifier_held = snapshot.is_reverse_modifier_held()
	large_increment_modifier_held = snapshot.is_large_increment_modifier_held()
	fine_increment_modifier_held = snapshot.is_fine_increment_modifier_held()
	up_tapped = snapshot.key_edge_pressed("scale_up") and not right_mouse_held
	down_tapped = snapshot.key_edge_pressed("scale_down") and not right_mouse_held

func to_dictionary() -> Dictionary:
	return {
		"up_pressed": up_pressed,
		"down_pressed": down_pressed,
		"reset_pressed": reset_pressed,
		"reverse_modifier_held": reverse_modifier_held,
		"large_increment_modifier_held": large_increment_modifier_held,
		"fine_increment_modifier_held": fine_increment_modifier_held,
		"up_tapped": up_tapped,
		"down_tapped": down_tapped
	}
