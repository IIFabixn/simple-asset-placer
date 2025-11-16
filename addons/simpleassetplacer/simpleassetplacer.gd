@tool
extends EditorPlugin

# Main Plugin
# Handles editor integration using instance-based architecture with ServiceRegistry

# Import core infrastructure
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ErrorHandler = preload("res://addons/simpleassetplacer/utils/error_handler.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const ServiceRegistryBuilder = preload(
	"res://addons/simpleassetplacer/core/service_registry_builder.gd"
)

# Import editor helpers
const DockManager = preload("res://addons/simpleassetplacer/editor/dock_manager.gd")
const ToolbarManager = preload("res://addons/simpleassetplacer/editor/toolbar_manager.gd")
const SceneTreeContextMenuManager = preload(
	"res://addons/simpleassetplacer/editor/scene_tree_context_menu_manager.gd"
)
const InputRouter = preload("res://addons/simpleassetplacer/editor/input_router.gd")

# Plugin state
var dock_manager: DockManager
var toolbar_manager: ToolbarManager
var scene_tree_context_menu_manager: SceneTreeContextMenuManager
var input_router: InputRouter
var filesystem_dock: Control = null

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
	_initialize_editor_integration()
	_setup_filesystem_context_menu()

	# Enable input forwarding for reliable input handling
	set_input_event_forwarding_always_enabled()

	PluginLogger.log_initialization_complete(PluginConstants.COMPONENT_MAIN)


func _exit_tree() -> void:
	PluginLogger.log_cleanup(PluginConstants.COMPONENT_MAIN)

	# Clean up in reverse order
	_cleanup_editor_integration()
	_cleanup_systems()
	_cleanup_filesystem_context_menu()

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

	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "All systems initialized")


func _cleanup_systems():
	"""Clean up all manager systems with error handling"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Starting system cleanup...")

	if not service_registry:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "No service registry to clean up")
		return

	# Exit any active modes first
	if service_registry.transformation_coordinator:
		_safe_cleanup(
			"TransformationCoordinator.exit_any_mode",
			func(): service_registry.transformation_coordinator.exit_any_mode()
		)

	# Clean up UI and visual systems via instance references
	if service_registry.overlay_manager:
		_safe_cleanup(
			"OverlayManager.cleanup_all_overlays",
			func(): service_registry.overlay_manager.cleanup_all_overlays()
		)
	if service_registry.preview_manager:
		_safe_cleanup(
			"PreviewManager.cleanup_preview",
			func(): service_registry.preview_manager.cleanup_preview()
		)

	# Clean up core systems
	if service_registry.transformation_coordinator:
		_safe_cleanup(
			"TransformationCoordinator.cleanup",
			func(): service_registry.transformation_coordinator.cleanup()
		)
	if service_registry.smooth_transform_manager:
		_safe_cleanup(
			"SmoothTransformManager.cleanup_all",
			func(): service_registry.smooth_transform_manager.cleanup_all()
		)

	# Clean up thumbnail systems
	if service_registry and service_registry.thumbnail_service:
		_safe_cleanup(
			"ThumbnailService.cleanup",
			func(): service_registry.thumbnail_service.cleanup()
		)

	# Clean up placement system
	if service_registry and service_registry.placement_strategy_service:
		_safe_cleanup(
			"PlacementStrategyService.cleanup",
			func(): service_registry.placement_strategy_service.cleanup()
		)

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
		PluginLogger.warning(
			PluginConstants.COMPONENT_MAIN,
			"✗ %s cleanup skipped - invalid callable" % component_name
		)
		return

	# Execute cleanup - any errors will be caught by Godot's error system
	# but won't crash the plugin entirely
	cleanup_func.call()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "✓ %s cleaned up" % component_name)


## Editor Integration


func _initialize_editor_integration() -> void:
	if not service_registry:
		PluginLogger.warning(
			PluginConstants.COMPONENT_MAIN,
			"Cannot initialize editor integration without service registry"
		)
		return

	dock_manager = DockManager.new(self, service_registry)
	dock_manager.setup()

	toolbar_manager = ToolbarManager.new(self, service_registry)
	toolbar_manager.set_dock_manager(dock_manager)
	toolbar_manager.setup()

	scene_tree_context_menu_manager = SceneTreeContextMenuManager.new(self, service_registry)
	scene_tree_context_menu_manager.setup(_get_dock())

	input_router = InputRouter.new(self, service_registry)


func _cleanup_editor_integration() -> void:
	if toolbar_manager:
		toolbar_manager.cleanup()
		toolbar_manager = null

	if scene_tree_context_menu_manager:
		scene_tree_context_menu_manager.cleanup()
		scene_tree_context_menu_manager = null

	if dock_manager:
		dock_manager.cleanup()
		dock_manager = null

	if input_router:
		input_router.cleanup()
		input_router = null


func _get_dock():
	return dock_manager.get_dock() if dock_manager else null


## FileSystem Dock Context Menu Management


func _setup_filesystem_context_menu():
	"""Set up FileSystem dock context menu integration"""
	filesystem_dock = get_editor_interface().get_file_system_dock()

	if filesystem_dock:
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "FileSystem dock reference obtained")
	else:
		PluginLogger.warning(
			PluginConstants.COMPONENT_MAIN, "Could not get FileSystem dock reference"
		)


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
	service_registry.transformation_coordinator.process_frame_input(
		camera, service_registry.settings_manager.get_combined_settings(), delta
	)

	# Update transform mode button state
	if toolbar_manager:
		toolbar_manager.set_transform_mode_active(
			service_registry.transformation_coordinator.is_transform_mode()
		)


func _is_plugin_ready() -> bool:
	"""Check if plugin is ready for processing"""
	return dock_manager and dock_manager.is_ready()


func _get_current_camera() -> Camera3D:
	"""Get the current 3D viewport camera"""
	if not service_registry or not service_registry.editor_interface:
		return null
	var viewport_3d = service_registry.editor_interface.get_editor_viewport_3d(0)
	if viewport_3d:
		return viewport_3d.get_camera_3d()
	return null


## Input Handling (Minimal - delegates to TransformationCoordinator)


func handles(object) -> bool:
	if input_router:
		return input_router.handles(object)
	return false


func _input(event: InputEvent) -> void:
	if input_router:
		input_router.process_input(event)


func _shortcut_input(event: InputEvent) -> void:
	if input_router:
		input_router.process_shortcut(event)


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if input_router:
		return input_router.forward_3d_gui_input(viewport_camera, event)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if input_router:
		return input_router.forward_canvas_gui_input(event)
	return false


func _on_asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary):
	"""Handle asset selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Asset selected: " + asset_path)

	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN,
			"Cannot start placement mode - service registry not initialized"
		)
		return

	# Update dock settings and get combined settings
	service_registry.settings_manager.update_dock_settings(settings)
	var combined_settings = service_registry.settings_manager.get_combined_settings()
	var dock_instance = _get_dock()

	# Start placement mode through the coordinator
	if mesh_resource and mesh_resource is Mesh:
		service_registry.transformation_coordinator.start_placement_mode(
			mesh_resource, null, -1, "", combined_settings, dock_instance
		)
	else:
		service_registry.transformation_coordinator.start_placement_mode(
			null, null, -1, asset_path, combined_settings, dock_instance
		)

	# Show user feedback
	if service_registry and service_registry.overlay_manager:
		service_registry.overlay_manager.show_status_message(
			"Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0
		)


