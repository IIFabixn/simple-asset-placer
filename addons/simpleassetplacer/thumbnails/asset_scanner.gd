@tool
extends RefCounted

class_name AssetScanner

"""
UNIFIED ASSET SCANNING SYSTEM
==============================

PURPOSE: Centralized asset discovery and validation to eliminate duplicate scanning logic.

RESPONSIBILITIES:
- Scan project directories for supported asset types
- Validate assets (check if they contain meshes)
- Filter assets by type and extension
- Provide consistent asset metadata structure

USED BY: AssetPlacerDock, ModelLibraryBrowser, MeshLibraryBrowser
"""

const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")

## Asset Scanning

static func scan_for_assets(root_path: String = "res://", include_meshlibs: bool = true, category_manager = null) -> Array:
	"""
	Scan directory tree for all supported 3D assets
	
	Args:
		root_path: Starting directory for scan
		include_meshlibs: Whether to include MeshLibrary files
		category_manager: Optional CategoryManager to filter ignored folders during scan
		
	Returns:
		Array of asset info dictionaries with keys: path, name, extension, type, is_meshlib
	"""
	var discovered_assets: Array = []
	_scan_directory_recursive(root_path, discovered_assets, include_meshlibs, category_manager)
	return discovered_assets

static func _scan_directory_recursive(path: String, discovered_assets: Array, include_meshlibs: bool, category_manager) -> void:
	"""Recursively scan directory for assets"""
	var dir = DirAccess.open(path)
	if not dir:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Failed to open directory: " + path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Skip hidden directories and .godot
			if file_name != ".godot":
				# Check if this directory should be ignored
				var should_scan = true
				if category_manager:
					should_scan = not category_manager.is_in_ignored_folder(full_path)
				
				if should_scan:
					_scan_directory_recursive(full_path, discovered_assets, include_meshlibs, category_manager)
		else:
			var extension = file_name.get_extension().to_lower()
			
			# Check if this is a supported extension
			if _is_supported_extension(extension):
				# Check if this asset should be ignored
				if category_manager and category_manager.is_ignored(full_path):
					file_name = dir.get_next()
					continue
				
				var asset_info = _process_asset_file(full_path, extension, include_meshlibs)
				if asset_info:
					discovered_assets.append(asset_info)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

static func _is_supported_extension(extension: String) -> bool:
	"""Check if file extension is supported"""
	return extension in PluginConstants.get_all_supported_extensions()

static func _process_asset_file(file_path: String, extension: String, include_meshlibs: bool) -> Dictionary:
	"""
	Process a potential asset file and return asset info if valid
	
	Returns empty dictionary if asset should be skipped
	"""
	var is_meshlib = false
	var has_mesh = false
	var asset_type = ""
	
	# Determine asset type and validate
	if PluginConstants.is_resource_extension(extension) or PluginConstants.is_meshlib_extension(extension):
		# Try to load resource safely
		if not ResourceLoader.exists(file_path):
			return {}
		
		var resource = load(file_path)
		if not resource:
			return {}
		
		if resource is MeshLibrary:
			is_meshlib = true
			has_mesh = true
			asset_type = "MeshLibrary"
			
			# Skip MeshLibraries if not requested
			if not include_meshlibs:
				return {}
		elif resource is Mesh:
			has_mesh = true
			asset_type = "3D Model"
		elif resource is PackedScene:
			has_mesh = scene_contains_mesh(resource)
			asset_type = "Scene" if has_mesh else ""
		elif _is_material_or_terrain(resource):
			# Skip materials and terrain resources
			return {}
		else:
			# Unknown resource type - try to check for mesh anyway
			has_mesh = _resource_contains_mesh(resource)
			asset_type = "Resource" if has_mesh else ""
	
	elif PluginConstants.is_scene_extension(extension):
		has_mesh = file_contains_mesh(file_path)
		asset_type = "Scene" if has_mesh else ""
	
	elif PluginConstants.is_3d_model_extension(extension):
		has_mesh = file_contains_mesh(file_path)
		asset_type = "3D Model" if has_mesh else ""
	
	# Only return asset info if it has mesh content
	if not has_mesh:
		return {}
	
	return {
		"path": file_path,
		"name": file_path.get_file().get_basename(),
		"extension": extension,
		"type": asset_type,
		"is_meshlib": is_meshlib
	}

