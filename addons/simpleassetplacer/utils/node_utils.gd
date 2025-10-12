@tool
extends RefCounted

class_name NodeUtils

"""
NODE VALIDATION AND UTILITY HELPERS
===================================

PURPOSE: Centralized utilities for common node operations and validation patterns.

RESPONSIBILITIES:
- Safe node validation (is_instance_valid checks)
- Safe method calling with validation
- Safe node cleanup with validation
- Common node operation helpers

ARCHITECTURE POSITION: Pure utility class
- No state management
- No dependencies on other managers
- Reusable across entire codebase

USAGE: Replace repeated `if node and is_instance_valid(node)` patterns
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

## Core Validation

static func is_valid(node: Node) -> bool:
	"""
	Check if node is valid and not queued for deletion.
	
	This is the canonical way to check node validity throughout the plugin.
	Replaces: if node and is_instance_valid(node)
	
	Args:
		node: Node to validate
	
	Returns:
		True if node exists and is valid, False otherwise
	"""
	return node != null and is_instance_valid(node)

static func is_valid_and_ready(node: Node) -> bool:
	"""
	Check if node is valid and has completed _ready().
	
	Useful for nodes that need @onready variables to be initialized.
	
	Args:
		node: Node to validate
	
	Returns:
		True if node is valid and ready, False otherwise
	"""
	return is_valid(node) and node.is_node_ready()

static func is_valid_and_in_tree(node: Node) -> bool:
	"""
	Check if node is valid and in scene tree.
	
	Many operations require nodes to be in the tree.
	
	Args:
		node: Node to validate
	
	Returns:
		True if node is valid and in tree, False otherwise
	"""
	return is_valid(node) and node.is_inside_tree()

## Safe Method Calling

static func safe_call(node: Node, method: String, args: Array = []) -> Variant:
	"""
	Safely call method on node with validation.
	
	Validates node before calling method. Returns null if validation fails.
	
	Args:
		node: Node to call method on
		method: Method name to call
		args: Array of arguments to pass
	
	Returns:
		Method return value, or null if validation failed
	
	Example:
		var result = NodeUtils.safe_call(overlay, "show_message", ["Hello"])
	"""
	if not is_valid(node):
		return null
	
	if not node.has_method(method):
		PluginLogger.warning("NodeUtils", "Node %s does not have method %s" % [node.name, method])
		return null
	
	return node.callv(method, args)

static func safe_set(node: Node, property: String, value: Variant) -> bool:
	"""
	Safely set property on node with validation.
	
	Args:
		node: Node to set property on
		property: Property name
		value: Value to set
	
	Returns:
		True if successful, False if validation failed
	
	Example:
		NodeUtils.safe_set(mesh_instance, "visible", false)
	"""
	if not is_valid(node):
		return false
	
	node.set(property, value)
	return true

static func safe_get(node: Node, property: String, default = null) -> Variant:
	"""
	Safely get property from node with validation.
	
	Args:
		node: Node to get property from
		property: Property name
		default: Default value if validation fails
	
	Returns:
		Property value, or default if validation failed
	
	Example:
		var pos = NodeUtils.safe_get(preview_mesh, "global_position", Vector3.ZERO)
	"""
	if not is_valid(node):
		return default
	
	return node.get(property)

## Safe Cleanup

static func safe_free(node: Node) -> void:
	"""
	Safely free node with validation.
	
	Validates node before calling queue_free().
	Replaces: if node and is_instance_valid(node): node.queue_free()
	
	Args:
		node: Node to free
	
	Example:
		NodeUtils.safe_free(preview_mesh)
	"""
	if is_valid(node):
		node.queue_free()

static func safe_remove_from_parent(node: Node) -> void:
	"""
	Safely remove node from parent with validation.
	
	Args:
		node: Node to remove from parent
	
	Example:
		NodeUtils.safe_remove_from_parent(overlay)
	"""
	if is_valid_and_in_tree(node):
		node.get_parent().remove_child(node)

## Node Queries

static func find_child_by_class(parent: Node, type_name: String, recursive: bool = false) -> Node:
	"""
	Find first child of specific class type.
	
	Args:
		parent: Parent node to search in
		type_name: Class name to search for (e.g., "MeshInstance3D")
		recursive: Whether to search recursively
	
	Returns:
		First matching child node, or null if not found
	
	Example:
		var mesh = NodeUtils.find_child_by_class(scene_root, "MeshInstance3D", true)
	"""
	if not is_valid(parent):
		return null
	
	for child in parent.get_children():
		if child.is_class(type_name):
			return child
		
		if recursive:
			var found = find_child_by_class(child, type_name, true)
			if found:
				return found
	
	return null

static func find_children_by_class(parent: Node, type_name: String, recursive: bool = false) -> Array:
	"""
	Find all children of specific class type.
	
	Args:
		parent: Parent node to search in
		type_name: Class name to search for
		recursive: Whether to search recursively
	
	Returns:
		Array of matching child nodes
	
	Example:
		var meshes = NodeUtils.find_children_by_class(scene_root, "MeshInstance3D", true)
	"""
	var results: Array = []
	
	if not is_valid(parent):
		return results
	
	for child in parent.get_children():
		if child.is_class(type_name):
			results.append(child)
		
		if recursive:
			results.append_array(find_children_by_class(child, type_name, true))
	
	return results

## Validation Helpers for Specific Node Types

static func validate_node3d(node: Node) -> bool:
	"""Check if node is valid Node3D"""
	return is_valid(node) and node is Node3D

static func validate_control(node: Node) -> bool:
	"""Check if node is valid Control"""
	return is_valid(node) and node is Control

static func validate_mesh_instance(node: Node) -> bool:
	"""Check if node is valid MeshInstance3D with mesh"""
	if not is_valid(node) or not node is MeshInstance3D:
		return false
	var mesh_inst = node as MeshInstance3D
	return mesh_inst.mesh != null

## Safe Operations with Auto-Cleanup

static func safe_hide(node: Node) -> bool:
	"""
	Safely hide node with validation.
	
	Args:
		node: Node to hide (must be CanvasItem or Node3D)
	
	Returns:
		True if successful, False if validation failed
	"""
	if not is_valid(node):
		return false
	
	if node is CanvasItem or node is Node3D:
		node.hide()
		return true
	
	return false

static func safe_show(node: Node) -> bool:
	"""
	Safely show node with validation.
	
	Args:
		node: Node to show (must be CanvasItem or Node3D)
	
	Returns:
		True if successful, False if validation failed
	"""
	if not is_valid(node):
		return false
	
	if node is CanvasItem or node is Node3D:
		node.show()
		return true
	
	return false

static func safe_set_visible(node: Node, visible: bool) -> bool:
	"""
	Safely set visibility with validation.
	
	Args:
		node: Node to set visibility on
		visible: Visibility state
	
	Returns:
		True if successful, False if validation failed
	"""
	if visible:
		return safe_show(node)
	else:
		return safe_hide(node)

## Cleanup with Null Assignment

static func cleanup_and_null(node_ref: Node) -> Node:
	"""
	Free node and return null for assignment.
	
	This helper enables the pattern:
		node = NodeUtils.cleanup_and_null(node)
	
	Which safely frees the node and assigns null in one line.
	
	Args:
		node_ref: Node to cleanup
	
	Returns:
		Always returns null
	
	Example:
		preview_mesh = NodeUtils.cleanup_and_null(preview_mesh)
	"""
	safe_free(node_ref)
	return null

## Debug Helpers

static func debug_print_node_tree(node: Node, indent: int = 0) -> void:
	"""
	Print node tree structure for debugging.
	
	Args:
		node: Root node to print from
		indent: Current indentation level (internal use)
	"""
	if not is_valid(node):
		PluginLogger.debug("NodeUtils", "  ".repeat(indent) + "<invalid node>")
		return
	
	var prefix = "  ".repeat(indent)
	var valid_status = "✓" if is_valid(node) else "✗"
	var tree_status = "T" if is_valid_and_in_tree(node) else "-"
	
	PluginLogger.debug("NodeUtils", "%s[%s%s] %s (%s)" % [prefix, valid_status, tree_status, node.name, node.get_class()])
	
	for child in node.get_children():
		debug_print_node_tree(child, indent + 1)

static func get_node_info(node: Node) -> Dictionary:
	"""
	Get comprehensive node information for debugging.
	
	Args:
		node: Node to get info for
	
	Returns:
		Dictionary with node information
	"""
	if not is_valid(node):
		return {
			"valid": false,
			"null": node == null
		}
	
	return {
		"valid": true,
		"name": node.name,
		"class": node.get_class(),
		"in_tree": node.is_inside_tree(),
		"ready": node.is_node_ready(),
		"path": str(node.get_path()) if node.is_inside_tree() else "<not in tree>",
		"parent": node.get_parent().name if node.get_parent() else "<no parent>",
		"children": node.get_child_count()
	}
