@tool
extends "res://addons/simpleassetplacer/placement/placement_strategy.gd"

class_name PlanePlacementStrategy

"""
PLANE-BASED PLACEMENT STRATEGY
==============================

PURPOSE: Calculate placement position using ray-to-plane projection.

STRATEGY: Projects the mouse ray onto a plane that passes through the object's current
position. This provides direct, natural mouse control (like collision strategy) while
constraining movement to a specific plane orientation.

KEY FEATURE: The plane dynamically follows the object's position, which prevents position
jumps when cycling between plane types (XZ/XY/YZ). When you change planes, the new plane
passes through the object's current position, so the next mouse raycast naturally continues
from where you were.

FEATURES:
- Direct ray-to-plane projection (natural mouse control)
- Support for three plane orientations (XZ/XY/YZ)
- Smooth plane cycling with NO position jumps
- Perfect for transform mode and precise placement
- Optional height tracking (updates plane height as object moves)

CONFIGURATION:
- plane_height: The fixed coordinate value for the plane (Y for XZ, Z for XY, X for YZ)
- plane_type: Which plane orientation to use (XZ=horizontal, XY/YZ=vertical)
- track_height: Whether plane height updates with object movement
- default_height: Fallback height if calculation fails

MODES:
- Placement Mode: Starts at default height, plane follows object as it moves
- Transform Mode: Locks to object position, plane always passes through object

USED BY: PlacementStrategyService when user selects plane-based placement"""

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const CursorWarpAdapter = preload("res://addons/simpleassetplacer/utils/cursor_warp_adapter.gd")

const ALIGNMENT_EPSILON := 0.05

# Plane type enum
enum PlaneType {
	XZ = 0,  # Horizontal plane (default)
	XY = 1,  # Vertical plane facing Z
	YZ = 2   # Vertical plane facing X
}

# Plane data structure for each plane type
class PlaneData:
	var normal: Vector3
	var axis_u: Vector3  # First basis vector in plane
	var axis_v: Vector3  # Second basis vector in plane
	var axis_index: int  # Which component (0=x, 1=y, 2=z) is used for height
	
	func _init(p_normal: Vector3, p_axis_u: Vector3, p_axis_v: Vector3, p_axis_index: int):
		normal = p_normal
		axis_u = p_axis_u
		axis_v = p_axis_v
		axis_index = p_axis_index

# Plane type definitions
static var PLANE_DEFINITIONS: Dictionary = {
	PlaneType.XZ: PlaneData.new(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, 1),      # Y is height
	PlaneType.XY: PlaneData.new(Vector3.BACK, Vector3.RIGHT, Vector3.UP, 2),         # Z is height
	PlaneType.YZ: PlaneData.new(Vector3.RIGHT, Vector3.UP, Vector3.FORWARD, 0)       # X is height
}

# Configuration
var plane_height: float = 0.0
var track_height: bool = false
var default_height: float = 0.0
var plane_type: PlaneType = PlaneType.XZ
var plane_height_locked: bool = false

# Position caching for movement tracking
var last_position: Vector3 = Vector3.ZERO
var has_last_position: bool = false

# Plane cycling protection - only freeze at the exact mouse position where plane was cycled
var _freeze_mouse_position: Vector2 = Vector2(-1, -1)
var _freeze_threshold: float = 5.0  # Pixels of mouse movement to unfreeze

## Helper Methods

func _get_plane_data(type: PlaneType = plane_type) -> PlaneData:
	"""Get plane configuration data for a plane type"""
	return PLANE_DEFINITIONS.get(type, PLANE_DEFINITIONS[PlaneType.XZ])

func _get_plane_component(position: Vector3, type: PlaneType = plane_type) -> float:
	"""Get the height component for a plane type (x, y, or z depending on plane)"""
	var plane_data = _get_plane_data(type)
	return position[plane_data.axis_index]

func _set_plane_component(position: Vector3, value: float, type: PlaneType = plane_type) -> Vector3:
	"""Set the height component for a plane type"""
	var plane_data = _get_plane_data(type)
	position[plane_data.axis_index] = value
	return position

