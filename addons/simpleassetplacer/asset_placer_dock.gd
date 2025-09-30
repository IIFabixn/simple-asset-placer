@tool
extends Control

class_name AssetPlacerDock

const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")
const MeshLibraryBrowser = preload("res://addons/simpleassetplacer/meshlib_browser.gd")
const ModelLibraryBrowser = preload("res://addons/simpleassetplacer/modellib_browser.gd")
const PlacementSettings = preload("res://addons/simpleassetplacer/placement_settings.gd")
const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")

signal asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary)
signal meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary)

# UI Components
var search_line_edit: LineEdit
var refresh_button: Button

var tab_container: TabContainer
var models_tab: Control
var meshlib_tab: Control
var scroll_container: ScrollContainer
var grid_container: GridContainer
var meshlib_browser: MeshLibraryBrowser
var modellib_browser: ModelLibraryBrowser
var placement_settings: PlacementSettings
var settings_tab: Control
var thumbnail_size: int = 64

# Asset Management
var discovered_assets: Array = []
var mesh_thumbnails: Dictionary = {}
var supported_extensions = ["obj", "fbx", "dae", "gltf", "glb", "blend", "tscn", "scn", "tres", "res", "meshlib"]

# Thumbnail generation queue to prevent conflicts
var thumbnail_queue: Array = []
var is_generating_thumbnails: bool = false

func _ready():
	name = "Asset Placer"
	setup_ui()
	discover_assets()

func setup_ui():
	set_custom_minimum_size(Vector2(200, 400))
	
	# Use anchors and offsets to fill the entire available space
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 8)
	main_margin.add_theme_constant_override("margin_right", 8)
	main_margin.add_theme_constant_override("margin_top", 8)
	main_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(main_margin)
	
	# Main layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	main_margin.add_child(vbox)
	
	# Header with search and refresh
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	# Search field
	search_line_edit = LineEdit.new()
	search_line_edit.placeholder_text = "Search assets..."
	search_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(search_line_edit)
	
	# Refresh button
	refresh_button = Button.new()
	refresh_button.text = "🔄"
	refresh_button.tooltip_text = "Refresh asset list"
	header.add_child(refresh_button)
	
	# Tab container for different asset types
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_container)
	
	# Models tab - now using ModelLibraryBrowser
	models_tab = Control.new()
	models_tab.name = "3D Models"
	tab_container.add_child(models_tab)
	
	# Add margin container for models tab
	var models_margin = MarginContainer.new()
	models_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	models_margin.add_theme_constant_override("margin_left", 8)
	models_margin.add_theme_constant_override("margin_right", 8)
	models_margin.add_theme_constant_override("margin_top", 8)
	models_margin.add_theme_constant_override("margin_bottom", 8)
	models_tab.add_child(models_margin)
	
	# Create ModelLibraryBrowser
	modellib_browser = ModelLibraryBrowser.new()
	modellib_browser.asset_item_selected.connect(_on_asset_selected)
	models_margin.add_child(modellib_browser)
	
	# MeshLibrary tab
	meshlib_tab = Control.new()
	meshlib_tab.name = "MeshLibraries"
	tab_container.add_child(meshlib_tab)
	
	# Add a margin container for better layout
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	meshlib_tab.add_child(margin)
	
	meshlib_browser = MeshLibraryBrowser.new()
	meshlib_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meshlib_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(meshlib_browser)
	
	# Initialize search state for meshlib browser
	if search_line_edit:
		meshlib_browser.set_search_text(search_line_edit.text)
	
	# Settings tab
	settings_tab = Control.new()
	settings_tab.name = "Settings"
	tab_container.add_child(settings_tab)
	
	# Add margin container for settings tab
	var settings_margin = MarginContainer.new()
	settings_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_margin.add_theme_constant_override("margin_left", 8)
	settings_margin.add_theme_constant_override("margin_right", 8)
	settings_margin.add_theme_constant_override("margin_top", 8)
	settings_margin.add_theme_constant_override("margin_bottom", 8)
	settings_tab.add_child(settings_margin)
	
	placement_settings = PlacementSettings.new()
	placement_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_margin.add_child(placement_settings)
	
	# Connect signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	search_line_edit.text_changed.connect(_on_search_changed)
	meshlib_browser.meshlib_item_selected.connect(_on_meshlib_item_selected)
	placement_settings.cache_cleared.connect(_on_cache_cleared)
	
	# Connect to resize events to adjust layout dynamically
	resized.connect(_on_dock_resized)
	
	# Call initial responsive sizing
	call_deferred("update_responsive_sizes")

