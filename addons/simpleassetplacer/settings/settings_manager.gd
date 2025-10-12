@tool
extends RefCounted

class_name SettingsManager

"""
SETTINGS MANAGER (CLEAN INSTANCE-BASED)
========================================

PURPOSE: Centralized settings management with caching and validation

RESPONSIBILITIES:
- Load/save settings from editor and files
- Provide unified settings access interface
- Cache settings for performance
- Validate settings with SettingsValidator
- Track plugin vs dock (UI) settings separately

ARCHITECTURE: Fully instance-based (no static code)
- Created once during plugin initialization via ServiceRegistry
- Injected to components that need settings access
- Pure dependency injection - no singletons

USED BY: All components that need settings access
DEPENDS ON: SettingsStorage, SettingsValidator
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SettingsStorage = preload("res://addons/simpleassetplacer/settings/settings_storage.gd")
const SettingsValidator = preload("res://addons/simpleassetplacer/settings/settings_validator.gd")

# Instance state (no statics!)
var _plugin_settings: Dictionary = {}
var _dock_settings: Dictionary = {}
var _combined_cache: Dictionary = {}
var _cache_dirty: bool = true

## Initialization

func _init() -> void:
	"""Initialize settings manager with defaults from editor"""
	_plugin_settings = SettingsStorage.load_from_editor_settings().duplicate(true)
	_dock_settings = {}
	_combined_cache = {}
	_cache_dirty = true
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager initialized")

## Settings Access

func get_default_settings() -> Dictionary:
	"""Get default plugin settings"""
	return SettingsStorage.get_default_settings().duplicate(true)

func get_combined_settings() -> Dictionary:
	"""Get combined plugin + dock settings (cached)
	
	Dock settings override plugin settings when both have same key.
	Cache is invalidated when settings are modified.
	"""
	if _cache_dirty:
		_rebuild_cache()
	return _combined_cache.duplicate()


func get_setting(key: String, default_value = null):
	"""Get a specific setting value
	
	Priority: dock settings > plugin settings > default value
	"""
	if _dock_settings.has(key):
		return _dock_settings[key]
	
	if _plugin_settings.has(key):
		return _plugin_settings[key]
	
	return default_value

func has_setting(key: String) -> bool:
	"""Check if a setting exists in plugin or dock settings"""
	return _dock_settings.has(key) or _plugin_settings.has(key)

## Settings Modification

func set_plugin_setting(key: String, value) -> void:
	"""Set a plugin setting (permanent)"""
	_plugin_settings[key] = value
	_cache_dirty = true

func set_plugin_settings(settings: Dictionary) -> void:
	"""Update multiple plugin settings at once"""
	for key in settings.keys():
		_plugin_settings[key] = settings[key]
	_cache_dirty = true

func set_dock_setting(key: String, value) -> void:
	"""Set a dock setting (runtime/UI)"""
	_dock_settings[key] = value
	_cache_dirty = true

func set_dock_settings(settings: Dictionary) -> void:
	"""Replace dock settings entirely"""
	_dock_settings = settings.duplicate()
	_cache_dirty = true

func update_dock_settings(settings: Dictionary) -> void:
	"""Merge new dock settings with existing ones"""
	for key in settings.keys():
		_dock_settings[key] = settings[key]
	_cache_dirty = true

## Settings Persistence (EditorSettings is the single source of truth)

func save_plugin_settings_to_editor() -> void:
	"""Save current plugin settings to EditorSettings
	
	This persists settings across Godot sessions.
	UI components should use SettingsPersistence instead.
	"""
	SettingsStorage.save_to_editor_settings(_plugin_settings)
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "Saved plugin settings to EditorSettings")

func reload_from_editor_settings() -> void:
	"""Reload settings from Godot's EditorSettings (single source of truth)"""
	_plugin_settings = SettingsStorage.load_from_editor_settings().duplicate(true)
	_cache_dirty = true
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Reloaded settings from EditorSettings")

## Settings Reset

func reset_to_defaults() -> void:
	"""Reset all settings to defaults"""
	_plugin_settings = get_default_settings()
	_dock_settings = {}
	_cache_dirty = true
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings reset to defaults")

