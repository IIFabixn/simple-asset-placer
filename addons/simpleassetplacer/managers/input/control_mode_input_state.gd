@tool
extends RefCounted

class_name ControlModeInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

# Modal system removed - only axis constraints remain
var axis_x_pressed: bool
var axis_y_pressed: bool
var axis_z_pressed: bool

func _init(snapshot: RawInputSnapshot) -> void:
	axis_x_pressed = snapshot.is_key_just_pressed("axis_x")
	axis_y_pressed = snapshot.is_key_just_pressed("axis_y")
	axis_z_pressed = snapshot.is_key_just_pressed("axis_z")

func to_dictionary() -> Dictionary:
	return {
		"axis_x_pressed": axis_x_pressed,
		"axis_y_pressed": axis_y_pressed,
		"axis_z_pressed": axis_z_pressed
	}
