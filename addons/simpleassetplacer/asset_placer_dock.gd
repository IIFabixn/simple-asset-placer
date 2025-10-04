@tool
extends Control

class_name AssetPlacerDock

const PluginLogger = preload("res://addons/simpleassetplacer/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/plugin_constants.gd")
const AssetScanner = preload("res://addons/simpleassetplacer/asset_scanner.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")
const MeshLibraryBrowser = preload("res://addons/simpleassetplacer/meshlib_browser.gd")
const ModelLibraryBrowser = preload("res://addons/simpleassetplacer/modellib_browser.gd")
const PlacementSettings = preload("res://addons/simpleassetplacer/placement_settings.gd")
const AssetThumbnailItem = preload("res://addons/simpleassetplacer/asset_thumbnail_item.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/category_manager.gd")

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
var supported_extensions = ["obj", "fbx", "dae", "gltf", "glb", "blend", "tscn", "scn", "tres", "res", "meshlib"]
var category_manager: CategoryManager = null

func _ready():
	name = "Asset Placer"
	
	# Initialize category manager
	category_manager = CategoryManager.new()
	category_manager.load_config_file()
	
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
	modellib_browser.set_category_manager(category_manager)
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
	meshlib_browser.set_category_manager(category_manager)
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
	
	# Ensure settings are loaded after UI setup
	call_deferred("_ensure_settings_loaded")
	
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
			for child in grid_container.get_children():
				if child is AssetThumbnailItem:
					child.update_thumbnail_size(thumbnail_size)

func discover_assets():
	"""Discover all 3D assets in the project using AssetScanner"""
	discovered_assets = AssetScanner.scan_for_assets("res://", true)
	update_meshlib_browser()
	# Discover assets for the model library browser
	if modellib_browser:
		modellib_browser.discover_assets()

func update_meshlib_browser():
	"""Update MeshLibrary browser with discovered MeshLibrary assets"""
	var meshlib_paths = AssetScanner.get_meshlib_paths(discovered_assets)
	meshlib_browser.populate_meshlib_options(meshlib_paths)

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int):
	var settings = placement_settings.get_placement_settings()
	meshlib_item_selected.emit(meshlib, item_id, settings)

func _on_asset_selected(asset_info: Dictionary):
	# Load the resource and emit signal
	var resource = load(asset_info.path)
	if resource:
		# Mark asset as used for recent tracking
		if category_manager:
			category_manager.mark_as_used(asset_info.path)
		
		var settings = placement_settings.get_placement_settings()
		asset_selected.emit(asset_info.path, resource, settings)
	else:
		PluginLogger.error(PluginConstants.COMPONENT_DOCK, "Failed to load resource: " + asset_info.path)

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
	"""Handle cache clear event - refresh browsers to regenerate thumbnails"""
	if modellib_browser:
		modellib_browser.update_asset_grid()

func _ensure_settings_loaded():
	"""Ensure settings are properly loaded and applied to UI after initialization"""
	if placement_settings:
		placement_settings.load_settings()

func get_placement_settings() -> Dictionary:
	"""Get current placement settings from the settings component"""
	if placement_settings and placement_settings.has_method("get_placement_settings"):
		return placement_settings.get_placement_settings()
	return {}

## Asset Cycling Coordination

func cycle_next_asset() -> bool:
	"""Cycle to the next asset in the currently active browser tab. Returns true if successful."""
	var active_tab = tab_container.get_current_tab_control()
	
	# Check which tab is active and delegate to the appropriate browser
	if active_tab == models_tab and modellib_browser:
		return modellib_browser.cycle_to_next_asset()
	elif active_tab == meshlib_tab and meshlib_browser:
		return meshlib_browser.cycle_to_next_item()
	
	return false

func cycle_previous_asset() -> bool:
	"""Cycle to the previous asset in the currently active browser tab. Returns true if successful."""
	var active_tab = tab_container.get_current_tab_control()
	
	# Check which tab is active and delegate to the appropriate browser
	if active_tab == models_tab and modellib_browser:
		return modellib_browser.cycle_to_previous_asset()
	elif active_tab == meshlib_tab and meshlib_browser:
		return meshlib_browser.cycle_to_previous_item()
	
	return false