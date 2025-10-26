@tool
extends RefCounted

class_name GridManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

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

USED BY: TransformationCoordinator
USES: OverlayManager, PositionManager, NodeUtils, PluginLogger
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

# Import mode state machine
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")

# Import state
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry

func _init(services: ServiceRegistry):
	_services = services

# === GRID STATE TRACKING ===

var _last_grid_center: Vector3 = Vector3.ZERO
var _last_grid_height: float = 0.0
var _grid_update_threshold: float = 5.0

## MAIN UPDATE FUNCTION

func update_grid_overlay(
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
	
	# Show grid if show_grid is enabled (snapping is independent)
	if show_grid and (current_mode == ModeStateMachine.Mode.PLACEMENT or current_mode == ModeStateMachine.Mode.TRANSFORM):
		var grid_size = settings.get("snap_step", 1.0)
		var offset = settings.get("snap_offset", Vector3.ZERO)
		var grid_extent_units = settings.get("grid_extent", 20.0)
		
		# Get center position based on current mode
		var center = _calculate_grid_center(current_mode, transform_state, placement_center, target_nodes)
		
		# Calculate number of grid cells based on grid size and desired world extent
		var grid_extent = int(ceil(grid_extent_units / grid_size))
		grid_extent = clamp(grid_extent, 5, 100)  # Min 5, max 100 cells
		
		# Check if grid needs updating
		# Use transform_state.snap.use_half_step directly (PositionManager accessor removed)
		var half_step_active = transform_state.snap.use_half_step if transform_state else false
		if should_update_grid(center, center.y, half_step_active):
			# Get plane type from placement strategy service if plane strategy is active
			var plane_type = "XZ"  # Default to horizontal
			if _services.placement_strategy_service:
				var strategy_type = _services.placement_strategy_service.get_active_strategy_type()
				if strategy_type == "plane":
					var plane_strategy = _services.placement_strategy_service.get_plane_strategy()
					if plane_strategy:
						var plane_type_enum = plane_strategy.get_plane_type()
						# Convert enum to string
						match plane_type_enum:
							0:  # PlaneType.XZ
								plane_type = "XZ"
							1:  # PlaneType.XY
								plane_type = "XY"
							2:  # PlaneType.YZ
								plane_type = "YZ"
			
			_services.overlay_manager.create_grid_overlay(center, grid_size, grid_extent, offset, half_step_active, plane_type)
			_last_grid_center = center
			_last_grid_height = center.y
	else:
		# Hide/remove grid if disabled or not in active mode
		cleanup_grid()

## GRID CENTER CALCULATION

func _calculate_grid_center(
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

func calculate_transform_center(target_nodes: Array) -> Vector3:
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

func should_update_grid(center: Vector3, height: float, half_step_active: bool) -> bool:
	"""Determine if the grid needs to be updated
	
	Args:
		center: New center position
		height: New height
		half_step_active: Whether half-step mode is active
		
	Returns:
		bool: True if grid should be updated, False otherwise
	"""
	# Check if grid needs updating based on position, height, half-step mode, or existence
	var distance_from_last_center = center.distance_to(_last_grid_center)
	var height_changed = abs(height - _last_grid_height) > 0.01
	var needs_update = distance_from_last_center > _grid_update_threshold or height_changed
	
	# Also check if grid overlay exists
	if not _services.overlay_manager.get_grid_overlay() or not is_instance_valid(_services.overlay_manager.get_grid_overlay()):
		needs_update = true
	
	# Check if half-step grid state changed
	var half_step_exists = _services.overlay_manager.get_half_step_grid_overlay() and is_instance_valid(_services.overlay_manager.get_half_step_grid_overlay())
	if half_step_active != half_step_exists:
		needs_update = true
	
	return needs_update

## CLEANUP

func cleanup_grid() -> void:
	"""Remove grid overlay and reset tracking"""
	_services.overlay_manager.remove_grid_overlay()
	_last_grid_center = Vector3.ZERO
	_last_grid_height = 0.0

func reset_tracking() -> void:
	"""Reset grid position tracking (call when starting new mode)"""
	_last_grid_center = Vector3.ZERO
	_last_grid_height = 0.0

## CONFIGURATION

func set_update_threshold(threshold: float) -> void:
	"""Set the distance threshold for grid updates
	
	Args:
		threshold: Distance in world units that triggers grid update
	"""
	_grid_update_threshold = max(0.1, threshold)  # Minimum 0.1 units

func get_update_threshold() -> float:
	"""Get the current update threshold
	
	Returns:
		float: Current threshold distance
	"""
	return _grid_update_threshold

## STATE QUERIES

func is_grid_visible() -> bool:
	"""Check if grid is currently visible
	
	Returns:
		bool: True if grid exists and is visible
	"""
	return _services.overlay_manager.grid_overlay != null and is_instance_valid(_services.overlay_manager.grid_overlay)

func get_last_grid_center() -> Vector3:
	"""Get the last grid center position
	
	Returns:
		Vector3: Last grid center position
	"""
	return _last_grid_center

func get_last_grid_height() -> float:
	"""Get the last grid height
	
	Returns:
		float: Last grid height
	"""
	return _last_grid_height

## DEBUG

func debug_print_state() -> void:
	"""Print current grid state for debugging"""
	PluginLogger.debug("GridManager", "Grid visible: " + str(is_grid_visible()))
	PluginLogger.debug("GridManager", "Last center: " + str(_last_grid_center))
	PluginLogger.debug("GridManager", "Last height: " + str(_last_grid_height))
	PluginLogger.debug("GridManager", "Update threshold: " + str(_grid_update_threshold))