func reset_plugin_settings() -> void:
	"""Reset plugin settings to defaults (keep dock settings)"""
	_plugin_settings = get_default_settings()
	_cache_dirty = true

func clear_dock_settings() -> void:
	"""Clear runtime dock settings"""
	_dock_settings = {}
	_cache_dirty = true

## Cache Management

func invalidate_cache() -> void:
	"""Force cache rebuild on next access"""
	_cache_dirty = true

## Key Binding Helpers

func is_plugin_key(key_string: String) -> bool:
	"""Check if key string matches any plugin keybinding"""
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
		"large_increment_modifier_key",
		"fine_increment_modifier_key",
		"cycle_next_asset_key",
		"cycle_previous_asset_key"
	]
	
	var settings = get_combined_settings()
	for plugin_key in plugin_key_names:
		if settings.get(plugin_key, "") == key_string:
			return true
	
	return false

func get_key_binding(action_name: String) -> String:
	"""Get the key binding for a specific action"""
	return get_setting(action_name, "")

func set_key_binding(action_name: String, key: String) -> void:
	"""Set a key binding for an action"""
	set_plugin_setting(action_name, key)

## Validation

func validate_setting(key: String, value: Variant, auto_clamp: bool = true) -> Dictionary:
	"""Validate a single setting using SettingsValidator
	
	Returns: {valid: bool, error: String, clamped_value: Variant, issues: Array}
	"""
	var report := SettingsValidator.validate_single(key, value, auto_clamp)
	
	if report.has("issues") and report["issues"].size() > 0:
		for issue in report["issues"]:
			var message: String = issue.get("message", "")
			var severity: String = issue.get("severity", SettingsValidator.ISSUE_ERROR)
			if severity == SettingsValidator.ISSUE_ERROR:
				PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Validation: %s" % message)

	return {
		"valid": report.get("valid", true),
		"error": report.get("error", ""),
		"clamped_value": report.get("clamped_value", value),
		"issues": report.get("issues", [])
	}

func validate_and_set_plugin_setting(key: String, value: Variant, auto_clamp: bool = true) -> bool:
	"""Validate and set a plugin setting
	
	Returns: True if value was accepted (possibly after clamping), false otherwise
	"""
	var validation = validate_setting(key, value, auto_clamp)
	
	if validation["valid"]:
		set_plugin_setting(key, validation["clamped_value"])
		return true

	if auto_clamp and validation["clamped_value"] != null:
		set_plugin_setting(key, validation["clamped_value"])
		return true

	return false

func validate_all() -> bool:
	"""Validate all current settings
	
	Returns: True if all settings are valid
	"""
	var combined := get_combined_settings().duplicate(true)
	var result := SettingsValidator.validate(combined, false)
	
	if result.has("issues") and result["issues"].size() > 0:
		for issue in result["issues"]:
			var message: String = issue.get("message", "")
			PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Validation: %s" % message)

	return result.get("is_valid", true)

## Debug & Info

func get_summary() -> Dictionary:
	"""Get summary of settings state for debugging"""
	return {
		"plugin_count": _plugin_settings.size(),
		"dock_count": _dock_settings.size(),
		"combined_count": get_combined_settings().size(),
		"cache_dirty": _cache_dirty,
		"valid": validate_all()
	}

func print_settings() -> void:
	"""Print all settings for debugging"""
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "=== Plugin Settings (%d) ===" % _plugin_settings.size())
	for key in _plugin_settings.keys():
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  %s: %s" % [key, str(_plugin_settings[key])])
	
	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "=== Dock Settings (%d) ===" % _dock_settings.size())
	for key in _dock_settings.keys():
		PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "  %s: %s" % [key, str(_dock_settings[key])])

## Internal

func _rebuild_cache() -> void:
	"""Rebuild the combined settings cache
	
	Priority: plugin settings as base, then override with dock settings
	"""
	_combined_cache = _plugin_settings.duplicate()
	for key in _dock_settings.keys():
		_combined_cache[key] = _dock_settings[key]
	_cache_dirty = false
