@tool
extends RefCounted

class_name NumericInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var digit_pressed: int = -1
var decimal_pressed: bool
var minus_pressed: bool
var plus_pressed: bool
var equals_pressed: bool
var backspace_pressed: bool
var enter_pressed: bool
var escape_pressed: bool

func _init(snapshot: RawInputSnapshot) -> void:
	for i in range(10):
		if snapshot.digit_just_pressed(i):
			digit_pressed = i
			break
	decimal_pressed = snapshot.decimal_just_pressed()
	minus_pressed = snapshot.minus_just_pressed()
	plus_pressed = snapshot.plus_just_pressed()
	equals_pressed = snapshot.equals_just_pressed()
	backspace_pressed = snapshot.backspace_just_pressed()
	enter_pressed = snapshot.enter_just_pressed()
	escape_pressed = snapshot.escape_just_pressed()

func has_input() -> bool:
	return digit_pressed >= 0 or decimal_pressed or minus_pressed or plus_pressed or equals_pressed or backspace_pressed or enter_pressed or escape_pressed

func to_dictionary() -> Dictionary:
	return {
		"digit_pressed": digit_pressed,
		"decimal_pressed": decimal_pressed,
		"minus_pressed": minus_pressed,
		"plus_pressed": plus_pressed,
		"equals_pressed": equals_pressed,
		"backspace_pressed": backspace_pressed,
		"enter_pressed": enter_pressed,
		"escape_pressed": escape_pressed
	}
