@tool
extends RefCounted

class_name UtilityManager

"""
UTILITY MANAGER (CLEAN ARCHITECTURE)
====================================

PURPOSE: Centralized utility functions for scene manipulation and node management.

RESPONSIBILITIES:
- Node name generation and uniqueness validation
- Scene node addition with proper undo/redo support
- Mesh extraction from various Node3D types (MeshInstance3D, CSG nodes, etc.)
- Asset instantiation and scene placement with transformations

ARCHITECTURE POSITION: Pure utility provider
- Does NOT manage state or mode switching
- Does NOT handle input or positioning logic
- Does NOT coordinate between other managers
- Provides focused utility functions for scene manipulation

USED BY: TransformationManager for scene placement operations
DELEGATES TO: EditorInterface for undo/redo and scene access
"""

# Import focused managers for transformation application
const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

## UTILITY FUNCTIONS

static func generate_unique_name(base_name: String, parent: Node) -> String:
	"""Generate a unique node name within the parent"""
	var unique_name = base_name
	var counter = 1
	
	# Check if a node with this name already exists
	while parent.has_node(NodePath(unique_name)):
		counter += 1
		unique_name = base_name + "_" + str(counter)
	
	return unique_name

static func add_node_with_undo_redo(node: Node, parent: Node, action_name: String):
	"""Add a node with undo/redo support"""
	var undo_redo = EditorInterface.get_editor_undo_redo()
	
	if undo_redo:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(parent, "add_child", node)
		undo_redo.add_do_property(node, "owner", EditorInterface.get_edited_scene_root())
		undo_redo.add_undo_method(parent, "remove_child", node)
		undo_redo.commit_action()
	else:
		# Fallback if undo/redo is not available
		parent.add_child(node)
		node.owner = EditorInterface.get_edited_scene_root()

static func extract_mesh_from_node3d(node: Node3D) -> Mesh:
	"""Extract a mesh from a Node3D (MeshInstance3D, CSG nodes, etc.)"""
	if node is MeshInstance3D:
		return node.mesh
	elif node is CSGShape3D:
		# Use the CSG shape's generated mesh
		var mesh_instance = node.get_meshes()
		if mesh_instance.size() > 1:
			return mesh_instance[1]  # The generated mesh is usually at index 1
	elif node.get_child_count() > 0:
		# Try to find mesh in children
		return extract_mesh_from_children(node)
	
	return null

static func extract_mesh_from_children(node: Node3D) -> Mesh:
	"""Recursively extract mesh from children nodes"""
	for child in node.get_children():
		if child is Node3D:
			var child_mesh = extract_mesh_from_node3d(child)
			if child_mesh:
				return child_mesh
	return null

static func place_asset_in_scene(asset_path: String, position: Vector3 = Vector3.ZERO, settings: Dictionary = {}, transform_state: TransformState = null) -> Node:
	"""Place an asset file in the scene with applied transformations"""
	PluginLogger.info("UtilityManager", "Placing asset: " + asset_path + " at position: " + str(position))
	
	# Load the asset
	var asset = load(asset_path)
	if not asset:
		PluginLogger.error("UtilityManager", "Failed to load asset: " + asset_path)
		return null
	
	var scene_instance = null
	
	# Handle different asset types
	if asset is PackedScene:
		scene_instance = asset.instantiate()
	elif asset is Mesh:
		scene_instance = MeshInstance3D.new()
		scene_instance.mesh = asset
	else:
		PluginLogger.error("UtilityManager", "Unsupported asset type for: " + asset_path)
		return null
	
	if not scene_instance:
		PluginLogger.error("UtilityManager", "Failed to instantiate asset: " + asset_path)
		return null
	
	# Generate unique name and add to scene first
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene:
		var base_name = asset_path.get_file().get_basename()
		var unique_name = generate_unique_name(base_name, current_scene)
		scene_instance.name = unique_name
		
		# Add to scene with undo/redo support
		add_node_with_undo_redo(scene_instance, current_scene, "Place Asset")
		
		# Now apply transforms (after node is in tree)
		scene_instance.global_position = position
		
		# Apply rotation from RotationManager
		if transform_state:
			RotationManager.apply_rotation_to_node(transform_state, scene_instance)
		
		# Apply random Y rotation if enabled
		if settings.get("random_rotation", false):
			var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
			scene_instance.rotate_y(random_y_rotation)
		
		# Apply scale (assume uniform scale from ScaleManager)
		var scale_multiplier = ScaleManager.get_scale(transform_state) if transform_state else 1.0
		PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
		var final_scale = scene_instance.scale * scale_multiplier
		
		# Apply scale immediately without smooth transitions (newly placed objects should snap to final scale)
		const SmoothTransformManager = preload("res://addons/simpleassetplacer/core/smooth_transform_manager.gd")
		SmoothTransformManager.apply_transform_immediately(scene_instance, scene_instance.global_position, scene_instance.rotation, final_scale)
		
		PluginLogger.info("UtilityManager", "Successfully placed asset as: " + unique_name + " with final scale: " + str(scene_instance.scale))
		return scene_instance
	else:
		PluginLogger.error("UtilityManager", "No current scene root found")
		scene_instance.queue_free()
		return null

