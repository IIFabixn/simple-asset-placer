@tool
extends RefCounted

class_name PositionInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var height_up_pressed: bool
var height_down_pressed: bool
var reset_height_pressed: bool
var position_left_pressed: bool
var position_right_pressed: bool
var position_forward_pressed: bool
var position_backward_pressed: bool
var reset_position_pressed: bool
var mouse_position: Vector2
var confirm_action: bool
var reverse_modifier_held: bool
var large_increment_modifier_held: bool
var fine_increment_modifier_held: bool
var height_up_tapped: bool
var height_down_tapped: bool
var position_forward_tapped: bool
var position_backward_tapped: bool
var position_left_tapped: bool
var position_right_tapped: bool

func _init(snapshot: RawInputSnapshot) -> void:
	var right_mouse_held: bool = snapshot.is_mouse_button_pressed("right")
	var height_up_just_pressed: bool = snapshot.is_key_just_pressed("height_up")
	var height_down_just_pressed: bool = snapshot.is_key_just_pressed("height_down")
	var pos_forward_just_pressed: bool = snapshot.is_key_just_pressed("position_forward")
	var pos_backward_just_pressed: bool = snapshot.is_key_just_pressed("position_backward")
	var pos_left_just_pressed: bool = snapshot.is_key_just_pressed("position_left")
	var pos_right_just_pressed: bool = snapshot.is_key_just_pressed("position_right")
	height_up_pressed = (height_up_just_pressed or snapshot.is_action_key_held_with_repeat("height_up", "height")) and not right_mouse_held
	height_down_pressed = (height_down_just_pressed or snapshot.is_action_key_held_with_repeat("height_down", "height")) and not right_mouse_held
	reset_height_pressed = snapshot.is_key_just_pressed("reset_height") and not right_mouse_held
	position_left_pressed = (pos_left_just_pressed or snapshot.is_action_key_held_with_repeat("position_left", "position")) and not right_mouse_held
	position_right_pressed = (pos_right_just_pressed or snapshot.is_action_key_held_with_repeat("position_right", "position")) and not right_mouse_held
	position_forward_pressed = (pos_forward_just_pressed or snapshot.is_action_key_held_with_repeat("position_forward", "position")) and not right_mouse_held
	position_backward_pressed = (pos_backward_just_pressed or snapshot.is_action_key_held_with_repeat("position_backward", "position")) and not right_mouse_held
	reset_position_pressed = snapshot.is_key_just_pressed("reset_position") and not right_mouse_held
	mouse_position = snapshot.mouse_position()
	confirm_action = (snapshot.is_mouse_button_just_pressed("left") and snapshot.is_mouse_in_viewport()) or snapshot.is_key_just_pressed("confirm")
	reverse_modifier_held = snapshot.is_reverse_modifier_held()
	large_increment_modifier_held = snapshot.is_large_increment_modifier_held()
	fine_increment_modifier_held = snapshot.is_fine_increment_modifier_held()
	height_up_tapped = height_up_just_pressed and not right_mouse_held
	height_down_tapped = height_down_just_pressed and not right_mouse_held
	position_forward_tapped = pos_forward_just_pressed and not right_mouse_held
	position_backward_tapped = pos_backward_just_pressed and not right_mouse_held
	position_left_tapped = pos_left_just_pressed and not right_mouse_held
	position_right_tapped = pos_right_just_pressed and not right_mouse_held

func to_dictionary() -> Dictionary:
	return {
		"height_up_pressed": height_up_pressed,
		"height_down_pressed": height_down_pressed,
		"reset_height_pressed": reset_height_pressed,
		"position_left_pressed": position_left_pressed,
		"position_right_pressed": position_right_pressed,
		"position_forward_pressed": position_forward_pressed,
		"position_backward_pressed": position_backward_pressed,
		"reset_position_pressed": reset_position_pressed,
		"mouse_position": mouse_position,
		"confirm_action": confirm_action,
		"reverse_modifier_held": reverse_modifier_held,
		"large_increment_modifier_held": large_increment_modifier_held,
		"fine_increment_modifier_held": fine_increment_modifier_held,
		"height_up_tapped": height_up_tapped,
		"height_down_tapped": height_down_tapped,
		"position_forward_tapped": position_forward_tapped,
		"position_backward_tapped": position_backward_tapped,
		"position_left_tapped": position_left_tapped,
		"position_right_tapped": position_right_tapped
	}
