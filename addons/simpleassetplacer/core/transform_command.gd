@tool
extends RefCounted

class_name TransformCommand

"""
TRANSFORM COMMAND DATA OBJECT
=============================

PURPOSE: Represents a single frame of transform intent collected from all input sources.

RESPONSIBILITIES:
- Store deltas for position, rotation, and scale adjustments
- Capture confirm/cancel intent and snap overrides
- Record contributing input sources for debugging and overlays
- Provide helpers to build commands from specific input paths
- Merge multiple partial commands while enforcing source precedence

SOURCE PRECEDENCE:
- Mouse pointer inputs (mouse-driven positioning) have highest priority
- Numeric overrides take precedence over direct inputs
- Direct inputs (keys, wheel, gamepad) are baseline contributions

USED BY: TransformActionRouter, TransformationCoordinator
"""

# === INPUT SOURCE FLAGS ===

const SOURCE_MOUSE_POINTER := "mouse_pointer"  # Renamed from SOURCE_MOUSE_MODAL (modal system removed)
const SOURCE_NUMERIC := "numeric"
const SOURCE_KEY_DIRECT := "key_direct"
const SOURCE_WHEEL := "wheel"
const SOURCE_GAMEPAD := "gamepad"

const _SOURCE_PRIORITY := {
	SOURCE_MOUSE_POINTER: 300,
	SOURCE_NUMERIC: 200,
	SOURCE_KEY_DIRECT: 100,
	SOURCE_WHEEL: 100,
	SOURCE_GAMEPAD: 100
}

const _PRIORITY_NONE := -1
const _AXES := ["X", "Y", "Z"]

# === PUBLIC DATA ===

var position_delta: Vector3 = Vector3.ZERO
var rotation_delta: Vector3 = Vector3.ZERO
var scale_delta: Vector3 = Vector3.ZERO
var snap_override: Dictionary = {}
var confirm: bool = false
var cancel: bool = false
var source_flags: Dictionary = {}
var axis_constraints: Dictionary = {
	"X": false,
	"Y": false,
	"Z": false
}
var metadata: Dictionary = {}

# Track priority ownership per field so merges can respect precedence
var _position_priority: int = _PRIORITY_NONE
var _rotation_priority: int = _PRIORITY_NONE
var _scale_priority: int = _PRIORITY_NONE
var _snap_priority: int = _PRIORITY_NONE
var _axis_priority: int = _PRIORITY_NONE

## FACTORY HELPERS

static func from_mouse_pointer(data: Dictionary) -> TransformCommand:
	"""Build a command from mouse pointer input (highest priority)."""
	var command := TransformCommand.new()
	command._apply_dictionary(data, SOURCE_MOUSE_POINTER)
	return command

## MUTATORS

func clear() -> void:
	"""Reset the command to an empty state."""
	position_delta = Vector3.ZERO
	rotation_delta = Vector3.ZERO
	scale_delta = Vector3.ZERO
	snap_override = {}
	confirm = false
	cancel = false
	source_flags.clear()
	axis_constraints = {
		"X": false,
		"Y": false,
		"Z": false
	}
	metadata.clear()
	_position_priority = _PRIORITY_NONE
	_rotation_priority = _PRIORITY_NONE
	_scale_priority = _PRIORITY_NONE
	_snap_priority = _PRIORITY_NONE
	_axis_priority = _PRIORITY_NONE

func set_position_delta(delta: Vector3, source_flag: String) -> void:
	_apply_vector_component("position_delta", delta, source_flag)

func set_rotation_delta(delta: Vector3, source_flag: String) -> void:
	_apply_vector_component("rotation_delta", delta, source_flag)

func set_scale_delta(delta: Vector3, source_flag: String) -> void:
	_apply_vector_component("scale_delta", delta, source_flag)

func set_snap_override(override: Dictionary, source_flag: String) -> void:
	if override == null:
		return
	var priority := _priority_for_source(source_flag)
	if priority >= _snap_priority:
		snap_override = override.duplicate(true)
		_snap_priority = priority
	_register_source(source_flag)

func set_axis_constraints_from_dict(constraints: Dictionary, source_flag: String) -> void:
	if constraints == null:
		return
	var sanitized := _sanitize_axis_constraints(constraints)
	var priority := _priority_for_source(source_flag)
	if priority >= _axis_priority:
		axis_constraints = sanitized
		_axis_priority = priority
	_register_source(source_flag)

func merge_metadata(additional_metadata: Dictionary) -> void:
	if additional_metadata == null:
		return
	for key in additional_metadata.keys():
		var value = additional_metadata[key]
		metadata[key] = _duplicate_if_needed(value)

func set_confirm(value: bool) -> void:
	confirm = value and not cancel

