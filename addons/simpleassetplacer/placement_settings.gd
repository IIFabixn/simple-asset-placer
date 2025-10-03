@tool
extends Control

class_name PlacementSettings

const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")

signal settings_changed()
signal cache_cleared()

# UI Controls
var snap_to_ground_check: CheckBox
var align_with_normal_check: CheckBox
var snap_enabled_check: CheckBox
var snap_step_spin: SpinBox
var show_grid_check: CheckBox
var random_rotation_check: CheckBox
var scale_spin: SpinBox
var collision_check: CheckBox
var grouping_check: CheckBox

# Reset behavior controls
var reset_height_on_exit_check: CheckBox
var reset_scale_on_exit_check: CheckBox
var reset_rotation_on_exit_check: CheckBox

# Rotation Controls
var rotate_y_key_button: Button
var rotate_x_key_button: Button
var rotate_z_key_button: Button
var reset_rotation_key_button: Button
var listening_button: Button = null  # Track which button is listening for input
var rotation_increment_spin: SpinBox
var fine_rotation_increment_spin: SpinBox
var large_rotation_increment_spin: SpinBox

# Scale Controls
var scale_up_key_button: Button
var scale_down_key_button: Button
var scale_reset_key_button: Button
var scale_increment_spin: SpinBox
var fine_scale_increment_spin: SpinBox
var large_scale_increment_spin: SpinBox

# Height Adjustment Controls
var height_up_key_button: Button
var height_down_key_button: Button
var reset_height_key_button: Button
var height_step_spin: SpinBox
var fine_height_increment_spin: SpinBox
var large_height_increment_spin: SpinBox

# Position Adjustment Controls
var position_left_key_button: Button
var position_right_key_button: Button
var position_forward_key_button: Button
var position_backward_key_button: Button
var reset_position_key_button: Button
var position_increment_spin: SpinBox
var fine_position_increment_spin: SpinBox
var large_position_increment_spin: SpinBox

# Modifier Key Controls
var reverse_modifier_key_button: Button
var large_increment_modifier_key_button: Button

# Control Key Controls
var cancel_key_button: Button
var transform_mode_key_button: Button

# Settings
var snap_to_ground: bool = false
var align_with_normal: bool = false  # Align object rotation with surface normal
var snap_enabled: bool = false  # User can enable when desired
var snap_step: float = 1.0
var snap_by_aabb: bool = true  # Snap by bounding box edges instead of pivot
var snap_offset: Vector3 = Vector3.ZERO  # Grid offset from world origin
var snap_y_enabled: bool = false  # Enable Y-axis (height) snapping
var snap_y_step: float = 1.0  # Grid size for Y-axis snapping
var snap_center_x: bool = false  # Snap to center of bounding box on X-axis
var snap_center_y: bool = false  # Snap to center of bounding box on Y-axis
var snap_center_z: bool = false  # Snap to center of bounding box on Z-axis
var show_grid: bool = false  # Show visual grid overlay
var grid_extent: float = 20.0  # Size of grid overlay in world units (radius from center)
var random_rotation: bool = false
var scale_multiplier: float = 1.0
var add_collision: bool = false
var group_instances: bool = false

# Reset behavior settings
var reset_height_on_exit: bool = false  # Whether to reset height offset when exiting modes
var reset_scale_on_exit: bool = false   # Whether to reset scale when exiting modes
var reset_rotation_on_exit: bool = false  # Whether to reset rotation when exiting modes

# Rotation Settings
var rotate_y_key: String = "Y"  # Y-axis rotation (yaw) - Y axis
var rotate_x_key: String = "X"  # X-axis rotation (pitch) - X axis
var rotate_z_key: String = "Z"  # Z-axis rotation (roll) - Z axis  
var reset_rotation_key: String = "T"  # T for reset (sTarT over)
var rotation_increment: float = 15.0
var fine_rotation_increment: float = 5.0
var large_rotation_increment: float = 90.0

# Scale Settings
var scale_up_key: String = "PAGE_UP"
var scale_down_key: String = "PAGE_DOWN"
var scale_reset_key: String = "HOME"
var scale_increment: float = 0.1
var fine_scale_increment: float = 0.01
var large_scale_increment: float = 0.5

# Height Adjustment Settings
var height_up_key: String = "Q"      # Raise preview height
var height_down_key: String = "E"    # Lower preview height
var reset_height_key: String = "R"   # Reset height offset to zero
var height_adjustment_step: float = 0.1
var fine_height_increment: float = 0.01
var large_height_increment: float = 1.0

# Position Adjustment Settings (manual XZ movement)
var position_left_key: String = "A"       # Move left (-X)
var position_right_key: String = "D"      # Move right (+X)
var position_forward_key: String = "W"    # Move forward (-Z)
var position_backward_key: String = "S"   # Move backward (+Z)
var reset_position_key: String = "G"      # Reset position offset to zero
var position_increment: float = 0.1       # Default position step
var fine_position_increment: float = 0.01 # Fine position step (with CTRL)
var large_position_increment: float = 1.0 # Large position step (with ALT)

# Modifier Key Settings
var reverse_modifier_key: String = "SHIFT"    # Reverse rotation direction
var large_increment_modifier_key: String = "ALT"  # Large increments

# Control Settings
var cancel_key: String = "ESCAPE"    # Cancel placement mode
var transform_mode_key: String = "TAB"  # Activate transform mode on selected object

func _ready():
	setup_ui()
	load_settings()
	# Connect to settings_changed signal to auto-save
	settings_changed.connect(save_settings)