func _on_dock_resized():
	# Calculate responsive thumbnail size based on available space
	update_responsive_sizes()
	
	# Adjust grid columns based on available width - fully adaptive
	if grid_container:
		var available_width = get_rect().size.x - 60  # Account for scroll margins
		var item_width = thumbnail_size + 16  # AssetThumbnailItem width (thumbnail + margins)
		var spacing = 12  # Grid separation - match grid_container settings
		
		# Calculate how many columns can fit with proper spacing
		var columns_that_fit = 1
		var total_width_needed = item_width
		
		# Keep adding columns while they fit (with 20px buffer for safety)
		while total_width_needed + spacing + item_width <= available_width - 20:
			columns_that_fit += 1
			total_width_needed += spacing + item_width
		
		grid_container.columns = max(1, columns_that_fit)
	
	# Also update both browser grids
	if meshlib_browser:
		meshlib_browser.update_grid_columns(get_rect().size.x)
	if modellib_browser:
		modellib_browser.update_grid_columns(get_rect().size.x)

func update_responsive_sizes():
	var dock_width = get_rect().size.x
	var old_thumbnail_size = thumbnail_size
	
	# Calculate optimal thumbnail size within 64-128px range based on available space
	var available_width = dock_width - 60  # Account for scroll margins
	var grid_spacing = 12   # Space between grid items - match grid_container settings
	
	# Start with minimum size and see how many columns we can fit
	var best_thumbnail_size = 64
	var best_columns = 1
	
	# Test different thumbnail sizes to find the best fit
	for test_size in range(64, 129, 8):  # Test in 8px increments from 64 to 128
		var test_item_width = test_size + 16  # AssetThumbnailItem width calculation
		var columns = 1
		var total_width = test_item_width
		
		# Calculate how many columns fit with this thumbnail size (with 20px buffer)
		while total_width + grid_spacing + test_item_width <= available_width - 20:
			columns += 1
			total_width += grid_spacing + test_item_width
		
		# Prefer more columns, but not at the expense of too-small thumbnails
		if columns > best_columns or (columns == best_columns and test_size > best_thumbnail_size):
			best_thumbnail_size = test_size
			best_columns = columns
	
	thumbnail_size = clamp(best_thumbnail_size, 64, 128)
	
	# Only refresh if size actually changed
	if old_thumbnail_size != thumbnail_size:
		# Update meshlib browser thumbnail size
		if meshlib_browser:
			meshlib_browser.update_thumbnail_size(thumbnail_size)
		
		# Update modellib browser thumbnail size
		if modellib_browser:
			modellib_browser.update_thumbnail_size(thumbnail_size)
		
		# Update existing thumbnail items or refresh grid
		if grid_container:
			var needs_refresh = false
			for child in grid_container.get_children():
				if child is AssetThumbnailItem:
					child.update_thumbnail_size(thumbnail_size)
				else:
					needs_refresh = true
			
			# If there are non-AssetThumbnailItem children, refresh the grid
			if needs_refresh:
				update_asset_grid()

func discover_assets():
	discovered_assets.clear()
	_scan_directory("res://")
	update_meshlib_browser()
	# Discover assets for the model library browser
	if modellib_browser:
		modellib_browser.discover_assets()

