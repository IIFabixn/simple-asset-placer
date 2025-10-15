@tool
extends RefCounted

class_name NavigationInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var tab_just_pressed: bool
var cancel_pressed: bool

func _init(snapshot: RawInputSnapshot) -> void:
	tab_just_pressed = snapshot.is_key_just_pressed("tab")
	cancel_pressed = snapshot.is_key_just_pressed("cancel")

func to_dictionary() -> Dictionary:
	return {
		"tab_just_pressed": tab_just_pressed,
		"cancel_pressed": cancel_pressed
	}
