@tool
extends RefCounted

class_name PickupHandler

"""
PICKUP HANDLER
==============

PURPOSE: Extract node data and convert existing scene nodes into placement assets

RESPONSIBILITIES:
- Extract mesh/scene data from selected Node3D objects
- Handle single and multi-node selection (create temporary container)
- Preserve transform properties (scale, rotation)
- Detect scene file paths for instanced scenes
- Create PackedScene from nodes when needed

ARCHITECTURE POSITION: Utility for pickup feature
- Used by context menu and keyboard shortcut handlers
- Prepares data for placement mode controller

USED BY: simpleassetplacer.gd, scene_tree_context_menu.gd
"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

## Public API


static func can_pickup_nodes(nodes: Array) -> bool:
	"""Check if the given nodes can be picked up for placement
	
	Args:
		nodes: Array of Node objects to check
		
	Returns:
		bool: True if at least one node is a valid Node3D
	"""
	if nodes.is_empty():
		return false

	for node in nodes:
		if node is Node3D:
			return true

	return false


static func extract_pickup_data(nodes: Array) -> Dictionary:
	"""Extract placement data from selected nodes
	
	Args:
		nodes: Array of Node3D objects to pickup
		
	Returns:
		Dictionary with keys:
			- success: bool (whether extraction succeeded)
			- asset_path: String (path to scene file or empty for PackedScene)
			- packed_scene: PackedScene (created from nodes if no scene file)
			- initial_scale: Vector3 (preserved from original node)
			- initial_rotation: Vector3 (preserved from original node in degrees)
			- node_count: int (number of nodes picked up)
			- error_message: String (if success is false)
	"""
	if nodes.is_empty():
		return _error_result("No nodes provided for pickup")

	# Filter to only Node3D objects
	var node3d_nodes: Array = []
	for node in nodes:
		if node is Node3D:
			node3d_nodes.append(node)

	if node3d_nodes.is_empty():
		return _error_result("No Node3D objects selected")

	# Handle single vs multi-node selection
	if node3d_nodes.size() == 1:
		return _extract_single_node(node3d_nodes[0])
	else:
		return _extract_multiple_nodes(node3d_nodes)


## Private Helpers - Single Node


static func _extract_single_node(node: Node3D) -> Dictionary:
	"""Extract data from a single Node3D
	
	Args:
		node: Single Node3D to extract
		
	Returns:
		Dictionary with pickup data
	"""
	# Check if node is an instanced scene
	var scene_file_path = node.scene_file_path

	# Preserve transform
	var initial_scale = node.scale
	var initial_rotation = node.rotation_degrees

	if scene_file_path and scene_file_path != "":
		# Node is an instanced scene - use the original scene file
		PluginLogger.info(
			PluginConstants.COMPONENT_MAIN, "Picking up instanced scene: " + scene_file_path
		)

		return {
			"success": true,
			"asset_path": scene_file_path,
			"packed_scene": null,
			"initial_scale": initial_scale,
			"initial_rotation": initial_rotation,
			"node_count": 1,
			"error_message": ""
		}
	else:
		# Node is not an instanced scene - create PackedScene from it
		var packed_scene = _create_packed_scene_from_node(node)

		if not packed_scene:
			return _error_result("Failed to create PackedScene from node: " + node.name)

		PluginLogger.info(
			PluginConstants.COMPONENT_MAIN, "Picking up node as PackedScene: " + node.name
		)

		return {
			"success": true,
			"asset_path": "",  # Empty path means use packed_scene
			"packed_scene": packed_scene,
			"initial_scale": initial_scale,
			"initial_rotation": initial_rotation,
			"node_count": 1,
			"error_message": ""
		}


## Private Helpers - Multiple Nodes


static func _extract_multiple_nodes(nodes: Array) -> Dictionary:
	"""Extract data from multiple Node3D objects
	
	Creates a temporary container node with all selected nodes as children
	
	Args:
		nodes: Array of Node3D objects
		
	Returns:
		Dictionary with pickup data
	"""
	# Create a temporary container
	var container = Node3D.new()
	container.name = "PickedUpNodes"

	# Track overall bounds for calculating center
	var has_scale = false
	var avg_scale = Vector3.ONE
	var scale_count = 0

	# Calculate center point of all selected nodes (for better pivot)
	var center_position = Vector3.ZERO
	var valid_node_count = 0
	for node in nodes:
		if node is Node3D and is_instance_valid(node) and node.get_parent() != null:
			center_position += node.global_position
			valid_node_count += 1

	if valid_node_count > 0:
		center_position /= float(valid_node_count)

	# Duplicate each node and add to container
	for node in nodes:
		if not node is Node3D:
			continue

		# Skip nodes that might be editor-only or cause issues
		if not is_instance_valid(node) or node.get_parent() == null:
			PluginLogger.warning(
				PluginConstants.COMPONENT_MAIN, "Skipping invalid or unparented node"
			)
			continue

		# Use DUPLICATE_USE_INSTANTIATION without scripts to avoid any initialization issues
		var duplicated = node.duplicate(Node.DUPLICATE_USE_INSTANTIATION)

		# Preserve the relative transform
		if duplicated and is_instance_valid(duplicated):
			# Clean up any UI elements that might have been duplicated
			_remove_ui_children(duplicated)

			# Ensure unique name to avoid conflicts when packing
			# This prevents Godot from showing naming conflict dialogs
			duplicated.name = _generate_unique_name(duplicated.name, container)

			# CRITICAL: Rename ALL children recursively to prevent naming conflicts
			# This ensures even deeply nested children don't conflict with the scene
			_rename_all_children_recursive(duplicated, "_pickup")

			# Safely add to container
			if is_instance_valid(container):
				container.add_child(duplicated)
				duplicated.owner = container

				# Position relative to center point for better pivot
				# This makes the container's origin at the center of the selection
				duplicated.position = node.global_position - center_position
				duplicated.rotation = node.global_rotation
				duplicated.scale = node.scale

				# Recursively set owner for all children to ensure PackedScene works correctly
				_set_owner_recursive(duplicated, container)
			else:
				PluginLogger.error(
					PluginConstants.COMPONENT_MAIN,
					"Container became invalid during node duplication"
				)
				duplicated.queue_free()
				return _error_result("Container became invalid during processing")

			# Track scale (we'll average them)
			if node.scale != Vector3.ONE:
				has_scale = true
				avg_scale += node.scale
				scale_count += 1

	# Calculate average scale if any nodes were scaled
	var initial_scale = Vector3.ONE
	if has_scale and scale_count > 0:
		initial_scale = avg_scale / float(scale_count + 1)  # +1 because we started with Vector3.ONE

	# Verify container has children
	if container.get_child_count() == 0:
		container.queue_free()
		return _error_result("No valid nodes were duplicated")

	# Create PackedScene from container
	var packed_scene = PackedScene.new()

	# Pack with error handling
	# Note: This might trigger editor dialogs if there are issues with the scene
	var result = packed_scene.pack(container)

	# Clean up temporary container
	container.queue_free()

	if result != OK:
		var error_msg = "Failed to pack nodes into scene (error code: %d)" % result
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, error_msg)
		return _error_result(error_msg)

	PluginLogger.info(
		PluginConstants.COMPONENT_MAIN, "Picking up %d nodes as temporary container" % nodes.size()
	)

	return {
		"success": true,
		"asset_path": "",  # Empty path means use packed_scene
		"packed_scene": packed_scene,
		"initial_scale": initial_scale,
		"initial_rotation": Vector3.ZERO,  # Container has no rotation
		"node_count": nodes.size(),
		"error_message": ""
	}


## Private Helpers - PackedScene Creation


static func _create_packed_scene_from_node(node: Node3D) -> PackedScene:
	"""Create a PackedScene from a single node
	
	Args:
		node: Node3D to convert to PackedScene
		
	Returns:
		PackedScene or null if failed
	"""
	# Duplicate the node to avoid modifying the original (without scripts to avoid issues)
	var duplicated = node.duplicate(Node.DUPLICATE_USE_INSTANTIATION)

	if not duplicated:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "Failed to duplicate node: " + node.name)
		return null

	# Clean up any UI elements that might cause issues
	_remove_ui_children(duplicated)

	# Reset transform for the packed scene (we'll apply it during placement)
	duplicated.transform = Transform3D.IDENTITY

	# Create PackedScene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(duplicated)

	# Clean up duplicated node
	duplicated.queue_free()

	if result != OK:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN, "Failed to pack node into scene: " + node.name
		)
		return null

	return packed_scene


## Private Helpers - Owner Management


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	"""Recursively set owner for a node and all its children
	
	This ensures PackedScene can properly pack all nodes in the hierarchy
	
	Args:
		node: Node to set owner for
		owner: The owner node to assign
	"""
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


static func _generate_unique_name(base_name: String, parent: Node) -> String:
	"""Generate a unique name that doesn't conflict with existing children
	
	This prevents Godot from showing naming conflict dialogs during scene packing
	
	Args:
		base_name: The desired base name for the node
		parent: Parent node to check for existing children
	
	Returns:
		String: A unique name (e.g., "tree-large_pickup_1")
	"""
	if not parent or not is_instance_valid(parent):
		return base_name

	# Check if base name is already unique
	var has_conflict = false
	for child in parent.get_children():
		if child.name == base_name:
			has_conflict = true
			break

	if not has_conflict:
		return base_name

	# Generate unique name by appending counter
	var counter = 1
	var unique_name = base_name + "_pickup_" + str(counter)

	# Safety limit to prevent infinite loop
	var max_attempts = 1000

	while counter < max_attempts:
		has_conflict = false
		for child in parent.get_children():
			if child.name == unique_name:
				has_conflict = true
				break

		if not has_conflict:
			return unique_name

		counter += 1
		unique_name = base_name + "_pickup_" + str(counter)

	# Fallback if we somehow hit the limit
	return base_name + "_pickup_" + str(Time.get_ticks_msec())


static func _rename_all_children_recursive(node: Node, suffix: String = "_pickup") -> void:
	"""Recursively rename all children to avoid naming conflicts
	
	This ensures that even deeply nested children don't conflict with scene nodes
	
	Args:
		node: Root node to start renaming from
		suffix: Suffix to append to all child names
	"""
	if not node or not is_instance_valid(node):
		return

	for child in node.get_children():
		# Rename this child
		child.name = child.name + suffix

		# Recurse into its children
		_rename_all_children_recursive(child, suffix)


static func _remove_ui_children(node: Node) -> void:
	"""Remove any UI/Control children from a node tree
	
	This prevents issues with dialogs and UI elements when duplicating nodes
	
	Args:
		node: Root node to clean UI elements from
	"""
	if not node or not is_instance_valid(node):
		return

	var children_to_remove: Array = []

	# Find all problematic children
	for child in node.get_children():
		# Remove UI elements (Control, CanvasItem, Window)
		if child is Control or child is CanvasItem or child is Window:
			children_to_remove.append(child)
		# Remove editor-specific nodes that might cause issues
		elif (
			child.get_class()
			in ["EditorFileDialog", "AcceptDialog", "ConfirmationDialog", "PopupMenu", "Popup"]
		):
			children_to_remove.append(child)
		elif child is Node3D:
			# Recurse into 3D nodes
			_remove_ui_children(child)

	# Remove problematic children
	for child in children_to_remove:
		if is_instance_valid(child) and child.get_parent() == node:
			node.remove_child(child)
			child.queue_free()


## Private Helpers - Error Handling


static func _error_result(message: String) -> Dictionary:
	"""Create an error result dictionary
	
	Args:
		message: Error message
		
	Returns:
		Dictionary with success=false and error message
	"""
	PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Pickup failed: " + message)

	return {
		"success": false,
		"asset_path": "",
		"packed_scene": null,
		"initial_scale": Vector3.ONE,
		"initial_rotation": Vector3.ZERO,
		"node_count": 0,
		"error_message": message
	}
