@tool
extends RefCounted

class_name PlacementSessionData

var mesh: Mesh = null
var meshlib = null
var item_id: int = -1
var asset_path: String = ""
var packed_scene: PackedScene = null
var settings: Dictionary = {}
var dock_reference = null
var undo_redo = null
var target_parent: Node = null
var confirm_exit_requested: bool = false


func reset() -> void:
	mesh = null
	meshlib = null
	item_id = -1
	asset_path = ""
	packed_scene = null
	settings = {}
	dock_reference = null
	undo_redo = null
	target_parent = null
	confirm_exit_requested = false


func configure_for_asset(
	mesh_resource: Mesh,
	mesh_library,
	library_item_id: int,
	resource_path: String,
	config: Dictionary,
	dock_ref,
	undo_redo_instance,
	target_parent_node
) -> void:
	reset()
	mesh = mesh_resource
	meshlib = mesh_library
	item_id = library_item_id
	asset_path = resource_path
	settings = config.duplicate(true)
	dock_reference = dock_ref
	undo_redo = undo_redo_instance
	target_parent = target_parent_node


func configure_for_packed_scene(
	packed_scene_resource: PackedScene,
	config: Dictionary,
	dock_ref,
	undo_redo_instance,
	target_parent_node
) -> void:
	reset()
	packed_scene = packed_scene_resource
	settings = config.duplicate(true)
	dock_reference = dock_ref
	undo_redo = undo_redo_instance
	target_parent = target_parent_node


func has_mesh_resource() -> bool:
	return mesh != null


func has_packed_scene() -> bool:
	return packed_scene != null


func has_asset_path() -> bool:
	return asset_path != ""


func is_meshlib_item() -> bool:
	return meshlib != null and item_id >= 0


func has_valid_parent() -> bool:
	return target_parent != null and is_instance_valid(target_parent)


func get_settings() -> Dictionary:
	return settings


func request_confirm_exit() -> void:
	confirm_exit_requested = true


func consume_confirm_exit() -> bool:
	var requested = confirm_exit_requested
	confirm_exit_requested = false
	return requested


func is_configured() -> bool:
	return has_mesh_resource() or has_packed_scene() or has_asset_path()
