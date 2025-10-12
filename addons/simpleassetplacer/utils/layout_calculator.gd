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

## Thumbnail Size Constants

const THUMBNAIL_SIZE_MIN: int = 48       # Minimum viable thumbnail size
const THUMBNAIL_SIZE_SMALL: int = 64     # Compact view (4-5 columns in typical dock)
const THUMBNAIL_SIZE_MEDIUM: int = 80    # Balanced view (3-4 columns)
const THUMBNAIL_SIZE_LARGE: int = 96     # Comfortable view (2-3 columns)
const THUMBNAIL_SIZE_MAX: int = 112      # Maximum size for detail view

const THUMBNAIL_SIZE_DEFAULT: int = THUMBNAIL_SIZE_SMALL  # Default starting size

## Grid Layout Calculations

static func calculate_grid_columns(available_width: float, item_size: int, item_spacing: int = 12, safety_margin: int = 20) -> int:
	"""Calculate optimal number of grid columns for given available width
	
	Args:
		available_width: Total width available for the grid
		item_size: Width of each grid item (base thumbnail size, margins added internally)
		item_spacing: Spacing between items
		safety_margin: Extra margin to prevent edge overflow
	
	Returns:
		Number of columns that fit (minimum 1)
	
	Note: Automatically adds 16px for internal item margins to item_size
	"""
	if available_width <= 0 or item_size <= 0:
		return 1
	
	# Item width includes the base size + internal margins (padding, borders, etc.)
	var item_width = item_size + 16
	
	# Calculate how many items fit with spacing
	# Formula: (available_width - safety_margin) / (item_width + spacing)
	var usable_width = available_width - safety_margin
	var total_item_width = item_width + item_spacing
	
	var columns = int(usable_width / total_item_width)
	
	# Ensure at least 1 column
	return max(1, columns)

static func calculate_responsive_thumbnail_size(
	dock_width: float, 
	min_size: int = THUMBNAIL_SIZE_MIN, 
	max_size: int = THUMBNAIL_SIZE_MAX
) -> int:
	"""Calculate responsive thumbnail size based on dock width
	
	Optimized for multi-column layouts with reasonable thumbnail sizes.
	
	Args:
		dock_width: Width of the dock or container
		min_size: Minimum thumbnail size (default: 48px)
		max_size: Maximum thumbnail size (default: 112px)
	
	Returns:
		Optimal thumbnail size within bounds
	
	Width Breakpoints:
		< 250px  : 48px (minimum, 2-3 columns)
		250-350px: 64px (small, 3-4 columns)
		350-450px: 80px (medium, 3-4 columns)
		450-550px: 96px (large, 3-4 columns)
		> 550px  : 112px (max, 4-5 columns)
	"""
	if dock_width <= 0:
		return min_size
	
	# Calculate based on optimized width ranges for multi-column layouts
	var thumbnail_size = min_size
	
	if dock_width < 250:
		# Very narrow: minimum size for 2-3 columns
		thumbnail_size = THUMBNAIL_SIZE_MIN
	elif dock_width < 350:
		# Narrow: small size for 3-4 columns
		thumbnail_size = THUMBNAIL_SIZE_SMALL
	elif dock_width < 450:
		# Medium: balanced size for 3-4 columns
		thumbnail_size = THUMBNAIL_SIZE_MEDIUM
	elif dock_width < 550:
		# Medium-wide: comfortable size for 3-4 columns
		thumbnail_size = THUMBNAIL_SIZE_LARGE
	else:
		# Wide: maximum size for 4-5 columns
		thumbnail_size = THUMBNAIL_SIZE_MAX
	
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

static func clamp_thumbnail_size(size: int, min_size: int = THUMBNAIL_SIZE_MIN, max_size: int = THUMBNAIL_SIZE_MAX) -> int:
	"""Clamp thumbnail size to valid range
	
	Ensures thumbnail size stays within reasonable bounds for UI layout.
	
	Args:
		size: Desired thumbnail size
		min_size: Minimum allowed size (default: 48px)
		max_size: Maximum allowed size (default: 112px)
	
	Returns:
		Clamped thumbnail size
	"""
	return clampi(size, min_size, max_size)

static func get_nearest_standard_thumbnail_size(size: int) -> int:
	"""Get the nearest standard thumbnail size
	
	Snaps to standard sizes for consistent UI experience.
	
	Args:
		size: Desired thumbnail size
	
	Returns:
		Nearest standard thumbnail size (48, 64, 80, 96, or 112)
	"""
	var sizes = [THUMBNAIL_SIZE_MIN, THUMBNAIL_SIZE_SMALL, THUMBNAIL_SIZE_MEDIUM, THUMBNAIL_SIZE_LARGE, THUMBNAIL_SIZE_MAX]
	var nearest = sizes[0]
	var min_diff = abs(size - nearest)
	
	for standard_size in sizes:
		var diff = abs(size - standard_size)
		if diff < min_diff:
			min_diff = diff
			nearest = standard_size
	
	return nearest

static func truncate_text(text: String, max_length: int = 20, ellipsis: String = "...") -> String:
	"""Truncate text to maximum length with ellipsis
	
	Useful for preventing UI overflow from long category names or labels.
	
	Args:
		text: Text to truncate
		max_length: Maximum length before truncation (default: 20)
		ellipsis: String to append when truncated (default: "...")
	
	Returns:
		Truncated text with ellipsis if needed
	"""
	if text.length() <= max_length:
		return text
	
	# Keep room for ellipsis
	var truncate_at = max(1, max_length - ellipsis.length())
	return text.substr(0, truncate_at) + ellipsis
