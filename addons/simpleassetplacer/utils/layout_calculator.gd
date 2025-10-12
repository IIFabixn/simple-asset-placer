@tool
extends RefCounted

class_name LayoutCalculator

"""
LAYOUT CALCULATION UTILITIES
============================

PURPOSE: Provides reusable layout calculation functions for UI components.

RESPONSIBILITIES:
- Grid column calculation based on available width
- Responsive layout sizing
- Item spacing calculations

ARCHITECTURE POSITION: Pure calculation utility with no state
- Does NOT handle UI creation or management
- Does NOT depend on specific UI components
- Provides static calculation methods only

USED BY: AssetPlacerDock, ModelLibraryBrowser, MeshLibraryBrowser
"""

## Grid Layout Calculations

static func calculate_grid_columns(available_width: float, item_size: int, item_spacing: int = 12, safety_margin: int = 20) -> int:
	"""Calculate optimal number of grid columns for given available width
	
	Args:
		available_width: Total width available for the grid
		item_size: Width of each grid item (thumbnail size)
		item_spacing: Spacing between items
		safety_margin: Extra margin to prevent edge overflow
	
	Returns:
		Number of columns that fit (minimum 1)
	"""
	if available_width <= 0 or item_size <= 0:
		return 1
	
	var columns = 1
	var item_width = item_size + 16  # Item size + internal margins
	var total_width_needed = item_width
	
	# Keep adding columns while they fit (with safety margin)
	while total_width_needed + item_spacing + item_width <= available_width - safety_margin:
		columns += 1
		total_width_needed += item_spacing + item_width
	
	return max(1, columns)

static func calculate_responsive_thumbnail_size(dock_width: float, min_size: int = 64, max_size: int = 128) -> int:
	"""Calculate responsive thumbnail size based on dock width
	
	Args:
		dock_width: Width of the dock or container
		min_size: Minimum thumbnail size
		max_size: Maximum thumbnail size
	
	Returns:
		Optimal thumbnail size within bounds
	"""
	if dock_width <= 0:
		return min_size
	
	# Calculate based on width ranges
	var thumbnail_size = min_size
	
	if dock_width < 300:
		# Very narrow: use minimum size
		thumbnail_size = min_size
	elif dock_width < 400:
		# Narrow: use 80px
		thumbnail_size = 80
	elif dock_width < 500:
		# Medium: use 96px
		thumbnail_size = 96
	elif dock_width < 600:
		# Medium-wide: use 112px
		thumbnail_size = 112
	else:
		# Wide: use maximum size
		thumbnail_size = max_size
	
	return clampi(thumbnail_size, min_size, max_size)

## Item Layout Calculations

static func calculate_item_position(index: int, columns: int, item_width: int, item_height: int, spacing: int = 12) -> Vector2:
	"""Calculate position for an item in a grid layout
	
	Args:
		index: Item index (0-based)
		columns: Number of columns in grid
		item_width: Width of each item
		item_height: Height of each item
		spacing: Spacing between items
	
	Returns:
		Vector2 position for the item
	"""
	if columns <= 0:
		columns = 1
	
	var row = index / columns
	var col = index % columns
	
	var x = col * (item_width + spacing)
	var y = row * (item_height + spacing)
	
	return Vector2(x, y)

static func calculate_grid_size(item_count: int, columns: int, item_width: int, item_height: int, spacing: int = 12) -> Vector2:
	"""Calculate total size needed for a grid layout
	
	Args:
		item_count: Total number of items
		columns: Number of columns
		item_width: Width of each item
		item_height: Height of each item
		spacing: Spacing between items
	
	Returns:
		Vector2 with total width and height needed
	"""
	if item_count <= 0 or columns <= 0:
		return Vector2.ZERO
	
	var rows = ceili(float(item_count) / float(columns))
	
	var total_width = columns * item_width + (columns - 1) * spacing
	var total_height = rows * item_height + (rows - 1) * spacing
	
	return Vector2(total_width, total_height)

## Helper Functions

static func calculate_items_per_row(container_width: float, item_size: int, min_items: int = 1, max_items: int = 10) -> int:
	"""Calculate how many items fit per row
	
	Args:
		container_width: Width of the container
		item_size: Size of each item
		min_items: Minimum items per row
		max_items: Maximum items per row
	
	Returns:
		Number of items that fit per row
	"""
	if container_width <= 0 or item_size <= 0:
		return min_items
	
	var items = int(container_width / item_size)
	return clampi(items, min_items, max_items)

static func calculate_centered_offset(container_size: float, content_size: float) -> float:
	"""Calculate offset to center content within container
	
	Args:
		container_size: Size of the container
		content_size: Size of the content
	
	Returns:
		Offset value to center the content
	"""
	if content_size >= container_size:
		return 0.0
	
	return (container_size - content_size) / 2.0
