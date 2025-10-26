@tool
extends RefCounted

class_name UtilityManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

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
const RotationManager = preload("res://addons/simpleassetplacer/managers/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

## UTILITY FUNCTIONS

func generate_unique_name(base_name: String, parent: Node) -> String:
	"""Generate a unique node name within the parent"""
	var unique_name = base_name
	var counter = 1
	
	# Check if a node with this name already exists
	while parent.has_node(NodePath(unique_name)):
		counter += 1
		unique_name = base_name + "_" + str(counter)
	
	return unique_name

func add_node_to_scene(node: Node, parent: Node) -> void:
	"""Add a node to the scene
	
	NOTE: This does NOT create undo/redo entries. Undo/redo is handled by
	TransformationCoordinator using UndoRedoHelper after the node is placed.
	This separation allows the coordinator to capture the full transform state.
	"""
	parent.add_child(node)
	node.owner = _services.editor_facade.get_edited_scene_root()
	
	# Verify node was added
	if node.is_inside_tree():
		PluginLogger.debug("UtilityManager", "Node added to scene: " + node.name + " (parent: " + parent.name + ", owner: " + str(node.owner) + ")")
	else:
		PluginLogger.error("UtilityManager", "Node failed to be added to scene tree: " + node.name)

func extract_mesh_from_node3d(node: Node3D) -> Mesh:
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

func extract_mesh_from_children(node: Node3D) -> Mesh:
	"""Recursively extract mesh from children nodes"""
	for child in node.get_children():
		if child is Node3D:
			var child_mesh = extract_mesh_from_node3d(child)
			if child_mesh:
				return child_mesh
	return null

func place_asset_in_scene(asset_path: String, position: Vector3 = Vector3.ZERO, settings: Dictionary = {}, transform_state: TransformState = null) -> Node:
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
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if current_scene:
		var base_name = asset_path.get_file().get_basename()
		var unique_name = generate_unique_name(base_name, current_scene)
		scene_instance.name = unique_name
		
		# Add to scene (undo/redo handled by TransformationCoordinator)
		add_node_to_scene(scene_instance, current_scene)
		
		# Now apply transforms (after node is in tree)
		# Calculate final rotation
		var final_rotation = Vector3.ZERO
		if transform_state:
			# Get rotation from transform state (includes surface alignment + manual offset)
			var surface_transform = Transform3D(Basis.from_euler(transform_state.values.surface_alignment_rotation), Vector3.ZERO)
			var manual_transform = Transform3D(Basis.from_euler(transform_state.values.manual_rotation_offset), Vector3.ZERO)
			var combined_transform = surface_transform * manual_transform
			final_rotation = combined_transform.basis.get_euler()
		
		# Apply random Y rotation if enabled
		if settings.get("random_rotation", false):
			var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
			final_rotation.y += random_y_rotation
		
		# Apply scale (assume uniform scale from scale_manager)
		var scale_multiplier = _services.scale_manager.get_scale(transform_state) if transform_state else 1.0
		PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
		var final_scale = scene_instance.scale * scale_multiplier
		
		# Apply all transforms immediately without smooth transitions (newly placed objects should snap to final state)
		_services.smooth_transform_manager.apply_transform_immediately(scene_instance, position, final_rotation, final_scale)
		
		PluginLogger.info("UtilityManager", "Successfully placed asset as: " + unique_name + " with final scale: " + str(scene_instance.scale))
		return scene_instance
	else:
		PluginLogger.error("UtilityManager", "No current scene root found")
		scene_instance.queue_free()
		return null

func place_from_meshlib(
	mesh: Mesh,
	meshlib: MeshLibrary,
	item_id: int,
	position: Vector3,
	rotation_offset: Vector3,
	transform_state: TransformState,
	settings: Dictionary = {}
) -> Node3D:
	"""Place a mesh from MeshLibrary"""
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	# Generate unique name and add to scene first
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if current_scene:
		var base_name = meshlib.get_item_name(item_id)
		var unique_name = generate_unique_name(base_name, current_scene)
		mesh_instance.name = unique_name
		
		# Add to scene (undo/redo handled by TransformationCoordinator)
		add_node_to_scene(mesh_instance, current_scene)
	
	# Get base rotation from MeshLibrary
	var base_rotation = _services.rotation_manager.get_current_rotation(transform_state)
	var final_rotation = base_rotation + rotation_offset
	
	# Apply random Y rotation if enabled
	if settings.get("random_rotation", false):
		var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
		final_rotation.y += random_y_rotation
		PluginLogger.debug("UtilityManager", "Applied random Y rotation: " + str(rad_to_deg(random_y_rotation)) + " degrees")
	
	# Apply scale (assume uniform scale from scale_manager)
	var scale_multiplier = _services.scale_manager.get_scale(transform_state) if transform_state else 1.0
	PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
	var final_scale = mesh_instance.scale * scale_multiplier
	
	# Apply all transforms immediately without smooth transitions (newly placed objects should snap to final state)
	_services.smooth_transform_manager.apply_transform_immediately(mesh_instance, position, final_rotation, final_scale)
	
	PluginLogger.info("UtilityManager", "Successfully placed MeshLibrary item as: " + mesh_instance.name + " with final scale: " + str(mesh_instance.scale))
	return mesh_instance

func place_direct_mesh(
	mesh: Mesh,
	position: Vector3,
	rotation_offset: Vector3,
	transform_state: TransformState,
	settings: Dictionary = {}
) -> Node3D:
	"""Place a direct mesh instance (for simple meshes without MeshLibrary)"""
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	# Generate unique name and add to scene first
	var current_scene = _services.editor_facade.get_edited_scene_root()
	if current_scene:
		var base_name = "Mesh"
		var unique_name = generate_unique_name(base_name, current_scene)
		mesh_instance.name = unique_name
		current_scene.add_child(mesh_instance)
		mesh_instance.owner = current_scene
	
	# Get base rotation from rotation manager
	var base_rotation = _services.rotation_manager.get_current_rotation(transform_state)
	var final_rotation = base_rotation + rotation_offset
	
	# Apply random Y rotation if enabled
	if settings.get("random_rotation", false):
		var random_y_rotation = randf_range(0.0, TAU)  # Full 360 degrees in radians
		final_rotation.y += random_y_rotation
		PluginLogger.debug("UtilityManager", "Applied random Y rotation: " + str(rad_to_deg(random_y_rotation)) + " degrees")
	
	# Apply scale (assume uniform scale from scale_manager)
	var scale_multiplier = _services.scale_manager.get_scale(transform_state) if transform_state else 1.0
	PluginLogger.info("UtilityManager", "Applying scale multiplier: " + str(scale_multiplier) + " (transform_state: " + ("present" if transform_state else "null") + ")")
	var final_scale = mesh_instance.scale * scale_multiplier
	
	# Apply all transforms immediately without smooth transitions (newly placed objects should snap to final state)
	_services.smooth_transform_manager.apply_transform_immediately(mesh_instance, position, final_rotation, final_scale)
	
	PluginLogger.info("UtilityManager", "Successfully placed direct mesh as: " + mesh_instance.name + " with final scale: " + str(mesh_instance.scale))
	return mesh_instance

## PLACEMENT WRAPPERS

func place_meshlib_item_in_scene(
	meshlib: MeshLibrary,
	item_id: int,
	position: Vector3,
	settings: Dictionary = {},
	transform_state: TransformState = null
) -> Node3D:
	"""Wrapper for placing MeshLibrary items (called by TransformationCoordinator)"""
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		PluginLogger.error("UtilityManager", "Failed to get mesh for item_id: " + str(item_id))
		return null
	
	return place_from_meshlib(mesh, meshlib, item_id, position, Vector3.ZERO, transform_state, settings)

func place_mesh_in_scene(
	mesh: Mesh,
	position: Vector3,
	settings: Dictionary = {},
	transform_state: TransformState = null
) -> Node3D:
	"""Wrapper for placing direct meshes (called by TransformationCoordinator)"""
	if not mesh:
		PluginLogger.error("UtilityManager", "Cannot place null mesh")
		return null
	
	return place_direct_mesh(mesh, position, Vector3.ZERO, transform_state, settings)