func setup_ui():
	# Set up main container to fill available space
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Create scroll container for settings
	var scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll_container)
	
	# Main content container with margins
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	scroll_container.add_child(margin_container)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin_container.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Placement Settings"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(title)
	
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	vbox.add_child(separator)
	
	# Snap to ground option
	snap_to_ground_check = CheckBox.new()
	snap_to_ground_check.text = "Snap to Ground"
	snap_to_ground_check.tooltip_text = "Place objects on the ground/surface below"
	snap_to_ground_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_to_ground_check)
	
	# Align with surface normal option
	align_with_normal_check = CheckBox.new()
	align_with_normal_check.text = "Align with Surface Normal"
	align_with_normal_check.tooltip_text = "Rotate objects to match the angle of the surface they're placed on"
	align_with_normal_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(align_with_normal_check)
	
	# Grid snapping option
	snap_enabled_check = CheckBox.new()
	snap_enabled_check.text = "Enable Grid Snapping"
	snap_enabled_check.button_pressed = false  # Default to disabled
	snap_enabled_check.tooltip_text = "Snap objects to a grid when placing"
	snap_enabled_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_enabled_check)
	
	# Show grid option
	show_grid_check = CheckBox.new()
	show_grid_check.text = "Show Grid Overlay"
	show_grid_check.button_pressed = false  # Default to disabled
	show_grid_check.tooltip_text = "Display a visual grid overlay in the 3D viewport"
	show_grid_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(show_grid_check)
	
	# Create a grid for all labeled input controls
	var settings_grid = GridContainer.new()
	settings_grid.columns = 2
	settings_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_theme_constant_override("h_separation", 8)
	settings_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(settings_grid)
	
	# Grid Size
	var snap_label = Label.new()
	snap_label.text = "Grid Size:"
	snap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(snap_label)
	
	snap_step_spin = SpinBox.new()
	snap_step_spin.min_value = 0.1
	snap_step_spin.max_value = 1000.0
	snap_step_spin.step = 0.1
	snap_step_spin.value = 1.0
	snap_step_spin.custom_minimum_size.x = 80
	snap_step_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_step_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	snap_step_spin.tooltip_text = "Grid spacing for snapping"
	settings_grid.add_child(snap_step_spin)
	
	# Grid Extent (visual size)
	var grid_extent_label = Label.new()
	grid_extent_label.text = "Grid Display Size:"
	grid_extent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(grid_extent_label)
	
	var grid_extent_spin = SpinBox.new()
	grid_extent_spin.name = "GridExtentSpin"
	grid_extent_spin.min_value = 5.0
	grid_extent_spin.max_value = 100.0
	grid_extent_spin.step = 5.0
	grid_extent_spin.value = 20.0
	grid_extent_spin.custom_minimum_size.x = 80
	grid_extent_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_extent_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid_extent_spin.tooltip_text = "Size of the grid overlay in world units (radius from center)"
	settings_grid.add_child(grid_extent_spin)
	
	# Snap by AABB checkbox (spans both columns)
	var snap_aabb_check = CheckBox.new()
	snap_aabb_check.name = "SnapAABBCheck"
	snap_aabb_check.text = "Snap by Bounding Box Edges"
	snap_aabb_check.button_pressed = true  # Default enabled
	snap_aabb_check.tooltip_text = "Snap assets by their edges instead of pivot point (aligns edges to grid)"
	snap_aabb_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_aabb_check)
	
	# Center snapping options
	var snap_center_label = Label.new()
	snap_center_label.text = "Snap to Center On:"
	snap_center_label.add_theme_font_size_override("font_size", 12)
	snap_center_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
	vbox.add_child(snap_center_label)
	
	var snap_center_x_check = CheckBox.new()
	snap_center_x_check.name = "SnapCenterXCheck"
	snap_center_x_check.text = "X-axis (Center on X)"
	snap_center_x_check.button_pressed = false
	snap_center_x_check.tooltip_text = "Snap to center of bounding box on X-axis instead of edges"
	snap_center_x_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_center_x_check)
	
	var snap_center_y_check = CheckBox.new()
	snap_center_y_check.name = "SnapCenterYCheck"
	snap_center_y_check.text = "Y-axis (Center on Y)"
	snap_center_y_check.button_pressed = false
	snap_center_y_check.tooltip_text = "Snap to center of bounding box on Y-axis instead of edges"
	snap_center_y_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_center_y_check)
	
	var snap_center_z_check = CheckBox.new()
	snap_center_z_check.name = "SnapCenterZCheck"
	snap_center_z_check.text = "Z-axis (Center on Z)"
	snap_center_z_check.button_pressed = false
	snap_center_z_check.tooltip_text = "Snap to center of bounding box on Z-axis instead of edges"
	snap_center_z_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_center_z_check)
	
	# Y-axis snapping checkbox (spans both columns)
	var snap_y_check = CheckBox.new()
	snap_y_check.name = "SnapYCheck"
	snap_y_check.text = "Enable Vertical (Y) Snapping"
	snap_y_check.button_pressed = false
	snap_y_check.tooltip_text = "Snap height to grid (useful for stacking objects)"
	snap_y_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(snap_y_check)
	
	# Y-axis snap step
	var snap_y_label = Label.new()
	snap_y_label.text = "Vertical Grid Size:"
	snap_y_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(snap_y_label)
	
	var snap_y_step_spin = SpinBox.new()
	snap_y_step_spin.name = "SnapYStepSpin"
	snap_y_step_spin.min_value = 0.1
	snap_y_step_spin.max_value = 1000.0
	snap_y_step_spin.step = 0.1
	snap_y_step_spin.value = 1.0
	snap_y_step_spin.custom_minimum_size.x = 80
	snap_y_step_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_y_step_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	snap_y_step_spin.tooltip_text = "Grid spacing for Y-axis snapping"
	settings_grid.add_child(snap_y_step_spin)
	
	# Grid offset X
	var offset_x_label = Label.new()
	offset_x_label.text = "Grid Offset X:"
	offset_x_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(offset_x_label)
	
	var offset_x_spin = SpinBox.new()
	offset_x_spin.name = "GridOffsetXSpin"
	offset_x_spin.min_value = -1000.0
	offset_x_spin.max_value = 1000.0
	offset_x_spin.step = 0.1
	offset_x_spin.value = 0.0
	offset_x_spin.custom_minimum_size.x = 80
	offset_x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offset_x_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	offset_x_spin.tooltip_text = "Offset the grid from world origin on X-axis"
	settings_grid.add_child(offset_x_spin)
	
	# Grid offset Z
	var offset_z_label = Label.new()
	offset_z_label.text = "Grid Offset Z:"
	offset_z_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(offset_z_label)
	
	var offset_z_spin = SpinBox.new()
	offset_z_spin.name = "GridOffsetZSpin"
	offset_z_spin.min_value = -1000.0
	offset_z_spin.max_value = 1000.0
	offset_z_spin.step = 0.1
	offset_z_spin.value = 0.0
	offset_z_spin.custom_minimum_size.x = 80
	offset_z_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offset_z_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	offset_z_spin.tooltip_text = "Offset the grid from world origin on Z-axis"
	settings_grid.add_child(offset_z_spin)
	
	# Random rotation option (spans both columns)
	random_rotation_check = CheckBox.new()
	random_rotation_check.text = "Random Y Rotation"
	random_rotation_check.tooltip_text = "Apply random rotation on Y axis"
	random_rotation_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(random_rotation_check)
	
	# Scale multiplier
	var scale_label = Label.new()
	scale_label.text = "Skalierung:"
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_grid.add_child(scale_label)
	
	scale_spin = SpinBox.new()
	scale_spin.min_value = 0.01
	scale_spin.max_value = 1000.0
	scale_spin.step = 0.1
	scale_spin.value = 1.0
	scale_spin.custom_minimum_size.x = 80
	scale_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	settings_grid.add_child(scale_spin)
	
	# Add collision shapes
	collision_check = CheckBox.new()
	collision_check.text = "Auto Collision"
	collision_check.tooltip_text = "Automatically add collision shapes"
	collision_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(collision_check)
	
	# Group instances
	grouping_check = CheckBox.new()
	grouping_check.text = "Group Instances"
	grouping_check.tooltip_text = "Group multiple instances of same asset"
	grouping_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grouping_check)
	
	# Add separator for reset behavior settings
	var reset_separator = HSeparator.new()
	reset_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(reset_separator)
	
	# Reset Behavior Settings section
	var reset_behavior_label = Label.new()
	reset_behavior_label.text = "Reset on Mode Exit"
	reset_behavior_label.add_theme_font_size_override("font_size", 14)
	reset_behavior_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(reset_behavior_label)
	
	# Reset height on exit
	reset_height_on_exit_check = CheckBox.new()
	reset_height_on_exit_check.text = "Reset Height Offset"
	reset_height_on_exit_check.tooltip_text = "Reset height offset to 0 when exiting placement/transform mode"
	reset_height_on_exit_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(reset_height_on_exit_check)
	
	# Reset scale on exit
	reset_scale_on_exit_check = CheckBox.new()
	reset_scale_on_exit_check.text = "Reset Scale"
	reset_scale_on_exit_check.tooltip_text = "Reset scale to 1.0 when exiting placement/transform mode"
	reset_scale_on_exit_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(reset_scale_on_exit_check)
	
	# Reset rotation on exit
	reset_rotation_on_exit_check = CheckBox.new()
	reset_rotation_on_exit_check.text = "Reset Rotation"
	reset_rotation_on_exit_check.tooltip_text = "Reset rotation to 0° when exiting placement/transform mode"
	reset_rotation_on_exit_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(reset_rotation_on_exit_check)
	
	# Add separator for rotation settings
	var rotation_separator = HSeparator.new()
	rotation_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(rotation_separator)
	
	# Rotation Settings section
	var rotation_label = Label.new()
	rotation_label.text = "Rotation Controls"
	rotation_label.add_theme_font_size_override("font_size", 14)
	rotation_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(rotation_label)
	
	# Key bindings for rotation
	var key_grid = GridContainer.new()
	key_grid.columns = 2
	key_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_theme_constant_override("h_separation", 8)
	key_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(key_grid)
	
	# Y-axis rotation key
	var rotate_y_label = Label.new()
	rotate_y_label.text = "Rotate Y-axis:"
	rotate_y_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(rotate_y_label)
	
	rotate_y_key_button = Button.new()
	rotate_y_key_button.text = rotate_y_key
	rotate_y_key_button.custom_minimum_size.x = 80
	rotate_y_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_y_key_button.tooltip_text = "Click to set key for Y-axis rotation (yaw). Press ESC to cancel."
	key_grid.add_child(rotate_y_key_button)
	
	# X-axis rotation key
	var rotate_x_label = Label.new()
	rotate_x_label.text = "Rotate X-axis:"
	rotate_x_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(rotate_x_label)
	
	rotate_x_key_button = Button.new()
	rotate_x_key_button.text = rotate_x_key
	rotate_x_key_button.custom_minimum_size.x = 80
	rotate_x_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_x_key_button.tooltip_text = "Click to set key for X-axis rotation (pitch). Press ESC to cancel."
	key_grid.add_child(rotate_x_key_button)
	
	# Z-axis rotation key
	var rotate_z_label = Label.new()
	rotate_z_label.text = "Rotate Z-axis:"
	rotate_z_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(rotate_z_label)
	
	rotate_z_key_button = Button.new()
	rotate_z_key_button.text = rotate_z_key
	rotate_z_key_button.custom_minimum_size.x = 80
	rotate_z_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_z_key_button.tooltip_text = "Click to set key for Z-axis rotation (roll). Press ESC to cancel."
	key_grid.add_child(rotate_z_key_button)
	
	# Reset rotation key
	var reset_rotation_label = Label.new()
	reset_rotation_label.text = "Reset Rotation:"
	reset_rotation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(reset_rotation_label)
	
	reset_rotation_key_button = Button.new()
	reset_rotation_key_button.text = reset_rotation_key
	reset_rotation_key_button.custom_minimum_size.x = 80
	reset_rotation_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_rotation_key_button.tooltip_text = "Click to set key for resetting rotations to 0°. Press ESC to cancel."
	key_grid.add_child(reset_rotation_key_button)
	
	# Add rotation increment settings to the same grid
	# Base Increment
	var increment_label = Label.new()
	increment_label.text = "Base Increment:"
	increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(increment_label)
	
	rotation_increment_spin = SpinBox.new()
	rotation_increment_spin.min_value = 1.0
	rotation_increment_spin.max_value = 180.0
	rotation_increment_spin.step = 1.0
	rotation_increment_spin.value = rotation_increment
	rotation_increment_spin.suffix = "°"
	rotation_increment_spin.custom_minimum_size.x = 80
	rotation_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rotation_increment_spin.tooltip_text = "Default rotation increment"
	key_grid.add_child(rotation_increment_spin)
	
	# Fine Increment
	var fine_increment_label = Label.new()
	fine_increment_label.text = "Fine Increment:"
	fine_increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(fine_increment_label)
	
	fine_rotation_increment_spin = SpinBox.new()
	fine_rotation_increment_spin.min_value = 0.1
	fine_rotation_increment_spin.max_value = 45.0
	fine_rotation_increment_spin.step = 0.1
	fine_rotation_increment_spin.value = fine_rotation_increment
	fine_rotation_increment_spin.suffix = "°"
	fine_rotation_increment_spin.custom_minimum_size.x = 80
	fine_rotation_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine_rotation_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fine_rotation_increment_spin.tooltip_text = "Fine rotation increment (currently unused)"
	key_grid.add_child(fine_rotation_increment_spin)
	
	# Large Increment
	var large_increment_label = Label.new()
	large_increment_label.text = "Large Increment:"
	large_increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_grid.add_child(large_increment_label)
	
	large_rotation_increment_spin = SpinBox.new()
	large_rotation_increment_spin.min_value = 45.0
	large_rotation_increment_spin.max_value = 180.0
	large_rotation_increment_spin.step = 15.0
	large_rotation_increment_spin.value = large_rotation_increment
	large_rotation_increment_spin.suffix = "°"
	large_rotation_increment_spin.custom_minimum_size.x = 80
	large_rotation_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	large_rotation_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	large_rotation_increment_spin.tooltip_text = "Ctrl+Key rotation increment"
	key_grid.add_child(large_rotation_increment_spin)
	
	# Add separator and scaling section
	# Add separator for scaling settings
	var scale_separator = HSeparator.new()
	scale_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(scale_separator)
	
	# Scale Settings section
	var scale_controls_label = Label.new()
	scale_controls_label.text = "Scale Controls"
	scale_controls_label.add_theme_font_size_override("font_size", 14)
	scale_controls_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(scale_controls_label)
	
	# Create grid for scale controls
	var scale_grid = GridContainer.new()
	scale_grid.columns = 2
	scale_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_theme_constant_override("h_separation", 8)
	scale_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(scale_grid)
	
	# Scale Up Key
	var scale_up_label = Label.new()
	scale_up_label.text = "Scale Up:"
	scale_up_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(scale_up_label)
	
	scale_up_key_button = Button.new()
	scale_up_key_button.text = scale_up_key
	scale_up_key_button.custom_minimum_size.x = 80
	scale_up_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_up_key_button.tooltip_text = "Click to set key for scaling up. Press ESC to cancel."
	scale_grid.add_child(scale_up_key_button)
	
	# Scale Down Key
	var scale_down_label = Label.new()
	scale_down_label.text = "Scale Down:"
	scale_down_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(scale_down_label)
	
	scale_down_key_button = Button.new()
	scale_down_key_button.text = scale_down_key
	scale_down_key_button.custom_minimum_size.x = 80
	scale_down_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_down_key_button.tooltip_text = "Click to set key for scaling down. Press ESC to cancel."
	scale_grid.add_child(scale_down_key_button)
	
	# Scale Reset Key
	var scale_reset_label = Label.new()
	scale_reset_label.text = "Reset Scale:"
	scale_reset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(scale_reset_label)
	
	scale_reset_key_button = Button.new()
	scale_reset_key_button.text = scale_reset_key
	scale_reset_key_button.custom_minimum_size.x = 80
	scale_reset_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_reset_key_button.tooltip_text = "Click to set key for resetting scale to 1.0x. Press ESC to cancel."
	scale_grid.add_child(scale_reset_key_button)
	
	# Scale Increment
	var scale_increment_label = Label.new()
	scale_increment_label.text = "Scale Increment:"
	scale_increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(scale_increment_label)
	
	scale_increment_spin = SpinBox.new()
	scale_increment_spin.min_value = 0.01
	scale_increment_spin.max_value = 2.0
	scale_increment_spin.step = 0.01
	scale_increment_spin.value = scale_increment
	scale_increment_spin.custom_minimum_size.x = 80
	scale_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_increment_spin.tooltip_text = "Default scale increment (keyboard keys)"
	scale_grid.add_child(scale_increment_spin)
	
	# Fine Scale Increment
	var fine_scale_increment_label = Label.new()
	fine_scale_increment_label.text = "Fine Increment:"
	fine_scale_increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(fine_scale_increment_label)
	
	fine_scale_increment_spin = SpinBox.new()
	fine_scale_increment_spin.min_value = 0.001
	fine_scale_increment_spin.max_value = 0.1
	fine_scale_increment_spin.step = 0.001
	fine_scale_increment_spin.value = fine_scale_increment
	fine_scale_increment_spin.custom_minimum_size.x = 80
	fine_scale_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine_scale_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fine_scale_increment_spin.tooltip_text = "Fine scale increment for mouse wheel"
	scale_grid.add_child(fine_scale_increment_spin)
	
	# Large Scale Increment
	var large_scale_increment_label = Label.new()
	large_scale_increment_label.text = "Large Increment:"
	large_scale_increment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_grid.add_child(large_scale_increment_label)
	
	large_scale_increment_spin = SpinBox.new()
	large_scale_increment_spin.min_value = 0.1
	large_scale_increment_spin.max_value = 5.0
	large_scale_increment_spin.step = 0.1
	large_scale_increment_spin.value = large_scale_increment
	large_scale_increment_spin.custom_minimum_size.x = 80
	large_scale_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	large_scale_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	large_scale_increment_spin.tooltip_text = "Large scale increment (with ALT modifier)"
	scale_grid.add_child(large_scale_increment_spin)
	
	# Add separator for height adjustment settings
	var height_separator = HSeparator.new()
	height_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(height_separator)
	
	# Height Adjustment section
	var height_label = Label.new()
	height_label.text = "Height Adjustment"
	height_label.add_theme_font_size_override("font_size", 14)
	height_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(height_label)
	
	# Height key grid
	var height_grid = GridContainer.new()
	height_grid.columns = 2
	height_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_theme_constant_override("h_separation", 8)
	height_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(height_grid)
	
	# Height Up Key
	var height_up_label = Label.new()
	height_up_label.text = "Raise Height:"
	height_up_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(height_up_label)
	
	height_up_key_button = Button.new()
	height_up_key_button.text = height_up_key
	height_up_key_button.custom_minimum_size.x = 80
	height_up_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_up_key_button.tooltip_text = "Click to set key for raising preview height. Press ESC to cancel."
	height_grid.add_child(height_up_key_button)
	
	# Height Down Key
	var height_down_label = Label.new()
	height_down_label.text = "Lower Height:"
	height_down_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(height_down_label)
	
	height_down_key_button = Button.new()
	height_down_key_button.text = height_down_key
	height_down_key_button.custom_minimum_size.x = 80
	height_down_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_down_key_button.tooltip_text = "Click to set key for lowering preview height. Press ESC to cancel."
	height_grid.add_child(height_down_key_button)
	
	# Reset Height Key
	var reset_height_label = Label.new()
	reset_height_label.text = "Reset Height:"
	reset_height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(reset_height_label)
	
	reset_height_key_button = Button.new()
	reset_height_key_button.text = reset_height_key
	reset_height_key_button.custom_minimum_size.x = 80
	reset_height_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_height_key_button.tooltip_text = "Click to set key for resetting height to base level. Press ESC to cancel."
	height_grid.add_child(reset_height_key_button)
	
	# Height Step
	var height_step_label = Label.new()
	height_step_label.text = "Height Step:"
	height_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(height_step_label)
	
	height_step_spin = SpinBox.new()
	height_step_spin.min_value = 0.01
	height_step_spin.max_value = 5.0
	height_step_spin.step = 0.01
	height_step_spin.value = height_adjustment_step
	height_step_spin.custom_minimum_size.x = 80
	height_step_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_step_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	height_step_spin.tooltip_text = "Step size for height adjustment (keyboard keys)"
	height_grid.add_child(height_step_spin)
	
	# Fine Height Increment
	var fine_height_label = Label.new()
	fine_height_label.text = "Fine Height Step:"
	fine_height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(fine_height_label)
	
	fine_height_increment_spin = SpinBox.new()
	fine_height_increment_spin.min_value = 0.001
	fine_height_increment_spin.max_value = 0.5
	fine_height_increment_spin.step = 0.001
	fine_height_increment_spin.value = fine_height_increment
	fine_height_increment_spin.custom_minimum_size.x = 80
	fine_height_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine_height_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fine_height_increment_spin.tooltip_text = "Fine height increment for mouse wheel"
	height_grid.add_child(fine_height_increment_spin)
	
	# Large Height Increment
	var large_height_label = Label.new()
	large_height_label.text = "Large Height Step:"
	large_height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_grid.add_child(large_height_label)
	
	large_height_increment_spin = SpinBox.new()
	large_height_increment_spin.min_value = 0.5
	large_height_increment_spin.max_value = 10.0
	large_height_increment_spin.step = 0.1
	large_height_increment_spin.value = large_height_increment
	large_height_increment_spin.custom_minimum_size.x = 80
	large_height_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	large_height_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	large_height_increment_spin.tooltip_text = "Large height increment (with ALT modifier)"
	height_grid.add_child(large_height_increment_spin)
	
	# Add separator for position adjustment
	var position_separator = HSeparator.new()
	position_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(position_separator)
	
	# Position Adjustment section
	var position_label = Label.new()
	position_label.text = "Position Adjustment (XZ Manual Movement)"
	position_label.add_theme_font_size_override("font_size", 14)
	position_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(position_label)
	
	# Grid for position controls
	var position_grid = GridContainer.new()
	position_grid.columns = 2
	position_grid.add_theme_constant_override("h_separation", 8)
	position_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(position_grid)
	
	# Move Left key
	var position_left_label = Label.new()
	position_left_label.text = "Move Left (-X):"
	position_left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(position_left_label)
	
	position_left_key_button = Button.new()
	position_left_key_button.text = position_left_key
	position_left_key_button.custom_minimum_size.x = 80
	position_left_key_button.pressed.connect(_on_key_binding_button_pressed.bind(position_left_key_button, "position_left_key"))
	position_grid.add_child(position_left_key_button)
	
	# Move Right key
	var position_right_label = Label.new()
	position_right_label.text = "Move Right (+X):"
	position_right_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(position_right_label)
	
	position_right_key_button = Button.new()
	position_right_key_button.text = position_right_key
	position_right_key_button.custom_minimum_size.x = 80
	position_right_key_button.pressed.connect(_on_key_binding_button_pressed.bind(position_right_key_button, "position_right_key"))
	position_grid.add_child(position_right_key_button)
	
	# Move Forward key
	var position_forward_label = Label.new()
	position_forward_label.text = "Move Forward (-Z):"
	position_forward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(position_forward_label)
	
	position_forward_key_button = Button.new()
	position_forward_key_button.text = position_forward_key
	position_forward_key_button.custom_minimum_size.x = 80
	position_forward_key_button.pressed.connect(_on_key_binding_button_pressed.bind(position_forward_key_button, "position_forward_key"))
	position_grid.add_child(position_forward_key_button)
	
	# Move Backward key
	var position_backward_label = Label.new()
	position_backward_label.text = "Move Backward (+Z):"
	position_backward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(position_backward_label)
	
	position_backward_key_button = Button.new()
	position_backward_key_button.text = position_backward_key
	position_backward_key_button.custom_minimum_size.x = 80
	position_backward_key_button.pressed.connect(_on_key_binding_button_pressed.bind(position_backward_key_button, "position_backward_key"))
	position_grid.add_child(position_backward_key_button)
	
	# Reset Position key
	var reset_position_label = Label.new()
	reset_position_label.text = "Reset Position Offset:"
	reset_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(reset_position_label)
	
	reset_position_key_button = Button.new()
	reset_position_key_button.text = reset_position_key
	reset_position_key_button.custom_minimum_size.x = 80
	reset_position_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_position_key_button.tooltip_text = "Click to set key for resetting position offset to zero. Press ESC to cancel."
	reset_position_key_button.pressed.connect(_on_key_binding_button_pressed.bind(reset_position_key_button, "reset_position_key"))
	position_grid.add_child(reset_position_key_button)
	
	# Position Step
	var position_step_label = Label.new()
	position_step_label.text = "Position Step:"
	position_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(position_step_label)
	
	position_increment_spin = SpinBox.new()
	position_increment_spin.min_value = 0.01
	position_increment_spin.max_value = 10.0
	position_increment_spin.step = 0.01
	position_increment_spin.value = position_increment
	position_increment_spin.custom_minimum_size.x = 80
	position_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	position_increment_spin.tooltip_text = "Normal position increment"
	position_grid.add_child(position_increment_spin)
	
	# Fine Position Step
	var fine_position_label = Label.new()
	fine_position_label.text = "Fine Position Step:"
	fine_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(fine_position_label)
	
	fine_position_increment_spin = SpinBox.new()
	fine_position_increment_spin.min_value = 0.001
	fine_position_increment_spin.max_value = 1.0
	fine_position_increment_spin.step = 0.001
	fine_position_increment_spin.value = fine_position_increment
	fine_position_increment_spin.custom_minimum_size.x = 80
	fine_position_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine_position_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fine_position_increment_spin.tooltip_text = "Fine position increment (with CTRL modifier)"
	position_grid.add_child(fine_position_increment_spin)
	
	# Large Position Step
	var large_position_label = Label.new()
	large_position_label.text = "Large Position Step:"
	large_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_grid.add_child(large_position_label)
	
	large_position_increment_spin = SpinBox.new()
	large_position_increment_spin.min_value = 0.5
	large_position_increment_spin.max_value = 10.0
	large_position_increment_spin.step = 0.1
	large_position_increment_spin.value = large_position_increment
	large_position_increment_spin.custom_minimum_size.x = 80
	large_position_increment_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	large_position_increment_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	large_position_increment_spin.tooltip_text = "Large position increment (with ALT modifier)"
	position_grid.add_child(large_position_increment_spin)
	
	# Add separator for modifier keys
	var modifier_separator = HSeparator.new()
	modifier_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(modifier_separator)
	
	# Modifier Keys section
	var modifier_label = Label.new()
	modifier_label.text = "Modifier Keys"
	modifier_label.add_theme_font_size_override("font_size", 14)
	modifier_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(modifier_label)
	
	# Modifier key grid
	var modifier_grid = GridContainer.new()
	modifier_grid.columns = 2
	modifier_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modifier_grid.add_theme_constant_override("h_separation", 8)
	modifier_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(modifier_grid)
	
	# Reverse Modifier Key
	var reverse_modifier_label = Label.new()
	reverse_modifier_label.text = "Reverse Direction:"
	reverse_modifier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modifier_grid.add_child(reverse_modifier_label)
	
	reverse_modifier_key_button = Button.new()
	reverse_modifier_key_button.text = reverse_modifier_key
	reverse_modifier_key_button.custom_minimum_size.x = 80
	reverse_modifier_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reverse_modifier_key_button.tooltip_text = "Click to set modifier key for reverse rotation direction. Press ESC to cancel."
	modifier_grid.add_child(reverse_modifier_key_button)
	
	# Large Increment Modifier Key
	var large_increment_modifier_label = Label.new()
	large_increment_modifier_label.text = "Large Increment:"
	large_increment_modifier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modifier_grid.add_child(large_increment_modifier_label)
	
	large_increment_modifier_key_button = Button.new()
	large_increment_modifier_key_button.text = large_increment_modifier_key
	large_increment_modifier_key_button.custom_minimum_size.x = 80
	large_increment_modifier_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	large_increment_modifier_key_button.tooltip_text = "Click to set modifier key for large increments. Press ESC to cancel."
	modifier_grid.add_child(large_increment_modifier_key_button)
	
	# Add separator for control settings
	var control_separator = HSeparator.new()
	control_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(control_separator)
	
	# Control Keys section
	var control_label = Label.new()
	control_label.text = "Control Keys"
	control_label.add_theme_font_size_override("font_size", 14)
	control_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(control_label)
	
	# Control key grid
	var control_grid = GridContainer.new()
	control_grid.columns = 2
	control_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_grid.add_theme_constant_override("h_separation", 8)
	control_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(control_grid)
	
	# Cancel Key
	var cancel_label = Label.new()
	cancel_label.text = "Cancel Placement:"
	cancel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_grid.add_child(cancel_label)
	
	cancel_key_button = Button.new()
	cancel_key_button.text = cancel_key
	cancel_key_button.custom_minimum_size.x = 80
	cancel_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_key_button.tooltip_text = "Click to set key for canceling placement mode. Press ESC to cancel."
	control_grid.add_child(cancel_key_button)
	
	# Transform Mode Key
	var transform_mode_label = Label.new()
	transform_mode_label.text = "Transform Mode:"
	transform_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_grid.add_child(transform_mode_label)
	
	transform_mode_key_button = Button.new()
	transform_mode_key_button.text = transform_mode_key
	transform_mode_key_button.custom_minimum_size.x = 80
	transform_mode_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transform_mode_key_button.tooltip_text = "Click to set key for activating transform mode on selected object. Press ESC to cancel."
	control_grid.add_child(transform_mode_key_button)
	
	# Add separator for utility settings
	var utility_separator = HSeparator.new()
	utility_separator.add_theme_constant_override("separation", 8)
	vbox.add_child(utility_separator)
	
	# Utility section
	var utility_label = Label.new()
	utility_label.text = "Utilities"
	utility_label.add_theme_font_size_override("font_size", 14)
	utility_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	vbox.add_child(utility_label)
	
	# Reset all settings button
	var reset_settings_button = Button.new()
	reset_settings_button.text = "Reset All Settings to Defaults"
	reset_settings_button.tooltip_text = "Reset all plugin settings to their default values"
	reset_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_settings_button.custom_minimum_size.y = 32
	vbox.add_child(reset_settings_button)
	
	# Add small separator between reset and clear cache
	var mini_separator = Control.new()
	mini_separator.custom_minimum_size.y = 8
	vbox.add_child(mini_separator)
	
	# Clear thumbnail cache button
	var clear_cache_button = Button.new()
	clear_cache_button.text = "Clear Thumbnail Cache"
	clear_cache_button.tooltip_text = "Clear cached thumbnails and regenerate them"
	clear_cache_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_cache_button.custom_minimum_size.y = 32
	vbox.add_child(clear_cache_button)
	
	# Add spacer at the end to push everything to the top
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Connect signals
	snap_to_ground_check.toggled.connect(_on_setting_changed)
	align_with_normal_check.toggled.connect(_on_setting_changed)
	snap_enabled_check.toggled.connect(_on_setting_changed)
	show_grid_check.toggled.connect(_on_show_grid_changed)
	snap_step_spin.value_changed.connect(_on_snap_step_changed)
	random_rotation_check.toggled.connect(_on_setting_changed)
	scale_spin.value_changed.connect(_on_scale_changed)
	collision_check.toggled.connect(_on_setting_changed)
	grouping_check.toggled.connect(_on_setting_changed)
	
	# Connect reset behavior control signals
	reset_height_on_exit_check.toggled.connect(_on_setting_changed)
	reset_scale_on_exit_check.toggled.connect(_on_setting_changed)
	reset_rotation_on_exit_check.toggled.connect(_on_setting_changed)
	
	# Connect rotation control signals
	rotate_y_key_button.pressed.connect(_on_key_binding_button_pressed.bind(rotate_y_key_button, "rotate_y_key"))
	rotate_x_key_button.pressed.connect(_on_key_binding_button_pressed.bind(rotate_x_key_button, "rotate_x_key"))
	rotate_z_key_button.pressed.connect(_on_key_binding_button_pressed.bind(rotate_z_key_button, "rotate_z_key"))
	reset_rotation_key_button.pressed.connect(_on_key_binding_button_pressed.bind(reset_rotation_key_button, "reset_rotation_key"))
	rotation_increment_spin.value_changed.connect(_on_rotation_increment_changed)
	fine_rotation_increment_spin.value_changed.connect(_on_rotation_increment_changed)
	large_rotation_increment_spin.value_changed.connect(_on_rotation_increment_changed)
	
	# Connect height control signals
	height_up_key_button.pressed.connect(_on_key_binding_button_pressed.bind(height_up_key_button, "height_up_key"))
	height_down_key_button.pressed.connect(_on_key_binding_button_pressed.bind(height_down_key_button, "height_down_key"))
	reset_height_key_button.pressed.connect(_on_key_binding_button_pressed.bind(reset_height_key_button, "reset_height_key"))
	
	# Connect scale control signals
	scale_up_key_button.pressed.connect(_on_key_binding_button_pressed.bind(scale_up_key_button, "scale_up_key"))
	scale_down_key_button.pressed.connect(_on_key_binding_button_pressed.bind(scale_down_key_button, "scale_down_key"))
	scale_reset_key_button.pressed.connect(_on_key_binding_button_pressed.bind(scale_reset_key_button, "scale_reset_key"))
	scale_increment_spin.value_changed.connect(_on_scale_increment_changed)
	fine_scale_increment_spin.value_changed.connect(_on_scale_increment_changed)
	large_scale_increment_spin.value_changed.connect(_on_scale_increment_changed)
	
	# Connect height adjustment spin box signals
	height_step_spin.value_changed.connect(_on_height_step_changed)
	fine_height_increment_spin.value_changed.connect(_on_height_step_changed)
	large_height_increment_spin.value_changed.connect(_on_height_step_changed)
	
	# Connect modifier key control signals
	reverse_modifier_key_button.pressed.connect(_on_key_binding_button_pressed.bind(reverse_modifier_key_button, "reverse_modifier_key"))
	large_increment_modifier_key_button.pressed.connect(_on_key_binding_button_pressed.bind(large_increment_modifier_key_button, "large_increment_modifier_key"))
	
	# Connect control key signals
	cancel_key_button.pressed.connect(_on_key_binding_button_pressed.bind(cancel_key_button, "cancel_key"))
	transform_mode_key_button.pressed.connect(_on_key_binding_button_pressed.bind(transform_mode_key_button, "transform_mode_key"))
	
	# Connect utility button signals
	reset_settings_button.pressed.connect(_on_reset_settings_pressed)
	clear_cache_button.pressed.connect(_on_clear_cache_pressed)

