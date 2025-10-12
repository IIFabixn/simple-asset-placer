@tool
extends InstanceManagerBase

class_name TransformationCoordinator

"""
TRANSFORMATION COORDINATOR
==========================

PURPOSE: Lightweight orchestration layer for placement and transform operations

RESPONSIBILITIES:
- Public API for starting/exiting modes
- Settings management and distribution
- Callback registration and invocation
- Frame input coordination (delegates to mode handlers)
- Cleanup coordination
- TAB key handling
- Mouse wheel input delegation
- Navigation input (escape, strategy cycling)

ARCHITECTURE POSITION: Public API and orchestrator
- Called by main plugin (SimpleAssetPlacer)
- Delegates to mode handlers (PlacementModeHandler, TransformModeHandler)
- Manages mode state via ModeStateMachine
- Coordinates with GridManager for grid overlays

USED BY: SimpleAssetPlacer (main plugin)
USES: ModeStateMachine, PlacementModeHandler, TransformModeHandler, GridManager,
      InputHandler, PositionManager, OverlayManager, PreviewManager, SmoothTransformManager,
      SettingsManager, PlacementStrategyManager, PluginLogger
"""

# Import base class
const InstanceManagerBase = preload("res://addons/simpleassetplacer/core/instance_manager_base.gd")

# === SINGLETON INSTANCE ===

static var _instance: TransformationCoordinator = null

static func _set_instance(instance: InstanceManagerBase) -> void:
	_instance = instance as TransformationCoordinator

static func _get_instance() -> InstanceManagerBase:
	return _instance

static func has_instance() -> bool:
	return _instance != null and is_instance_valid(_instance)

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

# Import core components
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const GridManager = preload("res://addons/simpleassetplacer/core/grid_manager.gd")

# Import mode handlers
const PlacementModeHandler = preload("res://addons/simpleassetplacer/modes/placement_mode_handler.gd")
const TransformModeHandler = preload("res://addons/simpleassetplacer/modes/transform_mode_handler.gd")

