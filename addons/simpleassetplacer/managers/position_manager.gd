@tool
extends RefCounted

class_name PositionManager

const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

"""
3D POSITIONING AND COLLISION SYSTEM (REFACTORED - STATELESS)
============================================================

PURPOSE: Pure position calculation service working with TransformState.

RESPONSIBILITIES:
- Position calculations using placement strategies
- General offset calculations (XYZ movement)
- Grid snapping calculations
- Position constraint validation
- Camera-relative movement calculations

ARCHITECTURE POSITION: Pure calculation service with NO state storage
- Does NOT store position state (uses TransformState)
- Does NOT handle input detection
- Does NOT handle UI or overlays
- Delegates actual raycasting to PlacementStrategyService
- Focused solely on position math

FULLY INSTANCE-BASED with ServiceRegistry injection

USED BY: TransformationCoordinator for positioning calculations
DEPENDS ON: TransformState, PlacementStrategyService, IncrementCalculator
"""

# Import dependencies
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")
const PlacementStrategy = preload("res://addons/simpleassetplacer/placement/placement_strategy.gd")
const IncrementCalculator = preload("res://addons/simpleassetplacer/utils/increment_calculator.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const TransformMath = preload("res://addons/simpleassetplacer/utils/transform_math.gd")

# === SERVICE REGISTRY ===

var _services: ServiceRegistry
var _placement_service: PlacementStrategyService

func _init(services: ServiceRegistry):
	_services = services
	if services and services.placement_strategy_service:
		_placement_service = services.placement_strategy_service
	else:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()

# === INSTANCE VARIABLES ===

var _collision_mask: int = 1
var _align_with_normal: bool = false
var _interpolation_enabled: bool = false
var _interpolation_speed: float = 10.0

## Core Position Management (REFACTORED)

func update_position_from_mouse(state: TransformState, camera: Camera3D, mouse_pos: Vector2, collision_layer: int = 1, lock_y_axis: bool = false, exclude_nodes: Array = []) -> Vector3:
	"""Update target position based on mouse position using placement strategy
	
	Args:
		state: TransformState to update
		camera: Camera3D for ray projection
		mouse_pos: Mouse position in viewport coordinates
		collision_layer: Physics collision layer (configured in PositionManager)
		lock_y_axis: If true, only XZ updates after initial setup
		exclude_nodes: Array of Node3D objects to exclude from collision (for transform mode)
	
	Returns:
		Calculated world position
	"""
	if not camera or not is_instance_valid(camera):
		PluginLogger.warning("PositionManager", "Invalid camera reference")
		return state.values.position
	
	if not state:
		PluginLogger.error("PositionManager", "Invalid TransformState reference")
		return Vector3.ZERO
	
	# Create ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Pass configuration to strategy manager (camera, mouse, exclusions, settings)
	var additional_config: Dictionary = {
		"camera": camera,
		"mouse_position": mouse_pos,
		"settings": _get_current_settings(),  # Pass settings for cursor_warp_enabled and other flags
		"base_position": state.values.base_position  # Pass base position (WITHOUT offset) so plane stays at base height
	}
	if exclude_nodes.size() > 0:
		additional_config["exclude_nodes"] = exclude_nodes

	# Use strategy manager to calculate position with exclusions and camera context
	var result: PlacementStrategy.PlacementResult = _calculate_position(from, to, additional_config)
	
	# Check if we got a valid result (null check added)
	if not result or result.position == Vector3.INF:
		# Invalid result - keep current position
		PluginLogger.debug("PositionManager", "Invalid placement result, keeping current position")
		return state.values.position
	
	# Update surface normal and base position from strategy
	state.values.surface_normal = result.normal
	state.values.base_position = result.position
	state.placement.last_raycast_xz = Vector2(result.position.x, result.position.z)
	state.placement.is_initial_position = false
	
	# Apply surface offset to prevent objects from sinking into surfaces
	# This gives us a clean position where the object sits properly on the surface
	# Pass the transform target nodes for Transform Mode, or use preview for Placement Mode
	var target_nodes_for_bounds = exclude_nodes if state.is_in_transform_mode() else []
	var surface_offset_position = _apply_surface_offset(state.values.base_position, state.values.surface_normal, target_nodes_for_bounds)
	
	# Set the target position (will be snapped if snapping is enabled)
	state.values.target_position = surface_offset_position
	
	# Apply standard grid snapping to the FINAL position (collision + surface offset)
	# This ensures objects align with the grid while still sitting properly on surfaces
	if state.snap.snap_enabled or state.snap.snap_y_enabled:
		if state.is_in_transform_mode():
			# In Transform mode: handle Y snapping separately
			if state.snap.snap_y_enabled:
				# Y Snap is ON: apply full grid snapping (all axes)
				state.values.target_position = _apply_grid_snap(state, state.values.target_position)
			else:
				# Y Snap is OFF: only snap XZ axes (preserve Y for Q/E keys)
				var preserved_y = state.values.target_position.y
				state.values.target_position = _apply_grid_snap_xz_only(state, state.values.target_position)
				state.values.target_position.y = preserved_y  # Restore Y position
		else:
			# Placement mode: apply standard grid snapping to all enabled axes
			state.values.target_position = _apply_grid_snap(state, state.values.target_position)
	
	# Update current position
	# NOTE: Do NOT add manual_position_offset here!
	# The offset is stored separately in state.values.manual_position_offset and applied
	# later in TransformApplicator.apply_transform_state() to allow unsnapped WASD adjustments
	var old_offset = state.values.manual_position_offset
	state.values.position = state.values.target_position
	
	# Debug: Verify offset wasn't changed
	if old_offset != state.values.manual_position_offset:
		PluginLogger.error("PositionManager", "BUG: manual_position_offset was changed! Was %s, now %s" % [old_offset, state.values.manual_position_offset])
	
	# Debug: Log manual_position_offset to verify it's preserved
	if state.values.manual_position_offset.length_squared() > 0.001:
		PluginLogger.debug("PositionManager", "Position updated to %s, offset preserved: %s" % [state.values.position, state.values.manual_position_offset])
	
	return state.values.position

func _apply_grid_snap(state: TransformState, pos: Vector3) -> Vector3:
	"""Apply grid snapping to a position (pivot-based with optional center snapping)"""
	var snapped_pos = pos
	
	# Determine effective snap steps (half if state.snap.use_half_step active)
	var effective_step_x = state.snap.snap_step if not state.snap.use_half_step else state.snap.snap_step * 0.5
	var effective_step_z = state.snap.snap_step if not state.snap.use_half_step else state.snap.snap_step * 0.5
	var effective_step_y = state.snap.snap_y_step if not state.snap.use_half_step else state.snap.snap_y_step * 0.5
	
	# Apply X-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_x = state.snap.snap_offset.x
		if state.snap.snap_center_x:
			offset_x += effective_step_x * 0.5
		snapped_pos.x = TransformMath.snap_value(pos.x, effective_step_x, offset_x)

	# Apply Z-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_z = state.snap.snap_offset.z
		if state.snap.snap_center_z:
			offset_z += effective_step_z * 0.5
		snapped_pos.z = TransformMath.snap_value(pos.z, effective_step_z, offset_z)

	# Handle Y-axis if enabled with optional center offset
	if state.snap.snap_y_enabled and state.snap.snap_y_step > 0:
		var offset_y = state.snap.snap_offset.y
		if state.snap.snap_center_y:
			offset_y += effective_step_y * 0.5
		snapped_pos.y = TransformMath.snap_value(pos.y, effective_step_y, offset_y)
	
	return snapped_pos

func _apply_grid_snap_xz_only(state: TransformState, pos: Vector3) -> Vector3:
	"""Apply grid snapping only to XZ axes (for Transform mode where Y is controlled by Q/E keys)"""
	var snapped_pos = pos
	
	# Determine effective snap steps (half if state.snap.use_half_step active)
	var effective_step_x = state.snap.snap_step if not state.snap.use_half_step else state.snap.snap_step * 0.5
	var effective_step_z = state.snap.snap_step if not state.snap.use_half_step else state.snap.snap_step * 0.5
	
	# Apply X-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_x = state.snap.snap_offset.x
		if state.snap.snap_center_x:
			offset_x += effective_step_x * 0.5
		snapped_pos.x = TransformMath.snap_value(pos.x, effective_step_x, offset_x)

	# Apply Z-axis snapping (only if snap_enabled and valid step)
	if state.snap.snap_enabled and state.snap.snap_step > 0:
		var offset_z = state.snap.snap_offset.z
		if state.snap.snap_center_z:
			offset_z += effective_step_z * 0.5
		snapped_pos.z = TransformMath.snap_value(pos.z, effective_step_z, offset_z)
	
	# NOTE: Y-axis is NOT snapped in this function - it's controlled by Q/E keys in Transform mode
	
	return snapped_pos

func _apply_surface_offset(hit_position: Vector3, surface_normal: Vector3, transform_nodes: Array = []) -> Vector3:
	"""Apply surface offset to place objects correctly on surfaces without clipping
	
	Works for both Placement Mode (using preview) and Transform Mode (using actual nodes).
	
	Args:
		hit_position: The raycast hit position on the surface
		surface_normal: The normal vector of the surface
		transform_nodes: Array of nodes being transformed (for Transform Mode), empty for Placement Mode
	
	ALGORITHM:
	1. Get the node(s) to calculate bounds from (preview for placement, actual nodes for transform)
	2. Get local AABB and current rotation/scale
	3. Transform all 8 corners by rotation and scale
	4. Project onto surface normal to find how far object extends against the normal
	5. Offset by that distance to prevent clipping
	"""
	var target_node = null
	var rotation = Vector3.ZERO
	var scale = Vector3.ONE
	
	# Determine which node to use for bounds calculation
	if transform_nodes.size() > 0:
		# Transform Mode: use the first transform target node
		target_node = transform_nodes[0] if transform_nodes[0] is Node3D else null
		if target_node and target_node is Node3D:
			rotation = target_node.rotation
			scale = target_node.scale
	elif _services and _services.preview_manager and _services.preview_manager.has_preview():
		# Placement Mode: use the preview node
		target_node = _services.preview_manager.get_preview_mesh()
		if target_node:
			rotation = _services.preview_manager.get_preview_rotation()
			scale = _services.preview_manager.get_preview_scale()
	
	# Fallback if no valid node
	if not target_node:
		print("[PositionManager] WARNING: No node for surface offset, using default")
		return hit_position + surface_normal * 0.5
	
	# Get local AABB - try multiple methods
	var local_aabb = AABB()
	
	# Method 1: Direct mesh access for simple MeshInstance3D
	if target_node is MeshInstance3D and target_node.mesh:
		local_aabb = target_node.mesh.get_aabb()
	# Method 2: VisualInstance3D.get_aabb() for visual nodes
	elif target_node is VisualInstance3D:
		local_aabb = target_node.get_aabb()
	# Method 3: Recursively combine children
	else:
		local_aabb = _get_combined_mesh_bounds(target_node)
	
	# Fallback if no bounds found
	if local_aabb.size == Vector3.ZERO:
		print("[PositionManager] WARNING: No bounds found, using default offset")
		return hit_position + surface_normal * 0.5
	
	# Create basis from rotation
	var basis = Basis.from_euler(rotation)
	
	# Get all 8 corners in local space
	var corners_local = [
		Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.position.z),
		Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.position.z),
		Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.position.z),
		Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.position.z),
		Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.end.z),
		Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.end.z),
		Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.end.z),
		Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.end.z),
	]
	
	# Transform corners to world orientation (apply scale and rotation, but not position)
	var corners_transformed = []
	for corner in corners_local:
		var scaled = corner * scale
		var rotated = basis * scaled
		corners_transformed.append(rotated)
	
	# Project all corners onto the surface normal and find the most negative
	var min_projection = INF
	for corner in corners_transformed:
		var proj = corner.dot(surface_normal)
		if proj < min_projection:
			min_projection = proj
	
	# The offset is the absolute value (how far the deepest point extends against the normal)
	var offset = abs(min_projection) + 0.001
	
	return hit_position + surface_normal * offset

