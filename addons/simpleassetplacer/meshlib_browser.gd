@tool
extends Control

class_name MeshLibraryBrowser

const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/category_manager.gd")
const TagManagementDialog = preload("res://addons/simpleassetplacer/tag_management_dialog.gd")

signal meshlib_item_selected(meshlib: MeshLibrary, item_id: int)

var category_filter: OptionButton
var meshlib_option: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var current_meshlib: MeshLibrary
var current_meshlib_path: String = ""
var thumbnail_size: int = 64
var selected_item_id: int = -1
var selected_button: AssetThumbnailItem = null
var current_search_text: String = ""
var current_category_filter: String = ""
var category_manager: CategoryManager = null
var meshlib_items_data: Array = []  # Store item metadata
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
	
	meshlib_option = OptionButton.new()
	meshlib_option.add_item("Select MeshLibrary...")
	vbox.add_child(meshlib_option)
	
	# Items scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(200, 300)
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
	meshlib_option.item_selected.connect(_on_meshlib_selected)

func set_category_manager(manager: CategoryManager):
	category_manager = manager

func update_grid_columns(available_width: float):
	if items_grid:
		# Calculate columns based on available width
		var item_width = thumbnail_size + 36  # Thumbnail + padding + text + margins
		var new_columns = max(1, int((available_width - 48) / item_width))
		items_grid.columns = min(new_columns, 3)  # Max 3 columns for meshlib items

func update_thumbnail_size(new_size: int):
	thumbnail_size = new_size
	# Refresh the items display with new thumbnail size
	if current_meshlib:
		populate_meshlib_items(current_meshlib)

func set_search_text(search_text: String):
	current_search_text = search_text
	# Refresh the items display with new search filter
	if current_meshlib:
		update_meshlib_grid()

func populate_meshlib_options(meshlib_paths: Array):
	meshlib_option.clear()
	meshlib_option.add_item("Select MeshLibrary...")
	
	for path in meshlib_paths:
		var meshlib_name = path.get_file().get_basename()
		meshlib_option.add_item(meshlib_name)
		meshlib_option.set_item_metadata(meshlib_option.get_item_count() - 1, path)

func _on_meshlib_selected(index: int):
	if index == 0:  # "Select MeshLibrary..." option
		current_meshlib = null
		current_meshlib_path = ""
		meshlib_items_data.clear()
		clear_items()
		return
	
	var meshlib_path = meshlib_option.get_item_metadata(index)
	var meshlib = load(meshlib_path)
	
	if meshlib is MeshLibrary:
		current_meshlib = meshlib
		current_meshlib_path = meshlib_path
		populate_meshlib_items(meshlib)
		populate_category_filter()

func clear_items():
	for child in items_grid.get_children():
		child.queue_free()

func populate_meshlib_items(meshlib: MeshLibrary):
	clear_items()
	meshlib_items_data.clear()
	
	var item_ids = meshlib.get_item_list()
	
	# Build item metadata with category info
	for item_id in item_ids:
		var item_name = meshlib.get_item_name(item_id)
		if item_name == "":
			item_name = "Item " + str(item_id)
		
		var item_data = {
			"id": item_id,
			"name": item_name,
			"meshlib_path": current_meshlib_path,
			"folder_categories": [],
			"custom_tags": []
		}
		
		# Extract categories from meshlib path
		if category_manager and not current_meshlib_path.is_empty():
			item_data["folder_categories"] = category_manager.extract_folder_categories(current_meshlib_path)
			# Use meshlib path + item name as key for custom tags
			var tag_key = current_meshlib_path + ":" + item_name
			item_data["custom_tags"] = category_manager.get_custom_tags(tag_key)
		
		meshlib_items_data.append(item_data)
	
	# Apply filters and display items
	update_meshlib_grid()

func update_meshlib_grid():
	clear_items()
	
	var filtered_items = get_filtered_meshlib_items()
	
	for item_data in filtered_items:
		# Create thumbnail item using the new AssetThumbnailItem class
		var thumbnail_item = AssetThumbnailItem.new(current_meshlib, item_data["id"], thumbnail_size)
		thumbnail_item.thumbnail_item_selected.connect(_on_meshlib_item_selected)
		items_grid.add_child(thumbnail_item)