# Import managers
const InputHandler = preload("res://addons/simpleassetplacer/managers/input_handler.gd")
const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/managers/preview_manager.gd")
const SmoothTransformManager = preload("res://addons/simpleassetplacer/core/smooth_transform_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
const UtilityManager = preload("res://addons/simpleassetplacer/managers/utility_manager.gd")

# Import settings and strategy managers
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")

# Import state
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

# === COORDINATOR STATE (INSTANCE-BASED) ===

# Instance variables (real data storage)
var _transform_state: TransformState = null
var _placement_data: Dictionary = {}
var _transform_data: Dictionary = {}
var _settings: Dictionary = {}
var _dock_reference = null
var _undo_redo: EditorUndoRedoManager = null
var _placement_end_callback: Callable
var _mesh_placed_callback: Callable
var _focus_grab_counter: int = 0

# === STATIC PROPERTIES (BACKWARD COMPATIBILITY) ===

# Unified transform state
static var transform_state: TransformState:
	get: return _get_instance()._transform_state if has_instance() else null
	set(value): if has_instance(): _get_instance()._transform_state = value

# Mode-specific data (managed by mode handlers, stored here)
static var placement_data: Dictionary:
	get: return _get_instance()._placement_data if has_instance() else {}
	set(value): if has_instance(): _get_instance()._placement_data = value

static var transform_data: Dictionary:
	get: return _get_instance()._transform_data if has_instance() else {}
	set(value): if has_instance(): _get_instance()._transform_data = value

# Settings reference
static var settings: Dictionary:
	get: return _get_instance()._settings if has_instance() else {}
	set(value): if has_instance(): _get_instance()._settings = value

# Dock reference (for UI updates)
static var dock_reference:
	get: return _get_instance()._dock_reference if has_instance() else null
	set(value): if has_instance(): _get_instance()._dock_reference = value

# Undo/Redo manager
static var undo_redo: EditorUndoRedoManager:
	get: return _get_instance()._undo_redo if has_instance() else null
	set(value): if has_instance(): _get_instance()._undo_redo = value

# Callbacks
static var placement_end_callback: Callable:
	get: return _get_instance()._placement_end_callback if has_instance() else Callable()
	set(value): if has_instance(): _get_instance()._placement_end_callback = value

static var mesh_placed_callback: Callable:
	get: return _get_instance()._mesh_placed_callback if has_instance() else Callable()
	set(value): if has_instance(): _get_instance()._mesh_placed_callback = value

# Focus management
static var focus_grab_counter: int:
	get: return _get_instance()._focus_grab_counter if has_instance() else 0
	set(value): if has_instance(): _get_instance()._focus_grab_counter = value

## MODE CONTROL (Public API)

static func start_placement_mode(
	mesh: Mesh = null,
	meshlib: MeshLibrary = null,
	item_id: int = -1,
	asset_path: String = "",
	placement_settings: Dictionary = {},
	dock_instance = null
) -> void:
	"""Start placement mode
	
	Args:
		mesh: Direct mesh to place
		meshlib: MeshLibrary containing the item
		item_id: ID of item in MeshLibrary
		asset_path: Path to scene/asset to place
		placement_settings: Placement settings dictionary
		dock_instance: Reference to dock UI
	"""
	# Exit any existing mode first
	exit_any_mode()
	
	# Transition to placement mode
	if not ModeStateMachine.transition_to_mode(ModeStateMachine.Mode.PLACEMENT):
		return
	
	# Store settings and dock reference
	settings = placement_settings
	dock_reference = dock_instance
	
	# Initialize transform state
	transform_state = TransformState.new()
	transform_state.configure_from_settings(placement_settings)
	
	# Ensure undo/redo manager is available
	_ensure_undo_redo()
	
	# Delegate to placement mode handler
	placement_data = PlacementModeHandler.enter_placement_mode(
		mesh,
		meshlib,
		item_id,
		asset_path,
		placement_settings,
		transform_state,
		undo_redo
	)
	
	# Store dock reference in placement data
	if placement_data:
		placement_data["dock_reference"] = dock_instance
	
	# Reset grid tracking for new placement
	GridManager.reset_tracking()
	
	# Grab focus for the 3D viewport
	focus_grab_counter = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()

static func start_transform_mode(target_nodes: Variant, dock_instance = null) -> void:
	"""Start transform mode for one or multiple nodes
	
	Args:
		target_nodes: Node3D or Array of Node3D objects to transform together
		dock_instance: Reference to dock UI
	"""
	# Exit any existing mode first
	exit_any_mode()
	
	# Transition to transform mode
	if not ModeStateMachine.transition_to_mode(ModeStateMachine.Mode.TRANSFORM):
		return
	
	# Store dock reference
	dock_reference = dock_instance
	
	# Initialize transform state
	transform_state = TransformState.new()
	if not settings.is_empty():
		transform_state.configure_from_settings(settings)
	
	# Ensure undo/redo manager is available
	_ensure_undo_redo()
	
	# Delegate to transform mode handler
	transform_data = TransformModeHandler.enter_transform_mode(
		target_nodes,
		settings,
		transform_state,
		undo_redo
	)
	
	# Store dock reference in transform data
	if transform_data:
		transform_data["dock_reference"] = dock_instance
	
	# Reset grid tracking for new transform session
	GridManager.reset_tracking()
	
	# Grab focus for the 3D viewport
	focus_grab_counter = PluginConstants.FOCUS_GRAB_FRAMES
	_grab_3d_viewport_focus()

static func exit_placement_mode() -> void:
	"""Exit placement mode"""
	if not ModeStateMachine.is_placement_mode():
		return
	
	# Delegate to placement mode handler
	PlacementModeHandler.exit_placement_mode(
		placement_data,
		transform_state,
		placement_end_callback,
		settings
	)
	
	# Clear data
	placement_data.clear()
	
	# Clear mode
	ModeStateMachine.clear_mode()

static func exit_transform_mode(confirm_changes: bool = true) -> void:
	"""Exit transform mode
	
	Args:
		confirm_changes: If false, restore original transforms
	"""
	if not ModeStateMachine.is_transform_mode():
		return
	
	# Delegate to transform mode handler
	TransformModeHandler.exit_transform_mode(
		transform_data,
		transform_state,
		confirm_changes,
		settings
	)
	
	# Clear data
	transform_data.clear()
	
	# Clear mode
	ModeStateMachine.clear_mode()

static func exit_any_mode() -> void:
	"""Exit whatever mode is currently active"""
	var mode = ModeStateMachine.get_current_mode()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			exit_placement_mode()
		ModeStateMachine.Mode.TRANSFORM:
			exit_transform_mode(false)

## FRAME PROCESSING

static func process_frame_input(
	camera: Camera3D,
	input_settings: Dictionary = {},
	delta: float = 1.0/60.0
) -> void:
	"""Process input for the current frame - coordinate with mode handlers
	
	Args:
		camera: The 3D camera for raycasting
		input_settings: Current input settings
		delta: Frame delta time
	"""
	# Null check camera
	if not camera or not is_instance_valid(camera):
		return
	
	# Store current settings
	settings = input_settings
	
	# Get the 3D viewport for proper mouse coordinate conversion
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	# Update input system with viewport context
	InputHandler.update_input_state(input_settings, viewport_3d)
	
	# Process global navigation input FIRST (mode switching, strategy cycling, escape)
	_process_navigation_input()
	
	# Re-fetch settings after navigation input (in case strategy was manually cycled)
	settings = SettingsManager.get_combined_settings()
	
	# Configure managers with current settings
	# Only configure if we have an active transform_state (mode is active)
	if transform_state:
		PositionManager.configure(transform_state, settings)
	_configure_smooth_transforms(settings)
	
	# Keep grabbing focus for the first few frames after mode starts
	if focus_grab_counter > 0:
		focus_grab_counter -= 1
		_grab_3d_viewport_focus()
	
	# Delegate to mode handler based on current mode
	var mode = ModeStateMachine.get_current_mode()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			PlacementModeHandler.process_input(camera, placement_data, transform_state, settings, delta)
		ModeStateMachine.Mode.TRANSFORM:
			TransformModeHandler.process_input(camera, transform_data, transform_state, settings, delta)
			# Check if transform mode wants to exit with confirmation
			if transform_data.get("_confirm_exit", false):
				transform_data.erase("_confirm_exit")  # Clear the flag
				exit_transform_mode(true)  # Exit with confirmation
				return  # Exit early - don't update overlays after mode exit
	
	# Update smooth transformations
	PreviewManager.update_smooth_transforms(delta)
	SmoothTransformManager.update_smooth_transforms(delta)
	
	# Update grid overlay AFTER position updates
	if mode != ModeStateMachine.Mode.NONE:
		var placement_center = PositionManager.get_base_position(transform_state) if transform_state else Vector3.ZERO
		var target_nodes = transform_data.get("target_nodes", []) if mode == ModeStateMachine.Mode.TRANSFORM else []
		GridManager.update_grid_overlay(mode, settings, transform_state, placement_center, target_nodes)

## MOUSE WHEEL INPUT

static func handle_mouse_wheel_input(event: InputEventMouseButton) -> bool:
	"""Process mouse wheel input using semantic data from InputHandler
	
	Args:
		event: The mouse button event
		
	Returns:
		bool: True if the event was handled (should be consumed)
	"""
	# Get semantic wheel input interpretation from InputHandler
	var wheel_input = InputHandler.get_mouse_wheel_input(event)
	
	# If no action key is held, don't consume the event
	if wheel_input.is_empty():
		return false
	
	# Process the semantic action
	match wheel_input.get("action"):
		"height":
			_apply_height_adjustment(wheel_input)
		"scale":
			_apply_scale_adjustment(wheel_input)
		"rotation":
			_apply_rotation_adjustment(wheel_input)
		"position":
			_apply_position_adjustment(wheel_input)
	
	return true  # Event was handled

## TAB KEY HANDLING

static func handle_tab_key_activation(dock_instance = null) -> void:
	"""Handle TAB key activation - coordinate between placement and transform modes
	
	Args:
		dock_instance: Reference to dock UI
	"""
	# Don't handle TAB if already in a mode
	if ModeStateMachine.is_any_mode_active():
		return
	
	# Check if 3D viewport or scene tree has focus
	if not _is_3d_context_focused():
		return
	
	var selection = EditorInterface.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	
	if selected_nodes.is_empty():
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "No node selected. Select a Node3D and press TAB.")
		return
	
	# Find ALL Node3D nodes in selection
	var target_node3ds = []
	for node in selected_nodes:
		if node is Node3D:
			target_node3ds.append(node)
	
	if target_node3ds.is_empty():
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Selected node is not a Node3D. Select a Node3D and press TAB.")
		return
	
	# Determine mode based on node context
	var first_node = target_node3ds[0]
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene and (first_node.is_ancestor_of(current_scene) or current_scene == first_node or first_node.is_inside_tree()):
		# Nodes are in scene - start transform mode
		start_transform_mode(target_node3ds, dock_instance)
		if target_node3ds.size() == 1:
			OverlayManager.show_status_message("Transform mode: " + first_node.name, Color.GREEN, 2.0)
		else:
			OverlayManager.show_status_message("Transform mode: " + str(target_node3ds.size()) + " nodes", Color.GREEN, 2.0)
	else:
		# Node is external - start placement mode
		start_placement_from_node3d(first_node, dock_instance)