func _on_setting_changed(value = null):
	snap_to_ground = snap_to_ground_check.button_pressed
	align_with_normal = align_with_normal_check.button_pressed
	snap_enabled = snap_enabled_check.button_pressed
	random_rotation = random_rotation_check.button_pressed
	add_collision = collision_check.button_pressed
	group_instances = grouping_check.button_pressed
	
	# New snap settings
	var snap_aabb_check = get_node_or_null("VBoxContainer/SnapAABBCheck")
	if snap_aabb_check:
		snap_by_aabb = snap_aabb_check.button_pressed
	
	var snap_center_x_check = get_node_or_null("VBoxContainer/SnapCenterXCheck")
	if snap_center_x_check:
		snap_center_x = snap_center_x_check.button_pressed
	
	var snap_center_y_check = get_node_or_null("VBoxContainer/SnapCenterYCheck")
	if snap_center_y_check:
		snap_center_y = snap_center_y_check.button_pressed
	
	var snap_center_z_check = get_node_or_null("VBoxContainer/SnapCenterZCheck")
	if snap_center_z_check:
		snap_center_z = snap_center_z_check.button_pressed
	
	var snap_y_check = get_node_or_null("VBoxContainer/SnapYCheck")
	if snap_y_check:
		snap_y_enabled = snap_y_check.button_pressed
	
	var snap_y_step_spin = get_node_or_null("VBoxContainer/SettingsGrid/SnapYStepSpin")
	if snap_y_step_spin:
		snap_y_step = snap_y_step_spin.value
	
	var offset_x_spin = get_node_or_null("VBoxContainer/SettingsGrid/GridOffsetXSpin")
	var offset_z_spin = get_node_or_null("VBoxContainer/SettingsGrid/GridOffsetZSpin")
	if offset_x_spin and offset_z_spin:
		snap_offset = Vector3(offset_x_spin.value, snap_offset.y, offset_z_spin.value)
	
	var grid_extent_spin = get_node_or_null("VBoxContainer/SettingsGrid/GridExtentSpin")
	if grid_extent_spin:
		grid_extent = grid_extent_spin.value
	
	# Reset behavior settings
	reset_height_on_exit = reset_height_on_exit_check.button_pressed
	reset_scale_on_exit = reset_scale_on_exit_check.button_pressed
	reset_rotation_on_exit = reset_rotation_on_exit_check.button_pressed
	
	settings_changed.emit()

