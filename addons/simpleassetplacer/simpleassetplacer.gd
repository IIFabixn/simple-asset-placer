@tool
extends EditorPlugin

# Main Plugin
# Only handles editor integration and delegates everything to TransformationCoordinator

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const ErrorHandler = preload("res://addons/simpleassetplacer/utils/error_handler.gd")

# Import specialized managers
const InputHandler = preload("res://addons/simpleassetplacer/managers/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/managers/preview_manager.gd")
const TransformationCoordinator = preload("res://addons/simpleassetplacer/core/transformation_coordinator.gd")

# Import placement strategy system
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")

# Import dock and utilities (keep existing)
const AssetPlacerDock = preload("res://addons/simpleassetplacer/ui/asset_placer_dock.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_generator.gd")
const ThumbnailQueueManager = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_queue_manager.gd")

# Toolbar scene
const ToolbarButtonsScene = preload("res://addons/simpleassetplacer/ui/toolbar_buttons.tscn")

# Plugin state
var dock: AssetPlacerDock
var toolbar_buttons: Control = null

# Manager instances (Phase 5.2: Instance-based architecture)
var transformation_coordinator: TransformationCoordinator = null
var overlay_manager: OverlayManager = null
var preview_manager: PreviewManager = null
var smooth_transform_manager: SmoothTransformManager = null
var input_handler: InputHandler = null
var position_manager: PositionManager = null
var mode_state_machine: ModeStateMachine = null
var grid_manager: GridManager = null

# Performance: Frame-based settings cache (Task 3.3)
# Avoids redundant SettingsManager.get_combined_settings() calls within the same frame
var _cached_settings: Dictionary = {}
var _settings_cache_frame: int = -1

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
	_load_settings()
	
	# Enable input forwarding for reliable input handling
	set_input_event_forwarding_always_enabled()
	
	PluginLogger.log_initialization_complete(PluginConstants.COMPONENT_MAIN)

func _exit_tree() -> void:
	PluginLogger.log_cleanup(PluginConstants.COMPONENT_MAIN)
	
	# Clean up in reverse order
	_cleanup_systems()
	_cleanup_toolbar()
	_cleanup_dock()
	
	PluginLogger.log_cleanup_complete(PluginConstants.COMPONENT_MAIN)

## System Initialization

func _initialize_systems():
	"""Initialize all manager systems"""
	# Initialize settings manager first
	SettingsManager.initialize()
	
	# Initialize error handler with editor interface instance
	ErrorHandler.initialize(get_editor_interface())
	
	# Initialize placement strategy system
	PlacementStrategyManager.initialize()
	
	# Create manager instances (Phase 5.2: Instance-based architecture)
	transformation_coordinator = TransformationCoordinator.new()
	TransformationCoordinator._set_instance(transformation_coordinator)
	
	overlay_manager = OverlayManager.new()
	OverlayManager._set_instance(overlay_manager)
	
	preview_manager = PreviewManager.new()
	PreviewManager._set_instance(preview_manager)
	
	smooth_transform_manager = SmoothTransformManager.new()
	SmoothTransformManager._set_instance(smooth_transform_manager)
	
	input_handler = InputHandler.new()
	InputHandler._set_instance(input_handler)
	
	position_manager = PositionManager.new()
	PositionManager._set_instance(position_manager)
	
	mode_state_machine = ModeStateMachine.new()
	ModeStateMachine._set_instance(mode_state_machine)
	
	grid_manager = GridManager.new()
	GridManager._set_instance(grid_manager)
	
	# Initialize core systems
	InputHandler.update_input_state({})  # Initialize with empty settings initially
	# Note: PositionManager.configure() is called when modes are started with transform_state
	OverlayManager.initialize_overlays()
	
	# Initialize thumbnail system
	ThumbnailGenerator.initialize()
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "All systems initialized")

