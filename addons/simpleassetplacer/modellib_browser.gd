@tool
extends Control

class_name ModelLibraryBrowser

const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")

signal asset_item_selected(asset_info: Dictionary)

var filter_options: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var discovered_assets: Array = []
var thumbnail_size: int = 64
var selected_item: AssetThumbnailItem = null
var current_search_text: String = ""
var supported_extensions = ["obj", "fbx", "gltf", "glb", "dae", "blend", "tscn", "scn", "tres", "res"]

func _ready():
	setup_ui()

func setup_ui():
	# Set up the main container to fill the available space
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# Filter options for 3D models
	filter_options = OptionButton.new()
	filter_options.add_item("All Models")
	filter_options.add_item("OBJ Files")
	filter_options.add_item("FBX Files")
	filter_options.add_item("GLTF Files")
	filter_options.add_item("DAE Files")
	filter_options.add_item("Blend Files")
	filter_options.add_item("Scene Files")
	filter_options.add_item("TRES Files")
	filter_options.add_item("RES Files")
	vbox.add_child(filter_options)
	
	# Items scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(200, 300)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)
	
	# Items grid
	items_grid = GridContainer.new()
	items_grid.columns = 2  # 2 columns to fit in dock, will adjust dynamically
	items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	items_grid.add_theme_constant_override("h_separation", 12)
	items_grid.add_theme_constant_override("v_separation", 12)
	scroll_container.add_child(items_grid)
	
	# Connect signals
	filter_options.item_selected.connect(_on_filter_changed)

func update_grid_columns(available_width: float):
	if items_grid:
		# Calculate columns based on available width
		var item_width = thumbnail_size + 36  # Thumbnail + padding + text + margins
		var new_columns = max(1, int((available_width - 48) / item_width))
		items_grid.columns = min(new_columns, 3)  # Max 3 columns for model items

func update_thumbnail_size(new_size: int):
	thumbnail_size = new_size
	# Refresh the items display with new thumbnail size
	update_asset_grid()

func discover_assets():
	discovered_assets.clear()
	_scan_directory("res://")
	update_asset_grid()

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
							# Skip MeshLibraries in the model browser
							file_name = dir.get_next()
							continue
						elif resource != null:
							# Check if other .tres/.res files contain meshes
							has_mesh = _resource_contains_mesh(resource)
					elif extension in ["tscn", "scn"]:
						# For Godot scene files, check if they contain meshes
						has_mesh = _scene_file_contains_mesh(full_path)
					else:
						# For 3D model files (.fbx, .obj, .gltf, .blend, etc.), check if they contain meshes
						has_mesh = _model_file_contains_mesh(full_path)
					
					# Only add assets that have meshes but are not MeshLibraries
					if has_mesh and not is_meshlib:
						var asset_type = "3D Model"
						if extension in ["tscn", "scn"]:
							asset_type = "Scene"
						
						var asset_info = {
							"path": full_path,
							"name": file_name.get_basename(),
							"extension": extension,
							"is_meshlib": false,
							"type": asset_type
						}
						discovered_assets.append(asset_info)
			
			file_name = dir.get_next()

func _resource_contains_mesh(resource: Resource) -> bool:
	# Check if a .tres/.res resource contains mesh data
	if resource is Mesh:
		return true
	elif resource is PackedScene:
		# For PackedScene, assume it contains meshes for simplicity
		return true
	elif resource is Material or resource.get_class().contains("Material"):
		# Materials don't contain meshes
		return false
	elif resource.get_class().contains("Terrain") or resource.get_class().contains("terrain"):
		# Terrain resources don't contain meshes
		return false
	
	# Unknown resource type, assume it might contain a mesh
	return false

func _scene_file_contains_mesh(path: String) -> bool:
	# For Godot scene files, assume they contain meshes for now
	# This could be enhanced to actually parse the scene if needed
	return true

func _model_file_contains_mesh(path: String) -> bool:
	# For 3D model formats, assume they contain meshes
	# These are standard 3D model file formats, so they should contain meshes
	return true

func clear_items():
	for child in items_grid.get_children():
		child.queue_free()

func update_asset_grid():
	clear_items()
	
	# Filter assets based on search and filter
	var filtered_assets = get_filtered_assets()
	
	# Create thumbnail items for each asset
	for asset in filtered_assets:
		var thumbnail_item = AssetThumbnailItem.create_for_asset(asset, thumbnail_size)
		thumbnail_item.asset_item_selected.connect(_on_asset_item_selected)
		items_grid.add_child(thumbnail_item)

func get_filtered_assets() -> Array:
	var search_text = current_search_text.to_lower()
	var selected_filter = filter_options.get_selected_id()
	
	var filtered = []
	for asset in discovered_assets:
		# Search filter
		if search_text != "" and not asset.name.to_lower().contains(search_text):
			continue
		
		# Extension filter
		match selected_filter:
			1: # OBJ Files only
				if asset.extension != "obj":
					continue
			2: # FBX Files only
				if asset.extension != "fbx":
					continue
			3: # GLTF Files only
				if not asset.extension in ["gltf", "glb"]:
					continue
			4: # DAE Files only
				if asset.extension != "dae":
					continue
			5: # Blend Files only
				if asset.extension != "blend":
					continue
			6: # Scene Files only
				if not asset.extension in ["tscn", "scn"]:
					continue
			7: # TRES Files only
				if asset.extension != "tres":
					continue
			8: # RES Files only
				if asset.extension != "res":
					continue
		
		filtered.append(asset)
	
	return filtered

func _on_filter_changed(index: int):
	update_asset_grid()

func _on_asset_item_selected(asset_info: Dictionary):
	# Clear previous selection
	if selected_item and is_instance_valid(selected_item):
		selected_item.set_selected(false)
	
	# Find the new selected item
	selected_item = null
	
	# Find the corresponding AssetThumbnailItem
	for child in items_grid.get_children():
		if child is AssetThumbnailItem:
			if child.get_asset_info() == asset_info:
				selected_item = child
				child.set_selected(true)
				break
	
	asset_item_selected.emit(asset_info)

func set_search_text(text: String):
	current_search_text = text
	update_asset_grid()