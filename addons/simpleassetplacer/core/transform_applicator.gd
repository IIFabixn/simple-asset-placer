@tool
extends RefCounted

class_name TransformApplicator

"""
TRANSFORM APPLICATION SERVICE
=============================

PURPOSE: Centralized service for applying transforms to Node3D objects.

RESPONSIBILITIES:
- Apply complete transform state to nodes (immediate, no smoothing)
- Apply grid snapping to positions
- Combine rotation sources (surface + manual)
- Scale original transforms appropriately
- Pure utility functions with no state

ARCHITECTURE POSITION: Pure static utility service
- Does NOT store state (receives TransformState)
- Does NOT calculate transforms (receives calculated values)
- Does NOT handle input or smoothing
- Focused solely on immediate transform application

REPLACES: 
- RotationManager.apply_rotation_to_node()
- ScaleManager.apply_scale_to_node()
- Scattered position application logic

USED BY: TransformationManager, PreviewManager, UtilityManager
DEPENDS ON: TransformState only (pure utility, no manager dependencies)
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

## MAIN APPLICATION METHODS

static func apply_transform_state(node: Node3D, state: TransformState, original_transform: Transform3D = Transform3D(), skip_position_snap: bool = true):
	"""Apply complete transform state to a node (immediate, no smoothing)
	
	Args:
		node: The Node3D to transform
		state: TransformState containing all transform data
		original_transform: Original transform (for transform mode), empty for placement mode
		skip_position_snap: If true, skip grid snapping (used when position is pre-snapped)
	"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	# Calculate final position: snap mouse position, then add keyboard offset (unsnapped)
	# This allows precise keyboard adjustments relative to a grid-snapped base position
	var base_position = state.position
	if state.snap.snap_enabled and not skip_position_snap:
		base_position = apply_grid_snap(base_position, state)
	var final_position = base_position + state.manual_position_offset
	
	# Calculate final rotation based on mode
	# Transform mode (has original_transform): original + manual_offset only
	# Placement mode (no original_transform): surface_alignment + manual_offset
	var is_transform_mode = original_transform != Transform3D()
	var final_rotation: Vector3
	
	if is_transform_mode:
		# Transform mode: preserve original rotation, add only manual adjustments
		var original_rotation = original_transform.basis.get_euler()
		final_rotation = original_rotation + state.manual_rotation_offset
	else:
		# Placement mode: use surface alignment + manual offset
		final_rotation = state.get_final_rotation()
	
	# Calculate final scale using ADDITIVE scaling for Transform mode
	# For transform mode: target_scale = original + (multiplier - 1.0)
	# This ensures consistent increments: +0.1 always adds 0.1 to scale, regardless of original scale
	# For placement mode (original_scale == Vector3.ONE): this reduces to just the multiplier
	var original_scale = original_transform.basis.get_scale() if original_transform != Transform3D() else Vector3.ONE
	var scale_offset = state.get_scale_vector() - Vector3.ONE
	var final_scale = original_scale + scale_offset
	
	# Apply immediately
	node.global_position = final_position
	node.rotation = final_rotation
	node.scale = final_scale

static func apply_position_only(node: Node3D, state: TransformState):
	"""Apply only position from state (immediate, no smoothing)"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	# Snap mouse position, then add keyboard offset (unsnapped)
	var base_position = state.position
	if state.snap.snap_enabled:
		base_position = apply_grid_snap(base_position, state)
	var final_position = base_position + state.manual_position_offset
	
	node.global_position = final_position

static func apply_rotation_only(node: Node3D, state: TransformState, original_rotation: Vector3 = Vector3.ZERO):
	"""Apply only rotation from state (immediate, no smoothing)
	
	Args:
		node: Node to apply rotation to
		state: TransformState with rotation data
		original_rotation: Original rotation (for transform mode)
	"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	# Combine original + surface alignment + manual offset
	var final_rotation = original_rotation + state.get_final_rotation()
	node.rotation = final_rotation