func _project_ray_to_plane(from: Vector3, ray_dir: Vector3, fallback: Vector3 = Vector3.ZERO, use_fallback: bool = false) -> Vector3:
	"""Project ray onto current plane type using base class helpers"""
	match plane_type:
		PlaneType.XZ:
			return project_to_horizontal_plane(from, ray_dir, plane_height, fallback, use_fallback)
		PlaneType.XY:
			return project_to_xy_plane(from, ray_dir, plane_height, fallback, use_fallback)
		PlaneType.YZ:
			return project_to_yz_plane(from, ray_dir, plane_height, fallback, use_fallback)
		_:
			return project_to_horizontal_plane(from, ray_dir, plane_height, fallback, use_fallback)

func _clear_cache() -> void:
	"""Clear all cached positioning data"""
	plane_height_locked = false
	last_position = Vector3.ZERO
	has_last_position = false
	_freeze_mouse_position = Vector2(-1, -1)

func _calculate_screen_delta_movement(camera: Camera3D, anchor_position: Vector3, screen_delta: Vector2) -> Variant:
	"""Convert screen space mouse delta to world space movement on the plane
	
	Returns:
		Vector3 world delta on success, null on failure, Vector3.ZERO if delta too small
	"""
	if screen_delta.length_squared() < 0.0001:
		return Vector3.ZERO
	
	if not camera or not is_instance_valid(camera):
		return null
	
	var viewport: SubViewport = camera.get_viewport()
	if not viewport:
		return null
	
	var viewport_size = viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return null
	
	# Handle cursor wrapping at viewport edges
	screen_delta = _wrap_screen_delta(screen_delta, viewport_size)
	
	# Get plane-aligned basis vectors
	var plane_data = _get_plane_data()
	var plane_normal = plane_data.normal
	var camera_basis = camera.global_transform.basis
	
	# Project camera axes onto plane
	var plane_right = _project_vector_onto_plane(camera_basis.x, plane_normal, plane_data.axis_u)
	var plane_up = _project_vector_onto_plane(camera_basis.y, plane_normal, plane_data.axis_v)
	
	if plane_right.length_squared() < 1e-6 or plane_up.length_squared() < 1e-6:
		return null
	
	# Calculate pixel-to-world scale based on camera type
	var pixel_scale = _calculate_pixel_to_world_scale(camera, anchor_position, viewport_size)
	if pixel_scale == null:
		return null
	
	# Calculate world space movement
	var world_delta = plane_right * (screen_delta.x * pixel_scale.x) - plane_up * (screen_delta.y * pixel_scale.y)
	return world_delta

func _wrap_screen_delta(delta: Vector2, viewport_size: Vector2) -> Vector2:
	"""Adjust screen delta for cursor wrapping at viewport edges"""
	var wrapped_delta = delta
	var wrap_threshold_x = viewport_size.x * 0.5
	var wrap_threshold_y = viewport_size.y * 0.5
	
	if abs(wrapped_delta.x) > wrap_threshold_x:
		wrapped_delta.x -= sign(wrapped_delta.x) * viewport_size.x
	if abs(wrapped_delta.y) > wrap_threshold_y:
		wrapped_delta.y -= sign(wrapped_delta.y) * viewport_size.y
	
	return wrapped_delta

func _project_vector_onto_plane(vector: Vector3, plane_normal: Vector3, fallback: Vector3) -> Vector3:
	"""Project a vector onto a plane, returning normalized result or fallback"""
	var projected = vector - plane_normal * vector.dot(plane_normal)
	if projected.length_squared() < 1e-6:
		return fallback
	return projected.normalized()

func _calculate_pixel_to_world_scale(camera: Camera3D, anchor_position: Vector3, viewport_size: Vector2) -> Variant:
	"""Calculate screen pixel to world unit conversion scale
	
	Returns:
		Vector2(x_scale, y_scale) on success, null on failure
	"""
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var camera_forward = -camera.global_transform.basis.z
		var to_anchor = anchor_position - camera.global_transform.origin
		var depth = abs(to_anchor.dot(camera_forward))
		depth = max(depth, 0.001)  # Prevent division by zero
		
		var vertical_fov = deg_to_rad(camera.fov)
		var pixels_to_world_y = (2.0 * depth * tan(vertical_fov * 0.5)) / viewport_size.y
		var aspect_ratio = viewport_size.x / viewport_size.y
		var pixels_to_world_x = pixels_to_world_y * aspect_ratio
		
		return Vector2(pixels_to_world_x, pixels_to_world_y)
	else:  # PROJECTION_ORTHOGONAL
		var vertical_size = camera.size * 2.0
		var pixels_to_world_y = vertical_size / viewport_size.y
		var horizontal_size = vertical_size * (viewport_size.x / viewport_size.y)
		var pixels_to_world_x = horizontal_size / viewport_size.x
		
		return Vector2(pixels_to_world_x, pixels_to_world_y)