func _scan_directory(path: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			var full_path = path + "/" + file_name
			
			if dir.current_is_dir() and not file_name.begins_with("."):
				# Skip .godot and other hidden directories
				if file_name != ".godot":
					_scan_directory(full_path)
			else:
				var extension = file_name.get_extension().to_lower()
				if extension in supported_extensions:
					# Check if it's a MeshLibrary resource
					var is_meshlib = false
					var has_mesh = false
					
					if extension in ["tres", "res", "meshlib"]:
						# Try to load resource safely
						var resource = null
						if ResourceLoader.exists(full_path):
							resource = load(full_path)
						
						if resource != null and resource is MeshLibrary:
							is_meshlib = true
							has_mesh = true  # MeshLibraries are always valid
						elif resource != null:
							# Check if other .tres/.res files contain meshes
							has_mesh = _resource_contains_mesh(resource)
					elif extension in ["tscn", "scn"]:
						# For Godot scene files, check if they contain meshes
						has_mesh = _scene_file_contains_mesh(full_path)
					else:
						# For 3D model files (.fbx, .obj, .gltf, .blend, etc.), check if they contain meshes
						has_mesh = _model_file_contains_mesh(full_path)
					
					# Only add assets that have meshes or are MeshLibraries
					if has_mesh:
						var asset_type = "MeshLibrary"
						if not is_meshlib:
							if extension in ["tscn", "scn"]:
								asset_type = "Scene"
							else:
								asset_type = "3D Model"
						
						var asset_info = {
							"path": full_path,
							"name": file_name.get_basename(),
							"extension": extension,
							"is_meshlib": is_meshlib,
							"type": asset_type
						}
						discovered_assets.append(asset_info)
			
			file_name = dir.get_next()

func update_asset_grid():
	# This function is no longer needed since the models tab now uses ModelLibraryBrowser
	# The grid_container is no longer used for the models tab
	pass

func get_filtered_assets() -> Array:
	# This function is no longer needed since filtering is handled by ModelLibraryBrowser
	# Return empty array to maintain compatibility
	return []

func update_meshlib_browser():
	# Get all MeshLibrary paths
	var meshlib_paths = []
	for asset in discovered_assets:
		if asset.is_meshlib:
			meshlib_paths.append(asset.path)
	
	meshlib_browser.populate_meshlib_options(meshlib_paths)

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int):
	var settings = placement_settings.get_placement_settings()
	meshlib_item_selected.emit(meshlib, item_id, settings)

func create_asset_thumbnail(asset_info: Dictionary):
	# Create the thumbnail item using our dedicated control
	var thumbnail_item = AssetThumbnailItem.create_for_asset(asset_info, thumbnail_size)
	
	# Connect signals
	thumbnail_item.asset_item_selected.connect(_on_asset_selected)
	
	# Add to grid
	grid_container.add_child(thumbnail_item)

func generate_thumbnail_for_asset(asset_info: Dictionary, thumbnail_rect: TextureRect):
	# Generate actual 3D thumbnail
	if asset_info.is_meshlib:
		# Use placeholder for MeshLibrary for now
		thumbnail_rect.texture = EditorInterface.get_editor_theme().get_icon("MeshLibrary", "EditorIcons")
	else:
		# Generate 3D mesh thumbnail asynchronously
		_generate_mesh_thumbnail_async(asset_info, thumbnail_rect)

func _generate_mesh_thumbnail_async(asset_info: Dictionary, thumbnail_rect: TextureRect):
	# Set placeholder first
	thumbnail_rect.texture = EditorInterface.get_editor_theme().get_icon("MeshInstance3D", "EditorIcons")
	
	# Queue thumbnail generation to avoid simultaneous generation conflicts
	_queue_thumbnail_generation(asset_info, thumbnail_rect)

func _on_asset_selected(asset_info: Dictionary):
	# Load the resource and emit signal
	var resource = load(asset_info.path)
	if resource:
		var settings = placement_settings.get_placement_settings()
		asset_selected.emit(asset_info.path, resource, settings)
	else:
		print("AssetPlacerDock: Failed to load resource: ", asset_info.path)

func _on_thumbnail_gui_input(event: InputEvent, asset_info: Dictionary):
	# For now, just handle click - drag and drop can be added later
	pass

func create_drag_preview(asset_info: Dictionary) -> Control:
	var preview = Label.new()
	preview.text = asset_info.name
	preview.add_theme_color_override("font_color", Color.WHITE)
	preview.add_theme_color_override("font_shadow_color", Color.BLACK)
	return preview

func _on_refresh_pressed():
	discover_assets()