static func apply_scale_only(node: Node3D, state: TransformState, original_scale: Vector3 = Vector3.ONE):
	"""Apply only scale from state (immediate, no smoothing)
	
	Uses ADDITIVE scaling: target = original + (multiplier - 1.0)
	This ensures consistent increments regardless of original scale.
	
	Args:
		node: The Node3D to scale
		state: TransformState containing scale data
		original_scale: Original scale to add offset to
	"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	var scale_offset = state.get_scale_vector() - Vector3.ONE
	var final_scale = original_scale + scale_offset
	node.scale = final_scale

## HELPER METHODS FOR DIRECT APPLICATION

static func apply_position(node: Node3D, pos: Vector3) -> void:
	"""Apply position directly to node (immediate)"""
	if NodeUtils.is_valid_and_in_tree(node):
		node.global_position = pos

static func apply_rotation(node: Node3D, q: Quaternion) -> void:
	"""Apply rotation directly to node via quaternion (immediate)"""
	if NodeUtils.is_valid_and_in_tree(node):
		node.quaternion = q

static func apply_scale(node: Node3D, scale: Vector3) -> void:
	"""Apply scale directly to node (immediate)"""
	if NodeUtils.is_valid_and_in_tree(node):
		var t := node.global_transform
		t.basis = t.basis.scaled(scale / t.basis.get_scale())
		node.global_transform = t

## GRID SNAPPING

static func apply_grid_snap(position: Vector3, state: TransformState, use_half_step: bool = false) -> Vector3:
	"""Apply grid snapping to a position based on state configuration
	
	Uses snappedf() for consistent snapping behavior with PositionManager.
	
	Args:
		position: Position to snap
		state: TransformState containing snap configuration
		use_half_step: Override to force half-step mode (for modal G mode with CTRL)
		
	Returns:
		Snapped position
	"""
	var snapped_pos = position
	
	# Determine effective snap steps (half-step if enabled via state OR parameter)
	var effective_snap_step = state.snap.snap_step
	if state.snap.use_half_step or use_half_step:
		effective_snap_step = state.snap.snap_step / 2.0
	
	var effective_y_step = state.snap.snap_y_step
	if state.snap.use_half_step or use_half_step:
		effective_y_step = state.snap.snap_y_step / 2.0
	
	# Apply X-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_x = state.snap.snap_offset.x
		if state.snap.snap_center_x:
			# Snap to center of grid cell (offset by half step before snapping)
			offset_x += effective_snap_step * 0.5
		# Use snappedf() instead of round() for proper grid snapping
		snapped_pos.x = snappedf(position.x - offset_x, effective_snap_step) + offset_x
	
	# Apply Z-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_z = state.snap.snap_offset.z
		if state.snap.snap_center_z:
			# Snap to center of grid cell (offset by half step before snapping)
			offset_z += effective_snap_step * 0.5
		# Use snappedf() instead of round() for proper grid snapping
		snapped_pos.z = snappedf(position.z - offset_z, effective_snap_step) + offset_z
	
	# Apply Y-axis snapping (separate control, only if enabled and valid step)
	if state.snap.snap_y_enabled and state.snap.snap_y_step > 0:
		var offset_y = state.snap.snap_offset.y
		if state.snap.snap_center_y:
			# Snap to center of grid cell (offset by half step before snapping)
			offset_y += effective_y_step * 0.5
		# Use snappedf() instead of round() for proper grid snapping
		snapped_pos.y = snappedf(position.y - offset_y, effective_y_step) + offset_y
	
	return snapped_pos

## UTILITY METHODS

static func copy_transform_from_node(node: Node3D, state: TransformState):
	"""Copy current transform from node into state (for transform mode initialization)"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	state.position = node.global_position
	state.target_position = node.global_position
	state.manual_rotation_offset = node.rotation
	state.set_non_uniform_scale(node.scale)

static func force_apply_immediate(node: Node3D, state: TransformState, original_transform: Transform3D = Transform3D()):
	"""Force immediate application without smooth transforms (for finalization)"""
	if not NodeUtils.is_valid_and_in_tree(node):
		return
	
	# Snap base position, then add keyboard offset (unsnapped)
	var base_position = state.position
	if state.snap.snap_enabled:
		base_position = apply_grid_snap(base_position, state)
	var final_position = base_position + state.manual_position_offset
	
	var final_rotation = state.get_final_rotation()
	var original_scale = original_transform.basis.get_scale() if original_transform != Transform3D() else Vector3.ONE
	var final_scale = original_scale * state.get_scale_vector()
	
	node.global_position = final_position
	node.rotation = final_rotation
	node.scale = final_scale

## TRANSFORM MODE HELPERS

static func apply_position_to_multiple_nodes(
	nodes: Array,
	state: TransformState,
	node_offsets: Dictionary,
	skip_center_snap: bool = false
):
	"""Apply position only to multiple nodes
	
	Args:
		nodes: Array of Node3D objects
		state: TransformState with position data
		node_offsets: Dictionary mapping nodes to offset from center
		skip_center_snap: If true, skip snapping the center position
	"""
	# Calculate snapped center position
	var center_pos = state.position
	if state.snap.snap_enabled and not skip_center_snap:
		center_pos = apply_grid_snap(center_pos, state)
	
	# Apply keyboard offset (unsnapped) to center
	var final_center = center_pos + state.manual_position_offset
	
	# Apply to each node
	for node in nodes:
		if not NodeUtils.is_valid_and_in_tree(node):
			continue
		
		# Get node offset from center
		var offset = node_offsets.get(node, Vector3.ZERO)
		node.global_position = final_center + offset