func _on_scale_changed(value: float):
	scale_multiplier = value
	settings_changed.emit()

func _on_snap_step_changed(value: float):
	snap_step = value
	settings_changed.emit()

func _on_show_grid_changed(value: bool):
	show_grid = value
	settings_changed.emit()

func _on_key_binding_button_pressed(button: Button, key_property: String):
	# Start listening for key input
	listening_button = button
	button.text = "Press any key..."
	button.modulate = Color.YELLOW
	
	# Store the property name to update when key is pressed
	button.set_meta("key_property", key_property)

func _input(event: InputEvent):
	if listening_button == null:
		return
	
	if event is InputEventKey and event.pressed:
		# Allow ESC to cancel key binding
		if event.keycode == KEY_ESCAPE:
			_cancel_key_binding()
			get_viewport().set_input_as_handled()
			return
		
		# Get the key name and build full key string with modifiers
		var base_key_string = OS.get_keycode_string(event.keycode)
		var key_string = ""
		
		# Handle standalone modifier keys (CTRL, ALT, SHIFT alone)
		if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			key_string = base_key_string  # Just "CTRL" or "SHIFT" etc.
		else:
			# Handle modifier combinations (CTRL+X, ALT+Y, etc.)
			if event.ctrl_pressed:
				key_string += "CTRL+"
			if event.alt_pressed:
				key_string += "ALT+"
			if event.shift_pressed:
				key_string += "SHIFT+"
			key_string += base_key_string
		
		# Update the appropriate key property
		var key_property = listening_button.get_meta("key_property")
		match key_property:
			"rotate_y_key":
				rotate_y_key = key_string
			"rotate_x_key":
				rotate_x_key = key_string
			"rotate_z_key":
				rotate_z_key = key_string
			"reset_rotation_key":
				reset_rotation_key = key_string
			"scale_up_key":
				scale_up_key = key_string
			"scale_down_key":
				scale_down_key = key_string
			"scale_reset_key":
				scale_reset_key = key_string
			"height_up_key":
				height_up_key = key_string
			"height_down_key":
				height_down_key = key_string
			"position_left_key":
				position_left_key = key_string
			"position_right_key":
				position_right_key = key_string
			"position_forward_key":
				position_forward_key = key_string
			"position_backward_key":
				position_backward_key = key_string
			"reset_position_key":
				reset_position_key = key_string
			"reverse_modifier_key":
				reverse_modifier_key = key_string
			"large_increment_modifier_key":
				large_increment_modifier_key = key_string
			"cancel_key":
				cancel_key = key_string
			"transform_mode_key":
				transform_mode_key = key_string
		
		# Update button display
		listening_button.text = key_string
		listening_button.modulate = Color.WHITE
		listening_button = null
		
		# Save settings
		settings_changed.emit()
		
		# Consume the event so it doesn't propagate
		get_viewport().set_input_as_handled()