static func start_placement_from_node3d(node: Node3D, dock_instance = null) -> void:
	"""Start placement mode from a Node3D by extracting its mesh
	
	Args:
		node: The Node3D to extract mesh from
		dock_instance: Reference to dock UI
	"""
	var extracted_mesh = UtilityManager.extract_mesh_from_node3d(node)
	if extracted_mesh:
		start_placement_mode(extracted_mesh, null, -1, "", settings, dock_instance)
		OverlayManager.show_status_message("Placement mode activated for: " + node.name, Color.GREEN, 2.0)
	else:
		OverlayManager.show_status_message("Could not extract mesh from: " + node.name, Color.RED, 3.0)

## STATE QUERIES (Delegates to ModeStateMachine)

static func is_any_mode_active() -> bool:
	"""Check if any transformation mode is currently active"""
	return ModeStateMachine.is_any_mode_active()

static func is_placement_mode() -> bool:
	"""Check if placement mode is active"""
	return ModeStateMachine.is_placement_mode()

static func is_transform_mode() -> bool:
	"""Check if transform mode is active"""
	return ModeStateMachine.is_transform_mode()

static func get_current_mode() -> int:
	"""Get the current mode (returns Mode enum)"""
	return ModeStateMachine.get_current_mode()

static func get_current_mode_string() -> String:
	"""Get the current mode as a string"""
	return ModeStateMachine.get_current_mode_string()

