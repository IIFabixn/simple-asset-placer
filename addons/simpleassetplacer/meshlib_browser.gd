@tool
extends Control

class_name MeshLibraryBrowser

signal meshlib_item_selected(meshlib: MeshLibrary, item_id: int)

var meshlib_option: OptionButton
var items_grid: GridContainer
var scroll_container: ScrollContainer
var current_meshlib: MeshLibrary
var thumbnail_size: int = 64
var selected_item_id: int = -1
var selected_button: Button = null
var current_search_text: String = ""

func _ready():
	setup_ui()

func setup_ui():
	# Set up the main container to fill the available space
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# MeshLibrary selector
	var label = Label.new()
	label.text = "MeshLibrary:"
	vbox.add_child(label)
	
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
	items_grid.add_theme_constant_override("h_separation", 8)
	items_grid.add_theme_constant_override("v_separation", 8)
	scroll_container.add_child(items_grid)
	
	# Connect signals
	meshlib_option.item_selected.connect(_on_meshlib_selected)

func update_grid_columns(available_width: float):
	if items_grid:
		# Calculate columns based on available width
		var item_width = thumbnail_size + 24  # Thumbnail + padding + text
		var new_columns = max(1, int((available_width - 32) / item_width))
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
		
		create_meshlib_item_thumbnail(meshlib, item_id)

func create_meshlib_item_thumbnail(meshlib: MeshLibrary, item_id: int):
	var button = Button.new()
	button.custom_minimum_size = Vector2(110, 120)  # Proper size for 2-column layout
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.flat = true
	button.text = ""  # Remove text, we'll use proper layout
	
	# Use a margin container to ensure proper spacing
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	button.add_child(margin)
	
	# Create vertical layout for thumbnail and label
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# Thumbnail area
	var thumbnail_rect = TextureRect.new()
	thumbnail_rect.custom_minimum_size = Vector2(64, 64)
	thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(thumbnail_rect)
	
	# Asset name label  
	var label = Label.new()
	var item_name = meshlib.get_item_name(item_id)
	if item_name == "":
		item_name = "Item " + str(item_id)
	label.text = item_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 20
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	# Generate thumbnail asynchronously - call on next frame to ensure UI is ready
	call_deferred("_generate_meshlib_thumbnail_async", meshlib, item_id, thumbnail_rect)
	
	# Store button reference for selection tracking
	button.set_meta("item_id", item_id)
	button.set_meta("meshlib", meshlib)
	
	# Connect signals
	button.pressed.connect(_on_meshlib_item_selected.bind(meshlib, item_id, button))
	
	items_grid.add_child(button)

func _generate_meshlib_thumbnail_async(meshlib: MeshLibrary, item_id: int, thumbnail_rect: TextureRect):
	# Set a better placeholder first
	var placeholder = EditorInterface.get_editor_theme().get_icon("MeshInstance3D", "EditorIcons")
	thumbnail_rect.texture = placeholder
	
	# Check if mesh exists in MeshLibrary
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		return
	
	# Generate actual 3D thumbnail
	var thumbnail_generator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")
	
	# Initialize thumbnail generator if not already done
	thumbnail_generator.initialize()
	
	# Wait a frame to ensure initialization is complete
	await get_tree().process_frame
	
	# First check if MeshLibrary has a built-in preview
	var preview = meshlib.get_item_preview(item_id)
	if preview and is_instance_valid(thumbnail_rect):
		thumbnail_rect.texture = preview
		return
	
	# Try the 3D thumbnail generation
	var thumbnail = await thumbnail_generator.generate_meshlib_thumbnail(meshlib, item_id)
	if thumbnail and is_instance_valid(thumbnail_rect):
		thumbnail_rect.texture = thumbnail
	else:
		_create_simple_mesh_icon(mesh, thumbnail_rect)

func _create_simple_mesh_icon(mesh: Mesh, thumbnail_rect: TextureRect):
	# Create a simple colored rectangle as a fallback
	var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	
	# Use different colors based on mesh properties
	var color = Color.GRAY
	if mesh is BoxMesh:
		color = Color.BLUE
	elif mesh is SphereMesh:
		color = Color.RED
	elif mesh is CylinderMesh:
		color = Color.GREEN
	else:
		# For other meshes, use a hash of the mesh data for consistent color
		var hash = str(mesh).hash()
		color = Color.from_hsv((hash % 360) / 360.0, 0.7, 0.8)
	
	image.fill(color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	thumbnail_rect.texture = texture

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, button: Button):
	# Clear previous selection
	if selected_button and is_instance_valid(selected_button):
		selected_button.modulate = Color.WHITE
		# Remove selection border if it exists
		var border = selected_button.get_child(0).get_child(0).get_node_or_null("SelectionBorder")
		if border:
			border.queue_free()
	
	# Set new selection
	selected_item_id = item_id
	selected_button = button
	
	# Add visual feedback
	if selected_button:
		selected_button.modulate = Color(1.2, 1.2, 1.2)  # Slightly brighter
		
		# Add selection border
		var vbox = selected_button.get_child(0).get_child(0)  # margin -> vbox
		var border = NinePatchRect.new()
		border.name = "SelectionBorder"
		border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		border.texture = EditorInterface.get_editor_theme().get_icon("GuiChecked", "EditorIcons")
		border.modulate = Color.CYAN
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(border)
		vbox.move_child(border, 0)  # Move to back
	
	meshlib_item_selected.emit(meshlib, item_id)

