@tool
extends Control

class_name MeshLibraryBrowser

const AssetThumbnailItem = preload("res://addons/simpleassetplacer/ui/asset_thumbnail_item.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/managers/category_manager.gd")
const TagManagementDialog = preload("res://addons/simpleassetplacer/ui/tag_management_dialog.gd")
const LayoutCalculator = preload("res://addons/simpleassetplacer/utils/layout_calculator.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

signal meshlib_item_selected(meshlib: MeshLibrary, item_id: int)

# Dependency injection
var _services: ServiceRegistry = null
var _thumbnail_queue_manager = null

# UI state
var category_filter: OptionButton
var meshlib_option: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var current_meshlib: MeshLibrary
var current_meshlib_path: String = ""
var thumbnail_size: int = LayoutCalculator.THUMBNAIL_SIZE_DEFAULT  # Use optimized default size
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
	
	# Category filter with manage button (side-by-side)
	var category_hbox = HBoxContainer.new()
	vbox.add_child(category_hbox)
	
	category_filter = OptionButton.new()
	category_filter.add_item("All Categories")
	category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_filter.clip_text = true  # Enable text clipping for long names
	category_hbox.add_child(category_filter)
	
	manage_tags_button = Button.new()
	manage_tags_button.text = "Manage Tags..."
	manage_tags_button.tooltip_text = "Open advanced tag management dialog for bulk operations"
	manage_tags_button.size_flags_horizontal = Control.SIZE_SHRINK_END  # Shrink to content
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

func set_services(services: ServiceRegistry) -> void:
	"""Inject ServiceRegistry for access to managers"""
	_services = services
	if _services and _services.thumbnail_queue_manager:
		_thumbnail_queue_manager = _services.thumbnail_queue_manager

func update_grid_columns(available_width: float):
	if items_grid:
		# Use LayoutCalculator for consistent grid calculation
		# Calculate columns based on actual thumbnail size (margins added internally)
		var columns = LayoutCalculator.calculate_grid_columns(available_width - 48, thumbnail_size, 12, 20)
		items_grid.columns = columns  # Fully adaptive - no artificial limit

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
	
	var last_meshlib_path = ""
	var last_meshlib_index = 0
	
	# Try to load the last selected meshlib from settings
	if _services and _services.settings_manager:
		last_meshlib_path = _services.settings_manager.get_setting("last_meshlib_path", "")
	
	for path in meshlib_paths:
		var meshlib_name = path.get_file().get_basename()
		meshlib_option.add_item(meshlib_name)
		meshlib_option.set_item_metadata(meshlib_option.get_item_count() - 1, path)
		
		# Check if this is the last selected meshlib
		if path == last_meshlib_path:
			last_meshlib_index = meshlib_option.get_item_count() - 1
	
	# Restore last selection if found
	if last_meshlib_index > 0:
		meshlib_option.select(last_meshlib_index)
		# Trigger the selection to load the meshlib
		call_deferred("_restore_last_meshlib", last_meshlib_index)

func _restore_last_meshlib(index: int):
	"""Restore the last selected meshlib (called deferred to ensure UI is ready)"""
	_on_meshlib_selected(index)

func _on_meshlib_selected(index: int):
	if index == 0:  # "Select MeshLibrary..." option
		current_meshlib = null
		current_meshlib_path = ""
		meshlib_items_data.clear()
		clear_items()
		# Clear the saved selection
		if _services and _services.settings_manager:
			_services.settings_manager.set_plugin_setting("last_meshlib_path", "")
			_services.settings_manager.save_plugin_settings_to_editor()
		return
	
	var meshlib_path = meshlib_option.get_item_metadata(index)
	var meshlib = load(meshlib_path)
	
	if meshlib is MeshLibrary:
		current_meshlib = meshlib
		current_meshlib_path = meshlib_path
		populate_meshlib_items(meshlib)
		populate_category_filter()
		
		# Save the selected meshlib path to settings
		if _services and _services.settings_manager:
			_services.settings_manager.set_plugin_setting("last_meshlib_path", meshlib_path)
			_services.settings_manager.save_plugin_settings_to_editor()

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
		if _thumbnail_queue_manager:
			thumbnail_item.set_queue_manager(_thumbnail_queue_manager)
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
	
	# Save the selected category to settings
	if _services and _services.settings_manager:
		_services.settings_manager.set_plugin_setting("last_meshlib_category", current_category_filter)
		_services.settings_manager.save_plugin_settings_to_editor()
	
	update_meshlib_grid()

func populate_category_filter():
	if not category_manager:
		return
	
	category_filter.clear()
	category_filter.add_item("All Categories")
	
	var last_category = ""
	var last_category_index = 0
	
	# Try to load the last selected category from settings
	if _services and _services.settings_manager:
		last_category = _services.settings_manager.get_setting("last_meshlib_category", "")
	
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
			if last_category == "⭐ Favorites":
				last_category_index = category_filter.get_item_count() - 1
		if has_recent:
			category_filter.add_item("🕐 Recent")
			if last_category == "🕐 Recent":
				last_category_index = category_filter.get_item_count() - 1
		
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
			var display_text = "  " + full_path
			category_filter.add_item(display_text)
			var item_index = category_filter.get_item_count() - 1
			# Store leaf name for matching
			category_filter.set_item_metadata(item_index, cat)
			# Add tooltip for long paths to show full hierarchy
			if display_text.length() > 25:
				category_filter.set_item_tooltip(item_index, full_path)
			# Check if this matches the last selected category
			if cat == last_category:
				last_category_index = item_index
	
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
			var display_text = "  " + tag
			category_filter.add_item(display_text)
			var item_index = category_filter.get_item_count() - 1
			# Add tooltip for long tag names
			if display_text.length() > 25:
				category_filter.set_item_tooltip(item_index, tag)
			# Check if this matches the last selected category
			if tag == last_category:
				last_category_index = item_index
	
	# Restore last category selection if found
	if last_category_index > 0:
		category_filter.select(last_category_index)
		# Update the filter (without saving again to avoid recursion)
		current_category_filter = last_category
		update_meshlib_grid()

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

## Asset Cycling

func cycle_to_next_item() -> bool:
	"""Cycle to the next meshlib item in the currently visible grid. Returns true if successful."""
	return _cycle_meshlib_item(1)

func cycle_to_previous_item() -> bool:
	"""Cycle to the previous meshlib item in the currently visible grid. Returns true if successful."""
	return _cycle_meshlib_item(-1)

func _cycle_meshlib_item(direction: int) -> bool:
	"""Internal method to cycle through meshlib items in the given direction (1 = next, -1 = previous)"""
	if not current_meshlib:
		return false
	
	# Get all visible item buttons
	var visible_items: Array[AssetThumbnailItem] = []
	for child in items_grid.get_children():
		if child is AssetThumbnailItem and child.visible:
			visible_items.append(child)
	
	if visible_items.is_empty():
		return false
	
	# Find current selection index
	var current_index = -1
	if selected_button and is_instance_valid(selected_button):
		current_index = visible_items.find(selected_button)
	
	# Calculate next index with wrap-around
	var next_index: int
	if current_index == -1:
		# No selection, start at beginning or end depending on direction
		next_index = 0 if direction > 0 else visible_items.size() - 1
	else:
		next_index = (current_index + direction) % visible_items.size()
		# Handle negative modulo for wrap-around
		if next_index < 0:
			next_index += visible_items.size()
	
	# Select the new item
	var next_button = visible_items[next_index]
	var next_item_id = next_button.get_item_id()
	
	# Trigger selection (this will emit the signal and update UI)
	_on_meshlib_item_selected(current_meshlib, next_item_id)
	
	# Scroll to make the selected item visible
	_scroll_to_item(next_button)
	
	return true

func _scroll_to_item(item: AssetThumbnailItem):
	"""Scroll the container to make the given item visible"""
	if not scroll_container or not item:
		return
	
	# Calculate item's position in the scroll container
	var item_rect = item.get_rect()
	var scroll_rect = scroll_container.get_rect()
	
	# Get current scroll position
	var current_scroll = scroll_container.scroll_vertical
	
	# Calculate the item's position relative to the scroll container
	var item_top = item.position.y
	var item_bottom = item.position.y + item_rect.size.y
	
	# Calculate visible area
	var visible_top = current_scroll
	var visible_bottom = current_scroll + scroll_rect.size.y
	
	# Scroll if item is not fully visible
	if item_top < visible_top:
		# Item is above visible area - scroll up
		scroll_container.scroll_vertical = item_top
	elif item_bottom > visible_bottom:
		# Item is below visible area - scroll down
		scroll_container.scroll_vertical = item_bottom - scroll_rect.size.y