static func get_current_scale() -> float:
	"""Get current scale multiplier"""
	if transform_state:
		return ScaleManager.get_scale(transform_state)
	return 1.0

## CALLBACKS

static func set_placement_end_callback(callback: Callable) -> void:
	"""Set the callback to call when placement ends"""
	placement_end_callback = callback

static func set_mesh_placed_callback(callback: Callable) -> void:
	"""Set the callback to call when a mesh is placed"""
	mesh_placed_callback = callback

## CLEANUP

static func cleanup_all() -> void:
	"""Clean up all manager resources (static wrapper for backward compatibility)"""
	exit_any_mode()
	OverlayManager.cleanup_all_overlays()
	PreviewManager.cleanup_preview()
	GridManager.cleanup_grid()

func cleanup() -> void:
	"""Override from InstanceManagerBase - called when instance is being destroyed"""
	cleanup_all()

## INTERNAL HELPERS

static func _ensure_undo_redo() -> void:
	"""Ensure undo/redo manager is initialized and available
	
	This lazily initializes the EditorUndoRedoManager reference.
	Called before entering any mode that needs undo support.
	"""
	if not undo_redo:
		undo_redo = EditorInterface.get_editor_undo_redo()
		if undo_redo:
			PluginLogger.debug("TransformationCoordinator", "Initialized EditorUndoRedoManager")
		else:
			PluginLogger.warning("TransformationCoordinator", "Failed to get EditorUndoRedoManager")
	placement_data.clear()
	transform_data.clear()
	settings.clear()
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Cleanup completed")