func _cancel_key_binding():
	if listening_button == null:
		return
	
	# Restore original key text
	var key_property = listening_button.get_meta("key_property")
	match key_property:
		"rotate_y_key":
			listening_button.text = rotate_y_key
		"rotate_x_key":
			listening_button.text = rotate_x_key
		"rotate_z_key":
			listening_button.text = rotate_z_key
		"reset_rotation_key":
			listening_button.text = reset_rotation_key
		"scale_up_key":
			listening_button.text = scale_up_key
		"scale_down_key":
			listening_button.text = scale_down_key
		"scale_reset_key":
			listening_button.text = scale_reset_key
		"height_up_key":
			listening_button.text = height_up_key
		"height_down_key":
			listening_button.text = height_down_key
		"position_left_key":
			listening_button.text = position_left_key
		"position_right_key":
			listening_button.text = position_right_key
		"position_forward_key":
			listening_button.text = position_forward_key
		"position_backward_key":
			listening_button.text = position_backward_key
		"reset_position_key":
			listening_button.text = reset_position_key
		"reverse_modifier_key":
			listening_button.text = reverse_modifier_key
		"large_increment_modifier_key":
			listening_button.text = large_increment_modifier_key
		"cancel_key":
			listening_button.text = cancel_key
		"transform_mode_key":
			listening_button.text = transform_mode_key
	
	listening_button.modulate = Color.WHITE
	listening_button = null

