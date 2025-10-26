@tool
extends RefCounted

class_name UndoRedoHelper

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
UNDO/REDO HELPER
================

PURPOSE: Centralized utility for creating undo/redo actions with Godot's EditorUndoRedoManager

RESPONSIBILITIES:
- Validate nodes and scene state before creating undo actions
- Create placement undo/redo actions (add/remove nodes)
- Create transform undo/redo actions (single and multiple objects)
- Handle errors and edge cases gracefully
- Provide consistent action naming

ARCHITECTURE POSITION: Utility class
- Used by TransformationCoordinator
- Wraps EditorUndoRedoManager API
- Provides validation and error handling

USED BY: TransformationCoordinator
USES: EditorInterface, PluginLogger
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

## VALIDATION

func is_valid_for_undo(node: Node) -> bool:
	"""Check if node is valid for undo operations
	
	Args:
		node: The node to validate
		
	Returns:
		bool: True if node can be used in undo operations
	"""
	if not node:
		return false
	if not is_instance_valid(node):
		return false
	if not node.is_inside_tree():
		return false
	return true

func is_scene_valid() -> bool:
	"""Check if the currently edited scene is valid
	
	Returns:
		bool: True if scene exists and is valid
	"""
	var scene = _services.editor_facade.get_edited_scene_root()
	if not scene:
		return false
	if not is_instance_valid(scene):
		return false
	return true

func validate_undo_manager(undo_redo: EditorUndoRedoManager) -> bool:
	"""Validate that undo manager is available and usable
	
	Args:
		undo_redo: The undo manager to validate
		
	Returns:
		bool: True if undo manager can be used
	"""
	if not undo_redo:
		PluginLogger.warning("UndoRedoHelper", "No undo manager provided")
		return false
	if not is_instance_valid(undo_redo):
		PluginLogger.warning("UndoRedoHelper", "Invalid undo manager")
		return false
	return true

## PLACEMENT UNDO/REDO

func create_placement_undo(
	undo_redo: EditorUndoRedoManager,
	placed_node: Node3D,
	action_name: String = ""
) -> bool:
	"""Create undo/redo action for a placed node
	
	This creates an action that:
	- On UNDO: Removes the node from the scene and frees it
	- On REDO: Re-adds the node to its parent
	
	Args:
		undo_redo: The editor's undo/redo manager
		placed_node: The node that was just placed
		action_name: Optional custom action name (default: "Place [NodeName]")
		
	Returns:
		bool: True if undo action was created successfully
	"""
	# Validate inputs
	if not validate_undo_manager(undo_redo):
		return false
	
	if not is_valid_for_undo(placed_node):
		PluginLogger.warning("UndoRedoHelper", "Invalid node for placement undo")
		return false
	
	var parent = placed_node.get_parent()
	if not parent or not is_instance_valid(parent):
		PluginLogger.warning("UndoRedoHelper", "Node has no valid parent for undo")
		return false
	
	# Generate action name if not provided
	if action_name.is_empty():
		action_name = "Place " + placed_node.name
	
	# Store the scene root
	var scene_root = _services.editor_facade.get_edited_scene_root()
	
	# IMPORTANT: The node is already in the scene. We need to remove it and re-add via undo/redo
	# to make it properly recognized by the editor.
	parent.remove_child(placed_node)
	
	# Create the undo/redo action
	undo_redo.create_action(action_name)
	
	# DO: Add node to parent and set owner
	undo_redo.add_do_method(parent, "add_child", placed_node)
	undo_redo.add_do_property(placed_node, "owner", scene_root)
	undo_redo.add_do_reference(placed_node)
	
	# UNDO: Remove node from scene
	undo_redo.add_undo_method(parent, "remove_child", placed_node)
	undo_redo.add_undo_reference(placed_node)
	
	# Commit the action - this will execute the DO methods, actually adding the node
	undo_redo.commit_action()
	
	PluginLogger.debug("UndoRedoHelper", "Created placement undo: " + action_name)
	return true

## TRANSFORM UNDO/REDO (SINGLE OBJECT)

