@tool
extends Control

class_name AssetPlacerDock

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const AssetScanner = preload("res://addons/simpleassetplacer/thumbnails/asset_scanner.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_generator.gd")
const MeshLibraryBrowser = preload("res://addons/simpleassetplacer/ui/meshlib_browser.gd")
const ModelLibraryBrowser = preload("res://addons/simpleassetplacer/ui/modellib_browser.gd")
const PlacementSettings = preload("res://addons/simpleassetplacer/ui/placement_settings.gd")
const AssetThumbnailItem = preload("res://addons/simpleassetplacer/ui/asset_thumbnail_item.gd")
const AboutTab = preload("res://addons/simpleassetplacer/ui/about_tab.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/managers/category_manager.gd")
const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")
const LayoutCalculator = preload("res://addons/simpleassetplacer/utils/layout_calculator.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

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
var meshlib_browser  # MeshLibraryBrowser (no type hint to avoid initialization issues)
var modellib_browser  # ModelLibraryBrowser (no type hint to avoid initialization issues)
var placement_settings: PlacementSettings
var settings_tab: Control
var about_tab: AboutTab
var thumbnail_size: int = LayoutCalculator.THUMBNAIL_SIZE_DEFAULT  # Use optimized default size

# Asset Management
var discovered_assets: Array = []
var supported_extensions = ["obj", "fbx", "dae", "gltf", "glb", "blend", "tscn", "scn", "tres", "res", "meshlib"]
var _category_manager: CategoryManager = null

# Category manager property with setter to propagate to child browsers
var category_manager: CategoryManager:
	get:
		return _category_manager
	set(value):
		_category_manager = value
		# Propagate to child browsers
		if modellib_browser:
			modellib_browser.set_category_manager(value)
		if meshlib_browser:
			meshlib_browser.set_category_manager(value)

# ServiceRegistry instance (injected)
var _services: ServiceRegistry = null

func set_services(services: ServiceRegistry) -> void:
	"""Inject ServiceRegistry for access to manager instances"""
	_services = services

func _ready():
	name = "Asset Placer"
	
	# Note: CategoryManager will be injected from plugin via set_category_manager()
	# Cannot create it here as it requires ServiceRegistry
	# category_manager = CategoryManager.new(service_registry)
	
	setup_ui()
	# Don't discover assets here - wait until category_manager is injected
	# so that ignored folders can be properly filtered
	# discover_assets() will be called from the plugin after injection

func setup_ui():
	set_custom_minimum_size(Vector2(260, 400))  # Match browser minimum width for consistent layout
	
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
	if not modellib_browser:
		PluginLogger.error(PluginConstants.COMPONENT_DOCK, "Failed to create ModelLibraryBrowser!")
	else:
		# Set category_manager if it was already injected before _ready()
		if _category_manager:
			modellib_browser.set_category_manager(_category_manager)
		# Pass services to browser
		if _services:
			modellib_browser.set_services(_services)
		modellib_browser.asset_item_selected.connect(_on_asset_selected)
		PluginLogger.debug(PluginConstants.COMPONENT_DOCK, "ModelLibraryBrowser created successfully")
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
	if not meshlib_browser:
		PluginLogger.error(PluginConstants.COMPONENT_DOCK, "Failed to create MeshLibraryBrowser!")
	else:
		# Set category_manager if it was already injected before _ready()
		if _category_manager:
			meshlib_browser.set_category_manager(_category_manager)
		# Pass services to browser
		if _services:
			meshlib_browser.set_services(_services)
		meshlib_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meshlib_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(meshlib_browser)
		PluginLogger.debug(PluginConstants.COMPONENT_DOCK, "MeshLibraryBrowser created successfully")
	
	# Initialize search state for meshlib browser
	if search_line_edit:
		meshlib_browser.set_search_text(search_line_edit.text)
	
	# Settings tab
	settings_tab = Control.new()
	settings_tab.name = "Settings"
	tab_container.add_child(settings_tab)

	# About tab provides inline documentation and links
	about_tab = AboutTab.new()
	about_tab.ensure_ready()
	tab_container.add_child(about_tab)
	
	# Add margin container for settings tab
	var settings_margin = MarginContainer.new()
	settings_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_margin.add_theme_constant_override("margin_left", 8)
	settings_margin.add_theme_constant_override("margin_right", 8)
	settings_margin.add_theme_constant_override("margin_top", 8)
	settings_margin.add_theme_constant_override("margin_bottom", 8)
	settings_tab.add_child(settings_margin)
	
	placement_settings = PlacementSettings.new()
	if _services:
		if _services.placement_strategy_service:
			placement_settings.set_placement_strategy_service(_services.placement_strategy_service)
		if _services.settings_persistence:
			placement_settings.set_settings_persistence(_services.settings_persistence)
		if _services.thumbnail_queue_manager:
			placement_settings.set_thumbnail_queue_manager(_services.thumbnail_queue_manager)
		if _services.settings_manager:
			placement_settings.set_settings_manager(_services.settings_manager)
	placement_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_margin.add_child(placement_settings)
	
	# Ensure settings are loaded after UI setup
	call_deferred("_ensure_settings_loaded")
	
	# Connect signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	search_line_edit.text_changed.connect(_on_search_changed)
	meshlib_browser.meshlib_item_selected.connect(_on_meshlib_item_selected)
	placement_settings.cache_cleared.connect(_on_cache_cleared)
	placement_settings.settings_changed.connect(_on_settings_changed)
	
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
		grid_container.columns = LayoutCalculator.calculate_grid_columns(available_width, thumbnail_size)
	
	# Also update both browser grids
	if meshlib_browser:
		meshlib_browser.update_grid_columns(get_rect().size.x)
	if modellib_browser:
		modellib_browser.update_grid_columns(get_rect().size.x)

func update_responsive_sizes():
	var dock_width = get_rect().size.x
	var old_thumbnail_size = thumbnail_size
	
	# Use LayoutCalculator for responsive thumbnail sizing
	thumbnail_size = LayoutCalculator.calculate_responsive_thumbnail_size(dock_width)
	
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
	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Starting asset discovery...")
	
	# Pass category_manager to AssetScanner so it filters during scan (more efficient)
	var all_assets = AssetScanner.scan_for_assets("res://", true, category_manager)
	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "AssetScanner found %d assets after filtering" % all_assets.size())
	
	# Assets are already filtered by AssetScanner, so just use them directly
	discovered_assets = all_assets
	
	# Clean up orphaned data after scanning assets
	if category_manager and discovered_assets.size() > 0:
		var asset_paths = []
		for asset in discovered_assets:
			asset_paths.append(asset.path)
		
		# Perform silent cleanup (only warns in console if items found)
		category_manager.cleanup_all_orphaned_data(asset_paths)
	
	update_meshlib_browser()
	
	# Pass discovered assets to the model library browser (no need to scan again)
	if modellib_browser:
		PluginLogger.debug(PluginConstants.COMPONENT_DOCK, "Passing discovered assets to ModelLibBrowser...")
		# Filter to only non-meshlib assets for the model browser
		var model_assets = AssetScanner.exclude_meshlibs(discovered_assets)
		modellib_browser.set_discovered_assets(model_assets)
	else:
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "ModelLibBrowser not initialized, skipping discovery")

