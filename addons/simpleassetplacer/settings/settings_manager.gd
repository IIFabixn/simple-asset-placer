extends Node
class_name SettingsManager

## Settings Manager
## Centralized singleton for managing plugin settings
## Eliminates duplicate() and merge() operations throughout the codebase

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SettingsStorage = preload("res://addons/simpleassetplacer/settings/settings_storage.gd")
const SettingsValidator = preload("res://addons/simpleassetplacer/settings/settings_validator.gd")

## Settings Storage

# Core plugin settings (loaded from file or defaults)
static var _plugin_settings: Dictionary = {}

# Runtime dock settings (UI state)
static var _dock_settings: Dictionary = {}

# Combined cache (plugin + dock) - regenerated when settings change
static var _combined_cache: Dictionary = {}
static var _cache_dirty: bool = true

## Default Settings

static func get_default_settings() -> Dictionary:
	"""Get default plugin settings"""
	return SettingsStorage.get_default_settings().duplicate(true)

## Initialization

static func initialize() -> void:
	"""Initialize settings manager with defaults"""
	_plugin_settings = SettingsStorage.load_from_editor_settings().duplicate(true)
	_dock_settings = {}
	_combined_cache = {}
	_cache_dirty = true

	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager initialized via SettingsStorage")

static func _load_from_editor_settings():
	"""Load plugin settings from Godot's EditorSettings (same source as UI)"""
	_plugin_settings = SettingsStorage.load_from_editor_settings().duplicate(true)
	_cache_dirty = true
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsManager: Plugin settings refreshed from EditorSettings via SettingsStorage")

static func reload_from_editor_settings():
	"""Reload settings from EditorSettings and invalidate cache (for real-time updates)"""
	_load_from_editor_settings()
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager reloaded from EditorSettings")

static func load_from_editor_settings(facade: Object) -> Dictionary:
	"""Load settings from EditorSettings via EditorFacade
	
	Args:
		facade: EditorFacade instance for accessing EditorSettings
		
	Returns:
		Dictionary with smooth transform and transform increment settings
	"""
	var es = facade.get_editor_settings()
	var d := {}
	d["smooth_transforms"] = es.get_setting("simpleassetplacer/smooth_transforms", true)
	d["smooth_transform_speed"] = es.get_setting("simpleassetplacer/smooth_transform_speed", 8.0)
	d["fine_rotation_increment"] = es.get_setting("simpleassetplacer/fine_rotation_increment", 5.0)
	d["large_rotation_increment"] = es.get_setting("simpleassetplacer/large_rotation_increment", 90.0)
	d["fine_scale_increment"] = es.get_setting("simpleassetplacer/fine_scale_increment", 0.01)
	d["large_scale_increment"] = es.get_setting("simpleassetplacer/large_scale_increment", 0.5)
	d["fine_height_increment"] = es.get_setting("simpleassetplacer/fine_height_increment", 0.01)
	return d

static func load_from_file(config_path: String = "user://simpleassetplacer_settings.cfg") -> bool:
	"""Load settings from ConfigFile"""
	var result := SettingsStorage.load_from_file(config_path)
	var loaded_settings: Dictionary = result.get("settings", get_default_settings())
	_plugin_settings = loaded_settings.duplicate(true)
	_cache_dirty = true

	var success: bool = result.get("success", false)
	if success:
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager loaded plugin settings from file: %s" % config_path)
	else:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "SettingsManager fallback to defaults; failed to load %s" % config_path)

	return success

static func save_to_file(config_path: String = "user://simpleassetplacer_settings.cfg") -> bool:
	"""Save settings to ConfigFile"""
	var success := SettingsStorage.save_to_file(_plugin_settings, config_path)
	if success:
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager saved plugin settings to file: %s" % config_path)
	else:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, "SettingsManager failed to persist settings to file: %s" % config_path)
	return success

## Settings Access

static func get_combined_settings() -> Dictionary:
	"""Get combined plugin + dock settings (cached)"""
	if _cache_dirty:
		_rebuild_cache()
	
	return _combined_cache

static func get_setting(key: String, default_value = null):
	"""Get a specific setting value (dock settings override plugin settings)"""
	# Check dock settings first (higher priority)
	if _dock_settings.has(key):
		return _dock_settings[key]
	
	# Fall back to plugin settings
	if _plugin_settings.has(key):
		return _plugin_settings[key]
	
	# Return default if not found
	return default_value

static func has_setting(key: String) -> bool:
	"""Check if a setting exists"""
	return _dock_settings.has(key) or _plugin_settings.has(key)

## Settings Modification

static func set_plugin_setting(key: String, value) -> void:
	"""Set a plugin setting (permanent setting)"""
	_plugin_settings[key] = value
	_cache_dirty = true

static func set_plugin_settings(settings: Dictionary) -> void:
	"""Update multiple plugin settings at once"""
	for key in settings.keys():
		_plugin_settings[key] = settings[key]
	_cache_dirty = true

static func set_dock_setting(key: String, value) -> void:
	"""Set a dock setting (runtime/UI setting)"""
	_dock_settings[key] = value
	_cache_dirty = true

static func set_dock_settings(settings: Dictionary) -> void:
	"""Update dock settings (runtime/UI settings)"""
	# Replace entire dock settings
	_dock_settings = settings.duplicate()
	_cache_dirty = true

