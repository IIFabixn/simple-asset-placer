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

	var scale_multiplier = SettingMeta.new("scale_multiplier", "simple_asset_placer/scale_multiplier", 1.0, SettingType.FLOAT, "Scale Multiplier")
	scale_multiplier.section = "basic"
	scale_multiplier.min_value = 0.01
	scale_multiplier.max_value = 10.0
	scale_multiplier.step = 0.01
	scale_multiplier.ui_tooltip = "Default scale multiplier for placed objects"
	settings.append(scale_multiplier)
	
	# Modal Control Settings
	var modal_control_exclusive = SettingMeta.new("modal_control_exclusive", "simple_asset_placer/modal_control_exclusive", true, SettingType.BOOL, "Exclusive Modal Controls")
	modal_control_exclusive.section = "basic"
	modal_control_exclusive.ui_tooltip = "When enabled, modal controls (G/R/L) disable other automatic transformations like surface alignment. Recommended for precise control."
	settings.append(modal_control_exclusive)

	var auto_modal_activation = SettingMeta.new("auto_modal_activation", "simple_asset_placer/auto_modal_activation", false, SettingType.BOOL, "Auto-activate Modal Controls")
	auto_modal_activation.section = "basic"
	auto_modal_activation.ui_tooltip = "When enabled, entering placement or transform will immediately activate Grab (G) like the legacy workflow."
	settings.append(auto_modal_activation)

	var cursor_warp_enabled = SettingMeta.new("cursor_warp_enabled", "simple_asset_placer/cursor_warp_enabled", true, SettingType.BOOL, "Enable Cursor Warp")
	cursor_warp_enabled.section = "basic"
	cursor_warp_enabled.ui_tooltip = "Warp the mouse back toward the viewport center when it nears the edge during modal transforms. Disable if you prefer no cursor repositioning."
	settings.append(cursor_warp_enabled)
	
	# Mouse control sensitivity
	var mouse_rotation_sensitivity = SettingMeta.new("mouse_rotation_sensitivity", "simple_asset_placer/mouse_rotation_sensitivity", 0.5, SettingType.FLOAT, "Mouse Rotation Sensitivity")
	mouse_rotation_sensitivity.section = "basic"
	mouse_rotation_sensitivity.min_value = 0.1
	mouse_rotation_sensitivity.max_value = 2.0
	mouse_rotation_sensitivity.step = 0.1
	mouse_rotation_sensitivity.ui_tooltip = "Sensitivity for mouse rotation in R mode (pixels to degrees)"
	settings.append(mouse_rotation_sensitivity)
	
	var mouse_scale_sensitivity = SettingMeta.new("mouse_scale_sensitivity", "simple_asset_placer/mouse_scale_sensitivity", 0.01, SettingType.FLOAT, "Mouse Scale Sensitivity")
	mouse_scale_sensitivity.section = "basic"
	mouse_scale_sensitivity.min_value = 0.001
	mouse_scale_sensitivity.max_value = 0.1
	mouse_scale_sensitivity.step = 0.001
	mouse_scale_sensitivity.ui_tooltip = "Sensitivity for mouse scaling in L mode (pixels to scale factor)"
	settings.append(mouse_scale_sensitivity)

	var mouse_sensitivity_curve = SettingMeta.new("mouse_sensitivity_curve", "simple_asset_placer/mouse_sensitivity_curve", "linear", SettingType.OPTION, "Sensitivity Curve")
	mouse_sensitivity_curve.section = "basic"
	mouse_sensitivity_curve.options = ["linear", "ease_in", "ease_out", "ease_in_out"]
	mouse_sensitivity_curve.ui_tooltip = "Shape mouse response when rotating or scaling: Linear = constant, Ease In = slower start, Ease Out = faster start, Ease In-Out = smooth blend."
	settings.append(mouse_sensitivity_curve)
	
	# Mouse sensitivity modifiers
	var fine_sensitivity_multiplier = SettingMeta.new("fine_sensitivity_multiplier", "simple_asset_placer/fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER, SettingType.FLOAT, "Fine Sensitivity Multiplier")
	fine_sensitivity_multiplier.section = "basic"
	fine_sensitivity_multiplier.min_value = 0.01
	fine_sensitivity_multiplier.max_value = 1.0
	fine_sensitivity_multiplier.step = 0.05
	fine_sensitivity_multiplier.ui_tooltip = "Multiplier for mouse sensitivity when CTRL is held in R/L modes (lower = more precise)"
	settings.append(fine_sensitivity_multiplier)
	
	var large_sensitivity_multiplier = SettingMeta.new("large_sensitivity_multiplier", "simple_asset_placer/large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER, SettingType.FLOAT, "Large Sensitivity Multiplier")
	large_sensitivity_multiplier.section = "basic"
	large_sensitivity_multiplier.min_value = 1.0
	large_sensitivity_multiplier.max_value = 10.0
	large_sensitivity_multiplier.step = 0.5
	large_sensitivity_multiplier.ui_tooltip = "Multiplier for mouse sensitivity when ALT is held in R/L modes (higher = faster movement)"
	settings.append(large_sensitivity_multiplier)
	
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
	
	# Rotation Snap Settings
	var snap_rotation_enabled = SettingMeta.new("snap_rotation_enabled", "simple_asset_placer/snap_rotation_enabled", false, SettingType.BOOL, "Enable Rotation Snapping")
	snap_rotation_enabled.section = "advanced_grid"
	snap_rotation_enabled.ui_tooltip = "Snap rotation to grid increments in R mode"
	settings.append(snap_rotation_enabled)
	
	var snap_rotation_step = SettingMeta.new("snap_rotation_step", "simple_asset_placer/snap_rotation_step", 15.0, SettingType.FLOAT, "Rotation Snap Step (degrees)")
	snap_rotation_step.section = "advanced_grid"
	snap_rotation_step.min_value = 1.0
	snap_rotation_step.max_value = 90.0
	snap_rotation_step.step = 1.0
	snap_rotation_step.ui_tooltip = "Rotation snap increment in degrees (e.g., 15° = 24 steps per 360°)"
	settings.append(snap_rotation_step)
	
	# Scale Snap Settings
	var snap_scale_enabled = SettingMeta.new("snap_scale_enabled", "simple_asset_placer/snap_scale_enabled", false, SettingType.BOOL, "Enable Scale Snapping")
	snap_scale_enabled.section = "advanced_grid"
	snap_scale_enabled.ui_tooltip = "Snap scale to grid increments in L mode"
	settings.append(snap_scale_enabled)
	
	var snap_scale_step = SettingMeta.new("snap_scale_step", "simple_asset_placer/snap_scale_step", 0.1, SettingType.FLOAT, "Scale Snap Step")
	snap_scale_step.section = "advanced_grid"
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
	
	# Key Bindings - Modal Control Modes (Blender-style)
	_add_key_binding(settings, "position_control_key", "G", "Position Control Mode (Grab)", "control_modes")
	_add_key_binding(settings, "rotation_control_key", "R", "Rotation Control Mode", "control_modes")
	_add_key_binding(settings, "scale_control_key", "L", "Scale Control Mode", "control_modes")
	
	# Key Bindings - Axis Constraints (used when modal control is active)
	# Note: X/Y/Z keys serve dual purpose:
	# - When G/R/L is pressed: Toggle axis constraints
	# - When G/R/L is NOT pressed: Used for numeric input (rotation)
	_add_key_binding(settings, "rotate_x_key", "X", "X-Axis Constraint/Rotate", "control_modes")
	_add_key_binding(settings, "rotate_y_key", "Y", "Y-Axis Constraint/Rotate", "control_modes")
	_add_key_binding(settings, "rotate_z_key", "Z", "Z-Axis Constraint/Rotate", "control_modes")
	
	# Key Bindings - Quick Height Adjustment (always available)
	_add_key_binding(settings, "height_up_key", "Q", "Raise Height", "height")
	_add_key_binding(settings, "height_down_key", "E", "Lower Height", "height")
	
	# Key Bindings - Modifiers
	_add_key_binding(settings, "reverse_modifier_key", "SHIFT", "Reverse Direction", "modifiers")
	_add_key_binding(settings, "large_increment_modifier_key", "ALT", "Large Increment (2x)", "modifiers")
	_add_key_binding(settings, "fine_increment_modifier_key", "CTRL", "Fine Increment (0.1x)", "modifiers")
	
	# Key Bindings - Control
	_add_key_binding(settings, "cancel_key", "ESCAPE", "Cancel Placement", "control")
	_add_key_binding(settings, "confirm_action_key", "ENTER", "Confirm Placement/Transform", "control")
	_add_key_binding(settings, "transform_mode_key", "TAB", "Transform Mode", "control")
	_add_key_binding(settings, "cycle_placement_mode_key", "P", "Cycle Placement Mode", "control")
	_add_key_binding(settings, "cycle_next_asset_key", "BRACKETRIGHT", "Cycle Next Asset", "control")
	_add_key_binding(settings, "cycle_previous_asset_key", "BRACKETLEFT", "Cycle Previous Asset", "control")
	
	# Increments - Height (Q/E quick adjustments)
	_add_increment(settings, "height_adjustment_step", 0.1, "Height Step", "height", 0.01, 5.0, 0.01)
	_add_increment(settings, "fine_height_increment", 0.01, "Fine Height Step (CTRL)", "height", 0.001, 0.5, 0.001)
	_add_increment(settings, "large_height_increment", 1.0, "Large Height Step (ALT)", "height", 0.5, 10.0, 0.1)
	
	# Increments - Numeric Input (for typed values)
	# These are used when typing numbers after pressing rotation/scale/position keys
	_add_increment(settings, "rotation_increment", 15.0, "Default Rotation (Numeric)", "numeric_input", 1.0, 180.0, 1.0)
	_add_increment(settings, "fine_rotation_increment", 5.0, "Fine Rotation (Numeric)", "numeric_input", 0.1, 45.0, 0.1)
	_add_increment(settings, "large_rotation_increment", 90.0, "Large Rotation (Numeric)", "numeric_input", 15.0, 180.0, 1.0)
	_add_increment(settings, "scale_increment", 0.1, "Default Scale (Numeric)", "numeric_input", 0.01, 1.0, 0.01)
	_add_increment(settings, "fine_scale_increment", 0.01, "Fine Scale (Numeric)", "numeric_input", 0.001, 0.1, 0.001)
	_add_increment(settings, "large_scale_increment", 0.5, "Large Scale (Numeric)", "numeric_input", 0.1, 2.0, 0.1)
	_add_increment(settings, "position_increment", 0.1, "Default Position (Numeric)", "numeric_input", 0.01, 10.0, 0.01)
	_add_increment(settings, "fine_position_increment", 0.01, "Fine Position (Numeric)", "numeric_input", 0.001, 1.0, 0.001)
	_add_increment(settings, "large_position_increment", 1.0, "Large Position (Numeric)", "numeric_input", 0.5, 10.0, 0.1)

	var debug_commands = SettingMeta.new("debug_commands", "simple_asset_placer/debug_commands", false, SettingType.BOOL, "Debug Command Logging")
	debug_commands.section = "debug"
	debug_commands.ui_tooltip = "Emit TransformCommand diagnostics to the console when enabled."
	settings.append(debug_commands)
	
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







