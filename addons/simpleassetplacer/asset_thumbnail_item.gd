@tool
extends Button

class_name AssetThumbnailItem

signal thumbnail_item_selected(meshlib: MeshLibrary, item_id: int)
signal asset_item_selected(asset_info: Dictionary)

var meshlib: MeshLibrary
var item_id: int
var asset_info: Dictionary
var thumbnail_size: int = 64
var is_selected: bool = false
var thumbnail_rect: TextureRect
var label: Label
var selection_border: NinePatchRect
var is_meshlib_item: bool = false
var ui_setup_complete: bool = false

# Constructor for MeshLibrary items
func _init(p_meshlib: MeshLibrary = null, p_item_id: int = -1, p_thumbnail_size: int = 64):
	if p_meshlib != null:
		meshlib = p_meshlib
		item_id = p_item_id
		is_meshlib_item = true
		thumbnail_size = p_thumbnail_size
		setup_ui()

# Alternative constructor for asset items
static func create_for_asset(p_asset_info: Dictionary, p_thumbnail_size: int = 64) -> AssetThumbnailItem:
	var item = AssetThumbnailItem.new()
	item.asset_info = p_asset_info
	item.thumbnail_size = p_thumbnail_size
	item.is_meshlib_item = false
	item.setup_ui()
	return item

func setup_ui():
	# Prevent multiple setup calls
	if ui_setup_complete:
		return
	
	custom_minimum_size = Vector2(thumbnail_size + 16, thumbnail_size + 40)  # Responsive size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Set a reasonable maximum size to prevent oversized buttons
	size_flags_stretch_ratio = 1.0
	flat = true
	text = ""  # Remove text, we'll use proper layout
	
	# Use a margin container to ensure proper spacing
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	
	# Create vertical layout for thumbnail and label
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	# Thumbnail area
	thumbnail_rect = TextureRect.new()
	thumbnail_rect.custom_minimum_size = Vector2(thumbnail_size, thumbnail_size)
	thumbnail_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumbnail_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Ensure the texture doesn't overflow by setting expand to false
	thumbnail_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	vbox.add_child(thumbnail_rect)
	
	# Asset name label  
	label = Label.new()
	var item_name: String
	if is_meshlib_item:
		item_name = meshlib.get_item_name(item_id)
		if item_name == "":
			item_name = "Item " + str(item_id)
	else:
		item_name = asset_info.get("name", "Unknown Asset")
	label.text = item_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 16
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	# Store metadata for external access
	if is_meshlib_item:
		set_meta("item_id", item_id)
		set_meta("meshlib", meshlib)
	else:
		set_meta("asset_info", asset_info)
	
	# Connect signals (only if not already connected)
	if not pressed.is_connected(_on_item_selected):
		pressed.connect(_on_item_selected)
	
	# Generate thumbnail asynchronously - call on next frame to ensure UI is ready
	call_deferred("_generate_thumbnail_async")
	
	# Mark setup as complete
	ui_setup_complete = true

func _generate_thumbnail_async():
	# Set a better placeholder first
	var placeholder = null
	if EditorInterface and EditorInterface.get_editor_theme():
		placeholder = EditorInterface.get_editor_theme().get_icon("MeshInstance3D", "EditorIcons")
	
	if placeholder:
		thumbnail_rect.texture = placeholder
	else:
		# Create a simple small fallback texture if EditorInterface is not available
		var icon_size = 32
		var image = Image.create(icon_size, icon_size, false, Image.FORMAT_RGB8)
		image.fill(Color(0.4, 0.4, 0.4))  # Dark gray instead of pure gray
		var fallback_texture = ImageTexture.new()
		fallback_texture.set_image(image)
		thumbnail_rect.texture = fallback_texture
	
	if is_meshlib_item:
		_generate_meshlib_thumbnail()
	else:
		_generate_asset_thumbnail()

func _generate_meshlib_thumbnail():
	# Check if mesh exists in MeshLibrary
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		return
	
	# First check if MeshLibrary has a built-in preview
	var preview = meshlib.get_item_preview(item_id)
	if preview and is_instance_valid(thumbnail_rect):
		thumbnail_rect.texture = preview
		return
	
	# Use the ThumbnailQueueManager for centralized, sequential processing
	var queue_manager = ThumbnailQueueManager.get_instance()
	var thumbnail = await queue_manager.request_meshlib_thumbnail(meshlib, item_id)
	
	if thumbnail and is_instance_valid(thumbnail_rect):
		thumbnail_rect.texture = thumbnail
	else:
		_create_simple_mesh_icon(mesh)

