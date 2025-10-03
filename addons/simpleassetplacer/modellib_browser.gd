@tool
extends Control

class_name ModelLibraryBrowser

const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/category_manager.gd")
const TagManagementDialog = preload("res://addons/simpleassetplacer/tag_management_dialog.gd")

signal asset_item_selected(asset_info: Dictionary)

var category_filter: OptionButton
var filter_options: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var discovered_assets: Array = []
var thumbnail_size: int = 64
var selected_item: AssetThumbnailItem = null
var current_search_text: String = ""
var current_category_filter: String = ""
var supported_extensions = ["obj", "fbx", "gltf", "glb", "dae", "blend", "tscn", "scn", "tres", "res"]
var category_manager: CategoryManager = null
var tag_management_dialog: TagManagementDialog = null
var manage_tags_button: Button = null

func _ready():
	setup_ui()

func setup_ui():
	# Set up the main container to fill the available space
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# Category filter with manage button
	var category_hbox = HBoxContainer.new()
	vbox.add_child(category_hbox)
	
	category_filter = OptionButton.new()
	category_filter.add_item("All Categories")
	category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_hbox.add_child(category_filter)
	
	manage_tags_button = Button.new()
	manage_tags_button.text = "Manage Tags..."
	manage_tags_button.tooltip_text = "Open advanced tag management dialog for bulk operations"
	manage_tags_button.custom_minimum_size = Vector2(110, 0)
	manage_tags_button.pressed.connect(_on_manage_tags_pressed)
	category_hbox.add_child(manage_tags_button)
	
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
	category_filter.item_selected.connect(_on_category_filter_changed)
	filter_options.item_selected.connect(_on_filter_changed)