func _apply_screen_delta(camera: Camera3D, anchor_position: Vector3, previous_mouse: Vector2, current_mouse: Vector2) -> Variant:
	"""Apply screen space mouse movement to world position
	
	Returns:
		Vector3 new position on success, null on failure
	"""
	var screen_delta = current_mouse - previous_mouse
	var world_delta = _calculate_screen_delta_movement(camera, anchor_position, screen_delta)
	
	if world_delta == null:
		return null
	
	return anchor_position + world_delta

func _maybe_warp_cursor(camera: Camera3D, mouse_pos: Vector2, settings: Dictionary) -> Dictionary:
	"""Check if cursor should be warped and perform warp if needed
	
	Returns:
		Dictionary with keys:
			- warped (bool): Whether cursor was warped
			- new_position (Vector2): New mouse position
	"""
	# Check if cursor warping is enabled
	# Unified cursor warp key: only 'cursor_warp_enabled' respected.
	if not settings.get("cursor_warp_enabled", true):
		return {"warped": false, "new_position": mouse_pos}
	
	if not camera or not is_instance_valid(camera):
		return {"warped": false, "new_position": mouse_pos}
	
	var viewport: SubViewport = camera.get_viewport()
	if not viewport:
		return {"warped": false, "new_position": mouse_pos}
	
	# Use CursorWarpAdapter to handle the warping logic
	var adapter = CursorWarpAdapter.new()
	return adapter.maybe_warp_cursor_in_viewport(mouse_pos, viewport)

## Strategy Implementation

func calculate_position(from: Vector3, to: Vector3, config: Dictionary) -> PlacementResult:
	"""Calculate position using ray-to-plane projection with dynamic plane positioning
	
	NEW APPROACH: Instead of screen-delta movement, we raycast onto a plane that passes through
	the object's current position. This gives direct mouse control (like collision strategy)
	while preventing jumps when changing plane axes (plane moves with the object).
	"""
	
	# Extract configuration early to get mouse position
	_update_config(config)
	
	var camera: Camera3D = config.get("camera")
	var has_camera: bool = camera and is_instance_valid(camera)
	var mouse_position: Vector2 = config.get("mouse_position", Vector2.ZERO)
	var settings: Dictionary = config.get("settings", {})
	
	# Check if position updates are frozen (mouse hasn't moved since plane cycle)
	if _freeze_mouse_position.x >= 0:
		var mouse_delta = mouse_position.distance_to(_freeze_mouse_position)
		if mouse_delta < _freeze_threshold:
			# Mouse hasn't moved enough - keep frozen
			var plane_data = _get_plane_data()
			return PlacementResult.new(last_position, plane_data.normal, false, from.distance_to(last_position))
		else:
			# Mouse moved - unfreeze
			_freeze_mouse_position = Vector2(-1, -1)
	
	var plane_data = _get_plane_data()
	var ray_dir = (to - from).normalized()
	
	# Initialize position on first call
	if not has_last_position:
		return _initialize_position(from, ray_dir, plane_data, camera, mouse_position, has_camera)
	
	# Handle cursor warping if enabled
	if has_camera:
		var warp_result = _maybe_warp_cursor(camera, mouse_position, settings)
		if warp_result.warped:
			# Cursor was warped - don't update position this frame
			return PlacementResult.new(last_position, plane_data.normal, false, from.distance_to(last_position))
	
	# DON'T update plane height during normal mouse movement in placement mode
	# The plane height should remain fixed at the initial/cycled position
	# This allows height offset (Q/E) to work correctly without the plane "chasing" the object
	# Only update if:
	# - track_height is enabled (for following moving surfaces)
	# - plane_height_locked is false AND we're in initial setup
	
	# For locked planes (transform mode), keep the plane at the locked position
	# For unlocked planes (placement mode), keep the plane at its initial height (Y=0 or last cycle position)
	
	# Project ray onto plane at current height
	var position = _project_ray_to_plane(from, ray_dir, last_position, true)
	
	# If projection returned zero vector (complete failure), keep last position
	# Note: We removed the check for "position == last_position" because that's a valid result
	# when the mouse hasn't moved or is pointing at the same location
	if position == Vector3.ZERO:
		PluginLogger.warning("PlanePlacementStrategy", "Ray projection completely failed (returned zero)")
		return PlacementResult.new(last_position, plane_data.normal, false, from.distance_to(last_position))
	
	# Apply grid snapping if enabled
	var snap_enabled = settings.get("snap_enabled", false)
	if snap_enabled:
		var snap_step = settings.get("snap_step", 1.0)
		var snap_offset = settings.get("snap_offset", Vector3.ZERO)
		if snap_step > 0:
			# Snap each axis independently
			position.x = snappedf(position.x - snap_offset.x, snap_step) + snap_offset.x
			position.y = snappedf(position.y - snap_offset.y, snap_step) + snap_offset.y
			position.z = snappedf(position.z - snap_offset.z, snap_step) + snap_offset.z
			
			# After snapping, ensure the plane component is exactly at plane_height
			# Grid snapping might cause tiny floating point drift off the plane
			position = _set_plane_component(position, plane_height)
	
	# Update cache
	last_position = position
	has_last_position = true
	
	# Update tracking if enabled
	if track_height:
		plane_height = _get_plane_component(position)
	
	var distance = from.distance_to(position)
	return PlacementResult.new(position, plane_data.normal, false, distance)