func _on_rotation_increment_changed(value: float):
	# Update rotation increment settings
	rotation_increment = rotation_increment_spin.value
	fine_rotation_increment = fine_rotation_increment_spin.value
	large_rotation_increment = large_rotation_increment_spin.value
	settings_changed.emit()

func _on_scale_increment_changed(value: float):
	# Update scale increment settings
	scale_increment = scale_increment_spin.value
	fine_scale_increment = fine_scale_increment_spin.value
	large_scale_increment = large_scale_increment_spin.value
	settings_changed.emit()

func _on_height_step_changed(value: float):
	# Update height adjustment steps
	height_adjustment_step = height_step_spin.value
	fine_height_increment = fine_height_increment_spin.value
	large_height_increment = large_height_increment_spin.value
	settings_changed.emit()

func _on_reset_settings_pressed():
	"""Reset all settings to their default values"""
	# Show confirmation dialog
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Are you sure you want to reset ALL settings to their default values?\n\nThis will reset:\n• All key bindings\n• All increments and steps\n• All checkboxes and options\n\nThis action cannot be undone."
	confirm_dialog.title = "Reset All Settings"
	confirm_dialog.ok_button_text = "Reset"
	confirm_dialog.cancel_button_text = "Cancel"
	
	# Add dialog to tree
	add_child(confirm_dialog)
	
	# Connect confirmed signal
	confirm_dialog.confirmed.connect(_perform_reset_settings)
	
	# Clean up dialog after closing
	confirm_dialog.close_requested.connect(confirm_dialog.queue_free)
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	confirm_dialog.confirmed.connect(confirm_dialog.queue_free)
	
	# Show the dialog
	confirm_dialog.popup_centered()

func _perform_reset_settings():
	"""Actually perform the settings reset after confirmation"""
	# Reset boolean settings
	snap_to_ground = false
	align_with_normal = false
	snap_enabled = false
	random_rotation = false
	add_collision = false
	group_instances = false
	
	# Reset numeric settings
	snap_step = 1.0
	scale_multiplier = 1.0
	
	# Reset behavior settings
	reset_height_on_exit = false
	reset_scale_on_exit = false
	reset_rotation_on_exit = false
	
	# Reset rotation settings
	rotate_y_key = "Y"
	rotate_x_key = "X"
	rotate_z_key = "Z"
	reset_rotation_key = "T"
	rotation_increment = 15.0
	fine_rotation_increment = 5.0
	large_rotation_increment = 90.0
	
	# Reset scale settings
	scale_up_key = "PAGE_UP"
	scale_down_key = "PAGE_DOWN"
	scale_reset_key = "HOME"
	scale_increment = 0.1
	fine_scale_increment = 0.01
	large_scale_increment = 0.5
	
	# Reset height settings
	height_up_key = "Q"
	height_down_key = "E"
	reset_height_key = "R"
	height_adjustment_step = 0.1
	fine_height_increment = 0.01
	large_height_increment = 1.0
	
	# Reset modifier keys
	reverse_modifier_key = "SHIFT"
	large_increment_modifier_key = "ALT"
	
	# Reset control keys
	cancel_key = "ESCAPE"
	transform_mode_key = "TAB"
	
	# Update UI to reflect the reset values
	update_ui_from_settings()
	
	# Save the reset settings and emit change signal
	save_settings()
	settings_changed.emit()
	
	print("Settings reset to defaults")

func _on_clear_cache_pressed():
	# Clear the thumbnail cache in ThumbnailGenerator
	ThumbnailGenerator.clear_cache()
	
	# Emit signal to refresh thumbnails
	cache_cleared.emit()

func get_placement_settings() -> Dictionary:
	return {
		"snap_to_ground": snap_to_ground,
		"align_with_normal": align_with_normal,
		"snap_enabled": snap_enabled,
		"snap_step": snap_step,
		"snap_by_aabb": snap_by_aabb,
		"snap_offset": snap_offset,
		"snap_y_enabled": snap_y_enabled,
		"snap_y_step": snap_y_step,
		"snap_center_x": snap_center_x,
		"snap_center_y": snap_center_y,
		"snap_center_z": snap_center_z,
		"show_grid": show_grid,
		"grid_extent": grid_extent,
		"random_rotation": random_rotation,
		"scale_multiplier": scale_multiplier,
		"add_collision": add_collision,
		"group_instances": group_instances,
		"rotate_y_key": rotate_y_key,
		"rotate_x_key": rotate_x_key,
		"rotate_z_key": rotate_z_key,
		"reset_rotation_key": reset_rotation_key,
		"rotation_increment": rotation_increment,
		"fine_rotation_increment": fine_rotation_increment,
		"large_rotation_increment": large_rotation_increment,
		"scale_up_key": scale_up_key,
		"scale_down_key": scale_down_key,
		"scale_reset_key": scale_reset_key,
		"scale_increment": scale_increment,
		"fine_scale_increment": fine_scale_increment,
		"large_scale_increment": large_scale_increment,
		"height_up_key": height_up_key,
		"height_down_key": height_down_key,
		"reset_height_key": reset_height_key,
		"height_adjustment_step": height_adjustment_step,
		"fine_height_increment": fine_height_increment,
		"large_height_increment": large_height_increment,
		"position_left_key": position_left_key,
		"position_right_key": position_right_key,
		"position_forward_key": position_forward_key,
		"position_backward_key": position_backward_key,
		"reset_position_key": reset_position_key,
		"position_increment": position_increment,
		"fine_position_increment": fine_position_increment,
		"large_position_increment": large_position_increment,
		"reverse_modifier_key": reverse_modifier_key,
		"large_increment_modifier_key": large_increment_modifier_key,
		"cancel_key": cancel_key,
		"transform_mode_key": transform_mode_key,
		
		# Reset behavior settings
		"reset_height_on_exit": reset_height_on_exit,
		"reset_scale_on_exit": reset_scale_on_exit,
		"reset_rotation_on_exit": reset_rotation_on_exit
	}