func _on_search_changed(new_text: String):
	# Update MeshLibrary browser search
	if meshlib_browser:
		meshlib_browser.set_search_text(new_text)
	# Also update ModelLibrary browser search
	if modellib_browser:
		modellib_browser.set_search_text(new_text)



func _on_cache_cleared():
	# Clear any pending thumbnail queue
	thumbnail_queue.clear()
	is_generating_thumbnails = false
	# Refresh both browsers to regenerate thumbnails
	if modellib_browser:
		modellib_browser.update_asset_grid()

func _queue_thumbnail_generation(asset_info: Dictionary, thumbnail_rect: TextureRect):
	# Add to queue
	thumbnail_queue.append({"asset_info": asset_info, "thumbnail_rect": thumbnail_rect})
	
	# Start processing if not already running
	if not is_generating_thumbnails:
		_process_thumbnail_queue()

func _process_thumbnail_queue():
	if thumbnail_queue.is_empty():
		is_generating_thumbnails = false
		return
	
	is_generating_thumbnails = true
	var item = thumbnail_queue.pop_front()
	var asset_info = item.asset_info
	var thumbnail_rect = item.thumbnail_rect
	
	# Check if thumbnail_rect is still valid (UI might have been refreshed)
	if not is_instance_valid(thumbnail_rect):
		# Skip and continue with next
		_process_thumbnail_queue()
		return
	
	# Generate thumbnail
	var thumbnail = await ThumbnailGenerator.generate_mesh_thumbnail(asset_info.path)
	
	# Apply thumbnail if successful and UI element still valid
	if thumbnail and is_instance_valid(thumbnail_rect):
		thumbnail_rect.texture = thumbnail
	
	# Continue with next item in queue
	_process_thumbnail_queue()

func _resource_contains_mesh(resource: Resource) -> bool:
	# Check if a .tres/.res resource contains mesh data
	if resource is Mesh:
		return true
	elif resource is PackedScene:
		# Check if the scene contains mesh instances
		var scene_instance = resource.instantiate()
		var has_mesh = _scene_has_mesh_recursive(scene_instance)
		scene_instance.queue_free()
		return has_mesh
	elif resource is Material or resource.get_class().contains("Material"):
		# Materials don't contain meshes
		return false
	elif resource.get_class().contains("Terrain") or resource.get_class().contains("terrain"):
		# Terrain resources don't contain meshes
		return false
	
	# Unknown resource type, assume it might contain a mesh
	return false

func _model_file_contains_mesh(file_path: String) -> bool:
	# Check if a 3D model file (.fbx, .obj, .gltf, .blend, etc.) contains meshes
	if not ResourceLoader.exists(file_path):
		return false
	
	var resource = load(file_path)
	if not resource:
		return false
	
	if resource is Mesh:
		return true
	elif resource is PackedScene:
		# Check if the scene contains mesh instances
		var scene_instance = resource.instantiate()
		var has_mesh = _scene_has_mesh_recursive(scene_instance)
		scene_instance.queue_free()
		return has_mesh
	
	return false

func _scene_has_mesh_recursive(node: Node) -> bool:
	# Check if this node or any child contains a mesh
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			return true
	
	# Also check for ImporterMeshInstance3D (used during import process)
	if node.get_class() == "ImporterMeshInstance3D":
		if node.has_method("get_mesh") and node.get_mesh():
			return true
	
	# Recursively check children
	for child in node.get_children():
		if _scene_has_mesh_recursive(child):
			return true
	
	return false

func _scene_file_contains_mesh(file_path: String) -> bool:
	# Check if a Godot scene file (.tscn, .scn) contains meshes
	if not ResourceLoader.exists(file_path):
		return false
	
	var scene_resource = load(file_path)
	if not scene_resource or not scene_resource is PackedScene:
		return false
	
	# Instantiate the scene and check for meshes
	var scene_instance = scene_resource.instantiate()
	var has_mesh = _scene_has_mesh_recursive(scene_instance)
	scene_instance.queue_free()
	return has_mesh

func get_placement_settings() -> Dictionary:
	"""Get current placement settings from the settings component"""
	if placement_settings and placement_settings.has_method("get_placement_settings"):
		return placement_settings.get_placement_settings()
	return {}