func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	"""Transform an AABB by a Transform3D
	
	In Godot 4.x, AABB doesn't have a transformed() method, so we manually
	transform all 8 corners and create a new AABB that contains them all.
	"""
	if aabb.size == Vector3.ZERO:
		return aabb
	
	# Get all 8 corners of the AABB
	var corners = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]
	
	# Transform all corners
	var transformed_corners = []
	for corner in corners:
		transformed_corners.append(transform * corner)
	
	# Create new AABB from transformed corners
	var result = AABB(transformed_corners[0], Vector3.ZERO)
	for i in range(1, transformed_corners.size()):
		result = result.expand(transformed_corners[i])
	
	return result

func _get_combined_mesh_bounds(node: Node) -> AABB:
	"""Get combined AABB of all visual instances in local space
	
	Uses Godot's built-in get_aabb() which handles complex hierarchies automatically.
	Returns bounds in LOCAL space (relative to the root node's pivot).
	"""
	var combined = AABB()
	var has_bounds = false
	
	# First try: if the node itself is a VisualInstance3D, use get_aabb()
	if node is VisualInstance3D:
		var aabb = node.get_aabb()
		if aabb.size != Vector3.ZERO:
			return aabb
	
	# Second try: if node is MeshInstance3D with a mesh
	if node is MeshInstance3D and node.mesh:
		return node.mesh.get_aabb()
	
	# Third try: recursively combine all VisualInstance3D children
	for child in node.get_children():
		if child is VisualInstance3D:
			var child_aabb = child.get_aabb()
			if child_aabb.size != Vector3.ZERO:
				# Transform child AABB by its local transform
				if child is Node3D and child.transform != Transform3D.IDENTITY:
					child_aabb = _transform_aabb(child_aabb, child.transform)
				
				if not has_bounds:
					combined = child_aabb
					has_bounds = true
				else:
					combined = combined.merge(child_aabb)
		elif child is Node3D:
			# Recurse into non-visual nodes
			var child_bounds = _get_combined_mesh_bounds(child)
			if child_bounds.size != Vector3.ZERO:
				# Transform by child's local transform
				if child.transform != Transform3D.IDENTITY:
					child_bounds = _transform_aabb(child_bounds, child.transform)
				
				if not has_bounds:
					combined = child_bounds
					has_bounds = true
				else:
					combined = combined.merge(child_bounds)
	
	return combined