func set_cancel(value: bool) -> void:
	if value:
		cancel = true
		confirm = false

func merge(other: TransformCommand) -> void:
	"""Merge another command into this one respecting source precedence."""
	if other == null:
		return

	_merge_vector_component("position_delta", other.position_delta, other._position_priority)
	_merge_vector_component("rotation_delta", other.rotation_delta, other._rotation_priority)
	_merge_vector_component("scale_delta", other.scale_delta, other._scale_priority)
	_merge_snap_override(other)
	_merge_axis_constraints(other)
	_merge_confirm_cancel(other)
	_merge_metadata(other)
	_merge_source_flags(other)

## QUERY HELPERS

func has_any_delta() -> bool:
	return position_delta != Vector3.ZERO or rotation_delta != Vector3.ZERO or scale_delta != Vector3.ZERO

func get_priority_for_axis() -> int:
	return _axis_priority

## INTERNAL HELPERS

func _apply_dictionary(data: Dictionary, source_flag: String) -> void:
	if data == null:
		return
	if data.has("position_delta"):
		set_position_delta(data.get("position_delta", Vector3.ZERO), source_flag)
	if data.has("rotation_delta"):
		set_rotation_delta(data.get("rotation_delta", Vector3.ZERO), source_flag)
	if data.has("scale_delta"):
		set_scale_delta(data.get("scale_delta", Vector3.ZERO), source_flag)
	if data.has("snap_override"):
		set_snap_override(data.get("snap_override", {}), source_flag)
	if data.has("axis_constraints"):
		set_axis_constraints_from_dict(data.get("axis_constraints", {}), source_flag)
	if data.has("confirm") and data["confirm"]:
		set_confirm(true)
	if data.has("cancel") and data["cancel"]:
		set_cancel(true)
	if data.has("metadata"):
		merge_metadata(data.get("metadata", {}))
	_register_source(source_flag)

func _apply_vector_component(property_name: String, delta: Vector3, source_flag: String) -> void:
	if delta == null:
		return
	var priority := _priority_for_source(source_flag)
	var priority_property := _priority_property_for(property_name)
	var current_priority := get(priority_property)
	if priority >= current_priority:
		set(property_name, delta)
		set(priority_property, priority)
	_register_source(source_flag)

func _merge_vector_component(property_name: String, incoming: Vector3, incoming_priority: int) -> void:
	if incoming_priority == _PRIORITY_NONE:
		return
	var priority_property := _priority_property_for(property_name)
	var current_priority := get(priority_property)
	if incoming_priority >= current_priority:
		set(property_name, incoming)
		set(priority_property, incoming_priority)

func _merge_snap_override(other: TransformCommand) -> void:
	if other.snap_override.is_empty():
		return
	if other._snap_priority >= _snap_priority:
		snap_override = other.snap_override.duplicate(true)
		_snap_priority = other._snap_priority

func _merge_axis_constraints(other: TransformCommand) -> void:
	if other._axis_priority == _PRIORITY_NONE:
		return
	if other._axis_priority >= _axis_priority:
		axis_constraints = other.axis_constraints.duplicate(true)
		_axis_priority = other._axis_priority

func _merge_confirm_cancel(other: TransformCommand) -> void:
	if other.cancel:
		cancel = true
		confirm = false
	elif other.confirm and not cancel:
		confirm = true

func _merge_metadata(other: TransformCommand) -> void:
	if other.metadata.is_empty():
		return
	for key in other.metadata.keys():
		metadata[key] = _duplicate_if_needed(other.metadata[key])

func _merge_source_flags(other: TransformCommand) -> void:
	for key in other.source_flags.keys():
		if other.source_flags[key]:
			source_flags[key] = true

func _priority_for_source(source_flag: String) -> int:
	if source_flag == null or source_flag.is_empty():
		return _SOURCE_PRIORITY[SOURCE_KEY_DIRECT]
	return _SOURCE_PRIORITY.get(source_flag, _SOURCE_PRIORITY[SOURCE_KEY_DIRECT])

func _register_source(source_flag: String) -> void:
	var flag := source_flag if source_flag != null and not source_flag.is_empty() else SOURCE_KEY_DIRECT
	source_flags[flag] = true

func _priority_property_for(property_name: String) -> String:
	match property_name:
		"position_delta":
			return "_position_priority"
		"rotation_delta":
			return "_rotation_priority"
		"scale_delta":
			return "_scale_priority"
		_:
			return "_position_priority"

func _sanitize_axis_constraints(input_constraints: Dictionary) -> Dictionary:
	var sanitized := {}
	for axis in _AXES:
		sanitized[axis] = bool(input_constraints.get(axis, false))
	return sanitized

func _duplicate_if_needed(value):
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	if typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	return value
