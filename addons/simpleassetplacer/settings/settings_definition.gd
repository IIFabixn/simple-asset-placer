@tool
extends RefCounted

class_name SettingsDefinition

const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

# Setting types
enum SettingType {
	BOOL,
	FLOAT,
	STRING,
	VECTOR3,
	KEY_BINDING,
	OPTION  # Dropdown/OptionButton
}

# Setting metadata structure
class SettingMeta:
	var id: String  # Internal variable name
	var editor_key: String  # EditorSettings key
	var default_value  # Default value
	var type: SettingType
	var ui_label: String
	var ui_tooltip: String = ""
	var min_value: float = 0.0
	var max_value: float = 100.0
	var step: float = 0.01
	var section: String = ""  # UI section grouping
	var options: Array = []  # For OPTION type: array of strings for dropdown
	
	func _init(p_id: String, p_editor_key: String, p_default, p_type: SettingType, p_label: String = ""):
		id = p_id
		editor_key = p_editor_key
		default_value = p_default
		type = p_type
		ui_label = p_label if p_label else p_id.capitalize()

# All settings definitions
static func get_all_settings() -> Array:
	var settings: Array = []
	
	# Basic Settings Section
	
	# Placement Strategy (new unified setting with dropdown)
	var placement_strategy = SettingMeta.new("placement_strategy", "simple_asset_placer/placement_strategy", "collision", SettingType.OPTION, "Placement Strategy")
	placement_strategy.section = "basic"
	placement_strategy.options = ["collision", "plane"]
	placement_strategy.ui_tooltip = "Collision: Raycast to surfaces | Plane: Fixed height projection"
	settings.append(placement_strategy)
	
	var align_normal = SettingMeta.new("align_with_normal", "simple_asset_placer/align_with_normal", false, SettingType.BOOL, "Align with Surface Normal")
	align_normal.section = "basic"
	align_normal.ui_tooltip = "Align object rotation with surface normal (works with collision placement)"
	settings.append(align_normal)
	
	var snap_enabled = SettingMeta.new("snap_enabled", "simple_asset_placer/snap_enabled", false, SettingType.BOOL, "Enable Grid Snapping")
	snap_enabled.section = "basic"
	snap_enabled.ui_tooltip = "Snap to grid during placement"
	settings.append(snap_enabled)
	
	var snap_step = SettingMeta.new("snap_step", "simple_asset_placer/snap_step", 1.0, SettingType.FLOAT, "Grid Size")
	snap_step.section = "basic"
	snap_step.min_value = 0.01
	snap_step.max_value = 10.0
	snap_step.step = 0.01
	snap_step.ui_tooltip = "Grid snapping step size"
	settings.append(snap_step)
	
	var show_grid = SettingMeta.new("show_grid", "simple_asset_placer/show_grid", false, SettingType.BOOL, "Show Grid Overlay")
	show_grid.section = "basic"
	show_grid.ui_tooltip = "Display visual grid overlay"
	settings.append(show_grid)
	
	var grid_extent = SettingMeta.new("grid_extent", "simple_asset_placer/grid_extent", 20.0, SettingType.FLOAT, "Grid Extent")
	grid_extent.section = "basic"
	grid_extent.min_value = 5.0
	grid_extent.max_value = 100.0
	grid_extent.step = 1.0
	grid_extent.ui_tooltip = "Size of grid overlay in world units"
	settings.append(grid_extent)
	
	var random_rotation = SettingMeta.new("random_rotation", "simple_asset_placer/random_rotation", false, SettingType.BOOL, "Random Y Rotation")
	random_rotation.section = "basic"
	random_rotation.ui_tooltip = "Apply random Y-axis rotation on placement"
	settings.append(random_rotation)
	
	var smooth_transforms_setting = SettingMeta.new("smooth_transforms", "simple_asset_placer/smooth_transforms", true, SettingType.BOOL, "Smooth Transforms")
	smooth_transforms_setting.section = "basic"
	smooth_transforms_setting.ui_tooltip = "Smoothly interpolate preview and transform updates"
	settings.append(smooth_transforms_setting)

	var smooth_transform_speed = SettingMeta.new("smooth_transform_speed", "simple_asset_placer/smooth_transform_speed", 8.0, SettingType.FLOAT, "Smooth Transform Speed")
	smooth_transform_speed.section = "basic"
	smooth_transform_speed.min_value = 0.01
	smooth_transform_speed.max_value = 100.0
	smooth_transform_speed.step = 0.1
	smooth_transform_speed.ui_tooltip = "Speed of smooth interpolation for transforms (higher = faster)"
	settings.append(smooth_transform_speed)

	var scale_multiplier = SettingMeta.new("scale_multiplier", "simple_asset_placer/scale_multiplier", 1.0, SettingType.FLOAT, "Scale Multiplier")
	scale_multiplier.section = "basic"
	scale_multiplier.min_value = 0.01
	scale_multiplier.max_value = 10.0
	scale_multiplier.step = 0.01
	scale_multiplier.ui_tooltip = "Default scale multiplier for placed objects"
	settings.append(scale_multiplier)
	
	# Placement Settings
	var continuous_placement_enabled = SettingMeta.new("continuous_placement_enabled", "simple_asset_placer/continuous_placement_enabled", true, SettingType.BOOL, "Continuous Placement")
	continuous_placement_enabled.section = "basic"
	continuous_placement_enabled.ui_tooltip = "Keep placement mode active after each placement. Disable to exit automatically for single-drop workflows."
	settings.append(continuous_placement_enabled)

	var auto_select_placed = SettingMeta.new("auto_select_placed", "simple_asset_placer/auto_select_placed", true, SettingType.BOOL, "Auto-select Placed Node")
	auto_select_placed.section = "basic"
	auto_select_placed.ui_tooltip = "Automatically select newly placed nodes in the scene tree and focus them in the inspector."
	settings.append(auto_select_placed)

	var cursor_warp_enabled = SettingMeta.new("cursor_warp_enabled", "simple_asset_placer/cursor_warp_enabled", true, SettingType.BOOL, "Enable Cursor Warp")
	cursor_warp_enabled.section = "basic"
	cursor_warp_enabled.ui_tooltip = "Warp the mouse back toward the viewport center when it nears the edge during mouse-based transforms. Disable if you prefer no cursor repositioning."
	settings.append(cursor_warp_enabled)
	
	# Increment modifiers for keyboard-based transforms
	var fine_sensitivity_multiplier = SettingMeta.new("fine_sensitivity_multiplier", "simple_asset_placer/fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER, SettingType.FLOAT, "Fine Increment Multiplier")
	fine_sensitivity_multiplier.section = "increments"
	fine_sensitivity_multiplier.min_value = 0.01
	fine_sensitivity_multiplier.max_value = 1.0
	fine_sensitivity_multiplier.step = 0.05
	fine_sensitivity_multiplier.ui_tooltip = "Multiplier for adjustment increments when CTRL modifier is held (lower = more precise)"
	settings.append(fine_sensitivity_multiplier)
	
	var large_sensitivity_multiplier = SettingMeta.new("large_sensitivity_multiplier", "simple_asset_placer/large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER, SettingType.FLOAT, "Large Increment Multiplier")
	large_sensitivity_multiplier.section = "increments"
	large_sensitivity_multiplier.min_value = 1.0
	large_sensitivity_multiplier.max_value = 10.0
	large_sensitivity_multiplier.step = 0.5
	large_sensitivity_multiplier.ui_tooltip = "Multiplier for adjustment increments when ALT modifier is held (higher = faster adjustments)"
	settings.append(large_sensitivity_multiplier)
	
	# Advanced Grid Settings
	var snap_offset = SettingMeta.new("snap_offset", "simple_asset_placer/snap_offset", Vector3.ZERO, SettingType.VECTOR3, "Grid Offset")
	snap_offset.section = "grid_snapping"
	snap_offset.ui_tooltip = "Grid offset from world origin"
	settings.append(snap_offset)
	
	var snap_y_enabled = SettingMeta.new("snap_y_enabled", "simple_asset_placer/snap_y_enabled", false, SettingType.BOOL, "Enable Y-Axis Snap")
	snap_y_enabled.section = "grid_snapping"
	settings.append(snap_y_enabled)
	
	var snap_y_step = SettingMeta.new("snap_y_step", "simple_asset_placer/snap_y_step", 1.0, SettingType.FLOAT, "Y-Axis Snap Step")
	snap_y_step.section = "grid_snapping"
	snap_y_step.min_value = 0.01
	snap_y_step.max_value = 10.0
	snap_y_step.step = 0.01
	settings.append(snap_y_step)
	
	var snap_center_x = SettingMeta.new("snap_center_x", "simple_asset_placer/snap_center_x", false, SettingType.BOOL, "Snap Center X")
	snap_center_x.section = "grid_snapping"
	settings.append(snap_center_x)
	
	var snap_center_y = SettingMeta.new("snap_center_y", "simple_asset_placer/snap_center_y", false, SettingType.BOOL, "Snap Center Y")
	snap_center_y.section = "grid_snapping"
	settings.append(snap_center_y)
	
	var snap_center_z = SettingMeta.new("snap_center_z", "simple_asset_placer/snap_center_z", false, SettingType.BOOL, "Snap Center Z")
	snap_center_z.section = "grid_snapping"
	settings.append(snap_center_z)
	
	# Rotation Snap Settings
	var snap_rotation_enabled = SettingMeta.new("snap_rotation_enabled", "simple_asset_placer/snap_rotation_enabled", false, SettingType.BOOL, "Enable Rotation Snapping")
	snap_rotation_enabled.section = "grid_snapping"
	snap_rotation_enabled.ui_tooltip = "Snap rotation to grid increments"
	settings.append(snap_rotation_enabled)
	
	var snap_rotation_step = SettingMeta.new("snap_rotation_step", "simple_asset_placer/snap_rotation_step", 15.0, SettingType.FLOAT, "Rotation Snap Step (degrees)")
	snap_rotation_step.section = "grid_snapping"
	snap_rotation_step.min_value = 1.0
	snap_rotation_step.max_value = 90.0
	snap_rotation_step.step = 1.0
	snap_rotation_step.ui_tooltip = "Rotation snap increment in degrees (e.g., 15° = 24 steps per 360°)"
	settings.append(snap_rotation_step)
	
	# Scale Snap Settings
	var snap_scale_enabled = SettingMeta.new("snap_scale_enabled", "simple_asset_placer/snap_scale_enabled", false, SettingType.BOOL, "Enable Scale Snapping")
	snap_scale_enabled.section = "grid_snapping"
	snap_scale_enabled.ui_tooltip = "Snap scale to grid increments"
	settings.append(snap_scale_enabled)
	
	var snap_scale_step = SettingMeta.new("snap_scale_step", "simple_asset_placer/snap_scale_step", 0.1, SettingType.FLOAT, "Scale Snap Step")
	snap_scale_step.section = "grid_snapping"
	snap_scale_step.min_value = 0.01
	snap_scale_step.max_value = 1.0
	snap_scale_step.step = 0.01
	snap_scale_step.ui_tooltip = "Scale snap increment (e.g., 0.1 = snap to 0.0, 0.1, 0.2, etc.)"
	settings.append(snap_scale_step)
	
	# Reset Behavior Settings
	var reset_height_on_exit = SettingMeta.new("reset_height_on_exit", "simple_asset_placer/reset_height_on_exit", false, SettingType.BOOL, "Reset Height on Exit")
	reset_height_on_exit.section = "reset_behavior"
	settings.append(reset_height_on_exit)
	
	var reset_scale_on_exit = SettingMeta.new("reset_scale_on_exit", "simple_asset_placer/reset_scale_on_exit", false, SettingType.BOOL, "Reset Scale on Exit")
	reset_scale_on_exit.section = "reset_behavior"
	settings.append(reset_scale_on_exit)
	
	var reset_rotation_on_exit = SettingMeta.new("reset_rotation_on_exit", "simple_asset_placer/reset_rotation_on_exit", false, SettingType.BOOL, "Reset Rotation on Exit")
	reset_rotation_on_exit.section = "reset_behavior"
	settings.append(reset_rotation_on_exit)
	
	var reset_position_on_exit = SettingMeta.new("reset_position_on_exit", "simple_asset_placer/reset_position_on_exit", false, SettingType.BOOL, "Reset Position on Exit")
	reset_position_on_exit.section = "reset_behavior"
	settings.append(reset_position_on_exit)
	
	# ========== KEYBINDS SECTION ==========
	# All keybinds consolidated into one section
	
	# Axis Constraints (X/Y/Z - constrain transformations to specific axes)
	_add_key_binding(settings, "rotate_x_key", "X", "X-Axis Constraint / Rotate X", "keybinds")
	_add_key_binding(settings, "rotate_y_key", "Y", "Y-Axis Constraint / Rotate Y", "keybinds")
	_add_key_binding(settings, "rotate_z_key", "Z", "Z-Axis Constraint / Rotate Z", "keybinds")
	
	# Position Adjustment Keys (WASD - camera-relative movement)
	_add_key_binding(settings, "position_forward_key", "W", "Move Forward", "keybinds")
	_add_key_binding(settings, "position_backward_key", "S", "Move Backward", "keybinds")
	_add_key_binding(settings, "position_left_key", "A", "Move Left", "keybinds")
	_add_key_binding(settings, "position_right_key", "D", "Move Right", "keybinds")
	
	# Height Adjustment Keys
	_add_key_binding(settings, "height_up_key", "Q", "Raise Height", "keybinds")
	_add_key_binding(settings, "height_down_key", "E", "Lower Height", "keybinds")
	_add_key_binding(settings, "reset_height_key", "R", "Reset Height", "keybinds")
	
	# Scale Adjustment Keys
	_add_key_binding(settings, "scale_up_key", "PAGE_UP", "Scale Up", "keybinds")
	_add_key_binding(settings, "scale_down_key", "PAGE_DOWN", "Scale Down", "keybinds")
	_add_key_binding(settings, "scale_reset_key", "HOME", "Reset Scale", "keybinds")
	
	# Reset Transform Keys
	_add_key_binding(settings, "reset_rotation_key", "T", "Reset Rotation", "keybinds")
	_add_key_binding(settings, "reset_position_key", "G", "Reset Position", "keybinds")
	
	# General Control Keys
	_add_key_binding(settings, "cancel_key", "ESCAPE", "Cancel/Exit Mode", "keybinds")
	_add_key_binding(settings, "confirm_action_key", "ENTER", "Confirm Placement/Transform", "keybinds")
	_add_key_binding(settings, "transform_mode_key", "TAB", "Transform Mode", "keybinds")
	_add_key_binding(settings, "cycle_placement_mode_key", "P", "Cycle Placement Strategy", "keybinds")
	
	# Asset Cycling Keys
	_add_key_binding(settings, "cycle_next_asset_key", "BRACKETRIGHT", "Next Asset (])", "keybinds")
	_add_key_binding(settings, "cycle_previous_asset_key", "BRACKETLEFT", "Previous Asset ([)", "keybinds")
	
	# Modifier Keys
	_add_key_binding(settings, "reverse_modifier_key", "SHIFT", "Reverse Modifier", "keybinds")
	_add_key_binding(settings, "large_increment_modifier_key", "ALT", "Large Increment Modifier", "keybinds")
	_add_key_binding(settings, "fine_increment_modifier_key", "CTRL", "Fine Increment Modifier", "keybinds")
	
	# ========== INCREMENTS SECTION ==========
	# All increment values consolidated into one section
	
	# Height Increments (Q/E keys)
	_add_increment(settings, "height_adjustment_step", 0.1, "Height Step", "increments", 0.01, 5.0, 0.01)
	_add_increment(settings, "fine_height_increment", 0.01, "Height Step (Fine/CTRL)", "increments", 0.001, 0.5, 0.001)
	_add_increment(settings, "large_height_increment", 1.0, "Height Step (Large/ALT)", "increments", 0.5, 10.0, 0.1)
	
	# Rotation Increments (numeric input)
	_add_increment(settings, "rotation_increment", 15.0, "Rotation Step", "increments", 1.0, 180.0, 1.0)
	_add_increment(settings, "fine_rotation_increment", 5.0, "Rotation Step (Fine/CTRL)", "increments", 0.1, 45.0, 0.1)
	_add_increment(settings, "large_rotation_increment", 90.0, "Rotation Step (Large/ALT)", "increments", 15.0, 180.0, 1.0)
	
	# Scale Increments (numeric input)
	_add_increment(settings, "scale_increment", 0.1, "Scale Step", "increments", 0.01, 1.0, 0.01)
	_add_increment(settings, "fine_scale_increment", 0.01, "Scale Step (Fine/CTRL)", "increments", 0.001, 0.1, 0.001)
	_add_increment(settings, "large_scale_increment", 0.5, "Scale Step (Large/ALT)", "increments", 0.1, 2.0, 0.1)
	
	# Position Increments (WASD keyboard movement)
	_add_increment(settings, "position_increment", 1.0, "Position Step", "increments", 0.1, 10.0, 0.1)
	_add_increment(settings, "fine_position_increment", 0.1, "Position Step (Fine/CTRL)", "increments", 0.01, 1.0, 0.01)
	_add_increment(settings, "large_position_increment", 5.0, "Position Step (Large/ALT)", "increments", 1.0, 20.0, 0.5)

	var debug_commands = SettingMeta.new("debug_commands", "simple_asset_placer/debug_commands", false, SettingType.BOOL, "Debug Command Logging")
	debug_commands.section = "debug"
	debug_commands.ui_tooltip = "Log detailed TransformCommand diagnostics to console (position/rotation/scale deltas, sources, constraints). Requires Logging Level set to 'Debug' to see output."
	settings.append(debug_commands)
	
	var log_level = SettingMeta.new("log_level", "simple_asset_placer/log_level", "info", SettingType.OPTION, "Logging Level")
	log_level.section = "debug"
	log_level.options = ["debug", "info", "warning", "error"]
	log_level.ui_tooltip = "Control which log messages are shown: Debug (all), Info (general), Warning (issues), Error (failures only)"
	settings.append(log_level)
	
	return settings

static func _add_key_binding(settings: Array, id: String, default_key: String, label: String, section: String):
	var meta = SettingMeta.new(id, "simple_asset_placer/" + id, default_key, SettingType.KEY_BINDING, label)
	meta.section = section
	meta.ui_tooltip = "Click to set key for " + label.to_lower() + ". Press ESC to cancel."
	settings.append(meta)

static func _add_increment(settings: Array, id: String, default_val: float, label: String, section: String, min_val: float, max_val: float, step_val: float):
	var meta = SettingMeta.new(id, "simple_asset_placer/" + id, default_val, SettingType.FLOAT, label)
	meta.section = section
	meta.min_value = min_val
	meta.max_value = max_val
	meta.step = step_val
	settings.append(meta)

# Get settings grouped by section
static func get_settings_by_section() -> Dictionary:
	var grouped = {}
	for setting in get_all_settings():
		if not grouped.has(setting.section):
			grouped[setting.section] = []
		grouped[setting.section].append(setting)
	return grouped

# Get setting by ID
static func get_setting_meta(id: String) -> SettingMeta:
	for setting in get_all_settings():
		if setting.id == id:
			return setting
	return null