static func update_dock_settings(settings: Dictionary) -> void:
	"""Merge new dock settings into existing dock settings"""
	for key in settings.keys():
		_dock_settings[key] = settings[key]
	_cache_dirty = true

## Settings Reset

static func reset_to_defaults() -> void:
	"""Reset all settings to defaults"""
	_plugin_settings = get_default_settings()
	_dock_settings = {}
	_cache_dirty = true
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings reset to defaults")

static func reset_plugin_settings() -> void:
	"""Reset only plugin settings to defaults"""
	_plugin_settings = get_default_settings()
	_cache_dirty = true

static func clear_dock_settings() -> void:
	"""Clear runtime dock settings"""
	_dock_settings = {}
	_cache_dirty = true

## Internal Cache Management

static func _rebuild_cache() -> void:
	"""Rebuild the combined settings cache"""
	_combined_cache = _plugin_settings.duplicate()
	
	# Merge dock settings (dock settings override plugin settings)
	for key in _dock_settings.keys():
		_combined_cache[key] = _dock_settings[key]
	
	_cache_dirty = false

static func invalidate_cache() -> void:
	"""Force cache rebuild on next access"""
	_cache_dirty = true

## Key Binding Helpers

static func is_plugin_key(key_string: String) -> bool:
	"""Check if a key string matches any plugin keybinding"""
	var plugin_key_names = [
		"cancel_key",
		"transform_mode_key", 
		"height_up_key",
		"height_down_key",
		"reset_height_key",
		"position_left_key",
		"position_right_key",
		"position_forward_key",
		"position_backward_key",
		"reset_position_key",
		"rotate_x_key",
		"rotate_y_key", 
		"rotate_z_key",
		"reset_rotation_key",
		"scale_up_key",
		"scale_down_key",
		"scale_reset_key",
		"reverse_modifier_key",
		"large_increment_modifier_key"
	]
	
	var settings = get_combined_settings()
	for plugin_key in plugin_key_names:
		if settings.get(plugin_key, "") == key_string:
			return true
	
	return false

static func get_key_binding(action_name: String) -> String:
	"""Get the key binding for a specific action"""
	return get_setting(action_name, "")

static func set_key_binding(action_name: String, key: String) -> void:
	"""Set a key binding for an action"""
	set_plugin_setting(action_name, key)

## Validation

static func validate_setting(key: String, value: Variant, auto_clamp: bool = true) -> Dictionary:
	"""
	Validate a single setting using SettingsValidator.

	Returns: {valid: bool, error: String, clamped_value: Variant, issues: Array}
	"""
	var report := SettingsValidator.validate_single(key, value, auto_clamp)
	if report.has("issues") and report["issues"].size() > 0:
		for issue in report["issues"]:
			var message: String = issue.get("message", "")
			var severity: String = issue.get("severity", SettingsValidator.ISSUE_ERROR)
			if severity == SettingsValidator.ISSUE_ERROR:
				PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Settings validation: %s" % message)
			else:
				PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "Settings validation warning: %s" % message)

	return {
		"valid": report.get("valid", true),
		"error": report.get("error", ""),
		"clamped_value": report.get("clamped_value", value),
		"issues": report.get("issues", [])
	}

static func validate_and_set_plugin_setting(key: String, value: Variant, auto_clamp: bool = true) -> bool:
	"""
	Validate and set a plugin setting via SettingsValidator.
	
	Returns: True if value was accepted (possibly after clamping), false otherwise.
	"""
	var validation = validate_setting(key, value, auto_clamp)
	if validation["valid"]:
		set_plugin_setting(key, validation["clamped_value"])
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsManager applied setting %s via validator" % key)
		return true

	if auto_clamp and validation["clamped_value"] != null and validation["clamped_value"] != value:
		PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager auto-adjusted %s to %s" % [key, str(validation["clamped_value"])])
		set_plugin_setting(key, validation["clamped_value"])
		return true

	return false

static func validate_settings() -> bool:
	"""Validate current settings via SettingsValidator"""
	var combined := get_combined_settings().duplicate(true)
	var result := SettingsValidator.validate(combined, false)

	if result.has("issues") and result["issues"].size() > 0:
		for issue in result["issues"]:
			var message: String = issue.get("message", "")
			var severity: String = issue.get("severity", SettingsValidator.ISSUE_ERROR)
			if severity == SettingsValidator.ISSUE_ERROR:
				PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Settings validation: %s" % message)
			else:
				PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "Settings validation warning: %s" % message)

	return result.get("is_valid", true)

## Debug

static func print_settings() -> void:
	"""Print current settings for debugging"""
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "=== Plugin Settings ===")
	for key in _plugin_settings.keys():
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  " + key + ": " + str(_plugin_settings[key]))
	
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "=== Dock Settings ===")
	for key in _dock_settings.keys():
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  " + key + ": " + str(_dock_settings[key]))
	
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "=== Combined Settings (Cache) ===")
	var combined = get_combined_settings()
	for key in combined.keys():
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  " + key + ": " + str(combined[key]))

static func get_settings_summary() -> Dictionary:
	"""Get summary of settings state"""
	return {
		"plugin_settings_count": _plugin_settings.size(),
		"dock_settings_count": _dock_settings.size(),
		"combined_settings_count": get_combined_settings().size(),
		"cache_dirty": _cache_dirty,
		"validation_passed": validate_settings()
	}







