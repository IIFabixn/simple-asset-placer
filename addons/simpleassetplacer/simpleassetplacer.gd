@tool
extends EditorPlugin

# Main Plugin
# Handles editor integration using instance-based architecture with ServiceRegistry

# Import core infrastructure
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ErrorHandler = preload("res://addons/simpleassetplacer/utils/error_handler.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const ServiceRegistryBuilder = preload("res://addons/simpleassetplacer/core/service_registry_builder.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_generator.gd")

# Import UI components (still needed for dock management)

# Import UI
const AssetPlacerDock = preload("res://addons/simpleassetplacer/ui/asset_placer_dock.gd")
const ToolbarButtonsScene = preload("res://addons/simpleassetplacer/ui/toolbar_buttons.tscn")

# Plugin state
var dock: AssetPlacerDock
var toolbar_buttons: Control = null
var filesystem_dock: Control = null

const ABOUT_TAB_SEEN_KEY := "simpleassetplacer/ui/about_tab_seen"

# Service registry
var service_registry: ServiceRegistry = null

## Plugin Lifecycle

func _enable_plugin() -> void:
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Plugin enabled")

func _disable_plugin() -> void:
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Plugin disabled")

func _enter_tree() -> void:
	PluginLogger.log_initialization(PluginConstants.COMPONENT_MAIN)
	
	# Initialize systems in order
	_initialize_systems()
	_setup_dock()
	_setup_toolbar()
	_setup_filesystem_context_menu()
	
	# Enable input forwarding for reliable input handling
	set_input_event_forwarding_always_enabled()
	
	PluginLogger.log_initialization_complete(PluginConstants.COMPONENT_MAIN)

func _exit_tree() -> void:
	PluginLogger.log_cleanup(PluginConstants.COMPONENT_MAIN)
	
	# Clean up in reverse order
	_cleanup_systems()
	_cleanup_toolbar()
	_cleanup_filesystem_context_menu()
	_cleanup_dock()
	
	PluginLogger.log_cleanup_complete(PluginConstants.COMPONENT_MAIN)

## System Initialization

func _initialize_systems():
	"""Initialize all manager systems with ServiceRegistry"""
	# Create ServiceRegistry using builder pattern
	service_registry = ServiceRegistryBuilder.create_full_registry(get_editor_interface())
	
	if not service_registry:
		push_error("Failed to build ServiceRegistry - plugin initialization aborted")
		return
	
	# Initialize error handler with editor interface instance
	ErrorHandler.initialize(get_editor_interface())
	
	# Initialize thumbnail system (still static)
	ThumbnailGenerator.initialize()
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "All systems initialized")