static func place_meshlib_item_in_scene(meshlib: MeshLibrary, item_id: int, position: Vector3, settings: Dictionary = {}, transform_state: TransformState = null) -> MeshInstance3D:
	"""Place a MeshLibrary item in the scene with applied transformations"""
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		PluginLogger.error("UtilityManager", "Invalid mesh for item ID: " + str(item_id))
		return null
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	# Generate unique name and add to scene first
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene:
		var base_name = meshlib.get_item_name(item_id)
		if base_name == "":
			base_name = "MeshLibItem"
		var unique_name = generate_unique_name(base_name, current_scene)
		mesh_instance.name = unique_name
		
		# Add to scene with undo/redo support
		add_node_with_undo_redo(mesh_instance, current_scene, "Place MeshLib Item")
		
		# Now apply transforms (after node is in tree)
		mesh_instance.global_position = position
		
		# Apply rotation from RotationManager
		if transform_state:
			RotationManager.apply_rotation_to_node(transform_state, mesh_instance)
		
		# Apply random Y rotation if enabled
		if settings.get("random_rotation", false):
			var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
			mesh_instance.rotate_y(random_y_rotation)
			PluginLogger.debug("UtilityManager", "Applied random Y rotation: " + str(rad_to_deg(random_y_rotation)) + " degrees")
		
		# Apply scale (assume uniform scale from ScaleManager)
		var scale_multiplier = ScaleManager.get_scale(transform_state) if transform_state else 1.0
		PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
		var final_scale = mesh_instance.scale * scale_multiplier
		
		# Apply scale immediately without smooth transitions (newly placed objects should snap to final scale)
		const SmoothTransformManager = preload("res://addons/simpleassetplacer/core/smooth_transform_manager.gd")
		SmoothTransformManager.apply_transform_immediately(mesh_instance, mesh_instance.global_position, mesh_instance.rotation, final_scale)
		
		PluginLogger.info("UtilityManager", "Successfully placed meshlib item as: " + unique_name + " with final scale: " + str(mesh_instance.scale))
		return mesh_instance
	else:
		PluginLogger.error("UtilityManager", "No current scene root found")
		mesh_instance.queue_free()
		return null

static func place_mesh_in_scene(mesh: Mesh, position: Vector3, settings: Dictionary = {}, transform_state: TransformState = null) -> MeshInstance3D:
	"""Place a mesh in the scene with applied transformations"""
	if not mesh:
		PluginLogger.error("UtilityManager", "No mesh provided")
		return null
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	# Generate unique name and add to scene first
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene:
		var base_name = "Mesh"
		var unique_name = generate_unique_name(base_name, current_scene)
		mesh_instance.name = unique_name
		
		# Add to scene with undo/redo support
		add_node_with_undo_redo(mesh_instance, current_scene, "Place Mesh")
		
		# Now apply transforms (after node is in tree)
		mesh_instance.global_position = position
		
		# Apply rotation from RotationManager
		if transform_state:
			RotationManager.apply_rotation_to_node(transform_state, mesh_instance)
		
		# Apply random Y rotation if enabled
		if settings.get("random_rotation", false):
			var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
			mesh_instance.rotate_y(random_y_rotation)
			PluginLogger.debug("UtilityManager", "Applied random Y rotation: " + str(rad_to_deg(random_y_rotation)) + " degrees")
		
		# Apply scale (assume uniform scale from ScaleManager)
		var scale_multiplier = ScaleManager.get_scale(transform_state) if transform_state else 1.0
		PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
		var final_scale = mesh_instance.scale * scale_multiplier
		
		# Apply scale immediately without smooth transitions (newly placed objects should snap to final scale)
		const SmoothTransformManager = preload("res://addons/simpleassetplacer/core/smooth_transform_manager.gd")
		SmoothTransformManager.apply_transform_immediately(mesh_instance, mesh_instance.global_position, mesh_instance.rotation, final_scale)
		
		PluginLogger.info("UtilityManager", "Successfully placed mesh as: " + unique_name + " with final scale: " + str(mesh_instance.scale))
		return mesh_instance
	else:
		PluginLogger.error("UtilityManager", "No current scene root found")
		mesh_instance.queue_free()
		return null






