@tool
extends RefCounted

class_name CategoryManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

## CategoryManager handles category detection, tag management, and filtering logic
## for the Simple Asset Placer plugin.
##
## Features:
## - Automatic folder-based category detection
## - Custom tag management via .assetcategories JSON files
## - Favorites and recent assets tracking
## - Tag usage statistics

signal categories_updated()
signal tags_changed()

# Configuration
const CONFIG_FILE_NAME = ".assetcategories"
const MAX_RECENT_ASSETS = 20
const EDITOR_SETTINGS_FAVORITES_KEY = "simple_asset_placer/categories/favorites"
const EDITOR_SETTINGS_RECENT_KEY = "simple_asset_placer/categories/recent_assets"
const EDITOR_SETTINGS_IGNORED_KEY = "simple_asset_placer/categories/ignored_assets"
const EDITOR_SETTINGS_IGNORED_FOLDERS_KEY = "simple_asset_placer/categories/ignored_folders"

# Category types
enum CategoryType {
	FOLDER,      # Auto-detected from folder structure
	CUSTOM_TAG,  # User-defined tags
	SPECIAL      # Favorites, Recent, etc.
}

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

# Data storage
var custom_tags: Dictionary = {}  # {"asset_name_or_path": ["tag1", "tag2"]}
var tag_usage: Dictionary = {}    # {"tag_name": usage_count}
var folder_categories: Dictionary = {}  # {"category_path": ["asset1", "asset2"]}
var favorites: Array = []  # Array of asset paths
var recent_assets: Array = []  # Array of asset paths (most recent first)
var ignored_assets: Array = []  # Array of ignored asset paths
var ignored_folders: Array = []  # Array of ignored folder paths
var config_file_path: String = ""
var recently_used_tags: Array = []  # Last used tags for quick access


func _init(services: ServiceRegistry):
	_services = services
	load_editor_settings()


## Load favorites and recent assets from EditorSettings
func load_editor_settings():
	if Engine.is_editor_hint():
		var editor_settings = _services.editor_facade.get_editor_settings()
		if editor_settings:
			# Load favorites
			if editor_settings.has_setting(EDITOR_SETTINGS_FAVORITES_KEY):
				favorites = editor_settings.get_setting(EDITOR_SETTINGS_FAVORITES_KEY)
			else:
				favorites = []
				editor_settings.set_setting(EDITOR_SETTINGS_FAVORITES_KEY, favorites)
			
			# Load recent assets
			if editor_settings.has_setting(EDITOR_SETTINGS_RECENT_KEY):
				recent_assets = editor_settings.get_setting(EDITOR_SETTINGS_RECENT_KEY)
			else:
				recent_assets = []
				editor_settings.set_setting(EDITOR_SETTINGS_RECENT_KEY, recent_assets)
			
			# Load ignored assets
			if editor_settings.has_setting(EDITOR_SETTINGS_IGNORED_KEY):
				ignored_assets = editor_settings.get_setting(EDITOR_SETTINGS_IGNORED_KEY)
			else:
				ignored_assets = []
				editor_settings.set_setting(EDITOR_SETTINGS_IGNORED_KEY, ignored_assets)
			
			# Load ignored folders
			if editor_settings.has_setting(EDITOR_SETTINGS_IGNORED_FOLDERS_KEY):
				ignored_folders = editor_settings.get_setting(EDITOR_SETTINGS_IGNORED_FOLDERS_KEY)
			else:
				# Initialize with default ignored folders
				ignored_folders = ["res://addons"]
				editor_settings.set_setting(EDITOR_SETTINGS_IGNORED_FOLDERS_KEY, ignored_folders)
			
			# Ensure addons folder is in the ignored list (for users who had previous version)
			if "res://addons" not in ignored_folders:
				ignored_folders.append("res://addons")
				editor_settings.set_setting(EDITOR_SETTINGS_IGNORED_FOLDERS_KEY, ignored_folders)