## SETTINGS

static func update_settings(new_settings: Dictionary) -> void:
	"""Update settings dictionary
	
	Args:
		new_settings: New settings to use
	"""
	settings = new_settings

## PRIVATE HELPERS

static func _configure_smooth_transforms(settings_dict: Dictionary) -> void:
	"""Configure smooth transforms for all managers with current settings"""
	var smooth_enabled = settings_dict.get("smooth_transforms", true)
	var smooth_speed = settings_dict.get("smooth_transform_speed", 8.0)
	
	PreviewManager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	SmoothTransformManager.configure(smooth_enabled, smooth_speed)
	RotationManager.configure_smooth_transforms(smooth_enabled, smooth_speed)
	ScaleManager.configure_smooth_transforms(smooth_enabled, smooth_speed)

static func _process_navigation_input() -> void:
	"""Process navigation and mode control input"""
	var nav_input = InputHandler.get_navigation_input()
	
	# Handle TAB key for mode switching
	if nav_input.tab_just_pressed:
		handle_tab_key_activation(dock_reference)
	
	# Handle cancel/escape
	if nav_input.cancel_pressed or nav_input.escape_pressed:
		exit_any_mode()
	
	# Handle placement mode cycling
	if InputHandler.should_cycle_placement_mode():
		_cycle_placement_strategy()

static func _cycle_placement_strategy() -> void:
	"""Cycle through placement strategies and update settings"""
	var new_strategy = PlacementStrategyManager.cycle_strategy()
	
	# Update the local settings dictionary
	if settings.has("placement_strategy"):
		settings["placement_strategy"] = new_strategy
	
	# Update SettingsManager immediately
	SettingsManager.update_dock_settings({"placement_strategy": new_strategy})
	
	# Update the dock UI dropdown
	if dock_reference and dock_reference.has_method("update_placement_strategy_ui"):
		dock_reference.update_placement_strategy_ui(new_strategy)
	
	# Show notification
	var strategy_name = PlacementStrategyManager.get_active_strategy_name()
	PluginLogger.info("TransformationCoordinator", "Placement mode: " + strategy_name)

static func _apply_height_adjustment(wheel_input: Dictionary) -> void:
	"""Apply height adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	if reverse:
		direction = -direction
	
	var step = settings.get("fine_height_increment", 0.01)
	
	var mode = ModeStateMachine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		if direction > 0:
			PositionManager.adjust_height(transform_state, step)
		else:
			PositionManager.adjust_height(transform_state, -step)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var accumulated_y_delta = transform_data.get("accumulated_y_delta", 0.0)
		accumulated_y_delta += step * direction
		transform_data["accumulated_y_delta"] = accumulated_y_delta

static func _apply_scale_adjustment(wheel_input: Dictionary) -> void:
	"""Apply scale adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var large_increment = wheel_input.get("large_increment", false)
	
	var step = settings.get("fine_scale_increment", 0.01)
	if large_increment:
		step = settings.get("large_scale_increment", 0.5)
	
	var mode = ModeStateMachine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var target_node = PreviewManager.preview_mesh
		if target_node:
			if direction > 0:
				ScaleManager.increase_scale(transform_state, step)
			else:
				ScaleManager.decrease_scale(transform_state, step)
			ScaleManager.apply_uniform_scale_to_node(transform_state, target_node, Vector3.ONE)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var target_nodes = transform_data.get("target_nodes", [])
		var original_transforms = transform_data.get("original_transforms", {})
		if not target_nodes.is_empty():
			if direction > 0:
				ScaleManager.increase_scale(transform_state, step)
			else:
				ScaleManager.decrease_scale(transform_state, step)
			for node in target_nodes:
				if node and node.is_inside_tree():
					var node_original_scale = original_transforms.get(node, Transform3D()).basis.get_scale()
					ScaleManager.apply_uniform_scale_to_node(transform_state, node, node_original_scale)