func _generate_asset_thumbnail():
	# For 3D model assets, prioritize 3D thumbnail generation, then fallback to icons
	var extension = asset_info.get("extension", "")
	var asset_path = asset_info.get("path", "")
	
	# For actual 3D model files, try 3D thumbnail generation first
	if extension in ["fbx", "obj", "gltf", "glb", "dae", "blend"] and asset_path != "":
		# Use the ThumbnailQueueManager for centralized, sequential processing
		var queue_manager = ThumbnailQueueManager.get_instance()
		var thumbnail = await queue_manager.request_asset_thumbnail(asset_path)
		
		if thumbnail and is_instance_valid(thumbnail_rect):
			thumbnail_rect.texture = thumbnail
			# Force a UI update
			thumbnail_rect.queue_redraw()
			return
	
	# For scene files or if 3D thumbnail failed, try appropriate editor icons
	var icon_name = "MeshInstance3D"
	match extension:
		"fbx", "obj", "gltf", "glb", "dae", "blend":
			icon_name = "MeshInstance3D"
		"tscn", "scn":
			icon_name = "PackedScene"
		"tres", "res":
			icon_name = "Resource"
	
	# Try to get the editor icon
	var icon_texture = null
	if EditorInterface and EditorInterface.get_editor_theme():
		icon_texture = EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
	
	if icon_texture:
		thumbnail_rect.texture = icon_texture
		return
	
	# As a last resort, create a simple geometric icon
	_create_simple_asset_icon(extension)

func _create_simple_mesh_icon(mesh: Mesh):
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

func _create_simple_asset_icon(extension: String):
	# Create a small icon-like image (fixed small size, not full thumbnail_size)
	var icon_size = 32  # Fixed small icon size regardless of thumbnail_size
	var image = Image.create(icon_size, icon_size, false, Image.FORMAT_RGB8)
	
	# Fill with transparent/dark background
	image.fill(Color(0.3, 0.3, 0.3, 1.0))
	
	# Use different accent colors based on file extension
	var accent_color = Color.WHITE
	match extension:
		"fbx":
			accent_color = Color.ORANGE
		"obj":
			accent_color = Color.CYAN
		"gltf", "glb":
			accent_color = Color.GREEN
		"dae":
			accent_color = Color.YELLOW
		"blend":
			accent_color = Color.PURPLE
		"tscn", "scn":
			accent_color = Color.BLUE
		"tres", "res":
			accent_color = Color.RED
		_:
			accent_color = Color.WHITE
	
	# Create a simple geometric icon pattern - a smaller centered shape
	var center = icon_size / 2
	var radius = icon_size / 6  # Much smaller radius
	
	# Draw a simple filled circle
	for y in range(icon_size):
		for x in range(icon_size):
			var dx = x - center
			var dy = y - center
			var distance = sqrt(dx * dx + dy * dy)
			if distance <= radius:
				image.set_pixel(x, y, accent_color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	thumbnail_rect.texture = texture

func _on_item_selected():
	if is_meshlib_item:
		thumbnail_item_selected.emit(meshlib, item_id)
	else:
		asset_item_selected.emit(asset_info)

func set_selected(selected: bool):
	is_selected = selected
	
	if is_selected:
		modulate = Color(1.2, 1.2, 1.2)  # Slightly brighter
		
		# Add selection border if it doesn't exist
		if not selection_border:
			var vbox = get_child(0).get_child(0)  # margin -> vbox
			selection_border = NinePatchRect.new()
			selection_border.name = "SelectionBorder"
			selection_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			selection_border.texture = EditorInterface.get_editor_theme().get_icon("GuiChecked", "EditorIcons")
			selection_border.modulate = Color.CYAN
			selection_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(selection_border)
			vbox.move_child(selection_border, 0)  # Move to back
	else:
		modulate = Color.WHITE
		
		# Remove selection border if it exists
		if selection_border:
			selection_border.queue_free()
			selection_border = null

func get_item_id() -> int:
	return item_id

func get_meshlib() -> MeshLibrary:
	return meshlib

func get_asset_info() -> Dictionary:
	return asset_info

func is_meshlib_type() -> bool:
	return is_meshlib_item

func update_thumbnail_size(new_size: int):
	thumbnail_size = new_size
	# Update the minimum size
	custom_minimum_size = Vector2(thumbnail_size + 16, thumbnail_size + 40)
	# Update the thumbnail rect size
	if thumbnail_rect:
		thumbnail_rect.custom_minimum_size = Vector2(thumbnail_size, thumbnail_size)