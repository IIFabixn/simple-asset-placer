@tool
extends RefCounted

class_name ServiceRegistryBuilder

"""
SERVICE REGISTRY BUILDER
========================

PURPOSE: Fluent builder pattern for constructing ServiceRegistry with all dependencies

RESPONSIBILITIES:
- Provide chainable methods for registering services
- Validate required dependencies
- Build and return fully configured ServiceRegistry
- Make service wiring explicit and readable

ARCHITECTURE POSITION: Factory/Builder for ServiceRegistry
- Used by SimpleAssetPlacer during _enter_tree
- Simplifies the complex initialization process
- Enables easier testing with mock services

USAGE:
	var registry = ServiceRegistryBuilder.new(editor_interface) \
		.with_settings() \
		.with_placement_strategies() \
		.with_core_managers() \
		.with_ui_managers() \
		.with_utility_managers() \
		.build()
"""

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const EditorFacade = preload("res://addons/simpleassetplacer/core/editor_facade.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const SettingsPersistence = preload("res://addons/simpleassetplacer/settings/settings_persistence.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")
const InputHandler = preload("res://addons/simpleassetplacer/managers/input_handler.gd")
const CursorWarpAdapter = preload("res://addons/simpleassetplacer/utils/cursor_warp_adapter.gd")
const PositionManager = preload("res://addons/simpleassetplacer/managers/position_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/managers/preview_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/managers/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const SmoothTransformManager = preload("res://addons/simpleassetplacer/managers/smooth_transform_manager.gd")
const GridManager = preload("res://addons/simpleassetplacer/managers/grid_manager.gd")
const TransformOperations = preload("res://addons/simpleassetplacer/core/transform_operations.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
const TransformActionRouter = preload("res://addons/simpleassetplacer/core/transform_action_router.gd")
const UtilityManager = preload("res://addons/simpleassetplacer/managers/utility_manager.gd")
const UndoRedoHelper = preload("res://addons/simpleassetplacer/utils/undo_redo_helper.gd")
const CategoryManager = preload("res://addons/simpleassetplacer/managers/category_manager.gd")
const TransformationCoordinator = preload("res://addons/simpleassetplacer/core/transformation_coordinator.gd")
const ThumbnailQueueManager = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_queue_manager.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

var _registry: ServiceRegistry
var _editor_interface: EditorInterface

func _init(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_registry = ServiceRegistry.new()


## Fluent Builder Methods

func with_settings() -> ServiceRegistryBuilder:
	"""Initialize settings management"""
	_registry.settings_manager = SettingsManager.new()
	_registry.settings_persistence = SettingsPersistence.new()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Settings managers registered")
	return self


func with_placement_strategies() -> ServiceRegistryBuilder:
	"""Initialize placement strategy system"""
	_registry.placement_strategy_service = PlacementStrategyService.new()
	_registry.placement_strategy_service.initialize()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Placement strategies registered")
	return self


func with_editor_facade() -> ServiceRegistryBuilder:
	"""Initialize editor interface facade"""
	_registry.editor_facade = EditorFacade.new(_editor_interface)
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Editor facade registered")
	return self


func with_input_systems() -> ServiceRegistryBuilder:
	"""Initialize input handling systems"""
	_registry.input_handler = InputHandler.new(_registry)
	_registry.cursor_warp_adapter = CursorWarpAdapter.new()
	_registry.input_handler.update_input_state({})  # Initialize with empty settings
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Input systems registered")
	return self


func with_transform_managers() -> ServiceRegistryBuilder:
	"""Initialize transform calculation managers (position, rotation, scale)"""
	_registry.position_manager = PositionManager.new(_registry)
	_registry.rotation_manager = RotationManager.new(_registry)
	_registry.scale_manager = ScaleManager.new(_registry)
	_registry.smooth_transform_manager = SmoothTransformManager.new(_registry)
	_registry.transform_operations = TransformOperations.new(_registry)
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Transform managers registered")
	return self


func with_visual_managers() -> ServiceRegistryBuilder:
	"""Initialize visual/rendering managers (preview, overlay, grid)"""
	_registry.preview_manager = PreviewManager.new(_registry)
	_registry.overlay_manager = OverlayManager.new(_registry)
	_registry.grid_manager = GridManager.new(_registry)
	_registry.overlay_manager.initialize_overlays()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Visual managers registered")
	return self


func with_state_machines() -> ServiceRegistryBuilder:
	"""Initialize state management systems"""
	_registry.mode_state_machine = ModeStateMachine.new(_registry)
	_registry.control_mode_state = ControlModeState.new()
	_registry.transform_action_router = TransformActionRouter.new(_registry)
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: State machines registered")
	return self


func with_utility_managers() -> ServiceRegistryBuilder:
	"""Initialize utility systems (undo/redo, categories, scene utilities)"""
	_registry.utility_manager = UtilityManager.new(_registry)
	_registry.undo_redo_helper = UndoRedoHelper.new(_registry)
	_registry.category_manager = CategoryManager.new(_registry)
	_registry.thumbnail_queue_manager = ThumbnailQueueManager.new()
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Utility managers registered")
	return self


func with_transformation_coordinator() -> ServiceRegistryBuilder:
	"""Initialize the high-level transformation coordinator"""
	_registry.transformation_coordinator = TransformationCoordinator.new(_registry)
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "ServiceRegistry: Transformation coordinator registered")
	return self


## Validation & Build

func validate() -> bool:
	"""Validate that all required services are registered"""
	var valid := true
	var missing := []
	
	# Check critical services
	if not _registry.editor_facade:
		missing.append("editor_facade")
		valid = false
	
	if not _registry.settings_manager:
		missing.append("settings_manager")
		valid = false
	
	if not _registry.transformation_coordinator:
		missing.append("transformation_coordinator")
		valid = false
	
	if not _registry.position_manager:
		missing.append("position_manager")
		valid = false
	
	if not _registry.preview_manager:
		missing.append("preview_manager")
		valid = false
	
	if not _registry.overlay_manager:
		missing.append("overlay_manager")
		valid = false
	
	if not _registry.input_handler:
		missing.append("input_handler")
		valid = false
	
	if not _registry.mode_state_machine:
		missing.append("mode_state_machine")
		valid = false
	
	if not valid:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, 
			"ServiceRegistry validation failed. Missing services: " + str(missing))
	
	return valid


func build() -> ServiceRegistry:
	"""Build and return the configured ServiceRegistry
	
	Returns:
		ServiceRegistry with all configured services, or null if validation fails
	"""
	if not validate():
		push_error("ServiceRegistryBuilder: Validation failed, cannot build registry")
		return null
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "ServiceRegistry built successfully with all required services")
	return _registry


## Convenience Methods

static func create_full_registry(editor_interface: EditorInterface) -> ServiceRegistry:
	"""Convenience method to create a fully configured ServiceRegistry with all systems
	
	This is the standard initialization path for the plugin.
	"""
	return ServiceRegistryBuilder.new(editor_interface) \
		.with_settings() \
		.with_editor_facade() \
		.with_placement_strategies() \
		.with_input_systems() \
		.with_transform_managers() \
		.with_visual_managers() \
		.with_state_machines() \
		.with_utility_managers() \
		.with_transformation_coordinator() \
		.build()


static func create_minimal_registry(editor_interface: EditorInterface) -> ServiceRegistry:
	"""Create a minimal ServiceRegistry for testing purposes
	
	Includes only the core services needed for basic functionality.
	"""
	return ServiceRegistryBuilder.new(editor_interface) \
		.with_settings() \
		.with_editor_facade() \
		.with_placement_strategies() \
		.with_transform_managers() \
		.build()