static func _apply_rotation_adjustment(wheel_input: Dictionary) -> void:
	"""Apply rotation adjustment based on wheel input"""
	var direction = wheel_input.get("direction", 0)
	var axis = wheel_input.get("axis", "Y")
	var large_increment = wheel_input.get("large_increment", false)
	var reverse = wheel_input.get("reverse_modifier", false)
	
	var rotation_step: float
	if large_increment:
		rotation_step = settings.get("large_rotation_increment", 90.0)
	else:
		rotation_step = settings.get("fine_rotation_increment", 5.0)
	
	if reverse:
		rotation_step = -rotation_step
	
	var step = rotation_step * direction
	
	var mode = ModeStateMachine.get_current_mode()
	if mode == ModeStateMachine.Mode.PLACEMENT:
		var target_node = PreviewManager.preview_mesh
		if target_node:
			RotationManager.apply_rotation_step(transform_state, target_node, axis, step, Vector3.ZERO, false)
	elif mode == ModeStateMachine.Mode.TRANSFORM:
		var target_nodes = transform_data.get("target_nodes", [])
		var original_transforms = transform_data.get("original_transforms", {})
		for node in target_nodes:
			if node and node.is_inside_tree():
				var node_original_rotation = original_transforms.get(node, Transform3D()).basis.get_euler()
				RotationManager.apply_rotation_step(transform_state, node, axis, step, node_original_rotation, false)

static func _apply_position_adjustment(wheel_input: Dictionary) -> void:
	"""Apply position adjustment based on wheel input (currently not used)"""
	# Reserved for future mouse wheel position adjustments
	pass

static func _grab_3d_viewport_focus() -> void:
	"""Grab keyboard focus for the 3D viewport"""
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	var base_control = EditorInterface.get_base_control()
	if not base_control:
		return
	
	var spatial_editor = _find_spatial_editor(base_control)
	if spatial_editor:
		if spatial_editor.focus_mode == Control.FOCUS_NONE:
			spatial_editor.focus_mode = Control.FOCUS_ALL
		spatial_editor.grab_focus()
		spatial_editor.call_deferred("grab_focus")

static func _find_spatial_editor(node: Node) -> Control:
	"""Find the Node3DEditor (spatial editor) control"""
	if node and node.get_class() == "Node3DEditor":
		if node is Control:
			return node
	
	if node:
		for child in node.get_children():
			var result = _find_spatial_editor(child)
			if result:
				return result
	
	return null

static func _is_3d_context_focused() -> bool:
	"""Check if 3D viewport or scene tree has focus"""
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return false
	
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return false
	
	var camera = viewport_3d.get_camera_3d()
	if not camera:
		return false
	
	# Check if focus is NOT in Inspector
	var base_control = EditorInterface.get_base_control()
	if base_control:
		var focused_control = base_control.get_viewport().gui_get_focus_owner()
		if focused_control:
			var current = focused_control
			var depth = 0
			while current and depth < 20:
				var control_class = current.get_class()
				var control_name = current.name if current.name else ""
				
				if "Inspector" in control_class or "Inspector" in control_name or "EditorProperty" in control_class:
					return false
				
				current = current.get_parent()
				depth += 1
	
	return true