## Save favorites and recent assets to EditorSettings
func save_editor_settings():
	if Engine.is_editor_hint():
		var editor_settings = _services.editor_facade.get_editor_settings()
		if editor_settings:
			editor_settings.set_setting(EDITOR_SETTINGS_FAVORITES_KEY, favorites)
			editor_settings.set_setting(EDITOR_SETTINGS_RECENT_KEY, recent_assets)
			editor_settings.set_setting(EDITOR_SETTINGS_IGNORED_KEY, ignored_assets)
			editor_settings.set_setting(EDITOR_SETTINGS_IGNORED_FOLDERS_KEY, ignored_folders)


## Extract folder-based categories from an asset path
## Returns array of category strings: ["props", "outdoor", "barrels"]
func extract_folder_categories(asset_path: String) -> Array:
	var categories = []
	
	# Check if the asset is within an ignored folder - if so, return empty categories
	if is_in_ignored_folder(asset_path):
		return categories
	
	# Remove res:// prefix and filename
	var path = asset_path.replace("res://", "")
	var dir_path = path.get_base_dir()
	
	if dir_path.is_empty():
		return categories
	
	# Split path into folder segments
	var segments = dir_path.split("/")
	
	# Build hierarchical categories, checking each cumulative path against ignored folders
	var cumulative_path = "res://"
	for segment in segments:
		if not segment.is_empty() and segment != ".":
			cumulative_path += segment
			# Check if this cumulative path is an ignored folder
			if is_folder_ignored(cumulative_path):
				# Stop processing - all subsequent segments are under an ignored folder
				break
			categories.append(segment)
			cumulative_path += "/"
	
	return categories


## Get the full hierarchical category path
## e.g., "assets > props > outdoor"
func get_category_hierarchy_string(categories: Array) -> String:
	return " > ".join(categories)