func _update_config(config: Dictionary) -> void:
	"""Update strategy configuration from config dictionary
	
	NOTE: plane_height should NOT be updated from config during normal operation!
	It should only be set explicitly via:
	- initialize_plane_for_placement() -> sets to 0.0
	- initialize_plane_from_position() -> sets from object position (transform mode)
	- cycle_plane() -> updates when user cycles plane type
	
	Updating plane_height from config every frame would cause it to drift and break offset preservation.
	"""
	# DO NOT update plane_height from config - it should only be set explicitly
	# if not plane_height_locked:
	#     plane_height = config.get("plane_height", 0.0)
	
	track_height = config.get("track_plane_height", false)
	default_height = config.get("default_height", 0.0)

func _initialize_position(from: Vector3, ray_dir: Vector3, plane_data: PlaneData, camera: Camera3D, 
	mouse_position: Vector2, has_camera_input: bool) -> PlacementResult:
	"""Initialize position on first calculation
	
	If plane is already locked (transform mode), use the locked position.
	Otherwise start by projecting the ray onto the plane.
	"""
	var initial_position: Vector3
	
	if plane_height_locked and has_last_position:
		# Transform mode: Keep the existing position that was set by initialize_plane_from_position
		initial_position = last_position
	else:
		# Placement mode: Project ray onto plane at configured height
		initial_position = _project_ray_to_plane(from, ray_dir, from, true)
		
		# If projection failed, start at camera position on plane
		if initial_position == Vector3.ZERO or initial_position == from:
			initial_position = from
			initial_position = _set_plane_component(initial_position, plane_height)
	
	last_position = initial_position
	has_last_position = true
	
	return PlacementResult.new(initial_position, plane_data.normal, false, from.distance_to(initial_position))

func get_strategy_name() -> String:
	return "Plane Placement"

func get_strategy_type() -> String:
	return "plane"

func configure(config: Dictionary) -> void:
	"""Configure plane strategy settings"""
	# Only update plane_height from config if not locked
	if not plane_height_locked:
		plane_height = config.get("plane_height", 0.0)
	track_height = config.get("track_plane_height", false)
	default_height = config.get("default_height", 0.0)

func reset() -> void:
	"""Reset strategy to defaults"""
	plane_height = 0.0
	track_height = false
	default_height = 0.0
	plane_height_locked = false
	plane_type = PlaneType.XZ
	last_position = Vector3.ZERO
	has_last_position = false

func set_plane_height(height: float) -> void:
	"""Manually set the plane height (used when track_height is enabled)"""
	plane_height = height
	plane_height_locked = true  # Lock when manually set

func get_plane_height() -> float:
	"""Get current plane height"""
	return plane_height

