@tool
extends EditorPlugin

# Main Plugin
# Only handles editor integration and delegates everything to TransformationManager

# Import specialized managers
const InputHandler = preload("res://addons/simpleassetplacer/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/overlay_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const TransformationManager = preload("res://addons/simpleassetplacer/transformation_manager.gd")

# Import dock and utilities (keep existing)
const AssetPlacerDock = preload("res://addons/simpleassetplacer/asset_placer_dock.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")
const ThumbnailQueueManager = preload("res://addons/simpleassetplacer/thumbnail_queue_manager.gd")

# Plugin state
var dock: AssetPlacerDock
var _settings: Dictionary = {}

## Plugin Lifecycle

func _enable_plugin() -> void:
	print("AssetPlacer: Plugin enabled")

func _disable_plugin() -> void:
	print("AssetPlacer: Plugin disabled")

func _enter_tree() -> void:
	print("AssetPlacer: Initializing...")
	
	# Initialize systems in order
	_initialize_systems()
	_setup_dock()
	_load_settings()
	
	# Enable input forwarding for reliable input handling
	set_input_event_forwarding_always_enabled()
	
	print("AssetPlacer: Initialization complete!")

func _exit_tree() -> void:
	print("AssetPlacer: Cleaning up...")
	
	# Clean up in reverse order
	_cleanup_systems()
	_cleanup_dock()
	
	print("AssetPlacer: Cleanup complete!")

## System Initialization

func _initialize_systems():
	"""Initialize all manager systems"""
	# Initialize core systems
	InputHandler.update_input_state({})  # Initialize with empty settings initially
	PositionManager.configure({})
	OverlayManager.initialize_overlays()
	PreviewManager.initialize()
	
	# Initialize thumbnail system
	ThumbnailGenerator.initialize()
	
	print("AssetPlacer: All systems initialized")

func _cleanup_systems():
	"""Clean up all manager systems"""
	# Exit any active modes
	TransformationManager.exit_any_mode()
	
	# Clean up systems
	OverlayManager.cleanup_all_overlays()
	PreviewManager.cleanup_preview()
	TransformationManager.cleanup()
	ThumbnailGenerator.cleanup()
	ThumbnailQueueManager.cleanup()

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
	
	print("AssetPlacer: Dock setup complete")

func _cleanup_dock():
	"""Clean up the dock"""
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null

## Settings Management

func _load_settings():
	"""Load plugin settings"""
	# Load default settings (could be enhanced to load from file)
	_settings = {
		"cancel_key": "ESCAPE",
		"height_up_key": "Q", 
		"height_down_key": "E",
		"rotate_x_key": "X",
		"rotate_y_key": "Y", 
		"rotate_z_key": "Z",
		"reset_rotation_key": "T",
		"scale_up_key": "PAGE_UP",
		"scale_down_key": "PAGE_DOWN",
		"scale_reset_key": "HOME",
		"collision_enabled": true,
		"snap_to_ground": true,
		"height_step_size": 0.1,
		"preview_opacity": 0.6
	}
	
	print("AssetPlacer: Settings loaded")

## Core Processing Loop

func _process(delta: float) -> void:
	"""Main processing loop - delegates everything to TransformationManager"""
	if not _is_plugin_ready():
		return
	
	# Get current camera for positioning
	var camera = _get_current_camera()
	if not camera:
		return
	
	# Delegate frame processing to coordinator
	# Get current settings from dock if available, otherwise use defaults
	var current_settings = _settings.duplicate()
	if dock and dock.has_method("get_placement_settings"):
		var dock_settings = dock.get_placement_settings()
		# Use merge with overwrite to ensure dock settings take priority
		current_settings.merge(dock_settings, true)  # true = overwrite existing keys
	
	TransformationManager.process_frame_input(camera, current_settings)

func _is_plugin_ready() -> bool:
	"""Check if plugin is ready for processing"""
	return dock != null

func _get_current_camera() -> Camera3D:
	"""Get the current 3D viewport camera"""
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if viewport_3d:
		return viewport_3d.get_camera_3d()
	return null

## Input Handling (Minimal - delegates to TransformationManager)

func handles(object) -> bool:
	"""Check if we should handle input for this object"""
	return TransformationManager.is_any_mode_active()

func _input(event: InputEvent) -> void:
	"""Handle input at the highest priority to prevent TAB focus issues and mouse wheel zoom"""
	
	# Handle mouse wheel events when modes are active to prevent viewport zoom
	if event is InputEventMouseButton and TransformationManager.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if TransformationManager.handle_mouse_wheel_input(event):
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
		
		# Get current settings for transform mode key
		var current_settings = {}
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			current_settings.merge(_settings, true)
			current_settings.merge(dock_settings, true)
		
		# Check if this is the transform mode key
		var transform_key = current_settings.get("transform_mode_key", "TAB")
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
		
		# Get current dock settings for key mappings
		var current_settings = {}
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			current_settings.merge(_settings, true)
			current_settings.merge(dock_settings, true)
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = current_settings.get("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event immediately to prevent focus change
			get_viewport().set_input_as_handled()
			# Let TransformationManager handle the actual mode activation
			return
		
		# For other plugin keys, only handle when modes are active
		if TransformationManager.is_any_mode_active():
			# Check if this key matches any of our plugin keybindings
			if _is_plugin_key(full_key_string, current_settings) or _is_plugin_key(key_string, current_settings):
				# This is our key - consume it to prevent Godot from processing it
				get_viewport().set_input_as_handled()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	"""Forward 3D GUI input - intercept and consume plugin-related keys and mouse wheel"""
	
	# Handle mouse wheel events when modes are active
	if event is InputEventMouseButton and TransformationManager.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if we should handle this event (action key is held)
			if TransformationManager.handle_mouse_wheel_input(event):
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
		
		# Get current dock settings for key mappings
		var current_settings = {}
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			current_settings.merge(_settings, true)
			current_settings.merge(dock_settings, true)
		
		# Special handling for transform mode key - intercept even when no mode is active
		var transform_key = current_settings.get("transform_mode_key", "TAB")
		if key_string == transform_key or full_key_string == transform_key:
			# Consume the event to prevent focus change 
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# For other plugin keys, only handle when modes are active
		if not TransformationManager.is_any_mode_active():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		
		# Get current dock settings for key mappings
		var settings_for_keys = {}
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			settings_for_keys.merge(_settings, true)
			settings_for_keys.merge(dock_settings, true)
		
		# Check if this key matches any of our plugin keybindings
		if _is_plugin_key(full_key_string, settings_for_keys) or _is_plugin_key(key_string, settings_for_keys):
			# This is our key - consume it to prevent Godot from processing it
			# Mark the event as handled to prevent further processing
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Let Godot handle other inputs
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	"""Handle canvas/2D GUI input - also intercept plugin keys"""
	
	# Only handle input when plugin modes are active
	if not TransformationManager.is_any_mode_active():
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
		
		# Get current dock settings for key mappings
		var current_settings = {}
		if dock and dock.has_method("get_placement_settings"):
			var dock_settings = dock.get_placement_settings()
			current_settings.merge(_settings, true)
			current_settings.merge(dock_settings, true)
		
		# Check if this key matches any of our plugin keybindings
		if _is_plugin_key(full_key_string, current_settings) or _is_plugin_key(key_string, current_settings):
			# This is our key - consume it to prevent Godot from processing it
			return true
	
	# Let Godot handle other inputs
	return false

func _is_plugin_key(key_string: String, settings: Dictionary) -> bool:
	"""Check if a key string matches any plugin keybinding"""
	var plugin_keys = [
		"cancel_key",
		"transform_mode_key", 
		"height_up_key",
		"height_down_key",
		"rotate_x_key",
		"rotate_y_key", 
		"rotate_z_key",
		"reset_rotation_key",
		"scale_up_key",
		"scale_down_key",
		"scale_reset_key",
		"reverse_modifier_key",
		"large_increment_modifier_key"
	]
	
	for plugin_key in plugin_keys:
		if settings.get(plugin_key, "") == key_string:
			return true
	
	return false

## Asset Selection Handlers (From Dock)

func _on_asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary):
	"""Handle asset selection from dock"""
	print("AssetPlacer: Asset selected: ", asset_path)
	
	# Merge dock settings with plugin settings
	var combined_settings = _settings.duplicate()
	combined_settings.merge(settings)
	
	# Start placement mode through the coordinator
	if mesh_resource and mesh_resource is Mesh:
		TransformationManager.start_placement_mode(mesh_resource, null, -1, "", combined_settings, dock)
	else:
		TransformationManager.start_placement_mode(null, null, -1, asset_path, combined_settings, dock)
	
	# Show user feedback
	OverlayManager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	"""Handle MeshLibrary item selection from dock"""
	print("AssetPlacer: MeshLib item selected: ", item_id)
	
	# Merge dock settings with plugin settings
	var combined_settings = _settings.duplicate()
	combined_settings.merge(settings)
	
	# Start placement mode through the coordinator
	TransformationManager.start_placement_mode(null, meshlib, item_id, "", combined_settings, dock)
	
	# Show user feedback
	OverlayManager.show_status_message("Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0)

## Settings and Configuration

func update_plugin_settings(new_settings: Dictionary):
	"""Update plugin settings"""
	_settings.merge(new_settings)
	print("AssetPlacer: Settings updated")

func get_plugin_settings() -> Dictionary:
	"""Get current plugin settings"""
	return _settings.duplicate()

## Debug and Information

func get_system_status() -> Dictionary:
	"""Get status of all systems for debugging"""
	return {
		"plugin_ready": _is_plugin_ready(),
		"dock_exists": dock != null,
		"current_mode": TransformationManager.get_current_mode(),
		"has_camera": _get_current_camera() != null,
		"settings_loaded": not _settings.is_empty()
	}

func debug_print_status():
	"""Print system status for debugging"""
	var status = get_system_status()
	print("AssetPlacer System Status:")
	for key in status:
		print("  ", key, ": ", status[key])