func save_settings():
	# Save settings to editor settings
	var editor_settings = EditorInterface.get_editor_settings()
	editor_settings.set_setting("simple_asset_placer/snap_to_ground", snap_to_ground)
	editor_settings.set_setting("simple_asset_placer/align_with_normal", align_with_normal)
	editor_settings.set_setting("simple_asset_placer/snap_enabled", snap_enabled)
	editor_settings.set_setting("simple_asset_placer/snap_step", snap_step)
	editor_settings.set_setting("simple_asset_placer/snap_by_aabb", snap_by_aabb)
	editor_settings.set_setting("simple_asset_placer/snap_offset", snap_offset)
	editor_settings.set_setting("simple_asset_placer/snap_y_enabled", snap_y_enabled)
	editor_settings.set_setting("simple_asset_placer/snap_y_step", snap_y_step)
	editor_settings.set_setting("simple_asset_placer/snap_center_x", snap_center_x)
	editor_settings.set_setting("simple_asset_placer/snap_center_y", snap_center_y)
	editor_settings.set_setting("simple_asset_placer/snap_center_z", snap_center_z)
	editor_settings.set_setting("simple_asset_placer/random_rotation", random_rotation)
	editor_settings.set_setting("simple_asset_placer/scale_multiplier", scale_multiplier)
	editor_settings.set_setting("simple_asset_placer/add_collision", add_collision)
	editor_settings.set_setting("simple_asset_placer/group_instances", group_instances)
	
	# Save reset behavior settings
	editor_settings.set_setting("simple_asset_placer/reset_height_on_exit", reset_height_on_exit)
	editor_settings.set_setting("simple_asset_placer/reset_scale_on_exit", reset_scale_on_exit)
	editor_settings.set_setting("simple_asset_placer/reset_rotation_on_exit", reset_rotation_on_exit)
	
	# Save rotation settings
	editor_settings.set_setting("simple_asset_placer/rotate_y_key", rotate_y_key)
	editor_settings.set_setting("simple_asset_placer/rotate_x_key", rotate_x_key)
	editor_settings.set_setting("simple_asset_placer/rotate_z_key", rotate_z_key)
	editor_settings.set_setting("simple_asset_placer/reset_rotation_key", reset_rotation_key)
	editor_settings.set_setting("simple_asset_placer/rotation_increment", rotation_increment)
	editor_settings.set_setting("simple_asset_placer/fine_rotation_increment", fine_rotation_increment)
	editor_settings.set_setting("simple_asset_placer/large_rotation_increment", large_rotation_increment)
	
	# Save scale settings
	editor_settings.set_setting("simple_asset_placer/scale_up_key", scale_up_key)
	editor_settings.set_setting("simple_asset_placer/scale_down_key", scale_down_key)
	editor_settings.set_setting("simple_asset_placer/scale_reset_key", scale_reset_key)
	editor_settings.set_setting("simple_asset_placer/scale_increment", scale_increment)
	editor_settings.set_setting("simple_asset_placer/fine_scale_increment", fine_scale_increment)
	editor_settings.set_setting("simple_asset_placer/large_scale_increment", large_scale_increment)
	
	# Save height adjustment settings
	editor_settings.set_setting("simple_asset_placer/height_up_key", height_up_key)
	editor_settings.set_setting("simple_asset_placer/height_down_key", height_down_key)
	editor_settings.set_setting("simple_asset_placer/reset_height_key", reset_height_key)
	editor_settings.set_setting("simple_asset_placer/height_adjustment_step", height_adjustment_step)
	editor_settings.set_setting("simple_asset_placer/fine_height_increment", fine_height_increment)
	editor_settings.set_setting("simple_asset_placer/large_height_increment", large_height_increment)
	
	# Save modifier key settings
	editor_settings.set_setting("simple_asset_placer/reverse_modifier_key", reverse_modifier_key)
	editor_settings.set_setting("simple_asset_placer/large_increment_modifier_key", large_increment_modifier_key)
	
	# Save control settings
	editor_settings.set_setting("simple_asset_placer/cancel_key", cancel_key)
	editor_settings.set_setting("simple_asset_placer/transform_mode_key", transform_mode_key)

func load_settings():
	# Load settings from editor settings
	var editor_settings = EditorInterface.get_editor_settings()
	
	# Load with default values if setting doesn't exist
	if editor_settings.has_setting("simple_asset_placer/snap_to_ground"):
		snap_to_ground = editor_settings.get_setting("simple_asset_placer/snap_to_ground")
	if editor_settings.has_setting("simple_asset_placer/align_with_normal"):
		align_with_normal = editor_settings.get_setting("simple_asset_placer/align_with_normal")
	if editor_settings.has_setting("simple_asset_placer/snap_enabled"):
		snap_enabled = editor_settings.get_setting("simple_asset_placer/snap_enabled")
	if editor_settings.has_setting("simple_asset_placer/snap_step"):
		snap_step = editor_settings.get_setting("simple_asset_placer/snap_step")
	if editor_settings.has_setting("simple_asset_placer/snap_by_aabb"):
		snap_by_aabb = editor_settings.get_setting("simple_asset_placer/snap_by_aabb")
	if editor_settings.has_setting("simple_asset_placer/snap_offset"):
		snap_offset = editor_settings.get_setting("simple_asset_placer/snap_offset")
	if editor_settings.has_setting("simple_asset_placer/snap_y_enabled"):
		snap_y_enabled = editor_settings.get_setting("simple_asset_placer/snap_y_enabled")
	if editor_settings.has_setting("simple_asset_placer/snap_y_step"):
		snap_y_step = editor_settings.get_setting("simple_asset_placer/snap_y_step")
	if editor_settings.has_setting("simple_asset_placer/snap_center_x"):
		snap_center_x = editor_settings.get_setting("simple_asset_placer/snap_center_x")
	if editor_settings.has_setting("simple_asset_placer/snap_center_y"):
		snap_center_y = editor_settings.get_setting("simple_asset_placer/snap_center_y")
	if editor_settings.has_setting("simple_asset_placer/snap_center_z"):
		snap_center_z = editor_settings.get_setting("simple_asset_placer/snap_center_z")
	if editor_settings.has_setting("simple_asset_placer/random_rotation"):
		random_rotation = editor_settings.get_setting("simple_asset_placer/random_rotation")
	if editor_settings.has_setting("simple_asset_placer/scale_multiplier"):
		scale_multiplier = editor_settings.get_setting("simple_asset_placer/scale_multiplier")
	if editor_settings.has_setting("simple_asset_placer/add_collision"):
		add_collision = editor_settings.get_setting("simple_asset_placer/add_collision")
	if editor_settings.has_setting("simple_asset_placer/group_instances"):
		group_instances = editor_settings.get_setting("simple_asset_placer/group_instances")
	
	# Load reset behavior settings
	if editor_settings.has_setting("simple_asset_placer/reset_height_on_exit"):
		reset_height_on_exit = editor_settings.get_setting("simple_asset_placer/reset_height_on_exit")
	if editor_settings.has_setting("simple_asset_placer/reset_scale_on_exit"):
		reset_scale_on_exit = editor_settings.get_setting("simple_asset_placer/reset_scale_on_exit")
	if editor_settings.has_setting("simple_asset_placer/reset_rotation_on_exit"):
		reset_rotation_on_exit = editor_settings.get_setting("simple_asset_placer/reset_rotation_on_exit")
	
	# Load rotation settings
	if editor_settings.has_setting("simple_asset_placer/rotate_y_key"):
		rotate_y_key = editor_settings.get_setting("simple_asset_placer/rotate_y_key")
	if editor_settings.has_setting("simple_asset_placer/rotate_x_key"):
		rotate_x_key = editor_settings.get_setting("simple_asset_placer/rotate_x_key")
	if editor_settings.has_setting("simple_asset_placer/rotate_z_key"):
		rotate_z_key = editor_settings.get_setting("simple_asset_placer/rotate_z_key")
	if editor_settings.has_setting("simple_asset_placer/reset_rotation_key"):
		reset_rotation_key = editor_settings.get_setting("simple_asset_placer/reset_rotation_key")
	if editor_settings.has_setting("simple_asset_placer/rotation_increment"):
		rotation_increment = editor_settings.get_setting("simple_asset_placer/rotation_increment")
	if editor_settings.has_setting("simple_asset_placer/fine_rotation_increment"):
		fine_rotation_increment = editor_settings.get_setting("simple_asset_placer/fine_rotation_increment")
	if editor_settings.has_setting("simple_asset_placer/large_rotation_increment"):
		large_rotation_increment = editor_settings.get_setting("simple_asset_placer/large_rotation_increment")
	
	# Load scale settings
	if editor_settings.has_setting("simple_asset_placer/scale_up_key"):
		scale_up_key = editor_settings.get_setting("simple_asset_placer/scale_up_key")
	if editor_settings.has_setting("simple_asset_placer/scale_down_key"):
		scale_down_key = editor_settings.get_setting("simple_asset_placer/scale_down_key")
	if editor_settings.has_setting("simple_asset_placer/scale_reset_key"):
		scale_reset_key = editor_settings.get_setting("simple_asset_placer/scale_reset_key")
	if editor_settings.has_setting("simple_asset_placer/scale_increment"):
		scale_increment = editor_settings.get_setting("simple_asset_placer/scale_increment")
	if editor_settings.has_setting("simple_asset_placer/fine_scale_increment"):
		fine_scale_increment = editor_settings.get_setting("simple_asset_placer/fine_scale_increment")
	if editor_settings.has_setting("simple_asset_placer/large_scale_increment"):
		large_scale_increment = editor_settings.get_setting("simple_asset_placer/large_scale_increment")
	
	# Load height adjustment settings
	if editor_settings.has_setting("simple_asset_placer/height_up_key"):
		height_up_key = editor_settings.get_setting("simple_asset_placer/height_up_key")
	if editor_settings.has_setting("simple_asset_placer/height_down_key"):
		height_down_key = editor_settings.get_setting("simple_asset_placer/height_down_key")
	if editor_settings.has_setting("simple_asset_placer/reset_height_key"):
		reset_height_key = editor_settings.get_setting("simple_asset_placer/reset_height_key")
	if editor_settings.has_setting("simple_asset_placer/height_adjustment_step"):
		height_adjustment_step = editor_settings.get_setting("simple_asset_placer/height_adjustment_step")
	if editor_settings.has_setting("simple_asset_placer/fine_height_increment"):
		fine_height_increment = editor_settings.get_setting("simple_asset_placer/fine_height_increment")
	if editor_settings.has_setting("simple_asset_placer/large_height_increment"):
		large_height_increment = editor_settings.get_setting("simple_asset_placer/large_height_increment")
	
	# Load modifier key settings
	if editor_settings.has_setting("simple_asset_placer/reverse_modifier_key"):
		reverse_modifier_key = editor_settings.get_setting("simple_asset_placer/reverse_modifier_key")
	if editor_settings.has_setting("simple_asset_placer/large_increment_modifier_key"):
		large_increment_modifier_key = editor_settings.get_setting("simple_asset_placer/large_increment_modifier_key")
	
	# Load control settings
	if editor_settings.has_setting("simple_asset_placer/cancel_key"):
		cancel_key = editor_settings.get_setting("simple_asset_placer/cancel_key")
	if editor_settings.has_setting("simple_asset_placer/transform_mode_key"):
		transform_mode_key = editor_settings.get_setting("simple_asset_placer/transform_mode_key")
	
	# Update UI to reflect loaded settings
	update_ui_from_settings()