func initialize_plane_from_position(position: Vector3) -> void:
	"""Initialize plane height from a starting position (for transform mode)
	
	With raycast-based positioning, we just need to set the initial height and position.
	"""
	plane_height = _get_plane_component(position)
	last_position = position
	has_last_position = true
	plane_height_locked = true
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, 
		"Plane initialized at height: %.2f for plane %s from position %v" % [plane_height, get_plane_name(), position])

func initialize_plane_for_placement() -> void:
	"""Initialize plane for placement mode (starts at origin)"""
	plane_height = 0.0
	plane_height_locked = false
	_clear_cache()
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Plane initialized for placement mode at height: 0.0")

func update_plane_height_from_position(position: Vector3) -> void:
	"""Update plane height to match a position (for height offset adjustments in transform mode)
	
	This allows the plane to follow the object when height is adjusted with Q/E in transform mode.
	"""
	plane_height = _get_plane_component(position)
	last_position = position

func cycle_plane(current_position: Vector3 = Vector3.ZERO, mouse_position: Vector2 = Vector2.ZERO) -> PlaneType:
	"""Cycle through available plane types (XZ -> XY -> YZ -> XZ)
	
	With the new raycast-based approach, cycling is seamless:
	- Plane height automatically updates to match object position
	- No jumps because the plane always passes through the object
	- Next mouse movement will raycast onto the new plane naturally
	
	Args:
		current_position: Current object position to anchor the new plane
		mouse_position: Current mouse position to freeze updates until mouse moves
	"""
	
	var old_type = plane_type
	
	# Cycle to next plane type
	match plane_type:
		PlaneType.XZ:
			plane_type = PlaneType.XY
		PlaneType.XY:
			plane_type = PlaneType.YZ
		PlaneType.YZ:
			plane_type = PlaneType.XZ
		_:
			plane_type = PlaneType.XZ
	
	# Determine reference position for alignment
	var reference_position = current_position
	if reference_position == Vector3.ZERO and has_last_position:
		reference_position = last_position
	
	# Update plane height to match reference position (no reprojection needed!)
	if reference_position != Vector3.ZERO:
		plane_height = _get_plane_component(reference_position)
		last_position = reference_position
		has_last_position = true
		plane_height_locked = true
		# No pending_reprojection flag needed - next frame's raycast handles it naturally
		
		PluginLogger.info(
			PluginConstants.COMPONENT_POSITION,
			"Plane cycled from %s to %s (plane_height: %.2f at position: %v)" % [
				_get_type_name(old_type),
				get_plane_name(),
				plane_height,
				reference_position
			]
		)
	
	# CRITICAL FIX: Freeze position updates until mouse moves
	# Store the current mouse position - we'll unfreeze once the mouse moves
	_freeze_mouse_position = mouse_position
	
	return plane_type

func _get_type_name(type: PlaneType) -> String:
	"""Helper to get plane type name"""
	match type:
		PlaneType.XZ:
			return "XZ"
		PlaneType.XY:
			return "XY"
		PlaneType.YZ:
			return "YZ"
		_:
			return "Unknown"

func set_plane_type(type: PlaneType) -> void:
	"""Set the active plane type
	
	With raycast-based positioning, plane changes are seamless.
	"""
	plane_type = type
	if has_last_position:
		# Update plane height to match current position
		plane_height = _get_plane_component(last_position)
		plane_height_locked = true
	PluginLogger.info(PluginConstants.COMPONENT_POSITION, "Plane type set to: %s" % get_plane_name())

func get_plane_type() -> PlaneType:
	"""Get current plane type"""
	return plane_type

func get_plane_name() -> String:
	"""Get human-readable name of current plane"""
	match plane_type:
		PlaneType.XZ:
			return "XZ (Horizontal)"
		PlaneType.XY:
			return "XY (Vertical - Front/Back)"
		PlaneType.YZ:
			return "YZ (Vertical - Left/Right)"
		_:
			return "Unknown"

func get_current_normal() -> Vector3:
	"""Get the normal vector of the current plane"""
	var plane_data = _get_plane_data()
	return plane_data.normal

func get_plane_data() -> Dictionary:
	"""Get the complete plane data (normal, axis_u, axis_v, axis_index) for the current plane"""
	var plane_data = _get_plane_data()
	return {
		"normal": plane_data.normal,
		"axis_u": plane_data.axis_u,
		"axis_v": plane_data.axis_v,
		"axis_index": plane_data.axis_index
	}







