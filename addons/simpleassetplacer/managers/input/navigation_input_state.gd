@tool
extends RefCounted

class_name NavigationInputState

const RawInputSnapshot = preload("res://addons/simpleassetplacer/managers/input/raw_input_snapshot.gd")

var tab_just_pressed: bool
var cancel_pressed: bool
var cycle_next_asset: bool
var cycle_previous_asset: bool

func _init(snapshot: RawInputSnapshot) -> void:
	tab_just_pressed = snapshot.is_key_just_pressed("tab")
	cancel_pressed = snapshot.is_key_just_pressed("cancel")
	cycle_next_asset = snapshot.is_key_just_pressed("cycle_next_asset") or snapshot.is_key_held_with_repeat("cycle_next_asset")
	cycle_previous_asset = snapshot.is_key_just_pressed("cycle_previous_asset") or snapshot.is_key_held_with_repeat("cycle_previous_asset")

func to_dictionary() -> Dictionary:
	return {
		"tab_just_pressed": tab_just_pressed,
		"cancel_pressed": cancel_pressed,
		"cycle_next_asset": cycle_next_asset,
		"cycle_previous_asset": cycle_previous_asset
	}
