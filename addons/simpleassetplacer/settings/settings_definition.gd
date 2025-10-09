@tool
extends RefCounted

class_name SettingsDefinition

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
	var placement_strategy = SettingMeta.new("placement_strategy", "simple_asset_placer/placement_strategy", "auto", SettingType.OPTION, "Placement Mode")
	placement_strategy.section = "basic"
	placement_strategy.options = ["auto", "collision", "plane"]
	placement_strategy.ui_tooltip = "Auto: Use snap_to_ground setting | Collision: Raycast to surfaces | Plane: Fixed height projection"
	settings.append(placement_strategy)
	
	# Legacy settings (kept for backward compatibility)
	var snap_to_ground = SettingMeta.new("snap_to_ground", "simple_asset_placer/snap_to_ground", true, SettingType.BOOL, "Snap to Ground (Legacy)")
	snap_to_ground.section = "basic"
	snap_to_ground.ui_tooltip = "Legacy: Use collision-based placement (now controlled by placement_strategy)"
	settings.append(snap_to_ground)
	
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
	
	var scale_multiplier = SettingMeta.new("scale_multiplier", "simple_asset_placer/scale_multiplier", 1.0, SettingType.FLOAT, "Scale Multiplier")
	scale_multiplier.section = "basic"
	scale_multiplier.min_value = 0.01
	scale_multiplier.max_value = 10.0
	scale_multiplier.step = 0.01
	scale_multiplier.ui_tooltip = "Default scale multiplier for placed objects"
	settings.append(scale_multiplier)
	
	var add_collision = SettingMeta.new("add_collision", "simple_asset_placer/add_collision", false, SettingType.BOOL, "Add Collision Shapes")
	add_collision.section = "basic"
	add_collision.ui_tooltip = "Automatically add collision shapes to placed objects"
	settings.append(add_collision)
	
	var group_instances = SettingMeta.new("group_instances", "simple_asset_placer/group_instances", false, SettingType.BOOL, "Group Instances")
	group_instances.section = "basic"
	group_instances.ui_tooltip = "Group all placed instances under a parent node"
	settings.append(group_instances)
	
	var smooth_transforms = SettingMeta.new("smooth_transforms", "simple_asset_placer/smooth_transforms", true, SettingType.BOOL, "Smooth Transformations")
	smooth_transforms.section = "basic"
	smooth_transforms.ui_tooltip = "Smoothly animate transformations with lerping/easing"
	settings.append(smooth_transforms)
	
	var smooth_transform_speed = SettingMeta.new("smooth_transform_speed", "simple_asset_placer/smooth_transform_speed", 8.0, SettingType.FLOAT, "Smooth Speed")
	smooth_transform_speed.section = "basic"
	smooth_transform_speed.min_value = 1.0
	smooth_transform_speed.max_value = 20.0
	smooth_transform_speed.step = 0.5
	smooth_transform_speed.ui_tooltip = "Speed of smooth transformations (higher = faster)"
	settings.append(smooth_transform_speed)
	
	# Advanced Grid Settings
	var snap_offset = SettingMeta.new("snap_offset", "simple_asset_placer/snap_offset", Vector3.ZERO, SettingType.VECTOR3, "Grid Offset")
	snap_offset.section = "advanced_grid"
	snap_offset.ui_tooltip = "Grid offset from world origin"
	settings.append(snap_offset)
	
	var snap_y_enabled = SettingMeta.new("snap_y_enabled", "simple_asset_placer/snap_y_enabled", false, SettingType.BOOL, "Enable Y-Axis Snap")
	snap_y_enabled.section = "advanced_grid"
	settings.append(snap_y_enabled)
	
	var snap_y_step = SettingMeta.new("snap_y_step", "simple_asset_placer/snap_y_step", 1.0, SettingType.FLOAT, "Y-Axis Snap Step")
	snap_y_step.section = "advanced_grid"
	snap_y_step.min_value = 0.01
	snap_y_step.max_value = 10.0
	snap_y_step.step = 0.01
	settings.append(snap_y_step)
	
	var snap_center_x = SettingMeta.new("snap_center_x", "simple_asset_placer/snap_center_x", false, SettingType.BOOL, "Snap Center X")
	snap_center_x.section = "advanced_grid"
	settings.append(snap_center_x)
	
	var snap_center_y = SettingMeta.new("snap_center_y", "simple_asset_placer/snap_center_y", false, SettingType.BOOL, "Snap Center Y")
	snap_center_y.section = "advanced_grid"
	settings.append(snap_center_y)
	
	var snap_center_z = SettingMeta.new("snap_center_z", "simple_asset_placer/snap_center_z", false, SettingType.BOOL, "Snap Center Z")
	snap_center_z.section = "advanced_grid"
	settings.append(snap_center_z)
	
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
	
	# Key Bindings - Rotation
	_add_key_binding(settings, "rotate_y_key", "Y", "Rotate Y-Axis", "rotation")
	_add_key_binding(settings, "rotate_x_key", "X", "Rotate X-Axis", "rotation")
	_add_key_binding(settings, "rotate_z_key", "Z", "Rotate Z-Axis", "rotation")
	_add_key_binding(settings, "reset_rotation_key", "T", "Reset Rotation", "rotation")
	
	# Key Bindings - Scale
	_add_key_binding(settings, "scale_up_key", "PAGE_UP", "Scale Up", "scale")
	_add_key_binding(settings, "scale_down_key", "PAGE_DOWN", "Scale Down", "scale")
	_add_key_binding(settings, "scale_reset_key", "HOME", "Reset Scale", "scale")
	
	# Key Bindings - Height
	_add_key_binding(settings, "height_up_key", "Q", "Raise Height", "height")
	_add_key_binding(settings, "height_down_key", "E", "Lower Height", "height")
	_add_key_binding(settings, "reset_height_key", "R", "Reset Height", "height")
	
	# Key Bindings - Position
	_add_key_binding(settings, "position_left_key", "A", "Move Left (-X)", "position")
	_add_key_binding(settings, "position_right_key", "D", "Move Right (+X)", "position")
	_add_key_binding(settings, "position_forward_key", "W", "Move Forward (-Z)", "position")
	_add_key_binding(settings, "position_backward_key", "S", "Move Backward (+Z)", "position")
	_add_key_binding(settings, "reset_position_key", "G", "Reset Position Offset", "position")
	
	# Key Bindings - Modifiers
	_add_key_binding(settings, "reverse_modifier_key", "SHIFT", "Reverse Direction", "modifiers")
	_add_key_binding(settings, "large_increment_modifier_key", "ALT", "Large Increment", "modifiers")
	_add_key_binding(settings, "fine_increment_modifier_key", "CTRL", "Fine Increment", "modifiers")
	
	# Key Bindings - Control
	_add_key_binding(settings, "cancel_key", "ESCAPE", "Cancel Placement", "control")
	_add_key_binding(settings, "confirm_action_key", "ENTER", "Confirm Placement/Transform", "control")
	_add_key_binding(settings, "transform_mode_key", "TAB", "Transform Mode", "control")
	_add_key_binding(settings, "cycle_placement_mode_key", "P", "Cycle Placement Mode", "control")
	_add_key_binding(settings, "cycle_next_asset_key", "BRACKETRIGHT", "Cycle Next Asset", "control")
	_add_key_binding(settings, "cycle_previous_asset_key", "BRACKETLEFT", "Cycle Previous Asset", "control")
	
	# Increments - Rotation
	_add_increment(settings, "rotation_increment", 15.0, "Rotation Step", "rotation", 1.0, 180.0, 1.0)
	_add_increment(settings, "fine_rotation_increment", 5.0, "Fine Rotation Step", "rotation", 0.1, 45.0, 0.1)
	_add_increment(settings, "large_rotation_increment", 90.0, "Large Rotation Step", "rotation", 15.0, 180.0, 1.0)
	
	# Increments - Scale
	_add_increment(settings, "scale_increment", 0.1, "Scale Step", "scale", 0.01, 1.0, 0.01)
	_add_increment(settings, "fine_scale_increment", 0.01, "Fine Scale Step", "scale", 0.001, 0.1, 0.001)
	_add_increment(settings, "large_scale_increment", 0.5, "Large Scale Step", "scale", 0.1, 2.0, 0.1)
	
	# Increments - Height
	_add_increment(settings, "height_adjustment_step", 0.1, "Height Step", "height", 0.01, 5.0, 0.01)
	_add_increment(settings, "fine_height_increment", 0.01, "Fine Height Step", "height", 0.001, 0.5, 0.001)
	_add_increment(settings, "large_height_increment", 1.0, "Large Height Step", "height", 0.5, 10.0, 0.1)
	
	# Increments - Position
	_add_increment(settings, "position_increment", 0.1, "Position Step", "position", 0.01, 10.0, 0.01)
	_add_increment(settings, "fine_position_increment", 0.01, "Fine Position Step", "position", 0.001, 1.0, 0.001)
	_add_increment(settings, "large_position_increment", 1.0, "Large Position Step", "position", 0.5, 10.0, 0.1)
	
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