## Load .assetcategories JSON file from the project
func load_config_file(search_path: String = "res://") -> bool:
	# Search for .assetcategories file
	var config_path = find_config_file(search_path)
	
	if config_path.is_empty():
		# No config file found, use defaults
		custom_tags.clear()
		tag_usage.clear()
		return false
	
	config_file_path = config_path
	
	# Load and parse JSON
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		PluginLogger.error("CategoryManager", "Failed to open config file: " + config_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		PluginLogger.error("CategoryManager", "Failed to parse JSON in " + config_path + " at line " + str(json.get_error_line()) + ": " + json.get_error_message())
		return false
	
	var data = json.data
	
	# Load tags
	if data.has("tags") and data["tags"] is Dictionary:
		custom_tags = data["tags"]
	else:
		custom_tags = {}
	
	# Load tag usage statistics
	if data.has("tag_usage") and data["tag_usage"] is Dictionary:
		tag_usage = data["tag_usage"]
	else:
		tag_usage = {}
		# Calculate usage from tags if not provided
		_recalculate_tag_usage()
	
	# Load recently used tags
	if data.has("recently_used") and data["recently_used"] is Array:
		recently_used_tags = data["recently_used"]
	else:
		recently_used_tags = []
	
	categories_updated.emit()
	return true


## Find .assetcategories file in the project
func find_config_file(search_path: String) -> String:
	# Check root first
	var root_config = search_path.path_join(CONFIG_FILE_NAME)
	if FileAccess.file_exists(root_config):
		return root_config
	
	# Search subdirectories (common locations)
	var common_paths = ["assets/", "addons/", "models/", ""]
	for path in common_paths:
		var full_path = search_path.path_join(path).path_join(CONFIG_FILE_NAME)
		if FileAccess.file_exists(full_path):
			return full_path
	
	return ""


## Save current tags and settings to .assetcategories file
func save_config_file() -> bool:
	if config_file_path.is_empty():
		# Create new config file in res://
		config_file_path = "res://".path_join(CONFIG_FILE_NAME)
	
	var data = {
		"tags": custom_tags,
		"tag_usage": tag_usage,
		"recently_used": recently_used_tags
	}
	
	var json_string = JSON.stringify(data, "\t")
	
	var file = FileAccess.open(config_file_path, FileAccess.WRITE)
	if not file:
		PluginLogger.error("CategoryManager", "Failed to save config file: " + config_file_path)
		return false
	
	file.store_string(json_string)
	file.close()
	
	return true


## Recalculate tag usage statistics from current tags
func _recalculate_tag_usage():
	tag_usage.clear()
	
	for asset_key in custom_tags:
		var tags = custom_tags[asset_key]
		if tags is Array:
			for tag in tags:
				if tag_usage.has(tag):
					tag_usage[tag] += 1
				else:
					tag_usage[tag] = 1


## Clean up tags for assets that no longer exist
func cleanup_orphaned_tags(valid_asset_paths: Array) -> Dictionary:
	"""
	Remove tags for assets that no longer exist in the project.
	
	Args:
		valid_asset_paths: Array of valid asset paths currently in the project
		
	Returns:
		Dictionary with cleanup results: {
			"removed_assets": int,  # Number of assets removed from tags
			"removed_tags": Array,  # List of tag names that became empty
			"assets_cleaned": Array  # List of asset keys that were removed
		}
	"""
	var removed_count = 0
	var removed_tag_names = []
	var cleaned_asset_keys = []
	
	# Build set of valid asset keys (using basename as key)
	var valid_keys = {}
	for path in valid_asset_paths:
		var key = path.get_file().get_basename()
		valid_keys[key] = true
	
	# Find tags for assets that no longer exist
	var keys_to_remove = []
	for asset_key in custom_tags.keys():
		if not valid_keys.has(asset_key):
			keys_to_remove.append(asset_key)
	
	# Remove orphaned tags
	for key in keys_to_remove:
		custom_tags.erase(key)
		cleaned_asset_keys.append(key)
		removed_count += 1
	
	# Recalculate tag usage statistics
	var old_tags = tag_usage.keys()
	_recalculate_tag_usage()
	
	# Find tags that no longer have any usage
	for old_tag in old_tags:
		if not tag_usage.has(old_tag) or tag_usage[old_tag] == 0:
			removed_tag_names.append(old_tag)
	
	# Save changes if any orphaned tags were removed
	if removed_count > 0:
		save_config_file()
		categories_updated.emit()
		
		# Log the cleanup results
		push_warning("CategoryManager: Cleaned up %d orphaned tag entries" % removed_count)
		if removed_tag_names.size() > 0:
			push_warning("CategoryManager: Removed %d unused tags: %s" % [removed_tag_names.size(), ", ".join(removed_tag_names)])
	
	return {
		"removed_assets": removed_count,
		"removed_tags": removed_tag_names,
		"assets_cleaned": cleaned_asset_keys
	}


## Validate and clean favorites list (remove non-existent assets)
func cleanup_favorites(valid_asset_paths: Array) -> int:
	"""
	Remove favorites that no longer exist in the project.
	
	Args:
		valid_asset_paths: Array of valid asset paths currently in the project
		
	Returns:
		Number of favorites removed
	"""
	var valid_paths_set = {}
	for path in valid_asset_paths:
		valid_paths_set[path] = true
	
	var favorites_to_remove = []
	for fav_path in favorites:
		if not valid_paths_set.has(fav_path):
			favorites_to_remove.append(fav_path)
	
	for path in favorites_to_remove:
		favorites.erase(path)
	
	if favorites_to_remove.size() > 0:
		save_editor_settings()
		categories_updated.emit()
		push_warning("CategoryManager: Cleaned up %d orphaned favorites" % favorites_to_remove.size())
	
	return favorites_to_remove.size()


## Validate and clean recent assets list (remove non-existent assets)
func cleanup_recent_assets(valid_asset_paths: Array) -> int:
	"""
	Remove recent assets that no longer exist in the project.
	
	Args:
		valid_asset_paths: Array of valid asset paths currently in the project
		
	Returns:
		Number of recent assets removed
	"""
	var valid_paths_set = {}
	for path in valid_asset_paths:
		valid_paths_set[path] = true
	
	var recent_to_remove = []
	for recent_path in recent_assets:
		if not valid_paths_set.has(recent_path):
			recent_to_remove.append(recent_path)
	
	for path in recent_to_remove:
		recent_assets.erase(path)
	
	if recent_to_remove.size() > 0:
		save_editor_settings()
		categories_updated.emit()
		push_warning("CategoryManager: Cleaned up %d orphaned recent assets" % recent_to_remove.size())
	
	return recent_to_remove.size()


## Perform full cleanup of all orphaned data
func cleanup_all_orphaned_data(valid_asset_paths: Array) -> Dictionary:
	"""
	Clean up all orphaned data (tags, favorites, recent assets).
	
	Args:
		valid_asset_paths: Array of valid asset paths currently in the project
		
	Returns:
		Dictionary with comprehensive cleanup results
	"""
	var tag_results = cleanup_orphaned_tags(valid_asset_paths)
	var favorites_removed = cleanup_favorites(valid_asset_paths)
	var recent_removed = cleanup_recent_assets(valid_asset_paths)
	
	return {
		"tags": tag_results,
		"favorites_removed": favorites_removed,
		"recent_removed": recent_removed,
		"total_items_cleaned": tag_results["removed_assets"] + favorites_removed + recent_removed
	}


## Get all custom tags for an asset (by name or path)
func get_custom_tags(asset_path: String) -> Array:
	var asset_name = asset_path.get_file().get_basename()
	
	# Try exact path match first
	if custom_tags.has(asset_path):
		return custom_tags[asset_path].duplicate()
	
	# Try filename match
	if custom_tags.has(asset_name):
		return custom_tags[asset_name].duplicate()
	
	return []


## Get all categories (folder + custom tags) for an asset
func get_all_categories(asset_path: String) -> Dictionary:
	return {
		"folder": extract_folder_categories(asset_path),
		"custom": get_custom_tags(asset_path),
		"is_favorite": is_favorite(asset_path),
		"is_recent": is_recent(asset_path)
	}


## Check if asset has a specific tag (custom or folder-based)
func has_category(asset_path: String, category: String) -> bool:
	# Check folder categories
	var folder_cats = extract_folder_categories(asset_path)
	if category in folder_cats:
		return true
	
	# Check custom tags
	var custom = get_custom_tags(asset_path)
	if category in custom:
		return true
	
	return false


## Add custom tag to an asset
func add_tag(asset_path: String, tag: String) -> bool:
	var asset_key = asset_path.get_file().get_basename()
	
	# Get existing tags
	var tags = []
	if custom_tags.has(asset_key):
		tags = custom_tags[asset_key]
	
	# Add tag if not already present
	if tag not in tags:
		tags.append(tag)
		custom_tags[asset_key] = tags
		
		# Update tag usage
		if tag_usage.has(tag):
			tag_usage[tag] += 1
		else:
			tag_usage[tag] = 1
		
		# Update recently used tags
		if tag in recently_used_tags:
			recently_used_tags.erase(tag)
		recently_used_tags.insert(0, tag)
		if recently_used_tags.size() > 10:
			recently_used_tags.resize(10)
		
		tags_changed.emit()
		return true
	
	return false


## Remove custom tag from an asset
func remove_tag(asset_path: String, tag: String) -> bool:
	var asset_key = asset_path.get_file().get_basename()
	
	if custom_tags.has(asset_key):
		var tags = custom_tags[asset_key]
		if tag in tags:
			tags.erase(tag)
			
			# Update tag usage
			if tag_usage.has(tag):
				tag_usage[tag] -= 1
				if tag_usage[tag] <= 0:
					tag_usage.erase(tag)
			
			# Remove key if no tags left
			if tags.is_empty():
				custom_tags.erase(asset_key)
			
			tags_changed.emit()
			return true
	
	return false


## Get all unique custom tag names
func get_all_custom_tags() -> Array:
	var all_tags = {}
	
	for asset_key in custom_tags:
		var tags = custom_tags[asset_key]
		if tags is Array:
			for tag in tags:
				all_tags[tag] = true
	
	var result = all_tags.keys()
	result.sort()
	return result


## Get recently used tags (limited to last N)
func get_recently_used_tags(limit: int = 5) -> Array:
	return recently_used_tags.slice(0, min(limit, recently_used_tags.size()))


## Get most frequently used tags
func get_most_used_tags(limit: int = 5) -> Array:
	var sorted_tags = []
	
	for tag in tag_usage:
		sorted_tags.append({"name": tag, "count": tag_usage[tag]})
	
	# Sort by usage count
	sorted_tags.sort_custom(func(a, b): return a["count"] > b["count"])
	
	var result = []
	for i in range(min(limit, sorted_tags.size())):
		result.append(sorted_tags[i]["name"])
	
	return result


## Add asset to favorites
func add_to_favorites(asset_path: String):
	if asset_path not in favorites:
		favorites.append(asset_path)
		save_editor_settings()
		categories_updated.emit()


## Remove asset from favorites
func remove_from_favorites(asset_path: String):
	if asset_path in favorites:
		favorites.erase(asset_path)
		save_editor_settings()
		categories_updated.emit()


## Toggle favorite status
func toggle_favorite(asset_path: String):
	if is_favorite(asset_path):
		remove_from_favorites(asset_path)
	else:
		add_to_favorites(asset_path)


## Check if asset is in favorites
func is_favorite(asset_path: String) -> bool:
	return asset_path in favorites


## Get all favorite assets
func get_favorites() -> Array:
	return favorites.duplicate()


## Add asset to ignored list
func add_to_ignored(asset_path: String):
	if asset_path not in ignored_assets:
		ignored_assets.append(asset_path)
		save_editor_settings()
		categories_updated.emit()


## Remove asset from ignored list
func remove_from_ignored(asset_path: String):
	if asset_path in ignored_assets:
		ignored_assets.erase(asset_path)
		save_editor_settings()
		categories_updated.emit()


## Toggle ignored status
func toggle_ignored(asset_path: String):
	if is_ignored(asset_path):
		remove_from_ignored(asset_path)
	else:
		add_to_ignored(asset_path)


## Check if asset is ignored
func is_ignored(asset_path: String) -> bool:
	# Check if the asset itself is ignored
	if asset_path in ignored_assets:
		return true
	
	# Check if the asset is within an ignored folder
	return is_in_ignored_folder(asset_path)


## Get all ignored assets
func get_ignored_assets() -> Array:
	return ignored_assets.duplicate()


## Add folder to ignored list
func add_folder_to_ignored(folder_path: String):
	# Normalize folder path (ensure it starts with res:// and doesn't end with /)
	var normalized_path = _normalize_folder_path(folder_path)
	
	if normalized_path not in ignored_folders:
		ignored_folders.append(normalized_path)
		save_editor_settings()
		categories_updated.emit()


## Remove folder from ignored list
func remove_folder_from_ignored(folder_path: String):
	var normalized_path = _normalize_folder_path(folder_path)
	
	if normalized_path in ignored_folders:
		ignored_folders.erase(normalized_path)
		save_editor_settings()
		categories_updated.emit()


## Toggle ignored status for a folder
func toggle_folder_ignored(folder_path: String):
	if is_folder_ignored(folder_path):
		remove_folder_from_ignored(folder_path)
	else:
		add_folder_to_ignored(folder_path)


## Check if a folder is directly ignored
func is_folder_ignored(folder_path: String) -> bool:
	var normalized_path = _normalize_folder_path(folder_path)
	return normalized_path in ignored_folders


## Check if an asset path is within an ignored folder
func is_in_ignored_folder(asset_path: String) -> bool:
	var normalized_asset = asset_path
	if not normalized_asset.begins_with("res://"):
		normalized_asset = "res://" + normalized_asset
	
	for ignored_folder in ignored_folders:
		# Check if the asset path starts with the ignored folder path
		if normalized_asset.begins_with(ignored_folder + "/") or normalized_asset == ignored_folder:
			return true
	
	return false


## Get all ignored folders
func get_ignored_folders() -> Array:
	return ignored_folders.duplicate()


## Get the parent folder of an asset path
func get_asset_folder(asset_path: String) -> String:
	var normalized_path = asset_path
	if not normalized_path.begins_with("res://"):
		normalized_path = "res://" + normalized_path
	
	return normalized_path.get_base_dir()


## Normalize folder path for consistent comparison
func _normalize_folder_path(folder_path: String) -> String:
	var normalized = folder_path
	
	# Ensure it starts with res://
	if not normalized.begins_with("res://"):
		normalized = "res://" + normalized
	
	# Remove trailing slash if present
	if normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	
	return normalized


## Add asset to recent list (called when asset is placed/used)
func mark_as_used(asset_path: String):
	# Remove if already in list
	if asset_path in recent_assets:
		recent_assets.erase(asset_path)
	
	# Add to front
	recent_assets.insert(0, asset_path)
	
	# Limit size
	if recent_assets.size() > MAX_RECENT_ASSETS:
		recent_assets.resize(MAX_RECENT_ASSETS)
	
	save_editor_settings()
	categories_updated.emit()


## Check if asset is in recent list
func is_recent(asset_path: String) -> bool:
	return asset_path in recent_assets


## Get recent assets
func get_recent_assets(limit: int = MAX_RECENT_ASSETS) -> Array:
	return recent_assets.slice(0, min(limit, recent_assets.size()))


## Get all unique folder categories from discovered assets
func get_all_folder_categories(assets: Array) -> Array:
	var categories_set = {}
	
	for asset in assets:
		if asset is Dictionary and asset.has("path"):
			var cats = extract_folder_categories(asset["path"])
			for cat in cats:
				categories_set[cat] = true
	
	var result = categories_set.keys()
	result.sort()
	return result


## Get all unique folder category paths with full hierarchy
## Returns array of dictionaries with "display" (full path) and "match" (leaf folder name)
func get_all_folder_category_paths(assets: Array) -> Array:
	var category_paths_set = {}
	
	for asset in assets:
		if asset is Dictionary and asset.has("path"):
			var cats = extract_folder_categories(asset["path"])
			
			# Build cumulative paths (e.g., "sample", "sample/assets", "sample/assets/blend")
			var path_parts = []
			for cat in cats:
				path_parts.append(cat)
				var full_path = " > ".join(path_parts)
				var leaf_name = cat
				
				# Store both display path and leaf name for matching
				if not category_paths_set.has(full_path):
					category_paths_set[full_path] = leaf_name
	
	# Convert to array and sort
	var result = []
	for path in category_paths_set.keys():
		result.append({"display": path, "match": category_paths_set[path]})
	
	# Sort by display path
	result.sort_custom(func(a, b): return a["display"] < b["display"])
	
	return result


## Build hierarchical category tree for display
## Returns nested dictionary structure
func build_category_tree(assets: Array) -> Dictionary:
	var tree = {}
	
	for asset in assets:
		if asset is Dictionary and asset.has("path"):
			var categories = extract_folder_categories(asset["path"])
			var current_node = tree
			
			for category in categories:
				if not current_node.has(category):
					current_node[category] = {}
				current_node = current_node[category]
	
	return tree