func _cleanup_systems():
	"""Clean up all manager systems with error handling"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Starting system cleanup...")
	
	# Wrap each cleanup to prevent cascade failures
	# Exit any active modes first
	_safe_cleanup("TransformationCoordinator.exit_any_mode", func(): TransformationCoordinator.exit_any_mode())
	
	# Clean up UI and visual systems
	_safe_cleanup("OverlayManager.cleanup_all_overlays", func(): OverlayManager.cleanup_all_overlays())
	_safe_cleanup("PreviewManager.cleanup_preview", func(): PreviewManager.cleanup_preview())
	
	# Clean up core systems
	_safe_cleanup("TransformationCoordinator.cleanup_all", func(): TransformationCoordinator.cleanup_all())
	_safe_cleanup("SmoothTransformManager.cleanup_all", func(): SmoothTransformManager.cleanup_all())
	
	# Clean up thumbnail systems
	_safe_cleanup("ThumbnailGenerator.cleanup", func(): ThumbnailGenerator.cleanup())
	_safe_cleanup("ThumbnailQueueManager.cleanup", func(): ThumbnailQueueManager.cleanup())
	
	# Clean up placement system
	_safe_cleanup("PlacementStrategyManager.cleanup", func(): PlacementStrategyManager.cleanup())
	
	# Clear manager instances (Phase 5.2: Instance-based architecture)
	if transformation_coordinator:
		transformation_coordinator.cleanup()
		TransformationCoordinator._set_instance(null)
		transformation_coordinator = null
	
	if overlay_manager:
		OverlayManager._set_instance(null)
		overlay_manager = null
	
	if preview_manager:
		PreviewManager._set_instance(null)
		preview_manager = null
	
	if smooth_transform_manager:
		smooth_transform_manager.cleanup()
		SmoothTransformManager._set_instance(null)
		smooth_transform_manager = null
	
	if input_handler:
		InputHandler._set_instance(null)
		input_handler = null
	
	if position_manager:
		PositionManager._set_instance(null)
		position_manager = null
	
	if mode_state_machine:
		ModeStateMachine._set_instance(null)
		mode_state_machine = null
	
	if grid_manager:
		GridManager._set_instance(null)
		grid_manager = null
	
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
	
	# Connect dock signals
	dock.asset_selected.connect(_on_asset_selected)
	dock.meshlib_item_selected.connect(_on_meshlib_item_selected)
	
	# Add to Godot dock
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Store dock reference for UI updates
	TransformationCoordinator.dock_reference = dock
	
	# Set PlacementSettings reference for status overlay (deferred to ensure dock is fully initialized)
	call_deferred("_connect_placement_settings_to_overlay")
	
	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Dock setup complete")

func _connect_placement_settings_to_overlay():
	"""Connect the PlacementSettings reference to the status overlay"""
	if dock and dock.has_method("get_placement_settings_instance"):
		var placement_settings = dock.get_placement_settings_instance()
		if placement_settings:
			OverlayManager.set_placement_settings_reference(placement_settings)
			PluginLogger.info(PluginConstants.COMPONENT_DOCK, "PlacementSettings reference connected to overlay")

func _cleanup_dock():
	"""Clean up the dock"""
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	
	# Clear dock reference
	TransformationCoordinator.dock_reference = null

## Toolbar Management

func _setup_toolbar():
	"""Set up the toolbar buttons in 3D viewport"""
	if ToolbarButtonsScene:
		toolbar_buttons = ToolbarButtonsScene.instantiate()
		
		# Add to spatial editor menu container
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_buttons)
		
		# Set PlacementSettings reference (deferred to ensure dock is fully initialized)
		call_deferred("_connect_placement_settings_to_toolbar")
		
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Toolbar setup complete")

func _connect_placement_settings_to_toolbar():
	"""Connect the PlacementSettings reference to the toolbar"""
	if dock and dock.has_method("get_placement_settings_instance") and toolbar_buttons:
		var placement_settings = dock.get_placement_settings_instance()
		if placement_settings and toolbar_buttons.has_method("set_placement_settings"):
			toolbar_buttons.set_placement_settings(placement_settings)
			OverlayManager.set_toolbar_reference(toolbar_buttons)
			PluginLogger.info(PluginConstants.COMPONENT_MAIN, "PlacementSettings reference connected to toolbar")

func _cleanup_toolbar():
	"""Clean up the toolbar"""
	if toolbar_buttons:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_buttons)
		toolbar_buttons.queue_free()
		toolbar_buttons = null
	
	# Clear toolbar reference in OverlayManager
	OverlayManager.set_toolbar_reference(null)

## Settings Management

func _load_settings():
	"""Load plugin settings from file or use defaults"""
	# Try to load from file, fallback to defaults
	SettingsManager.load_from_file()
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings loaded")

## Core Processing Loop

func _get_frame_settings() -> Dictionary:
	"""
	Get combined settings for the current frame (cached).
	
	Performance optimization: Settings are fetched once per frame and cached.
	This avoids redundant EditorSettings queries when settings are accessed
	multiple times within the same frame.
	
	Cache automatically invalidates each frame via frame number check.
	"""
	var current_frame = Engine.get_process_frames()
	
	if _settings_cache_frame != current_frame:
		# Cache miss - fetch fresh settings
		_cached_settings = SettingsManager.get_combined_settings()
		_settings_cache_frame = current_frame
	
	# Cache hit - return cached settings
	return _cached_settings

func _process(delta: float) -> void:
	"""Main processing loop - delegates everything to TransformationCoordinator"""
	if not _is_plugin_ready():
		return
	
	# Get current camera for positioning
	var camera = _get_current_camera()
	if not camera:
		return
	
	# Update dock settings in SettingsManager if available
	if dock and dock.has_method("get_placement_settings"):
		var dock_settings = dock.get_placement_settings()
		SettingsManager.set_dock_settings(dock_settings)
		# Invalidate cache when settings change
		_settings_cache_frame = -1
	
	# Delegate frame processing to coordinator with cached settings (Task 3.3 optimization)
	TransformationCoordinator.process_frame_input(camera, _get_frame_settings(), delta)
	
	# Update transform mode button state
	if toolbar_buttons and toolbar_buttons.has_method("set_transform_mode_active"):
		toolbar_buttons.set_transform_mode_active(TransformationCoordinator.is_transform_mode())

func _is_plugin_ready() -> bool:
	"""Check if plugin is ready for processing"""
	return dock != null

func _get_current_camera() -> Camera3D:
	"""Get the current 3D viewport camera"""
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if viewport_3d:
		return viewport_3d.get_camera_3d()
	return null

## Input Handling (Minimal - delegates to TransformationCoordinator)

func handles(object) -> bool:
	"""Check if we should handle input for this object"""
	return TransformationCoordinator.is_any_mode_active()

func _input(event: InputEvent) -> void:
	"""Handle input at the highest priority to prevent TAB focus issues and mouse wheel zoom"""
	
	# Handle mouse wheel events when modes are active to prevent viewport zoom
	if event is InputEventMouseButton and TransformationCoordinator.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if TransformationCoordinator.handle_mouse_wheel_input(event):
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
		
		# Update dock settings in SettingsManager
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			SettingsManager.set_dock_settings(dock_settings)
		
		# Check if this is the transform mode key
		var transform_key = SettingsManager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Only handle if we have a selected Node3D
			var selection = EditorInterface.get_selection()
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
		
		# Update dock settings in SettingsManager
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			SettingsManager.set_dock_settings(dock_settings)
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = SettingsManager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event immediately to prevent focus change
			get_viewport().set_input_as_handled()
			# Let TransformationCoordinator handle the actual mode activation
			return
		
		# For other plugin keys, only handle when modes are active
		if TransformationCoordinator.is_any_mode_active():
			# Check if this key matches any of our plugin keybindings
			if SettingsManager.is_plugin_key(full_key_string) or SettingsManager.is_plugin_key(key_string):
				# This is our key - consume it to prevent Godot from processing it
				get_viewport().set_input_as_handled()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	"""Forward 3D GUI input - intercept and consume plugin-related keys and mouse wheel"""
	
	# Handle mouse wheel events when modes are active
	if event is InputEventMouseButton and TransformationCoordinator.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if TransformationCoordinator.handle_mouse_wheel_input(event):
				# Event was handled - consume it IMMEDIATELY to prevent viewport zoom
				# Mark as handled first, then return stop
				event.set_canceled(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	
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
		
		# Update dock settings in SettingsManager
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			SettingsManager.set_dock_settings(dock_settings)
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = SettingsManager.get_setting("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event to prevent focus change 
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# For other plugin keys, only handle when modes are active
		if not TransformationCoordinator.is_any_mode_active():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		
		# Check if this key matches any of our plugin keybindings
		if SettingsManager.is_plugin_key(full_key_string) or SettingsManager.is_plugin_key(key_string):
			# This is our key - consume it to prevent Godot from processing it
			# Mark the event as handled and STOP further processing
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	# Let Godot handle other inputs
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	"""Handle canvas/2D GUI input - also intercept plugin keys"""
	
	# Only handle input when plugin modes are active
	if not TransformationCoordinator.is_any_mode_active():
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
		
		# Update dock settings in SettingsManager
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			SettingsManager.set_dock_settings(dock_settings)
		
		# Check if this key matches any of our plugin keybindings
		if SettingsManager.is_plugin_key(full_key_string) or SettingsManager.is_plugin_key(key_string):
			# This is our key - consume it to prevent Godot from processing it
			return true
	
	# Let Godot handle other inputs
	return false

## Asset Selection Handlers (From Dock)

func _on_asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary):
	"""Handle asset selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Asset selected: " + asset_path)
	
	# Update dock settings and get combined settings
	SettingsManager.update_dock_settings(settings)
	_settings_cache_frame = -1  # Invalidate cache when settings change
	var combined_settings = _get_frame_settings()  # Use cached getter
	
	# Start placement mode through the coordinator
	if mesh_resource and mesh_resource is Mesh:
		TransformationCoordinator.start_placement_mode(mesh_resource, null, -1, "", combined_settings, dock)
	else:
		TransformationCoordinator.start_placement_mode(null, null, -1, asset_path, combined_settings, dock)
	
	# Show user feedback
	OverlayManager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	"""Handle MeshLibrary item selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "MeshLib item selected: " + str(item_id))
	
	# Update dock settings and get combined settings
	SettingsManager.update_dock_settings(settings)
	_settings_cache_frame = -1  # Invalidate cache when settings change
	var combined_settings = _get_frame_settings()  # Use cached getter
	
	# Start placement mode through the coordinator
	TransformationCoordinator.start_placement_mode(null, meshlib, item_id, "", combined_settings, dock)
	
	# Show user feedback
	OverlayManager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

## Settings and Configuration

func update_plugin_settings(new_settings: Dictionary):
	"""Update plugin settings"""
	SettingsManager.set_plugin_settings(new_settings)
	_settings_cache_frame = -1  # Invalidate cache when settings change
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings updated")

func get_plugin_settings() -> Dictionary:
	"""Get current plugin settings (cached per frame)"""
	return _get_frame_settings()

## Debug and Information

func get_system_status() -> Dictionary:
	"""Get status of all systems for debugging"""
	return {
		"plugin_ready": _is_plugin_ready(),
		"dock_exists": dock != null,
		"current_mode": TransformationCoordinator.get_current_mode(),
		"has_camera": _get_current_camera() != null,
		"settings_loaded": SettingsManager.get_settings_summary()["plugin_settings_count"] > 0
	}

func debug_print_status():
	"""Print system status for debugging"""
	var status = get_system_status()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "System Status:")
	for key in status:
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  " + key + ": " + str(status[key]))







