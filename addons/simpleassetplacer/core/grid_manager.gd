@tool
extends "res://addons/simpleassetplacer/core/instance_manager_base.gd"

class_name GridManager

# === SINGLETON INSTANCE ===

static var _instance: GridManager = null

static func _set_instance(instance: InstanceManagerBase) -> void:
	_instance = instance as GridManager

static func _get_instance() -> InstanceManagerBase:
	return _instance

static func has_instance() -> bool:
	return _instance != null and is_instance_valid(_instance)

"""
GRID MANAGER
============

PURPOSE: Manages grid overlay creation, positioning, and updates

RESPONSIBILITIES:
- Grid overlay creation and positioning
- Half-step grid management
- Grid position tracking (prevent unnecessary updates)
- Grid visibility control
- Grid cleanup

ARCHITECTURE POSITION: Specialized manager for grid overlays
- Used by TransformationCoordinator during frame processing
- Delegates to OverlayManager for actual grid rendering
- Tracks grid state to minimize redundant updates

PHASE 5.2: Converted to instance-based architecture with hybrid static pattern

USED BY: TransformationCoordinator
USES: OverlayManager, PositionManager, NodeUtils, PluginLogger
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

# Import managers
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")

# Import mode state machine
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")

# Import state
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

# === GRID STATE TRACKING ===

# Instance variables (Phase 5.2: Instance-based architecture)
var __last_grid_center: Vector3 = Vector3.ZERO
var __last_grid_height: float = 0.0
var __grid_update_threshold: float = 5.0

# Static properties forwarding to instance (Phase 5.2: Hybrid pattern)
static var last_grid_center: Vector3:
	get: return _get_instance().__last_grid_center if has_instance() else Vector3.ZERO
	set(value): if has_instance(): _get_instance().__last_grid_center = value

static var last_grid_height: float:
	get: return _get_instance().__last_grid_height if has_instance() else 0.0
	set(value): if has_instance(): _get_instance().__last_grid_height = value

static var grid_update_threshold: float:
	get: return _get_instance().__grid_update_threshold if has_instance() else 5.0
	set(value): if has_instance(): _get_instance().__grid_update_threshold = value

## MAIN UPDATE FUNCTION

static func update_grid_overlay(
	current_mode: int,  # ModeStateMachine.Mode
	settings: Dictionary,
	transform_state: TransformState,
	placement_center: Vector3 = Vector3.ZERO,
	target_nodes: Array = []
) -> void:
	"""Update or create grid overlay based on current settings and mode
	
	Args:
		current_mode: Current mode (ModeStateMachine.Mode enum value)
		settings: Current plugin settings dictionary
		transform_state: Current transform state
		placement_center: Center position for placement mode (from PositionManager)
		target_nodes: Array of nodes for transform mode center calculation
	"""
	var show_grid = settings.get("show_grid", false)
	var snap_enabled = settings.get("snap_enabled", false)
	
	# Only show grid if both grid display and snapping are enabled
	if show_grid and snap_enabled and (current_mode == ModeStateMachine.Mode.PLACEMENT or current_mode == ModeStateMachine.Mode.TRANSFORM):
		var grid_size = settings.get("snap_step", 1.0)
		var offset = settings.get("snap_offset", Vector3.ZERO)
		var grid_extent_units = settings.get("grid_extent", 20.0)
		
		# Get center position based on current mode
		var center = _calculate_grid_center(current_mode, transform_state, placement_center, target_nodes)
		
		# Calculate number of grid cells based on grid size and desired world extent
		var grid_extent = int(ceil(grid_extent_units / grid_size))
		grid_extent = clamp(grid_extent, 5, 100)  # Min 5, max 100 cells
		
		# Check if grid needs updating
		var half_step_active = PositionManager.use_half_step
		if should_update_grid(center, center.y, half_step_active):
			OverlayManager.create_grid_overlay(center, grid_size, grid_extent, offset, half_step_active)
			last_grid_center = center
			last_grid_height = center.y
	else:
		# Hide/remove grid if disabled or not in active mode
		cleanup_grid()

## GRID CENTER CALCULATION

static func _calculate_grid_center(
	current_mode: int,
	transform_state: TransformState,
	placement_center: Vector3,
	target_nodes: Array
) -> Vector3:
	"""Calculate the center position for the grid based on current mode
	
	Args:
		current_mode: Current mode (ModeStateMachine.Mode enum value)
		transform_state: Current transform state
		placement_center: Pre-calculated center for placement mode
		target_nodes: Array of nodes for transform mode
		
	Returns:
		Vector3: The center position for the grid
	"""
	var center = Vector3.ZERO
	
	if current_mode == ModeStateMachine.Mode.PLACEMENT:
		# Use base position (without height offset) for grid placement
		# No coordinate inversion needed - grid is now independent of scene root transform
		center = placement_center
	elif current_mode == ModeStateMachine.Mode.TRANSFORM:
		# Use center of selected nodes
		# No coordinate inversion needed - grid is now independent of scene root transform
		center = calculate_transform_center(target_nodes)
	
	return center

static func calculate_transform_center(target_nodes: Array) -> Vector3:
	"""Calculate the center position of all target nodes
	
	Args:
		target_nodes: Array of Node3D objects
		
	Returns:
		Vector3: The center position of all valid nodes
	"""
	var center = Vector3.ZERO
	var valid_count = 0
	
	for node in target_nodes:
		if NodeUtils.is_valid_and_in_tree(node):
			center += node.global_position
			valid_count += 1
	
	if valid_count > 0:
		center /= valid_count
	
	return center

## UPDATE DETECTION

static func should_update_grid(center: Vector3, height: float, half_step_active: bool) -> bool:
	"""Determine if the grid needs to be updated
	
	Args:
		center: New center position
		height: New height
		half_step_active: Whether half-step mode is active
		
	Returns:
		bool: True if grid should be updated, False otherwise
	"""
	# Check if grid needs updating based on position, height, half-step mode, or existence
	var distance_from_last_center = center.distance_to(last_grid_center)
	var height_changed = abs(height - last_grid_height) > 0.01
	var needs_update = distance_from_last_center > grid_update_threshold or height_changed
	
	# Also check if grid overlay exists
	if not OverlayManager.grid_overlay or not is_instance_valid(OverlayManager.grid_overlay):
		needs_update = true
	
	# Check if half-step grid state changed
	var half_step_exists = OverlayManager.half_step_grid_overlay and is_instance_valid(OverlayManager.half_step_grid_overlay)
	if half_step_active != half_step_exists:
		needs_update = true
	
	return needs_update

## CLEANUP

static func cleanup_grid() -> void:
	"""Remove grid overlay and reset tracking"""
	OverlayManager.remove_grid_overlay()
	last_grid_center = Vector3.ZERO
	last_grid_height = 0.0

static func reset_tracking() -> void:
	"""Reset grid position tracking (call when starting new mode)"""
	last_grid_center = Vector3.ZERO
	last_grid_height = 0.0

## CONFIGURATION

static func set_update_threshold(threshold: float) -> void:
	"""Set the distance threshold for grid updates
	
	Args:
		threshold: Distance in world units that triggers grid update
	"""
	grid_update_threshold = max(0.1, threshold)  # Minimum 0.1 units

static func get_update_threshold() -> float:
	"""Get the current update threshold
	
	Returns:
		float: Current threshold distance
	"""
	return grid_update_threshold

## STATE QUERIES

static func is_grid_visible() -> bool:
	"""Check if grid is currently visible
	
	Returns:
		bool: True if grid exists and is visible
	"""
	return OverlayManager.grid_overlay != null and is_instance_valid(OverlayManager.grid_overlay)

static func get_last_grid_center() -> Vector3:
	"""Get the last grid center position
	
	Returns:
		Vector3: Last grid center position
	"""
	return last_grid_center

static func get_last_grid_height() -> float:
	"""Get the last grid height
	
	Returns:
		float: Last grid height
	"""
	return last_grid_height

## DEBUG

static func debug_print_state() -> void:
	"""Print current grid state for debugging"""
	PluginLogger.debug("GridManager", "Grid visible: " + str(is_grid_visible()))
	PluginLogger.debug("GridManager", "Last center: " + str(last_grid_center))
	PluginLogger.debug("GridManager", "Last height: " + str(last_grid_height))
	PluginLogger.debug("GridManager", "Update threshold: " + str(grid_update_threshold))
