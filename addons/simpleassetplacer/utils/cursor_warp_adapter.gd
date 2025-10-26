@tool
extends RefCounted

class_name CursorWarpAdapter

"""Adapter around Input.warp_mouse to simplify testing."""

func warp_mouse(position: Vector2) -> void:
	if position == null:
		return
	Input.warp_mouse(position)

func maybe_warp_cursor_in_viewport(mouse_pos: Vector2, viewport: SubViewport) -> Dictionary:
	"""
	Check if cursor is near viewport edge and warp to center if needed.
	
	Args:
		mouse_pos: Current mouse position in viewport coordinates
		viewport: The viewport to check bounds against
	
	Returns:
		Dictionary with keys:
			- warped (bool): Whether cursor was warped
			- new_position (Vector2): New mouse position (center if warped, original if not)
	"""
	if not viewport:
		return {"warped": false, "new_position": mouse_pos}
	
	var viewport_rect: Rect2 = viewport.get_visible_rect()
	var local_rect := Rect2(Vector2.ZERO, viewport_rect.size)
	
	if local_rect.size.x <= 1.0 or local_rect.size.y <= 1.0:
		return {"warped": false, "new_position": mouse_pos}
	
	# Define margin from edges where warping triggers
	var warp_margin := 50.0
	var max_margin: float = min(local_rect.size.x, local_rect.size.y) * 0.45
	if max_margin > 0.0:
		warp_margin = min(warp_margin, max_margin)
	
	# Create safe zone (area where cursor doesn't warp)
	var safe_rect := local_rect.grow(-warp_margin)
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		safe_rect = local_rect
	
	# Check if cursor is in safe zone
	if safe_rect.has_point(mouse_pos):
		return {"warped": false, "new_position": mouse_pos}
	
	# Cursor is near edge - warp to center
	var local_center := local_rect.size * 0.5
	var warp_target_global: Vector2 = viewport.get_screen_transform() * local_center
	
	warp_mouse(warp_target_global)
	
	return {"warped": true, "new_position": local_center}
