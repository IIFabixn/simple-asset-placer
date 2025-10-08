@tool
extends RefCounted

class_name TransformApplicator

"""
TRANSFORM APPLICATION SERVICE
=============================

PURPOSE: Centralized service for applying transforms to Node3D objects.

RESPONSIBILITIES:
- Apply complete transform state to nodes
- Handle smooth transform integration
- Apply grid snapping to positions
- Combine rotation sources (surface + manual)
- Scale original transforms appropriately
- Coordinate with SmoothTransformManager

ARCHITECTURE POSITION: Pure application service
- Does NOT store state (receives TransformState)
- Does NOT calculate transforms (receives calculated values)
- Does NOT handle input
- Focused solely on applying transforms to nodes

REPLACES: 
- RotationManager.apply_rotation_to_node()
- ScaleManager.apply_scale_to_node()
- Scattered position application logic

USED BY: TransformationManager, PreviewManager, UtilityManager
DEPENDS ON: TransformState, SmoothTransformManager
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/transform_state.gd")
const SmoothTransformManager = preload("res://addons/simpleassetplacer/smooth_transform_manager.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/plugin_logger.gd")

## MAIN APPLICATION METHODS

static func apply_transform_state(node: Node3D, state: TransformState, original_transform: Transform3D = Transform3D()):
	"""Apply complete transform state to a node
	
	Args:
		node: The Node3D to transform
		state: TransformState containing all transform data
		original_transform: Original transform (for transform mode), empty for placement mode
	"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	# Calculate final position with snapping
	var final_position = state.get_final_position()
	if state.snap_enabled:
		final_position = apply_grid_snap(final_position, state)
	
	# Calculate final rotation (surface + manual)
	var final_rotation = state.get_final_rotation()
	
	# Calculate final scale (original * multiplier)
	var original_scale = original_transform.basis.get_scale() if original_transform != Transform3D() else Vector3.ONE
	var final_scale = original_scale * state.get_scale_vector()
	
	# Apply using smooth transforms if enabled
	if SmoothTransformManager._smooth_enabled:
		SmoothTransformManager.set_target_position(node, final_position)
		SmoothTransformManager.set_target_rotation(node, final_rotation)
		SmoothTransformManager.set_target_scale(node, final_scale)
	else:
		node.global_position = final_position
		node.rotation = final_rotation
		node.scale = final_scale

static func apply_position_only(node: Node3D, state: TransformState):
	"""Apply only position from state (useful for preview updates)"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	var final_position = state.get_final_position()
	if state.snap_enabled:
		final_position = apply_grid_snap(final_position, state)
	
	if SmoothTransformManager._smooth_enabled:
		SmoothTransformManager.set_target_position(node, final_position)
	else:
		node.global_position = final_position

static func apply_rotation_only(node: Node3D, state: TransformState, original_rotation: Vector3 = Vector3.ZERO):
	"""Apply only rotation from state
	
	Args:
		node: The Node3D to rotate
		state: TransformState containing rotation data
		original_rotation: Original rotation (for transform mode)
	"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	# Combine original + surface alignment + manual offset
	var final_rotation = original_rotation + state.get_final_rotation()
	
	if SmoothTransformManager._smooth_enabled:
		SmoothTransformManager.set_target_rotation(node, final_rotation)
	else:
		node.rotation = final_rotation

