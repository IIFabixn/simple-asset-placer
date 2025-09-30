@tool
extends Control

class_name MeshLibraryBrowser

const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")

signal meshlib_item_selected(meshlib: MeshLibrary, item_id: int)

var meshlib_option: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var current_meshlib: MeshLibrary
var thumbnail_size: int = 64
var selected_item_id: int = -1
var selected_button: AssetThumbnailItem = null
var current_search_text: String = ""

func _ready():
	setup_ui()

func setup_ui():
	# Set up the main container to fill the available space
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
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
	meshlib_option.item_selected.connect(_on_meshlib_selected)

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
		populate_meshlib_items(current_meshlib)

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
		clear_items()
		return
	
	var meshlib_path = meshlib_option.get_item_metadata(index)
	var meshlib = load(meshlib_path)
	
	if meshlib is MeshLibrary:
		current_meshlib = meshlib
		populate_meshlib_items(meshlib)

func clear_items():
	for child in items_grid.get_children():
		child.queue_free()

func populate_meshlib_items(meshlib: MeshLibrary):
	clear_items()
	
	var item_ids = meshlib.get_item_list()
	
	for item_id in item_ids:
		# Apply search filter if active
		if current_search_text != "":
			var item_name = meshlib.get_item_name(item_id)
			if item_name == "":
				item_name = "Item " + str(item_id)
			
			# Skip items that don't match search
			if not item_name.to_lower().contains(current_search_text.to_lower()):
				continue
		
		# Create thumbnail item using the new AssetThumbnailItem class
		var thumbnail_item = AssetThumbnailItem.new(meshlib, item_id, thumbnail_size)
		thumbnail_item.thumbnail_item_selected.connect(_on_meshlib_item_selected)
		items_grid.add_child(thumbnail_item)

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