## Position Offset Management (Unified System)

func adjust_offset_normal(state: TransformState, delta: float) -> void:
	"""Adjust position offset along the plane's normal direction (Q/E keys)
	- XZ plane (horizontal): adjusts Y (perpendicular to plane)
	- XY plane: adjusts Z (perpendicular to plane)
	- YZ plane: adjusts X (perpendicular to plane)
	"""
	var normal_dir = _get_plane_normal_direction(state)
	state.values.manual_position_offset += normal_dir * delta

func adjust_offset_y(state: TransformState, delta: float) -> void:
	"""Adjust the Y component of position offset directly (world Y axis)"""
	state.values.manual_position_offset.y += delta

func adjust_offset_x(state: TransformState, delta: float) -> void:
	"""Adjust the X component of position offset (world X axis)"""
	state.values.manual_position_offset.x += delta

func adjust_offset_z(state: TransformState, delta: float) -> void:
	"""Adjust the Z component of position offset (world Z axis)"""
	state.values.manual_position_offset.z += delta

func adjust_offset_normal_with_modifiers(state: TransformState, base_delta: float, modifiers: Dictionary) -> void:
	"""Adjust offset along plane normal with modifier-calculated step (Q/E keys)
	
	Args:
		state: TransformState to modify
		base_delta: Base step (e.g., 0.1)
		modifiers: Modifier state from InputHandler.get_modifier_state()
	"""
	var step = IncrementCalculator.calculate_height_step(base_delta, modifiers)
	adjust_offset_normal(state, step)