func update_meshlib_browser():
	"""Update MeshLibrary browser with discovered MeshLibrary assets"""
	if not meshlib_browser:
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "MeshLibBrowser not initialized yet, skipping meshlib update")
		return
	
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
	# Clean up orphaned data before refreshing
	if category_manager and discovered_assets.size() > 0:
		var asset_paths = []
		for asset in discovered_assets:
			asset_paths.append(asset.path)
		
		# Perform cleanup
		var cleanup_results = category_manager.cleanup_all_orphaned_data(asset_paths)
		
		# Log cleanup results if anything was cleaned
		if cleanup_results["total_items_cleaned"] > 0:
			PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Cleanup completed: %d tags, %d favorites, %d recent assets removed" % [
				cleanup_results["tags"]["removed_assets"],
				cleanup_results["favorites_removed"],
				cleanup_results["recent_removed"]
			])
	
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

func _on_settings_changed():
	"""Handle settings change event"""
	# NOTE: Don't reload from EditorSettings here!
	# The settings_changed signal means PlacementSettings just saved new values,
	# but EditorSettings might not have them yet (async write).
	# Reloading here would restore old values and cause button states to flip back.
	# The button update handlers will get the correct values from PlacementSettings directly.
	pass

func _ensure_settings_loaded():
	"""Ensure settings are properly loaded and applied to UI after initialization"""
	if placement_settings:
		placement_settings.load_settings()

func get_placement_settings() -> Dictionary:
	"""Get current placement settings from the settings component"""
	if placement_settings and placement_settings.has_method("get_placement_settings"):
		return placement_settings.get_placement_settings()
	return {}

func get_placement_settings_instance() -> PlacementSettings:
	"""Get the PlacementSettings instance (for passing to other components)"""
	return placement_settings

func refresh_placement_settings_ui():
	"""Reload placement settings UI from saved values (useful after programmatic changes)"""
	if placement_settings and placement_settings.has_method("load_settings"):
		placement_settings.load_settings()

func update_placement_strategy_ui(strategy: String):
	"""Update the placement strategy dropdown UI to reflect programmatic changes"""
	if not placement_settings:
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Cannot update placement strategy UI - placement_settings not available")
		return
	
	if not "ui_controls" in placement_settings:
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Cannot update placement strategy UI - ui_controls not found")
		return
	
	var ui_controls = placement_settings.ui_controls
	if not ui_controls.has("placement_strategy"):
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Cannot update placement strategy UI - control not found")
		return
	
	var option_button = ui_controls["placement_strategy"]
	if not option_button is OptionButton:
		PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Cannot update placement strategy UI - control is not OptionButton")
		return
	
	# Find the index of the strategy in the options
	var all_settings = SettingsDefinition.get_all_settings()
	for setting in all_settings:
		if setting.id == "placement_strategy" and setting.options:
			var selected_index = setting.options.find(strategy)
			if selected_index >= 0:
				# Update the UI dropdown
				option_button.selected = selected_index
				
				# Update the node property
				placement_settings.set("placement_strategy", strategy)
				
				# Save to EditorSettings so it persists (but don't emit settings_changed signal)
				# The coordinator already updated SettingsManager and triggered necessary reconfigurations
				placement_settings.save_settings_without_signal()
				
				PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Updated placement strategy UI to: " + strategy)
			else:
				PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Strategy not found in options: " + strategy)
			return
	
	PluginLogger.warning(PluginConstants.COMPONENT_DOCK, "Could not find placement_strategy setting definition")


func show_about_tab() -> void:
	"""Switch the tab container to the About documentation panel"""
	if not tab_container or not about_tab:
		return
	var tab_index = tab_container.get_tab_idx_from_control(about_tab)
	if tab_index >= 0:
		tab_container.set_current_tab(tab_index)

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