static func apply_scale_only(node: Node3D, state: TransformState, original_scale: Vector3 = Vector3.ONE):
	"""Apply only scale from state
	
	Args:
		node: The Node3D to scale
		state: TransformState containing scale data
		original_scale: Original scale to multiply with
	"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	var final_scale = original_scale * state.get_scale_vector()
	
	if SmoothTransformManager._smooth_enabled:
		SmoothTransformManager.set_target_scale(node, final_scale)
	else:
		node.scale = final_scale

## GRID SNAPPING

static func apply_grid_snap(position: Vector3, state: TransformState) -> Vector3:
	"""Apply grid snapping to a position based on state configuration
	
	Args:
		position: Position to snap
		state: TransformState containing snap configuration
		
	Returns:
		Snapped position
	"""
	var snapped_pos = position
	
	# Determine effective snap step (half-step if enabled)
	var effective_snap_step = state.snap_step
	if state.use_half_step:
		effective_snap_step = state.snap_step / 2.0
	
	# Apply X-axis snapping
	if state.snap_enabled:
		var snap_x = position.x
		if state.snap_center_x:
			# Snap to center of grid cell
			snap_x = round((position.x - state.snap_offset.x) / effective_snap_step) * effective_snap_step + state.snap_offset.x
		else:
			# Snap to grid lines
			snap_x = round((position.x - state.snap_offset.x) / effective_snap_step) * effective_snap_step + state.snap_offset.x
		snapped_pos.x = snap_x
	
	# Apply Z-axis snapping
	if state.snap_enabled:
		var snap_z = position.z
		if state.snap_center_z:
			snap_z = round((position.z - state.snap_offset.z) / effective_snap_step) * effective_snap_step + state.snap_offset.z
		else:
			snap_z = round((position.z - state.snap_offset.z) / effective_snap_step) * effective_snap_step + state.snap_offset.z
		snapped_pos.z = snap_z
	
	# Apply Y-axis snapping (separate control)
	if state.snap_y_enabled:
		var snap_y = position.y
		if state.snap_center_y:
			snap_y = round((position.y - state.snap_offset.y) / state.snap_y_step) * state.snap_y_step + state.snap_offset.y
		else:
			snap_y = round((position.y - state.snap_offset.y) / state.snap_y_step) * state.snap_y_step + state.snap_offset.y
		snapped_pos.y = snap_y
	
	return snapped_pos

## UTILITY METHODS

static func copy_transform_from_node(node: Node3D, state: TransformState):
	"""Copy current transform from node into state (for transform mode initialization)"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	state.position = node.global_position
	state.target_position = node.global_position
	state.manual_rotation_offset = node.rotation
	state.set_non_uniform_scale(node.scale)

static func force_apply_immediate(node: Node3D, state: TransformState, original_transform: Transform3D = Transform3D()):
	"""Force immediate application without smooth transforms (for finalization)"""
	if not node or not is_instance_valid(node) or not node.is_inside_tree():
		return
	
	var final_position = state.get_final_position()
	if state.snap_enabled:
		final_position = apply_grid_snap(final_position, state)
	
	var final_rotation = state.get_final_rotation()
	var original_scale = original_transform.basis.get_scale() if original_transform != Transform3D() else Vector3.ONE
	var final_scale = original_scale * state.get_scale_vector()
	
	node.global_position = final_position
	node.rotation = final_rotation
	node.scale = final_scale

## TRANSFORM MODE HELPERS

static func apply_to_multiple_nodes(nodes: Array, state: TransformState, center_position: Vector3, node_offsets: Dictionary, original_transforms: Dictionary):
	"""Apply transform state to multiple nodes maintaining relative positions
	
	Args:
		nodes: Array of Node3D objects
		state: TransformState to apply
		center_position: Center point for the group
		node_offsets: Dictionary mapping node -> offset from center
		original_transforms: Dictionary mapping node -> original Transform3D
	"""
	for node in nodes:
		if not node or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		
		# Calculate this node's position based on group center + offset
		var node_offset = node_offsets.get(node, Vector3.ZERO)
		var node_position = state.position + node_offset
		
		# Create temporary state for this node
		var node_state = TransformState.new()
		node_state.position = node_position
		node_state.manual_rotation_offset = state.manual_rotation_offset
		node_state.surface_alignment_rotation = state.surface_alignment_rotation
		node_state.non_uniform_multiplier = state.non_uniform_multiplier
		node_state.scale_multiplier = state.scale_multiplier
		node_state.snap_enabled = state.snap_enabled
		node_state.snap_step = state.snap_step
		node_state.snap_offset = state.snap_offset
		
		var original_transform = original_transforms.get(node, Transform3D())
		apply_transform_state(node, node_state, original_transform)
