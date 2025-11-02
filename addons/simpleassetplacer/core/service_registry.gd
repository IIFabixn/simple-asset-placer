@tool
extends RefCounted

class_name ServiceRegistry

"""
SERVICE REGISTRY
================

PURPOSE: Lightweight container for all plugin service/manager instances

RESPONSIBILITIES:
- Hold references to all manager instances
- Provide explicit dependency injection
- Make service wiring clear and testable
- No logic, just storage and access

ARCHITECTURE POSITION: Service container
- Created by SimpleAssetPlacer during _enter_tree
- Passed to managers that need access to other services
- Destroyed during _exit_tree

USED BY: SimpleAssetPlacer, all managers
"""

# Note: All type hints reference global class_name declarations, not local preloads
# This avoids shadowing class names with GDScript resource references

# Core editor interface
var editor_interface: EditorInterface

# Settings and configuration
var settings_manager: SettingsManager
var settings_persistence: SettingsPersistence

# Core managers
var transformation_coordinator: TransformationCoordinator
var position_manager: PositionManager
var rotation_manager: RotationManager
var scale_manager: ScaleManager
var grid_manager: GridManager
var mode_state_machine: ModeStateMachine
var control_mode_state: ControlModeState

# UI managers
var preview_manager: PreviewManager
var overlay_manager: OverlayManager
var input_handler: InputHandler

# Transform managers
var smooth_transform_manager: SmoothTransformManager
var transform_applicator: TransformApplicator

# Placement system
var placement_strategy_service: PlacementStrategyService
var transform_action_router: TransformActionRouter

# Utility managers
var utility_manager: UtilityManager
var category_manager: CategoryManager
var undo_redo_helper: UndoRedoHelper
var cursor_warp_adapter: CursorWarpAdapter

# Thumbnail system
var thumbnail_generator: ThumbnailGenerator
var thumbnail_queue_manager: ThumbnailQueueManager

# Transform state (shared)
var transform_state: TransformState

# Undo/Redo manager (from editor)
var undo_redo: EditorUndoRedoManager

## Initialization

func _init() -> void:
	"""Initialize empty registry"""
	pass

## Validation

func validate() -> bool:
	"""Validate that all critical services are registered
	
	Returns:
		bool: True if all required services are present
	"""
	var valid = true
	
	if not editor_interface:
		push_error("ServiceRegistry: editor_interface is not registered")
		valid = false
	
	if not transformation_coordinator:
		push_error("ServiceRegistry: transformation_coordinator is not registered")
		valid = false
	
	if not position_manager:
		push_error("ServiceRegistry: position_manager is not registered")
		valid = false
	
	if not preview_manager:
		push_error("ServiceRegistry: preview_manager is not registered")
		valid = false
	
	if not overlay_manager:
		push_error("ServiceRegistry: overlay_manager is not registered")
		valid = false
	
	return valid

## Cleanup

func cleanup() -> void:
	"""Clear all references"""
	editor_interface = null
	settings_manager = null
	settings_persistence = null
	transformation_coordinator = null
	position_manager = null
	rotation_manager = null
	scale_manager = null
	grid_manager = null
	mode_state_machine = null
	control_mode_state = null
	preview_manager = null
	overlay_manager = null
	input_handler = null
	smooth_transform_manager = null
	transform_applicator = null
	placement_strategy_service = null
	transform_action_router = null
	utility_manager = null
	category_manager = null
	cursor_warp_adapter = null
	thumbnail_generator = null
	thumbnail_queue_manager = null
	transform_state = null
	undo_redo = null