func increase_offset_normal(state: TransformState) -> void:
	"""Increase offset along plane normal by one step (Q key)"""
	# Use Y snap step if Y snapping is enabled, otherwise use state's configured height_adjustment_step
	var step = state.snap.snap_y_step if state.snap.snap_y_enabled else state.placement.height_adjustment_step
	adjust_offset_normal(state, step)

func decrease_offset_normal(state: TransformState) -> void:
	"""Decrease offset along plane normal by one step (E key)"""
	# Use Y snap step if Y snapping is enabled, otherwise use state's configured height_adjustment_step
	var step = state.snap.snap_y_step if state.snap.snap_y_enabled else state.placement.height_adjustment_step
	adjust_offset_normal(state, -step)

func reset_offset_normal(state: TransformState) -> void:
	"""Reset offset along plane normal to zero"""
	var normal_dir = _get_plane_normal_direction(state)
	# Remove only the component along the normal direction
	var current_offset = state.values.manual_position_offset
	var normal_component = current_offset.dot(normal_dir)
	state.values.manual_position_offset -= normal_dir * normal_component

# Position adjustment functions (plane-relative with camera awareness)
func move_left(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position left relative to plane orientation and camera view"""
	var move_dir = _get_plane_right_direction(state, camera) * -1.0  # Left is negative right
	var movement = move_dir * delta
	state.values.manual_position_offset += movement

func move_right(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position right relative to plane orientation and camera view"""
	var move_dir = _get_plane_right_direction(state, camera)
	var movement = move_dir * delta
	state.values.manual_position_offset += movement

func move_forward(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position forward relative to plane orientation and camera view"""
	var move_dir = _get_plane_forward_direction(state, camera)
	var movement = move_dir * delta
	state.values.manual_position_offset += movement

func move_backward(state: TransformState, delta: float, camera: Camera3D = null) -> void:
	"""Move the position backward relative to plane orientation and camera view"""
	var move_dir = _get_plane_forward_direction(state, camera) * -1.0  # Backward is negative forward
	var movement = move_dir * delta
	state.values.manual_position_offset += movement

func move_direction_with_modifiers(state: TransformState, direction: String, base_delta: float, modifiers: Dictionary, camera: Camera3D = null) -> void:
	"""Move in a direction with modifier-calculated step
	
	Args:
		state: TransformState to modify
		direction: Movement direction ("left", "right", "forward", "backward")
		base_delta: Base movement step (e.g., 0.5 units)
		modifiers: Modifier state from InputHandler.get_modifier_state()
		camera: Camera for relative movement
	"""
	var step = IncrementCalculator.calculate_position_step(base_delta, modifiers)
	
	match direction.to_lower():
		"left":
			move_left(state, step, camera)
		"right":
			move_right(state, step, camera)
		"forward":
			move_forward(state, step, camera)
		"backward":
			move_backward(state, step, camera)
		_:
			PluginLogger.warning("PositionManager", "Invalid direction: " + direction)

func _get_plane_forward_direction(state: TransformState, camera: Camera3D = null) -> Vector3:
	"""Get the forward direction for the current plane based on plane type and camera
	- Vertical planes (XY/YZ): Forward is always UP (Y axis) for W/S
	- Horizontal plane (XZ): Forward snapped to nearest axis (X or Z) based on camera"""
	var plane_data = _get_service().get_current_plane_data()
	
	# Check if this is a horizontal plane (normal points up/down)
	var normal = plane_data.get("normal", Vector3.UP) if plane_data else Vector3.UP
	var is_horizontal = abs(normal.y) > 0.9  # Normal is mostly vertical = horizontal plane
	
	if is_horizontal:
		# XZ Plane: Snap camera forward to nearest axis (X or Z)
		if camera:
			var cam_forward = -camera.global_transform.basis.z
			cam_forward.y = 0  # Project to XZ plane
			if cam_forward.length_squared() > 0.01:
				cam_forward = cam_forward.normalized()
				# Snap to nearest axis
				if abs(cam_forward.z) > abs(cam_forward.x):
					# Primarily Z direction
					return Vector3(0, 0, sign(cam_forward.z))
				else:
					# Primarily X direction
					return Vector3(sign(cam_forward.x), 0, 0)
		# Fallback to Z axis
		return Vector3.FORWARD
	else:
		# Vertical planes (XY/YZ): W/S always controls Y axis (up/down)
		return Vector3.UP

func _get_plane_normal_direction(state: TransformState) -> Vector3:
	"""Get the normal direction for the current plane (perpendicular to plane surface)
	- XZ plane (horizontal): normal is Y axis (up/down)
	- XY plane: normal is Z axis (forward/back)
	- YZ plane: normal is X axis (left/right)
	
	This is used for Q/E keys to move perpendicular to the active plane.
	"""
	return get_plane_normal_direction(state)

func get_plane_normal_direction(state: TransformState) -> Vector3:
	"""Get the normal direction for the current plane (perpendicular to plane surface) - Public API
	- XZ plane (horizontal): normal is Y axis (up/down)
	- XY plane: normal is Z axis (forward/back)
	- YZ plane: normal is X axis (left/right)
	"""
	var plane_data = _get_service().get_current_plane_data()
	
	if plane_data:
		# Use the actual plane normal from the placement strategy
		var normal = plane_data.get("normal", Vector3.UP)
		return normal.normalized()
	
	# Fallback: assume XZ plane (most common)
	return Vector3.UP

func _get_plane_right_direction(state: TransformState, camera: Camera3D = null) -> Vector3:
	"""Get the right direction for the current plane based on plane type and camera
	- Always camera-relative but snapped to nearest axis for precise movement"""
	var plane_data = _get_service().get_current_plane_data()
	
	# Check if this is a horizontal plane
	var normal = plane_data.get("normal", Vector3.UP) if plane_data else Vector3.UP
	var is_horizontal = abs(normal.y) > 0.9
	
	if is_horizontal:
		# XZ Plane: Snap camera right to nearest axis (X or Z)
		if camera:
			var cam_right = camera.global_transform.basis.x
			cam_right.y = 0  # Project to XZ plane
			if cam_right.length_squared() > 0.01:
				cam_right = cam_right.normalized()
				# Snap to nearest axis
				if abs(cam_right.x) > abs(cam_right.z):
					# Primarily X direction
					return Vector3(sign(cam_right.x), 0, 0)
				else:
					# Primarily Z direction
					return Vector3(0, 0, sign(cam_right.z))
		# Fallback to X axis
		return Vector3.RIGHT
	else:
		# Vertical planes: Snap camera right to the plane's horizontal axis
		if camera:
			# Get camera right and project it onto the plane
			var cam_right = camera.global_transform.basis.x
			# Project onto plane by removing the component along the plane normal
			var projected_right = cam_right - normal * cam_right.dot(normal)
			if projected_right.length_squared() > 0.01:
				projected_right = projected_right.normalized()
				
				# Snap to nearest axis on the plane
				# XY plane: snap to X
				# YZ plane: snap to Y or Z
				if abs(normal.z) > 0.9:
					# XY plane: only X axis available (Y is forward)
					return Vector3(sign(projected_right.x), 0, 0) if abs(projected_right.x) > 0.01 else Vector3.RIGHT
				else:
					# YZ plane: Y or Z axis
					if abs(projected_right.y) > abs(projected_right.z):
						return Vector3(0, sign(projected_right.y), 0)
					else:
						return Vector3(0, 0, sign(projected_right.z))
		
		# Fallback: use plane's inherent right direction
		# XY plane (normal is BACK): right is X
		# YZ plane (normal is RIGHT): right is Z
		if abs(normal.z) > 0.9:
			return Vector3.RIGHT
		else:
			return Vector3.FORWARD

func reset_position(state: TransformState) -> void:
	"""Reset manual position offset to zero"""
	# Remove the current offset from positions
	state.values.position -= state.values.manual_position_offset
	state.values.target_position -= state.values.manual_position_offset
	# Clear the offset
	state.values.manual_position_offset = Vector3.ZERO

func apply_position_delta(state: TransformState, delta: Vector3) -> void:
	"""Apply a position delta to the manual position offset
	
	Args:
		state: TransformState to modify
		delta: Position delta to apply (in world space)
	"""
	state.values.manual_position_offset += delta
	
func rotate_manual_offset(state: TransformState, axis: String, angle_degrees: float) -> void:
	"""Rotate the manual position offset around the specified axis
	This is called when the preview mesh rotates so the offset rotates with it"""
	if state.values.manual_position_offset.length_squared() < 0.0001:
		# No offset to rotate
		return
	
	# Convert degrees to radians
	var angle_rad = deg_to_rad(angle_degrees)
	
	var rotated_offset = Vector3.ZERO
	
	# Rotate around the specified axis
	match axis.to_upper():
		"X":
			# Rotate around X axis (affects Y and Z)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.values.manual_position_offset.x,  # X doesn't change
				state.values.manual_position_offset.y * cos_angle - state.values.manual_position_offset.z * sin_angle,
				state.values.manual_position_offset.y * sin_angle + state.values.manual_position_offset.z * cos_angle
			)
		"Y":
			# Rotate around Y axis (affects X and Z)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.values.manual_position_offset.x * cos_angle - state.values.manual_position_offset.z * sin_angle,
				state.values.manual_position_offset.y,  # Y doesn't change
				state.values.manual_position_offset.x * sin_angle + state.values.manual_position_offset.z * cos_angle
			)
		"Z":
			# Rotate around Z axis (affects X and Y)
			var cos_angle = cos(angle_rad)
			var sin_angle = sin(angle_rad)
			rotated_offset = Vector3(
				state.values.manual_position_offset.x * cos_angle - state.values.manual_position_offset.y * sin_angle,
				state.values.manual_position_offset.x * sin_angle + state.values.manual_position_offset.y * cos_angle,
				state.values.manual_position_offset.z  # Z doesn't change
			)
		_:
			return
	
	# Update positions to account for the rotated offset
	state.values.position -= state.values.manual_position_offset  # Remove old offset
	state.values.manual_position_offset = rotated_offset  # Update to rotated offset
	state.values.position += state.values.manual_position_offset  # Apply new offset
	state.values.target_position = state.values.position

func set_base_height(state: TransformState, y: float) -> void:
	"""Set the base height reference point"""
	state.values.base_position.y = y
	state.values.target_position = state.values.base_position
	state.values.position = state.values.target_position

func reset_for_new_placement(state: TransformState, reset_height_offset: bool = true, reset_position_offset: bool = true) -> void:
	"""Reset position manager state for a new placement session
	
	reset_height_offset: If true, reset Y offset to 0. If false, preserve current Y offset.
	reset_position_offset: If true, reset manual_position_offset to 0. If false, preserve current offset."""
	state.placement.is_initial_position = true
	if reset_height_offset:
		state.values.manual_position_offset.y = 0.0
	
	state.values.position = Vector3.ZERO
	state.values.target_position = Vector3.ZERO
	state.values.base_position = Vector3.ZERO
	state.values.surface_normal = Vector3.UP
	state.placement.last_raycast_xz = Vector2.ZERO
	if reset_position_offset:
		state.values.manual_position_offset = Vector3.ZERO  # Reset all offset for new placement

func _calculate_position(from: Vector3, to: Vector3, additional_config: Dictionary) -> PlacementStrategy.PlacementResult:
	"""Calculate placement position using the injected service"""
	return _get_service().calculate_position(from, to, additional_config)

## Position Getters and Setters

func get_current_position(state: TransformState) -> Vector3:
	"""Get the current calculated position"""
	return state.values.position

func get_target_position(state: TransformState) -> Vector3:
	"""Get the target position (may be different during interpolation)"""
	return state.values.target_position

func set_position(state: TransformState, pos: Vector3) -> void:
	"""Directly set the current position"""
	state.values.position = pos
	state.values.target_position = pos
	state.values.base_position = pos
	state.values.manual_position_offset = Vector3.ZERO

func get_offset_y(state: TransformState) -> float:
	"""Get the current Y offset from base"""
	return state.values.manual_position_offset.y

func get_base_position(state: TransformState) -> Vector3:
	"""Get the base position (current position without offset applied)
	This is useful for positioning the grid overlay at ground level"""
	return state.values.base_position

func get_surface_normal(state: TransformState) -> Vector3:
	"""Get the surface normal at the current position"""
	return state.values.surface_normal

## Position Validation and Constraints

func is_valid_position(pos: Vector3) -> bool:
	"""Check if a position is valid for object placement"""
	# Basic bounds checking
	if abs(pos.x) > 10000 or abs(pos.z) > 10000:
		return false
	
	# Check for reasonable Y values
	if pos.y < -1000 or pos.y > 1000:
		return false
	
	return true

func clamp_position_to_bounds(pos: Vector3, bounds: AABB = AABB()) -> Vector3:
	"""Clamp position to specified bounds"""
	if bounds.size == Vector3.ZERO:
		# Default bounds if none specified
		bounds = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	
	return Vector3(
		clampf(pos.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(pos.y, bounds.position.y, bounds.position.y + bounds.size.y),
		clampf(pos.z, bounds.position.z, bounds.position.z + bounds.size.z)
	)

## Position Interpolation and Smoothing

func enable_smooth_positioning(speed: float = 10.0) -> void:
	"""Enable smooth position interpolation"""
	_interpolation_enabled = true
	_interpolation_speed = speed

func disable_smooth_positioning() -> void:
	"""Disable position interpolation"""
	_interpolation_enabled = false

func update_smooth_position(state: TransformState, delta: float) -> void:
	"""Update position with smooth interpolation (call from _process)"""
	if not _interpolation_enabled:
		return
	
	if state.values.position.distance_to(state.values.target_position) > 0.01:
		state.values.position = state.values.position.lerp(state.values.target_position, _interpolation_speed * delta)

## Configuration


func configure(state: TransformState, config: Dictionary) -> void:
	"""Configure position manager settings and placement strategies"""
	
	# Configure instance-scoped flags
	_collision_mask = config.get("collision_mask", _collision_mask)
	_interpolation_enabled = config.get("interpolation_enabled", _interpolation_enabled)
	_interpolation_speed = config.get("interpolation_speed", _interpolation_speed)
	_align_with_normal = config.get("align_with_normal", _align_with_normal)

	# Configure state-specific settings from config (CRITICAL for grid snapping!)
	if config.has("height_adjustment_step"):
		state.placement.height_adjustment_step = config.get("height_adjustment_step", state.placement.height_adjustment_step)
	state.placement.align_with_normal = _align_with_normal
	
	# Update snap settings from config (these must be synchronized with UI settings)
	state.snap.snap_enabled = config.get("snap_enabled", state.snap.snap_enabled)
	state.snap.snap_step = config.get("snap_step", state.snap.snap_step)
	state.snap.snap_offset = config.get("snap_offset", state.snap.snap_offset)
	state.snap.snap_y_enabled = config.get("snap_y_enabled", state.snap.snap_y_enabled)
	state.snap.snap_y_step = config.get("snap_y_step", state.snap.snap_y_step)
	state.snap.snap_center_x = config.get("snap_center_x", state.snap.snap_center_x)
	state.snap.snap_center_y = config.get("snap_center_y", state.snap.snap_center_y)
	state.snap.snap_center_z = config.get("snap_center_z", state.snap.snap_center_z)

	# Forward config (unmodified) to strategy service for collision mask etc.
	_get_service().configure(config)

func get_configuration(state: TransformState) -> Dictionary:
	"""Get current configuration (authoritative state + local flags)"""
	return {
		"height_adjustment_step": state.placement.height_adjustment_step,
		"collision_mask": _collision_mask,
		"interpolation_enabled": _interpolation_enabled,
		"snap_enabled": state.snap.snap_enabled,
		"snap_step": state.snap.snap_step,
		"interpolation_speed": _interpolation_speed,
		"align_with_normal": _align_with_normal,
		"placement_strategy": _get_service().get_active_strategy_type(),
		"use_half_step": state.snap.use_half_step
	}

func _get_service() -> PlacementStrategyService:
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	return _placement_service

func _get_current_settings() -> Dictionary:
	"""Get current settings dictionary for passing to placement strategies"""
	if _services and _services.settings_manager:
		return _services.settings_manager.get_combined_settings()
	return {}

## Transform Node Positioning (for Transform Mode)

func update_transform_node_position(state: TransformState, transform_node: Node3D, camera: Camera3D, mouse_pos: Vector2) -> void:
	"""Update position of a transform mode node based on mouse input"""
	if not transform_node or not camera:
		return
	
	# Calculate world position from mouse
	var world_pos = update_position_from_mouse(state, camera, mouse_pos)
	
	# Position is already calculated with proper height offset in update_position_from_mouse
	# Just apply it directly (no need to recalculate)
	
	if transform_node.is_inside_tree():
		transform_node.global_position = world_pos

func start_transform_positioning(state: TransformState, node: Node3D) -> void:
	"""Initialize positioning for transform mode"""
	if node and node.is_inside_tree():
		set_position(state, node.global_position)
		state.values.base_position = node.global_position
		state.values.manual_position_offset = Vector3.ZERO  # Reset offset for transform mode

## Utility Functions

func get_distance_to_camera(state: TransformState, camera: Camera3D) -> float:
	"""Get distance from current position to camera"""
	if camera:
		return state.values.position.distance_to(camera.global_position)
	return 0.0

func is_position_in_camera_view(state: TransformState, camera: Camera3D) -> bool:
	"""Check if current position is within camera view frustum"""
	if not camera:
		return false
	
	# Simple distance-based check
	var distance = get_distance_to_camera(state, camera)
	return distance > 0.1 and distance < 1000.0

func get_surface_normal_at_position(pos: Vector3) -> Vector3:
	"""Get surface normal at a given position (if collision detection finds one)"""
	# This would require more complex collision detection
	# For now, return up vector as default
	return Vector3.UP

## Debug and Visualization

func debug_print_position_state(state: TransformState) -> void:
	"""Print current position state for debugging"""
	PluginLogger.debug("PositionManager", "Position: %v, Offset Y: %.2f" % [state.values.position, state.values.manual_position_offset.y])

func get_position_info(state: TransformState) -> Dictionary:
	"""Get comprehensive position information"""
	return {
		"current_position": state.values.position,
		"target_position": state.values.target_position,
		"base_position": state.values.base_position,
		"manual_position_offset": state.values.manual_position_offset,
		"offset_y": state.values.manual_position_offset.y,
		"surface_normal": state.values.surface_normal,
		"total_position": state.values.base_position + state.values.manual_position_offset,
		"is_interpolating": _interpolation_enabled and state.values.position.distance_to(state.values.target_position) > 0.01
	}

## Property accessors for half-step mode



