@tool
extends RefCounted

class_name TransformSessionData

var target_nodes: Array = []
var original_transforms: Dictionary = {}
var original_rotations: Dictionary = {}
var node_offsets: Dictionary = {}
var center_position: Vector3 = Vector3.ZERO
var original_center_position: Vector3 = Vector3.ZERO
var settings: Dictionary = {}
var dock_reference = null
var undo_redo = null
var confirm_exit_requested: bool = false


func reset() -> void:
	target_nodes = []
	original_transforms = {}
	original_rotations = {}
	node_offsets = {}
	center_position = Vector3.ZERO
	original_center_position = Vector3.ZERO
	settings = {}
	dock_reference = null
	undo_redo = null
	confirm_exit_requested = false


func configure(
	nodes: Array,
	node_transform_map: Dictionary,
	node_rotation_map: Dictionary,
	node_offset_map: Dictionary,
	snapped_center: Vector3,
	original_center: Vector3,
	config: Dictionary,
	dock_ref,
	undo_redo_instance
) -> void:
	reset()
	target_nodes = nodes
	original_transforms = node_transform_map
	original_rotations = node_rotation_map
	node_offsets = node_offset_map
	center_position = snapped_center
	original_center_position = original_center
	settings = config.duplicate(true)
	dock_reference = dock_ref
	undo_redo = undo_redo_instance


func has_targets() -> bool:
	return not target_nodes.is_empty()


func request_confirm_exit() -> void:
	confirm_exit_requested = true


func consume_confirm_exit() -> bool:
	var requested = confirm_exit_requested
	confirm_exit_requested = false
	return requested


func get_settings() -> Dictionary:
	return settings


func get_center_position() -> Vector3:
	return center_position


func set_center_position(new_center: Vector3) -> void:
	center_position = new_center


func get_original_center_position() -> Vector3:
	return original_center_position


func set_original_center_position(new_center: Vector3) -> void:
	original_center_position = new_center


func get_node_offset(node) -> Vector3:
	return node_offsets.get(node, Vector3.ZERO)


func set_node_offset(node, offset: Vector3) -> void:
	node_offsets[node] = offset