func trigger_transform_mode(selected_nodes: Array) -> void:
	"""Trigger transform mode for selected nodes (from context menu)
	
	Args:
		selected_nodes: Array of Node3D objects selected in the scene tree
	"""
	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN,
			"Cannot start transform mode - service registry not initialized"
		)
		return

	# Filter to only Node3D objects
	var node3d_nodes = selected_nodes.filter(func(node): return node is Node3D)

	if node3d_nodes.is_empty():
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "No valid Node3D objects to transform")
		return

	PluginLogger.info(
		PluginConstants.COMPONENT_MAIN,
		"Transform mode triggered for %d node(s)" % node3d_nodes.size()
	)

	# Start transform mode with selected nodes
	service_registry.transformation_coordinator.start_transform_mode(node3d_nodes, _get_dock())


func trigger_pickup_mode(selected_nodes: Array) -> void:
	"""Trigger pickup mode for selected nodes (from context menu or keybind)
	
	Args:
		selected_nodes: Array of Node objects selected in the scene tree
	"""
	const PickupHandler = preload("res://addons/simpleassetplacer/utils/pickup_handler.gd")

	PluginLogger.info(
		PluginConstants.COMPONENT_MAIN,
		"Pickup mode triggered for %d node(s)" % selected_nodes.size()
	)

	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN,
			"Cannot start pickup mode - service registry not initialized"
		)
		return

	# Extract pickup data from selected nodes
	var pickup_data = PickupHandler.extract_pickup_data(selected_nodes)

	if not pickup_data.success:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN, "Pickup failed: " + pickup_data.error_message
		)
		if service_registry.overlay_manager:
			service_registry.overlay_manager.show_status_message(
				"Pickup failed: " + pickup_data.error_message, Color.RED, 3.0
			)
		return

	# Get current settings
	var combined_settings = service_registry.settings_manager.get_combined_settings()

	# Apply initial transform from picked node
	combined_settings["initial_scale"] = pickup_data.initial_scale
	combined_settings["initial_rotation"] = pickup_data.initial_rotation

	# Start placement mode with picked asset
	if pickup_data.packed_scene:
		# Use PackedScene directly (for non-instanced nodes or multi-selection)
		service_registry.transformation_coordinator.start_placement_mode_with_scene(
			pickup_data.packed_scene, combined_settings, _get_dock()
		)
	elif not pickup_data.asset_path.is_empty():
		# Use scene file path (for instanced scenes)
		service_registry.transformation_coordinator.start_placement_mode(
			null, null, -1, pickup_data.asset_path, combined_settings, _get_dock()
		)
	else:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "Invalid pickup data - no asset")
		return

	# Show user feedback
	var node_label = "node" if pickup_data.node_count == 1 else "%d nodes" % pickup_data.node_count
	if service_registry.overlay_manager:
		service_registry.overlay_manager.show_status_message(
			"Picked up %s - Left-click to place, ESC to exit" % node_label, Color.GREEN, 3.0
		)


func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	"""Handle MeshLibrary item selection from dock"""
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "MeshLib item selected: " + str(item_id))

	if not service_registry or not service_registry.transformation_coordinator:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN,
			"Cannot start placement mode - service registry not initialized"
		)
		return

	# Update dock settings and get combined settings
	service_registry.settings_manager.update_dock_settings(settings)
	var combined_settings = service_registry.settings_manager.get_combined_settings()

	# Extract mesh from meshlib for placement
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		PluginLogger.error(
			PluginConstants.COMPONENT_MAIN,
			"Failed to get mesh for item_id: " + str(item_id)
		)
		return

	# Start placement mode through the coordinator
	service_registry.transformation_coordinator.start_placement_mode(
		mesh, meshlib, item_id, "", combined_settings, _get_dock()
	)

	# Show user feedback
	if service_registry and service_registry.overlay_manager:
		service_registry.overlay_manager.show_status_message(
			"Placement mode started - Left-click to place, ESC to exit", Color.GREEN, 3.0
		)


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
		"dock_exists": _get_dock() != null,
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