func update_ui_from_settings():
	# Temporarily disconnect signals to prevent triggering _on_setting_changed
	_disconnect_ui_signals()
	
	# Update UI controls to match the loaded settings
	if snap_to_ground_check:
		snap_to_ground_check.button_pressed = snap_to_ground
	if align_with_normal_check:
		align_with_normal_check.button_pressed = align_with_normal
	if snap_enabled_check:
		snap_enabled_check.button_pressed = snap_enabled
	if snap_step_spin:
		snap_step_spin.value = snap_step
	if random_rotation_check:
		random_rotation_check.button_pressed = random_rotation
	if scale_spin:
		scale_spin.value = scale_multiplier
	if collision_check:
		collision_check.button_pressed = add_collision
	if grouping_check:
		grouping_check.button_pressed = group_instances
	
	# Update snap center controls
	var snap_center_x_check = get_node_or_null("VBoxContainer/SnapCenterXCheck")
	if snap_center_x_check:
		snap_center_x_check.button_pressed = snap_center_x
	var snap_center_y_check = get_node_or_null("VBoxContainer/SnapCenterYCheck")
	if snap_center_y_check:
		snap_center_y_check.button_pressed = snap_center_y
	var snap_center_z_check = get_node_or_null("VBoxContainer/SnapCenterZCheck")
	if snap_center_z_check:
		snap_center_z_check.button_pressed = snap_center_z
	
	# Update reset behavior controls
	if reset_height_on_exit_check:
		reset_height_on_exit_check.button_pressed = reset_height_on_exit
	if reset_scale_on_exit_check:
		reset_scale_on_exit_check.button_pressed = reset_scale_on_exit
	if reset_rotation_on_exit_check:
		reset_rotation_on_exit_check.button_pressed = reset_rotation_on_exit
	
	# Reconnect signals after UI update
	_connect_ui_signals()
	
	# Update rotation controls
	if rotate_y_key_button:
		rotate_y_key_button.text = rotate_y_key
	if rotate_x_key_button:
		rotate_x_key_button.text = rotate_x_key
	if rotate_z_key_button:
		rotate_z_key_button.text = rotate_z_key
	if reset_rotation_key_button:
		reset_rotation_key_button.text = reset_rotation_key
	if rotation_increment_spin:
		rotation_increment_spin.value = rotation_increment
	if fine_rotation_increment_spin:
		fine_rotation_increment_spin.value = fine_rotation_increment
	if large_rotation_increment_spin:
		large_rotation_increment_spin.value = large_rotation_increment
	
	# Update scale controls
	if scale_up_key_button:
		scale_up_key_button.text = scale_up_key
	if scale_down_key_button:
		scale_down_key_button.text = scale_down_key
	if scale_reset_key_button:
		scale_reset_key_button.text = scale_reset_key
	if scale_increment_spin:
		scale_increment_spin.value = scale_increment
	if fine_scale_increment_spin:
		fine_scale_increment_spin.value = fine_scale_increment
	if large_scale_increment_spin:
		large_scale_increment_spin.value = large_scale_increment
	
	# Update height adjustment controls
	if height_up_key_button:
		height_up_key_button.text = height_up_key
	if height_down_key_button:
		height_down_key_button.text = height_down_key
	if reset_height_key_button:
		reset_height_key_button.text = reset_height_key
	if height_step_spin:
		height_step_spin.value = height_adjustment_step
	if fine_height_increment_spin:
		fine_height_increment_spin.value = fine_height_increment
	if large_height_increment_spin:
		large_height_increment_spin.value = large_height_increment

func _disconnect_ui_signals():
	"""Temporarily disconnect UI signals to prevent unwanted save triggers"""
	if snap_to_ground_check and snap_to_ground_check.toggled.is_connected(_on_setting_changed):
		snap_to_ground_check.toggled.disconnect(_on_setting_changed)
	if align_with_normal_check and align_with_normal_check.toggled.is_connected(_on_setting_changed):
		align_with_normal_check.toggled.disconnect(_on_setting_changed)
	if snap_enabled_check and snap_enabled_check.toggled.is_connected(_on_setting_changed):
		snap_enabled_check.toggled.disconnect(_on_setting_changed)
	if random_rotation_check and random_rotation_check.toggled.is_connected(_on_setting_changed):
		random_rotation_check.toggled.disconnect(_on_setting_changed)
	if collision_check and collision_check.toggled.is_connected(_on_setting_changed):
		collision_check.toggled.disconnect(_on_setting_changed)
	if grouping_check and grouping_check.toggled.is_connected(_on_setting_changed):
		grouping_check.toggled.disconnect(_on_setting_changed)
	if reset_height_on_exit_check and reset_height_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_height_on_exit_check.toggled.disconnect(_on_setting_changed)
	if reset_scale_on_exit_check and reset_scale_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_scale_on_exit_check.toggled.disconnect(_on_setting_changed)
	if reset_rotation_on_exit_check and reset_rotation_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_rotation_on_exit_check.toggled.disconnect(_on_setting_changed)

func _connect_ui_signals():
	"""Reconnect UI signals after updating UI from loaded settings"""
	if snap_to_ground_check and not snap_to_ground_check.toggled.is_connected(_on_setting_changed):
		snap_to_ground_check.toggled.connect(_on_setting_changed)
	if align_with_normal_check and not align_with_normal_check.toggled.is_connected(_on_setting_changed):
		align_with_normal_check.toggled.connect(_on_setting_changed)
	if snap_enabled_check and not snap_enabled_check.toggled.is_connected(_on_setting_changed):
		snap_enabled_check.toggled.connect(_on_setting_changed)
	if random_rotation_check and not random_rotation_check.toggled.is_connected(_on_setting_changed):
		random_rotation_check.toggled.connect(_on_setting_changed)
	if collision_check and not collision_check.toggled.is_connected(_on_setting_changed):
		collision_check.toggled.connect(_on_setting_changed)
	if grouping_check and not grouping_check.toggled.is_connected(_on_setting_changed):
		grouping_check.toggled.connect(_on_setting_changed)
	if reset_height_on_exit_check and not reset_height_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_height_on_exit_check.toggled.connect(_on_setting_changed)
	if reset_scale_on_exit_check and not reset_scale_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_scale_on_exit_check.toggled.connect(_on_setting_changed)
	if reset_rotation_on_exit_check and not reset_rotation_on_exit_check.toggled.is_connected(_on_setting_changed):
		reset_rotation_on_exit_check.toggled.connect(_on_setting_changed)
	
	# Update modifier key controls
	if reverse_modifier_key_button:
		reverse_modifier_key_button.text = reverse_modifier_key
	if large_increment_modifier_key_button:
		large_increment_modifier_key_button.text = large_increment_modifier_key
	
	# Update control key controls
	if cancel_key_button:
		cancel_key_button.text = cancel_key
	if transform_mode_key_button:
		transform_mode_key_button.text = transform_mode_key