func create_transform_undo(
	undo_redo: EditorUndoRedoManager,
	target_node: Node3D,
	original_transform: Transform3D,
	new_transform: Transform3D = Transform3D(),
	action_name: String = ""
) -> bool:
	"""Create undo/redo action for a single node's transform
	
	This creates an action that:
	- On UNDO: Restores the original transform
	- On REDO: Applies the new transform
	
	Args:
		undo_redo: The editor's undo/redo manager
		target_node: The node that was transformed
		original_transform: The node's transform before modification
		new_transform: The node's transform after modification (default: current transform)
		action_name: Optional custom action name (default: "Transform [NodeName]")
		
	Returns:
		bool: True if undo action was created successfully
	"""
	# Validate inputs
	if not validate_undo_manager(undo_redo):
		return false
	
	if not is_valid_for_undo(target_node):
		PluginLogger.warning("UndoRedoHelper", "Invalid node for transform undo")
		return false
	
	# Use current transform if new_transform not specified
	if new_transform == Transform3D():
		new_transform = target_node.transform
	
	# Generate action name if not provided
	if action_name.is_empty():
		action_name = "Transform " + target_node.name
	
	# Create the undo/redo action
	undo_redo.create_action(action_name)
	
	# DO: Apply new transform (needed for redo)
	undo_redo.add_do_property(target_node, "transform", new_transform)
	
	# UNDO: Restore original transform
	undo_redo.add_undo_property(target_node, "transform", original_transform)
	
	# Commit the action
	undo_redo.commit_action()
	
	PluginLogger.debug("UndoRedoHelper", "Created transform undo: " + action_name)
	return true

## TRANSFORM UNDO/REDO (MULTIPLE OBJECTS)

func create_multi_transform_undo(
	undo_redo: EditorUndoRedoManager,
	target_nodes: Array,
	original_transforms: Dictionary,
	action_name: String = ""
) -> bool:
	"""Create undo/redo action for multiple nodes' transforms
	
	This creates a single action that affects all nodes atomically:
	- On UNDO: Restores all nodes to their original transforms
	- On REDO: Applies the new transforms to all nodes
	
	Args:
		undo_redo: The editor's undo/redo manager
		target_nodes: Array of Node3D objects that were transformed
		original_transforms: Dictionary mapping node -> original Transform3D
		action_name: Optional custom action name (default: "Transform N objects")
		
	Returns:
		bool: True if undo action was created successfully
	"""
	# Validate inputs
	if not validate_undo_manager(undo_redo):
		return false
	
	if target_nodes.is_empty():
		PluginLogger.warning("UndoRedoHelper", "No nodes provided for multi-transform undo")
		return false
	
	# Validate all nodes and collect valid ones
	var valid_nodes = []
	for node in target_nodes:
		if is_valid_for_undo(node) and original_transforms.has(node):
			valid_nodes.append(node)
		else:
			PluginLogger.warning("UndoRedoHelper", "Skipping invalid node in multi-transform: " + str(node))
	
	if valid_nodes.is_empty():
		PluginLogger.warning("UndoRedoHelper", "No valid nodes for multi-transform undo")
		return false
	
	# Generate action name if not provided
	if action_name.is_empty():
		action_name = "Transform " + str(valid_nodes.size()) + " objects"
	
	# Create the undo/redo action
	undo_redo.create_action(action_name)
	
	# Add do/undo properties for each valid node
	for node in valid_nodes:
		var original = original_transforms[node]
		var new_transform = node.transform
		
		# DO: Apply new transform
		undo_redo.add_do_property(node, "transform", new_transform)
		
		# UNDO: Restore original transform
		undo_redo.add_undo_property(node, "transform", original)
	
	# Commit the action
	undo_redo.commit_action()
	
	PluginLogger.debug("UndoRedoHelper", "Created multi-transform undo: " + action_name + " (" + str(valid_nodes.size()) + " nodes)")
	return true

## ERROR HANDLING

func handle_undo_error(context: String, error_message: String) -> void:
	"""Log and handle undo/redo errors
	
	Args:
		context: Context where error occurred (e.g., "placement", "transform")
		error_message: Description of the error
	"""
	PluginLogger.error("UndoRedo [" + context + "]", error_message)

## UTILITY FUNCTIONS

func get_action_description(
	action_type: String,
	node_name: String = "",
	node_count: int = 1
) -> String:
	"""Generate a descriptive action name for the History panel
	
	Args:
		action_type: Type of action ("Place", "Transform", etc.)
		node_name: Name of the node (for single node actions)
		node_count: Number of nodes (for multi-node actions)
		
	Returns:
		String: Formatted action description
	"""
	if node_count > 1:
		return action_type + " " + str(node_count) + " objects"
	elif not node_name.is_empty():
		return action_type + " " + node_name
	else:
		return action_type

func should_create_undo(confirm_changes: bool) -> bool:
	"""Determine if an undo entry should be created based on confirmation
	
	Args:
		confirm_changes: Whether changes are being confirmed (vs. canceled)
		
	Returns:
		bool: True if undo entry should be created
	"""
	# Only create undo entries when confirming changes
	# If canceling (ESC key), don't create undo because changes are reverted immediately
	return confirm_changes