func get_filtered_meshlib_items() -> Array:
	var filtered = []
	
	for item_data in meshlib_items_data:
		# Search filter
		if current_search_text != "":
			if not item_data["name"].to_lower().contains(current_search_text.to_lower()):
				continue
		
		# Category filter
		if current_category_filter != "":
			var passes_category_filter = false
			
			# Handle special categories
			if current_category_filter == "⭐ Favorites":
				if category_manager:
					var fav_key = item_data["meshlib_path"] + ":" + item_data["name"]
					if category_manager.is_favorite(fav_key):
						passes_category_filter = true
			elif current_category_filter == "🕐 Recent":
				if category_manager:
					var recent_key = item_data["meshlib_path"] + ":" + item_data["name"]
					if category_manager.is_recent(recent_key):
						passes_category_filter = true
			else:
				# Remove leading spaces from hierarchical display
				var clean_category = current_category_filter.strip_edges()
				
				# Check folder categories
				if clean_category in item_data["folder_categories"]:
					passes_category_filter = true
				
				# Check custom tags
				if clean_category in item_data["custom_tags"]:
					passes_category_filter = true
			
			if not passes_category_filter:
				continue
		
		filtered.append(item_data)
	
	return filtered

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int):
	# Clear previous selection
	if selected_button and is_instance_valid(selected_button):
		if selected_button is AssetThumbnailItem:
			selected_button.set_selected(false)
	
	# Find the new selected button
	selected_item_id = item_id
	selected_button = null
	
	# Find the corresponding AssetThumbnailItem
	for child in items_grid.get_children():
		if child is AssetThumbnailItem:
			if child.get_item_id() == item_id:
				selected_button = child
				child.set_selected(true)
				break
	
	meshlib_item_selected.emit(meshlib, item_id)

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
	update_meshlib_grid()

func populate_category_filter():
	if not category_manager:
		return
	
	category_filter.clear()
	category_filter.add_item("All Categories")
	
	# Add special categories first
	var has_special = false
	
	# Note: For MeshLib items, we use meshlib_path:item_name as the key
	# Check if any items are favorited or recent
	for item_data in meshlib_items_data:
		var item_key = item_data["meshlib_path"] + ":" + item_data["name"]
		if category_manager.is_favorite(item_key) or category_manager.is_recent(item_key):
			has_special = true
			break
	
	if has_special:
		# Only show if items exist in these categories
		var has_favorites = false
		var has_recent = false
		
		for item_data in meshlib_items_data:
			var item_key = item_data["meshlib_path"] + ":" + item_data["name"]
			if category_manager.is_favorite(item_key):
				has_favorites = true
			if category_manager.is_recent(item_key):
				has_recent = true
		
		if has_favorites:
			category_filter.add_item("⭐ Favorites")
		if has_recent:
			category_filter.add_item("🕐 Recent")
		
		category_filter.add_separator()
	
	# Get all folder categories from meshlib path with full hierarchy
	var folder_categories = []
	if not current_meshlib_path.is_empty():
		folder_categories = category_manager.extract_folder_categories(current_meshlib_path)
	
	if folder_categories.size() > 0:
		category_filter.add_item("📁 Folder Categories")
		category_filter.set_item_disabled(category_filter.get_item_count() - 1, true)
		
		# Build cumulative path for display
		var path_parts = []
		for cat in folder_categories:
			path_parts.append(cat)
			var full_path = " > ".join(path_parts)
			category_filter.add_item("  " + full_path)
			# Store leaf name for matching
			category_filter.set_item_metadata(category_filter.get_item_count() - 1, cat)
	
	# Get custom tags used by any item
	var all_tags_set = {}
	for item_data in meshlib_items_data:
		for tag in item_data["custom_tags"]:
			all_tags_set[tag] = true
	
	var custom_tags = all_tags_set.keys()
	custom_tags.sort()
	
	if custom_tags.size() > 0:
		if folder_categories.size() > 0:
			category_filter.add_separator()
		
		category_filter.add_item("🏷️ Custom Tags")
		category_filter.set_item_disabled(category_filter.get_item_count() - 1, true)
		
		for tag in custom_tags:
			category_filter.add_item("  " + tag)

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
	
	# Setup with current meshlib items data and show
	tag_management_dialog.setup(category_manager, meshlib_items_data)
	tag_management_dialog.popup_centered()

func _on_tags_modified_in_dialog() -> void:
	# Refresh the meshlib display when tags are modified
	if current_meshlib:
		populate_meshlib_items(current_meshlib)