func _cleanup_systems():
	"""Clean up all manager systems with error handling"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Starting system cleanup...")
	
	if not service_registry:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "No service registry to clean up")
		return
	
	# Exit any active modes first
	if service_registry.transformation_coordinator:
		_safe_cleanup("TransformationCoordinator.exit_any_mode", func(): service_registry.transformation_coordinator.exit_any_mode())
	
	# Clean up UI and visual systems via instance references
	if service_registry.overlay_manager:
		_safe_cleanup("OverlayManager.cleanup_all_overlays", func(): service_registry.overlay_manager.cleanup_all_overlays())
	if service_registry.preview_manager:
		_safe_cleanup("PreviewManager.cleanup_preview", func(): service_registry.preview_manager.cleanup_preview())
	
	# Clean up core systems
	if service_registry.transformation_coordinator:
		_safe_cleanup("TransformationCoordinator.cleanup", func(): service_registry.transformation_coordinator.cleanup())
	if service_registry.smooth_transform_manager:
		_safe_cleanup("SmoothTransformManager.cleanup_all", func(): service_registry.smooth_transform_manager.cleanup_all())
	
	# Clean up thumbnail systems
	_safe_cleanup("ThumbnailGenerator.cleanup", func(): ThumbnailGenerator.cleanup())
	if service_registry and service_registry.thumbnail_queue_manager:
		_safe_cleanup("ThumbnailQueueManager.cleanup", func(): service_registry.thumbnail_queue_manager.cleanup())
	
	# Clean up placement system
	if service_registry and service_registry.placement_strategy_service:
		_safe_cleanup("PlacementStrategyService.cleanup", func(): service_registry.placement_strategy_service.cleanup())
	
	# Clean up service registry
	if service_registry:
		service_registry.cleanup()
		service_registry = null
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "System cleanup completed")

func _safe_cleanup(component_name: String, cleanup_func: Callable) -> void:
	"""Execute cleanup with error handling to prevent cascade failures
	
	Args:
		component_name: Name of component being cleaned (for logging)
		cleanup_func: Callable containing the cleanup operation
		
	Note: GDScript doesn't have try/catch, but this wrapper provides a
	centralized logging point and prevents null callable crashes
	"""
	if not cleanup_func or not cleanup_func.is_valid():
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "✗ %s cleanup skipped - invalid callable" % component_name)
		return
	
	# Execute cleanup - any errors will be caught by Godot's error system
	# but won't crash the plugin entirely
	cleanup_func.call()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "✓ %s cleaned up" % component_name)

## Dock Management

func _setup_dock():
	"""Set up the asset placer dock"""
	dock = AssetPlacerDock.new()
	dock.name = "Asset Placer"
	
	# Inject services into dock
	if dock.has_method("set_services"):
		dock.set_services(service_registry)
	
	# Connect dock signals
	dock.asset_selected.connect(_on_asset_selected)
	dock.meshlib_item_selected.connect(_on_meshlib_item_selected)
	
	# Inject CategoryManager into dock
	if service_registry and service_registry.category_manager:
		dock.category_manager = service_registry.category_manager
		service_registry.category_manager.load_config_file()
	
	# Add to Godot dock
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Discover assets after dock is fully initialized (deferred to ensure _ready() completes)
	if service_registry and service_registry.category_manager:
		dock.call_deferred("discover_assets")
	
	# Store dock reference for UI updates
	if service_registry and service_registry.transformation_coordinator:
		service_registry.transformation_coordinator.set_dock_reference(dock)
	
	# Set PlacementSettings reference for status overlay (deferred to ensure dock is fully initialized)
	call_deferred("_connect_placement_settings_to_overlay")
	call_deferred("_maybe_show_about_tab")
	
	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Dock setup complete")

func _connect_placement_settings_to_overlay():
	"""Connect the PlacementSettings reference to the status overlay"""
	if dock and dock.has_method("get_placement_settings_instance") and service_registry and service_registry.overlay_manager:
		var placement_settings = dock.get_placement_settings_instance()
		if placement_settings:
			service_registry.overlay_manager.set_placement_settings_reference(placement_settings)
			PluginLogger.info(PluginConstants.COMPONENT_DOCK, "PlacementSettings reference connected to overlay")

func _cleanup_dock():
	"""Clean up the dock"""
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	
	# Clear dock reference
	if service_registry and service_registry.transformation_coordinator:
		service_registry.transformation_coordinator.set_dock_reference(null)

func _maybe_show_about_tab() -> void:
	"""Show the About tab the first time the plugin loads for a user."""
	if not dock or not dock.has_method("show_about_tab"):
		return
	var editor_settings := get_editor_interface().get_editor_settings()
	if not editor_settings:
		return
	if editor_settings.has_setting(ABOUT_TAB_SEEN_KEY) and editor_settings.get_setting(ABOUT_TAB_SEEN_KEY):
		return
	dock.call_deferred("show_about_tab")
	if not editor_settings.has_setting(ABOUT_TAB_SEEN_KEY) or not editor_settings.get_setting(ABOUT_TAB_SEEN_KEY):
		editor_settings.set_setting(ABOUT_TAB_SEEN_KEY, true)
		if editor_settings.has_method("save"):
			editor_settings.save()
	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "About tab displayed for first-time setup")

## Toolbar Management

func _setup_toolbar():
	"""Set up the toolbar buttons in 3D viewport"""
	if ToolbarButtonsScene:
		toolbar_buttons = ToolbarButtonsScene.instantiate()
		
		# Inject services into toolbar
		if toolbar_buttons.has_method("set_services"):
			toolbar_buttons.set_services(service_registry)
		
		# Set TransformationCoordinator reference
		if toolbar_buttons.has_method("set_transformation_coordinator"):
			toolbar_buttons.set_transformation_coordinator(service_registry.transformation_coordinator)
		
		# Add to spatial editor menu container
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_buttons)
		
		# Set PlacementSettings reference (deferred to ensure dock is fully initialized)
		call_deferred("_connect_placement_settings_to_toolbar")
		
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Toolbar setup complete")

func _connect_placement_settings_to_toolbar():
	"""Connect the PlacementSettings reference to the toolbar"""
	if dock and dock.has_method("get_placement_settings_instance") and toolbar_buttons and service_registry and service_registry.overlay_manager:
		var placement_settings = dock.get_placement_settings_instance()
		if placement_settings and toolbar_buttons.has_method("set_placement_settings"):
			toolbar_buttons.set_placement_settings(placement_settings)
			service_registry.overlay_manager.set_toolbar_reference(toolbar_buttons)
			PluginLogger.info(PluginConstants.COMPONENT_MAIN, "PlacementSettings reference connected to toolbar")

func _cleanup_toolbar():
	"""Clean up the toolbar"""
	if toolbar_buttons:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_buttons)
		toolbar_buttons.queue_free()
		toolbar_buttons = null
	
	# Clear toolbar reference in OverlayManager
	if service_registry and service_registry.overlay_manager:
		service_registry.overlay_manager.set_toolbar_reference(null)

## FileSystem Dock Context Menu Management

func _setup_filesystem_context_menu():
	"""Set up FileSystem dock context menu integration"""
	# Get the FileSystem dock
	filesystem_dock = get_editor_interface().get_file_system_dock()
	
	if filesystem_dock:
		# Connect to the files_moved signal to handle context menu
		# Note: Godot doesn't provide a direct way to add context menu items to FileSystem dock
		# We'll use the add_resource_conversion_plugin approach or override via signals
		# For now, we'll log that the feature is ready but needs user to use asset browser context menu
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "FileSystem dock reference obtained")
	else:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Could not get FileSystem dock reference")

func _cleanup_filesystem_context_menu():
	"""Clean up FileSystem dock context menu integration"""
	filesystem_dock = null

## Core Processing Loop

func _process(delta: float) -> void:
	"""Main processing loop - delegates everything to TransformationCoordinator"""
	if not _is_plugin_ready():
		return
	
	if not service_registry or not service_registry.transformation_coordinator:
		return
	
	# Get current camera for positioning
	var camera = _get_current_camera()
	if not camera:
		return
	
	# Delegate frame processing to coordinator
	service_registry.transformation_coordinator.process_frame_input(camera, service_registry.settings_manager.get_combined_settings(), delta)
	
	# Update transform mode button state
	if toolbar_buttons and toolbar_buttons.has_method("set_transform_mode_active"):
		toolbar_buttons.set_transform_mode_active(service_registry.transformation_coordinator.is_transform_mode())

func _is_plugin_ready() -> bool:
	"""Check if plugin is ready for processing"""
	return dock != null

func _get_current_camera() -> Camera3D:
	"""Get the current 3D viewport camera"""
	if not service_registry or not service_registry.editor_facade:
		return null
	var viewport_3d = service_registry.editor_facade.get_editor_viewport_3d(0)
	if viewport_3d:
		return viewport_3d.get_camera_3d()
	return null

## Input Handling (Minimal - delegates to TransformationCoordinator)

func handles(object) -> bool:
	"""Check if we should handle input for this object"""
	if not service_registry or not service_registry.transformation_coordinator:
		return false
	return service_registry.transformation_coordinator.is_any_mode_active()

func _input(event: InputEvent) -> void:
	"""Handle input at the highest priority to prevent TAB focus issues and mouse wheel zoom"""
	
	if not service_registry or not service_registry.transformation_coordinator or not service_registry.settings_manager:
		return
	
	# Handle mouse wheel events when modes are active to prevent viewport zoom
	if event is InputEventMouseButton and service_registry.transformation_coordinator.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if service_registry.transformation_coordinator.handle_mouse_wheel_input(event):
				# Event was handled - consume it IMMEDIATELY to prevent viewport zoom
				get_viewport().set_input_as_handled()
				return
	
	if event is InputEventKey and event.pressed:
		var key_string = OS.get_keycode_string(event.keycode)
		
		# Build full key string with modifiers
		var full_key_string = ""
		if event.ctrl_pressed:
			full_key_string += "CTRL+"
		if event.alt_pressed:
			full_key_string += "ALT+"
		if event.shift_pressed:
			full_key_string += "SHIFT+"
		full_key_string += key_string
		
		# Check if this is the transform mode key
		var transform_key = service_registry.settings_manager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Only handle if we have a selected Node3D
			if not service_registry or not service_registry.editor_facade:
				return
			var selection = service_registry.editor_facade.get_selection()
			var selected_nodes = selection.get_selected_nodes()
			
			# Check if we have a valid Node3D selected
			for node in selected_nodes:
				if node is Node3D:
					# This is our transform mode activation - consume the event completely
					get_viewport().set_input_as_handled()
					# Prevent it from propagating as a TAB navigation event
					return
			
			# If no valid Node3D selected, let TAB act normally (but consume it anyway for now)
			get_viewport().set_input_as_handled()

func _shortcut_input(event: InputEvent) -> void:
	"""Handle shortcut input with high priority to prevent conflicts"""
	
	if not service_registry or not service_registry.settings_manager:
		return
	
	# Handle key events to prevent conflicts with Godot shortcuts
	if event is InputEventKey and event.pressed:
		var key_string = OS.get_keycode_string(event.keycode)
		
		# Build full key string with modifiers
		var full_key_string = ""
		if event.ctrl_pressed:
			full_key_string += "CTRL+"
		if event.alt_pressed:
			full_key_string += "ALT+"
		if event.shift_pressed:
			full_key_string += "SHIFT+"
		full_key_string += key_string
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = service_registry.settings_manager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event immediately to prevent focus change
			get_viewport().set_input_as_handled()
			# Let TransformationCoordinator handle the actual mode activation
			return
		
		# For other plugin keys, only handle when modes are active
		if service_registry and service_registry.transformation_coordinator and service_registry.transformation_coordinator.is_any_mode_active():
			# Check if this key matches any of our plugin keybindings
			if service_registry.settings_manager.is_plugin_key(full_key_string) or service_registry.settings_manager.is_plugin_key(key_string):
				# This is our key - consume it to prevent Godot from processing it
				get_viewport().set_input_as_handled()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	"""Forward 3D GUI input - intercept and consume plugin-related keys and mouse wheel"""
	
	if not service_registry or not service_registry.transformation_coordinator or not service_registry.settings_manager:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Handle mouse motion when modes are active
	if event is InputEventMouseMotion and service_registry.transformation_coordinator.is_any_mode_active():
		service_registry.transformation_coordinator.handle_mouse_motion(viewport_camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Handle mouse button events when modes are active
	if event is InputEventMouseButton and service_registry.transformation_coordinator.is_any_mode_active():
		# Handle middle mouse button for plane cycling
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			# Check if plane strategy is active
			if service_registry.placement_strategy_service and service_registry.placement_strategy_service.get_active_strategy_type() == "plane":
				# Get current preview position to avoid jumping
				var current_pos = Vector3.ZERO
				if service_registry.preview_manager:
					current_pos = service_registry.preview_manager.get_preview_position()
				
				# Pass the current mouse position to freeze updates until mouse moves
				var plane_name = service_registry.placement_strategy_service.cycle_plane(current_pos, event.position)
				if plane_name:
					PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Plane cycled to: " + plane_name)
				# Consume the event
				event.set_canceled(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# Handle mouse wheel events
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if service_registry.transformation_coordinator.handle_mouse_wheel_input(event):
				# Event was handled - consume it IMMEDIATELY to prevent viewport zoom
				# Mark as handled first, then return stop
				event.set_canceled(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	# Handle key events to prevent conflicts with Godot shortcuts
	# Note: Don't filter event.echo here - let individual handlers decide
	if event is InputEventKey and event.pressed:
		var key_string = OS.get_keycode_string(event.keycode)
		
		# Build full key string with modifiers
		var full_key_string = ""
		if event.ctrl_pressed:
			full_key_string += "CTRL+"
		if event.alt_pressed:
			full_key_string += "ALT+"
		if event.shift_pressed:
			full_key_string += "SHIFT+"
		full_key_string += key_string
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = service_registry.settings_manager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event to prevent focus change 
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# For other plugin keys, only handle when modes are active
		if not service_registry or not service_registry.transformation_coordinator or not service_registry.transformation_coordinator.is_any_mode_active():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		
		# Check if this key matches any of our plugin keybindings
		if service_registry.settings_manager.is_plugin_key(full_key_string) or service_registry.settings_manager.is_plugin_key(key_string):
			# This is our key - consume it to prevent Godot from processing it
			# Mark the event as handled and STOP further processing
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	# Let Godot handle other inputs
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	"""Handle canvas/2D GUI input - also intercept plugin keys"""
	
	# Only handle input when plugin modes are active
	if not service_registry or not service_registry.transformation_coordinator or not service_registry.settings_manager or not service_registry.transformation_coordinator.is_any_mode_active():
		return false
	
	# Handle key events to prevent conflicts with Godot shortcuts
	if event is InputEventKey and event.pressed:
		var key_string = OS.get_keycode_string(event.keycode)
		
		# Build full key string with modifiers
		var full_key_string = ""
		if event.ctrl_pressed:
			full_key_string += "CTRL+"
		if event.alt_pressed:
			full_key_string += "ALT+"
		if event.shift_pressed:
			full_key_string += "SHIFT+"
		full_key_string += key_string
		
		# Check if this key matches any of our plugin keybindings
		if service_registry.settings_manager.is_plugin_key(full_key_string) or service_registry.settings_manager.is_plugin_key(key_string):
			# This is our key - consume it to prevent Godot from processing it
			return true
	
	# Let Godot handle other inputs
	return false

func _on_asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary):
	"""Handle asset selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Asset selected: " + asset_path)
	
	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "Cannot start placement mode - service registry not initialized")
		return
	
	# Update dock settings and get combined settings
	service_registry.settings_manager.update_dock_settings(settings)
	var combined_settings = service_registry.settings_manager.get_combined_settings()
	
	# Start placement mode through the coordinator
	if mesh_resource and mesh_resource is Mesh:
		service_registry.transformation_coordinator.start_placement_mode(mesh_resource, null, -1, "", combined_settings, dock)
	else:
		service_registry.transformation_coordinator.start_placement_mode(null, null, -1, asset_path, combined_settings, dock)
	
	# Show user feedback
	if service_registry and service_registry.overlay_manager:
		service_registry.overlay_manager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	"""Handle MeshLibrary item selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "MeshLib item selected: " + str(item_id))
	
	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "Cannot start placement mode - service registry not initialized")
		return
	
	# Update dock settings and get combined settings
	service_registry.settings_manager.update_dock_settings(settings)
	var combined_settings = service_registry.settings_manager.get_combined_settings()
	
	# Start placement mode through the coordinator
	service_registry.transformation_coordinator.start_placement_mode(null, meshlib, item_id, "", combined_settings, dock)
	
	# Show user feedback
	if service_registry and service_registry.overlay_manager:
		service_registry.overlay_manager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

## Settings and Configuration

func update_plugin_settings(new_settings: Dictionary):
	"""Update plugin settings"""
	service_registry.settings_manager.set_plugin_settings(new_settings)
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings updated")

func get_plugin_settings() -> Dictionary:
	"""Get current plugin settings"""
	return service_registry.settings_manager.get_combined_settings()

## Debug and Information

func get_system_status() -> Dictionary:
	"""Get status of all systems for debugging"""
	var current_mode = "NONE"
	if service_registry and service_registry.transformation_coordinator:
		current_mode = service_registry.transformation_coordinator.get_current_mode()
	
	var settings_summary = {}
	if service_registry and service_registry.settings_manager:
		settings_summary = service_registry.settings_manager.get_summary()
	
	return {
		"plugin_ready": _is_plugin_ready(),
		"dock_exists": dock != null,
		"current_mode": current_mode,
		"has_camera": _get_current_camera() != null,
		"settings": settings_summary
	}

func debug_print_status():
	"""Print system status for debugging"""
	var status = get_system_status()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "System Status:")
	for key in status:
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  " + key + ": " + str(status[key]))







