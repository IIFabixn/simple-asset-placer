@tool
extends RefCounted

class_name SettingsStorage

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")

static func get_default_settings() -> Dictionary:
	var defaults: Dictionary = {
		"cancel_key": "ESCAPE",
		"transform_mode_key": "TAB",
		"height_up_key": "Q",
		"height_down_key": "E",
		"reset_height_key": "R",
		"position_left_key": "A",
		"position_right_key": "D",
		"position_forward_key": "W",
		"position_backward_key": "S",
		"reset_position_key": "C",
		"rotate_x_key": "X",
		"rotate_y_key": "Y",
		"rotate_z_key": "Z",
		"reset_rotation_key": "T",
		"scale_up_key": "PAGE_UP",
		"scale_down_key": "PAGE_DOWN",
		"scale_reset_key": "HOME",
		"reverse_modifier_key": "SHIFT",
		"large_increment_modifier_key": "CTRL",
		"cycle_next_asset_key": "BRACKETRIGHT",
		"cycle_previous_asset_key": "BRACKETLEFT",
		"placement_strategy": "collision",
		"snap_to_grid": false,
		"randomize_rotation": false,
		"randomize_scale": false,
		"preview_opacity": PluginConstants.DEFAULT_PREVIEW_OPACITY,
		"show_grid": true,
		"show_overlay": true,
		"height_step_size": PluginConstants.DEFAULT_HEIGHT_STEP,
		"rotation_increment": PluginConstants.DEFAULT_ROTATION_INCREMENT,
		"scale_increment": PluginConstants.DEFAULT_SCALE_INCREMENT,
		"position_increment": PluginConstants.DEFAULT_POSITION_INCREMENT,
		"grid_size": PluginConstants.DEFAULT_GRID_SIZE,
		"use_surface_normal": true,
		"auto_select_placed": true,
		"auto_modal_activation": false,
		"reset_height_on_exit": false,
		"reset_position_on_exit": false,
		"reset_scale_on_exit": false,
		"reset_rotation_on_exit": false,
		"last_meshlib_path": "",
		"last_model_category": "",
		"last_meshlib_category": "",
		"snap_enabled": false,
		"snap_step": 1.0,
		"snap_rotation_enabled": false,
		"snap_rotation_step": 15.0,
		"snap_scale_enabled": false,
		"snap_scale_step": 0.1,
		"smooth_transforms": true,
		"smooth_transform_speed": 8.0,
		"fine_rotation_increment": 5.0,
		"large_rotation_increment": 90.0,
		"fine_scale_increment": 0.01,
		"large_scale_increment": 0.5,
		"fine_height_increment": 0.01,
		"fine_position_increment": 0.01,
		"large_position_increment": 1.0,
		"large_height_increment": 1.0,
		"cursor_warp_enabled": true,
		"mouse_sensitivity_curve": "linear",
		"fine_sensitivity_multiplier": PluginConstants.FINE_SENSITIVITY_MULTIPLIER,
		"large_sensitivity_multiplier": PluginConstants.LARGE_SENSITIVITY_MULTIPLIER,
		"debug_commands": false
	}

	for setting_meta in SettingsDefinition.get_all_settings():
		if not defaults.has(setting_meta.id):
			defaults[setting_meta.id] = setting_meta.default_value

	return defaults

static func load_from_editor_settings() -> Dictionary:
	var settings := get_default_settings()
	var editor_settings := EditorInterface.get_editor_settings()

	for setting_meta in SettingsDefinition.get_all_settings():
		if editor_settings.has_setting(setting_meta.editor_key):
			settings[setting_meta.id] = editor_settings.get_setting(setting_meta.editor_key)

	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsStorage: Loaded settings from EditorSettings")
	return settings

static func load_from_file(config_path: String = "user://simpleassetplacer_settings.cfg") -> Dictionary:
	var settings := get_default_settings()
	var config := ConfigFile.new()
	var err := config.load(config_path)

	if err != OK:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "SettingsStorage: Could not load settings from %s (code %d), using defaults" % [config_path, err])
		return {
			"settings": settings,
			"success": false
		}

	if config.has_section("settings"):
		for key in config.get_section_keys("settings"):
			settings[key] = config.get_value("settings", key)

	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsStorage: Loaded settings from %s" % config_path)
	return {
		"settings": settings,
		"success": true
	}

static func save_to_file(settings: Dictionary, config_path: String = "user://simpleassetplacer_settings.cfg") -> bool:
	var config := ConfigFile.new()

	for key in settings.keys():
		config.set_value("settings", key, settings[key])

	var err := config.save(config_path)
	if err != OK:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "SettingsStorage: Failed to save settings to %s (code %d)" % [config_path, err])
		return false

	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsStorage: Saved settings to %s" % config_path)
	return true
