@tool
extends RefCounted

class_name ControlModeInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var position_control_pressed: bool
var rotation_control_pressed: bool
var scale_control_pressed: bool
var axis_x_pressed: bool
var axis_y_pressed: bool
var axis_z_pressed: bool

func _init(snapshot: RawInputSnapshot) -> void:
	position_control_pressed = snapshot.is_key_just_pressed("position_control")
	rotation_control_pressed = snapshot.is_key_just_pressed("rotation_control")
	scale_control_pressed = snapshot.is_key_just_pressed("scale_control")
	axis_x_pressed = snapshot.is_key_just_pressed("axis_x")
	axis_y_pressed = snapshot.is_key_just_pressed("axis_y")
	axis_z_pressed = snapshot.is_key_just_pressed("axis_z")

func to_dictionary() -> Dictionary:
	return {
		"position_control_pressed": position_control_pressed,
		"rotation_control_pressed": rotation_control_pressed,
		"scale_control_pressed": scale_control_pressed,
		"axis_x_pressed": axis_x_pressed,
		"axis_y_pressed": axis_y_pressed,
		"axis_z_pressed": axis_z_pressed
	}