## Asset Validation

static func file_contains_mesh(file_path: String) -> bool:
	"""
	Check if a file contains mesh data
	
	Works for: 3D models (.fbx, .obj, .gltf, etc.), scene files (.tscn, .scn)
	"""
	if not ResourceLoader.exists(file_path):
		return false
	
	var resource = load(file_path)
	if not resource:
		return false
	
	if resource is Mesh:
		return true
	elif resource is PackedScene:
		return scene_contains_mesh(resource)
	
	return false

static func scene_contains_mesh(scene: PackedScene) -> bool:
	"""Check if a PackedScene contains any mesh instances"""
	if not scene:
		return false
	
	var scene_instance = scene.instantiate()
	if not scene_instance:
		return false
	
	var has_mesh = _node_tree_has_mesh(scene_instance)
	scene_instance.queue_free()
	return has_mesh

static func _node_tree_has_mesh(node: Node) -> bool:
	"""Recursively check if node tree contains any meshes"""
	# Check if this node is a MeshInstance3D
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			return true
	
	# Check for ImporterMeshInstance3D (used during import process)
	if node.get_class() == "ImporterMeshInstance3D":
		if node.has_method("get_mesh") and node.get_mesh():
			return true
	
	# Recursively check children
	for child in node.get_children():
		if _node_tree_has_mesh(child):
			return true
	
	return false

static func _resource_contains_mesh(resource: Resource) -> bool:
	"""Check if a generic resource contains mesh data"""
	if resource is Mesh:
		return true
	elif resource is PackedScene:
		return scene_contains_mesh(resource)
	
	# Unknown resource type, assume no mesh
	return false

static func _is_material_or_terrain(resource: Resource) -> bool:
	"""Check if resource is a material or terrain (should be filtered out)"""
	if resource is Material:
		return true
	
	var resource_class = resource.get_class()
	if resource_class.contains("Material") or resource_class.contains("Terrain") or resource_class.contains("terrain"):
		return true
	
	return false

## Filtering

static func filter_by_extension(assets: Array, extension: String) -> Array:
	"""Filter assets by specific extension"""
	if extension == "" or extension == "all":
		return assets
	
	var filtered = []
	for asset in assets:
		if asset.extension == extension:
			filtered.append(asset)
	
	return filtered

static func filter_by_type(assets: Array, asset_type: String) -> Array:
	"""Filter assets by type (3D Model, Scene, MeshLibrary, etc.)"""
	if asset_type == "" or asset_type == "all":
		return assets
	
	var filtered = []
	for asset in assets:
		if asset.type == asset_type:
			filtered.append(asset)
	
	return filtered

static func filter_by_search(assets: Array, search_text: String) -> Array:
	"""Filter assets by search text (searches in name and path)"""
	if search_text == "":
		return assets
	
	var search_lower = search_text.to_lower()
	var filtered = []
	
	for asset in assets:
		var name_lower = asset.name.to_lower()
		var path_lower = asset.path.to_lower()
		
		if search_lower in name_lower or search_lower in path_lower:
			filtered.append(asset)
	
	return filtered

static func exclude_meshlibs(assets: Array) -> Array:
	"""Remove MeshLibrary assets from array"""
	var filtered = []
	for asset in assets:
		if not asset.get("is_meshlib", false):
			filtered.append(asset)
	return filtered

static func only_meshlibs(assets: Array) -> Array:
	"""Keep only MeshLibrary assets"""
	var filtered = []
	for asset in assets:
		if asset.get("is_meshlib", false):
			filtered.append(asset)
	return filtered

## Utility

static func get_meshlib_paths(assets: Array) -> Array:
	"""Extract paths of all MeshLibrary assets"""
	var paths = []
	for asset in assets:
		if asset.get("is_meshlib", false):
			paths.append(asset.path)
	return paths

static func get_asset_by_path(assets: Array, path: String) -> Dictionary:
	"""Find asset info by path"""
	for asset in assets:
		if asset.path == path:
			return asset
	return {}