func set_category_manager(manager: CategoryManager):
	category_manager = manager

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
	populate_category_filter()
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
						
						# Extract category information
						var folder_categories = []
						var custom_tags = []
						if category_manager:
							folder_categories = category_manager.extract_folder_categories(full_path)
							custom_tags = category_manager.get_custom_tags(full_path)
						
						var asset_info = {
							"path": full_path,
							"name": file_name.get_basename(),
							"extension": extension,
							"is_meshlib": false,
							"type": asset_type,
							"folder_categories": folder_categories,
							"custom_tags": custom_tags
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
		thumbnail_item.set_category_manager(category_manager)
		thumbnail_item.asset_item_selected.connect(_on_asset_item_selected)
		thumbnail_item.context_menu_requested.connect(_on_context_menu_requested)
		items_grid.add_child(thumbnail_item)

func get_filtered_assets() -> Array:
	var search_text = current_search_text.to_lower()
	var selected_filter = filter_options.get_selected_id()
	
	# Check if we're viewing ignored assets specifically
	var viewing_ignored = current_category_filter == "🚫 Ignored Assets"
	
	var filtered = []
	for asset in discovered_assets:
		var is_ignored = category_manager and category_manager.is_ignored(asset.path)
		
		# Filter based on ignored state and current view
		if viewing_ignored:
			# Only show ignored assets in this view
			if not is_ignored:
				continue
		else:
			# Skip ignored assets in all other views
			if is_ignored:
				continue
		
		# Search filter
		if search_text != "" and not asset.name.to_lower().contains(search_text):
			continue
		
		# Category filter
		if current_category_filter != "":
			var passes_category_filter = false
			
			# Handle special categories
			if current_category_filter == "⭐ Favorites":
				if category_manager and category_manager.is_favorite(asset.path):
					passes_category_filter = true
			elif current_category_filter == "🕐 Recent":
				if category_manager and category_manager.is_recent(asset.path):
					passes_category_filter = true
			elif current_category_filter == "🚫 Ignored Assets":
				# Already filtered above, so all remaining assets pass
				passes_category_filter = true
			else:
				# Remove leading spaces from hierarchical display
				var clean_category = current_category_filter.strip_edges()
				
				# Check folder categories
				if asset.has("folder_categories") and clean_category in asset.folder_categories:
					passes_category_filter = true
				
				# Check custom tags
				if asset.has("custom_tags") and clean_category in asset.custom_tags:
					passes_category_filter = true
			
			if not passes_category_filter:
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

func _on_category_filter_changed(index: int):
	if index == 0:
		current_category_filter = ""
	else:
		# Check if this item has metadata (for folder categories with full paths)
		var metadata = category_filter.get_item_metadata(index)
		if metadata != null:
			# Use the leaf folder name for matching
			current_category_filter = metadata
		else:
			# Use the display text (for special categories and custom tags)
			current_category_filter = category_filter.get_item_text(index)
	
	# Save the selected category to settings
	const SettingsManager = preload("res://addons/simpleassetplacer/settings_manager.gd")
	SettingsManager.set_plugin_setting("last_model_category", current_category_filter)
	SettingsManager.save_to_file()
	
	update_asset_grid()

func populate_category_filter():
	if not category_manager:
		return
	
	category_filter.clear()
	category_filter.add_item("All Categories")
	
	var last_category = ""
	var last_category_index = 0
	
	# Try to load the last selected category from settings
	const SettingsManager = preload("res://addons/simpleassetplacer/settings_manager.gd")
	last_category = SettingsManager.get_setting("last_model_category", "")
	
	# Add special categories first
	var favorites = category_manager.get_favorites()
	var recent = category_manager.get_recent_assets()
	var ignored = category_manager.get_ignored_assets()
	
	if favorites.size() > 0:
		category_filter.add_item("⭐ Favorites")
		if last_category == "⭐ Favorites":
			last_category_index = category_filter.get_item_count() - 1
	
	if recent.size() > 0:
		category_filter.add_item("🕐 Recent")
		if last_category == "🕐 Recent":
			last_category_index = category_filter.get_item_count() - 1
	
	if ignored.size() > 0:
		category_filter.add_item("🚫 Ignored Assets")
		if last_category == "🚫 Ignored Assets":
			last_category_index = category_filter.get_item_count() - 1
	
	if favorites.size() > 0 or recent.size() > 0 or ignored.size() > 0:
		category_filter.add_separator()
	
	# Get all folder categories with full paths
	var folder_category_paths = category_manager.get_all_folder_category_paths(discovered_assets)
	
	if folder_category_paths.size() > 0:
		category_filter.add_item("📁 Folder Categories")
		category_filter.set_item_disabled(category_filter.get_item_count() - 1, true)
		
		for cat_info in folder_category_paths:
			# Display full path, but store leaf name for matching
			category_filter.add_item("  " + cat_info["display"])
			# Store the leaf name in metadata for filtering
			category_filter.set_item_metadata(category_filter.get_item_count() - 1, cat_info["match"])
			# Check if this matches the last selected category
			if cat_info["match"] == last_category:
				last_category_index = category_filter.get_item_count() - 1
	
	# Get custom tags
	var custom_tags = category_manager.get_all_custom_tags()
	
	if custom_tags.size() > 0:
		if folder_category_paths.size() > 0:
			category_filter.add_separator()
		
		category_filter.add_item("🏷️ Custom Tags")
		category_filter.set_item_disabled(category_filter.get_item_count() - 1, true)
		
		for tag in custom_tags:
			category_filter.add_item("  " + tag)
			# Check if this matches the last selected category
			if tag == last_category:
				last_category_index = category_filter.get_item_count() - 1
	
	# Restore last category selection if found
	if last_category_index > 0:
		category_filter.select(last_category_index)
		# Update the filter (without saving again to avoid recursion)
		current_category_filter = last_category
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

func _on_context_menu_requested(asset_item: AssetThumbnailItem, position: Vector2):
	if not category_manager:
		return
	
	var asset_path = asset_item.get_asset_path()
	if asset_path.is_empty():
		return
	
	# Create popup menu
	var popup = PopupMenu.new()
	add_child(popup)
	
	# Build menu structure - use dict to map menu_id to action
	var menu_actions = {}
	var menu_id = 0
	
	# Folder categories section (display only, not actionable)
	var folder_cats = category_manager.extract_folder_categories(asset_path)
	if folder_cats.size() > 0:
		popup.add_item("📁 Folder Categories", menu_id)
		popup.set_item_disabled(menu_id, true)
		menu_id += 1
		
		for cat in folder_cats:
			popup.add_item("  " + cat, menu_id)
			popup.set_item_disabled(menu_id, true)
			menu_id += 1
		
		popup.add_separator()
		menu_id += 1
	
	# Recently used tags
	var recent_tags = category_manager.get_recently_used_tags(5)
	if recent_tags.size() > 0:
		popup.add_item("🕐 Recent Tags", menu_id)
		popup.set_item_disabled(menu_id, true)
		menu_id += 1
		
		var current_tags = category_manager.get_custom_tags(asset_path)
		for tag in recent_tags:
			var is_assigned = tag in current_tags
			var prefix = "✓ " if is_assigned else "  "
			popup.add_item(prefix + tag, menu_id)
			menu_actions[menu_id] = {"type": "tag", "name": tag, "assigned": is_assigned, "asset_path": asset_path}
			menu_id += 1
		
		popup.add_separator()
		menu_id += 1
	
	# All custom tags
	var all_tags = category_manager.get_all_custom_tags()
	if all_tags.size() > 0:
		popup.add_item("🏷️ All Tags...", menu_id)
		menu_actions[menu_id] = {"type": "all_tags_submenu", "asset_path": asset_path}
		menu_id += 1
	
	# New tag option
	popup.add_item("+ New Tag...", menu_id)
	menu_actions[menu_id] = {"type": "new_tag", "asset_path": asset_path}
	menu_id += 1
	
	popup.add_separator()
	menu_id += 1
	
	# Favorites
	var is_fav = category_manager.is_favorite(asset_path)
	var fav_text = "⭐ Remove from Favorites" if is_fav else "⭐ Add to Favorites"
	popup.add_item(fav_text, menu_id)
	menu_actions[menu_id] = {"type": "favorite", "asset_path": asset_path}
	menu_id += 1
	
	# Ignore asset
	var is_ignored = category_manager.is_ignored(asset_path)
	var ignore_text = "✓ Unignore Asset" if is_ignored else "🚫 Ignore Asset"
	popup.add_item(ignore_text, menu_id)
	menu_actions[menu_id] = {"type": "ignore", "asset_path": asset_path}
	menu_id += 1
	
	# Connect signal with proper dictionary
	popup.id_pressed.connect(func(id): _on_context_menu_item_selected(id, menu_actions, popup))
	
	# Show popup at cursor position
	popup.popup_on_parent(Rect2(position, Vector2.ZERO))

func _on_context_menu_item_selected(id: int, menu_actions: Dictionary, popup: PopupMenu):
	if not menu_actions.has(id):
		popup.queue_free()
		return
	
	var action = menu_actions[id]
	
	match action.get("type", ""):
		"tag":
			# Toggle tag
			var tag_name = action["name"]
			var asset_path = action.get("asset_path", "")
			if action["assigned"]:
				category_manager.remove_tag(asset_path, tag_name)
			else:
				category_manager.add_tag(asset_path, tag_name)
			category_manager.save_config_file()
			
			# Refresh asset data
			discover_assets()
		
		"new_tag":
			# Show dialog to create new tag
			_show_new_tag_dialog(action["asset_path"])
		
		"favorite":
			var asset_path = action["asset_path"]
			var was_favorite = category_manager.is_favorite(asset_path)
			category_manager.toggle_favorite(asset_path)
			
			# Update category filter dropdown (in case Favorites category needs to be added/removed)
			populate_category_filter()
			
			# Only regenerate the grid if necessary:
			# 1. We're viewing the Favorites category and the asset was removed from it
			# 2. We're viewing all assets (empty filter) - to update the favorite badge
			# If viewing other categories, the favorite status doesn't affect visibility
			if current_category_filter == "⭐ Favorites" and was_favorite:
				# Asset was removed from favorites, need to update grid
				update_asset_grid()
			elif current_category_filter == "":
				# Viewing all assets - could update badges, but that requires full regeneration
				# For now, skip update to avoid thumbnail regeneration
				# TODO: Add a refresh_badges() function to update badges without regenerating thumbnails
				pass
		
		"ignore":
			var asset_path = action["asset_path"]
			var was_ignored = category_manager.is_ignored(asset_path)
			category_manager.toggle_ignored(asset_path)
			
			# Update category filter dropdown (in case Ignored Assets category needs to be added/removed)
			populate_category_filter()
			
			# Update the grid if:
			# 1. We're viewing the Ignored Assets category
			# 2. We're viewing a category and the asset was removed/added
			if current_category_filter == "🚫 Ignored Assets":
				# Always update when viewing ignored assets
				update_asset_grid()
			elif not was_ignored:
				# Asset was just ignored, remove it from the current view
				update_asset_grid()
		
		"all_tags_submenu":
			# Show all tags dialog
			_show_all_tags_dialog(action.get("asset_path", ""))
	
	popup.queue_free()

func _show_new_tag_dialog(asset_path: String):
	# Create input dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Create New Tag"
	dialog.dialog_autowrap = true
	dialog.size = Vector2i(300, 150)
	add_child(dialog)
	
	# Create input field
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter tag name:"
	vbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "e.g., medieval, outdoor"
	vbox.add_child(line_edit)
	
	# Handle confirmation
	dialog.confirmed.connect(func():
		var tag_name = line_edit.text.strip_edges().to_lower()
		if tag_name.is_empty():
			return
		
		# Add tag to asset
		category_manager.add_tag(asset_path, tag_name)
		category_manager.save_config_file()
		
		# Refresh display
		discover_assets()
		
		dialog.queue_free()
	)
	
	# Handle cancel
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	# Show dialog
	dialog.popup_centered()
	line_edit.grab_focus()

func _show_all_tags_dialog(asset_path: String):
	# Create a dialog showing all available tags
	var dialog = AcceptDialog.new()
	dialog.title = "All Tags"
	dialog.dialog_autowrap = true
	dialog.size = Vector2i(350, 400)
	dialog.ok_button_text = "Close"
	add_child(dialog)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Click tags to toggle assignment:"
	vbox.add_child(label)
	
	# Scroll container for tags
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(scroll)
	
	var tags_vbox = VBoxContainer.new()
	scroll.add_child(tags_vbox)
	
	var all_tags = category_manager.get_all_custom_tags()
	var current_tags = category_manager.get_custom_tags(asset_path)
	
	for tag in all_tags:
		var checkbox = CheckBox.new()
		checkbox.text = tag
		checkbox.button_pressed = tag in current_tags
		checkbox.toggled.connect(func(pressed):
			if pressed:
				category_manager.add_tag(asset_path, tag)
			else:
				category_manager.remove_tag(asset_path, tag)
			category_manager.save_config_file()
			# Don't refresh immediately, let user select multiple
		)
		tags_vbox.add_child(checkbox)
	
	if all_tags.size() == 0:
		var no_tags = Label.new()
		no_tags.text = "No tags available. Create one with '+ New Tag...' option."
		tags_vbox.add_child(no_tags)
	
	# Handle dialog close
	dialog.confirmed.connect(func():
		discover_assets()  # Refresh after dialog closes
		dialog.queue_free()
	)
	
	dialog.popup_centered()

func _on_manage_tags_pressed() -> void:
	if not category_manager:
		return
	
	# Create dialog if it doesn't exist
	if not tag_management_dialog or not is_instance_valid(tag_management_dialog):
		tag_management_dialog = TagManagementDialog.new()
		# Add to the editor's root to ensure it appears properly
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			var base_control = editor_interface.get_base_control()
			base_control.add_child(tag_management_dialog)
		else:
			add_child(tag_management_dialog)
		
		# Connect to refresh signal
		tag_management_dialog.tags_modified.connect(_on_tags_modified_in_dialog)
	
	# Setup with current assets and show
	tag_management_dialog.setup(category_manager, discovered_assets)
	tag_management_dialog.popup_centered()

func _on_tags_modified_in_dialog() -> void:
	# Refresh the asset grid and category filter when tags are modified
	discover_assets()