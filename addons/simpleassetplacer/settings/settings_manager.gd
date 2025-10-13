extends Node
class_name SettingsManager

## Settings Manager
## Centralized singleton for managing plugin settings
## Eliminates duplicate() and merge() operations throughout the codebase

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const SmoothTransformManager = preload("res://addons/simpleassetplacer/managers/smooth_transform_manager.gd")

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
	return {
		# Key bindings
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
		
		# Asset cycling keys
		"cycle_next_asset_key": "BRACKETRIGHT",  # ] key
		"cycle_previous_asset_key": "BRACKETLEFT",  # [ key
		
		# Placement behavior
		"placement_strategy": "auto",  # New: 'collision', 'plane', or 'auto'
		"snap_to_ground": true,  # Legacy: used when placement_strategy is 'auto'
		"snap_to_grid": false,
		"randomize_rotation": false,
		"randomize_scale": false,
		
		# Visual settings
		"preview_opacity": PluginConstants.DEFAULT_PREVIEW_OPACITY,
		"show_grid": true,
		"show_overlay": true,
		
		# Increment sizes
		"height_step_size": PluginConstants.DEFAULT_HEIGHT_STEP,
		"rotation_increment": PluginConstants.DEFAULT_ROTATION_INCREMENT,
		"scale_increment": PluginConstants.DEFAULT_SCALE_INCREMENT,
		"position_increment": PluginConstants.DEFAULT_POSITION_INCREMENT,
		"grid_size": PluginConstants.DEFAULT_GRID_SIZE,
		
		# Advanced
		"use_surface_normal": true,
		"auto_select_placed": true,
		
		# Reset behavior on exit
		"reset_height_on_exit": false,
		"reset_position_on_exit": false,
		"reset_scale_on_exit": false,
		"reset_rotation_on_exit": false,
		
		# Last used selections (for restoring state)
		"last_meshlib_path": "",
		"last_model_category": "",
		"last_meshlib_category": "",
	}

## Initialization

static func initialize() -> void:
	"""Initialize settings manager with defaults"""
	_plugin_settings = get_default_settings()
	_dock_settings = {}
	_load_from_editor_settings()  # Load from EditorSettings to sync with UI
	_cache_dirty = true
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "SettingsManager initialized")

static func _load_from_editor_settings():
	"""Load plugin settings from Godot's EditorSettings (same source as UI)"""
	var editor_settings = EditorInterface.get_editor_settings()
	
	# Import from settings definitions to ensure we get all UI-configurable settings
	const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting_meta in all_settings:
		if editor_settings.has_setting(setting_meta.editor_key):
			var value = editor_settings.get_setting(setting_meta.editor_key)
			_plugin_settings[setting_meta.id] = value
		# If not found in EditorSettings, keep the default value
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings loaded from EditorSettings")

static func reload_from_editor_settings():
	"""Reload settings from EditorSettings and invalidate cache (for real-time updates)"""
	_load_from_editor_settings()
	_cache_dirty = true
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings reloaded from EditorSettings")

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
	var config = ConfigFile.new()
	var err = config.load(config_path)
	
	if err != OK:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, 
			"Could not load settings from: " + config_path + " (using defaults)")
		_plugin_settings = get_default_settings()
		return false
	
	# Load settings from config file
	_plugin_settings = get_default_settings()  # Start with defaults
	
	for key in _plugin_settings.keys():
		if config.has_section_key("settings", key):
			_plugin_settings[key] = config.get_value("settings", key)
	
	_cache_dirty = true
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings loaded from: " + config_path)
	return true

static func save_to_file(config_path: String = "user://simpleassetplacer_settings.cfg") -> bool:
	"""Save settings to ConfigFile"""
	var config = ConfigFile.new()
	
	# Save all plugin settings
	for key in _plugin_settings.keys():
		config.set_value("settings", key, _plugin_settings[key])
	
	var err = config.save(config_path)
	if err != OK:
		PluginLogger.error(PluginConstants.COMPONENT_MAIN, 
			"Failed to save settings to: " + config_path)
		return false
	
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Settings saved to: " + config_path)
	return true

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

static func validate_setting(key: String, value: Variant) -> Dictionary:
	"""
	Validate a single setting value.
	
	Returns: {valid: bool, error: String, clamped_value: Variant}
	- valid: Whether the value is acceptable
	- error: Human-readable error message (empty if valid)
	- clamped_value: Value clamped to valid range (if applicable)
	"""
	var result = {"valid": true, "error": "", "clamped_value": value}
	
	# Numeric range validation
	match key:
		"height_step_size", "position_increment":
			if value is float or value is int:
				if value <= 0.0:
					result["valid"] = false
					result["error"] = "%s must be greater than 0 (got %s)" % [key, str(value)]
					result["clamped_value"] = 0.1  # Safe minimum
		
		"rotation_increment":
			if value is float or value is int:
				if value <= 0.0:
					result["valid"] = false
					result["error"] = "rotation_increment must be greater than 0 (got %s)" % str(value)
					result["clamped_value"] = 1.0  # Safe minimum
		
		"scale_increment":
			if value is float or value is int:
				if value <= 0.0:
					result["valid"] = false
					result["error"] = "scale_increment must be greater than 0 (got %s)" % str(value)
					result["clamped_value"] = 0.1  # Safe minimum
		
		"grid_size", "snap_step":
			if value is float or value is int:
				if value <= 0.0:
					result["valid"] = false
					result["error"] = "%s must be greater than 0 (got %s)" % [key, str(value)]
					result["clamped_value"] = 1.0  # Safe default
		
		"preview_opacity":
			if value is float or value is int:
				if value < 0.0 or value > 1.0:
					result["valid"] = false
					result["error"] = "preview_opacity must be between 0.0 and 1.0 (got %s)" % str(value)
					result["clamped_value"] = clampf(value, 0.0, 1.0)
		
		"smooth_transform_speed":
			if value is float or value is int:
				if value <= 0.0:
					result["valid"] = false
					result["error"] = "smooth_transform_speed must be greater than 0 (got %s)" % str(value)
					result["clamped_value"] = 1.0  # Safe minimum
				elif value > 100.0:
					result["valid"] = false
					result["error"] = "smooth_transform_speed must be 100 or less (got %s)" % str(value)
					result["clamped_value"] = 100.0  # Safe maximum
	
	return result

static func validate_and_set_plugin_setting(key: String, value: Variant, auto_clamp: bool = true) -> bool:
	"""
	Validate and set a plugin setting.
	
	Args:
		key: Setting key
		value: Setting value
		auto_clamp: If true, automatically clamp invalid values to valid range
	
	Returns: True if value was valid or successfully clamped, False otherwise
	"""
	var validation = validate_setting(key, value)
	
	if validation["valid"]:
		# Value is valid, set it directly
		set_plugin_setting(key, value)
		return true
	else:
		# Value is invalid
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Settings validation: " + validation["error"])
		
		if auto_clamp:
			# Use clamped value
			PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Auto-clamping %s to %s" % [key, str(validation["clamped_value"])])
			set_plugin_setting(key, validation["clamped_value"])
			return true
		else:
			# Reject invalid value
			return false

static func validate_settings() -> bool:
	"""Validate current settings (check for conflicts, invalid values, etc.)"""
	var errors: Array[String] = []
	
	# Check for duplicate key bindings
	var key_bindings: Dictionary = {}
	var key_actions = [
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
		"scale_reset_key"
	]
	
	var settings = get_combined_settings()
	for action in key_actions:
		var key = settings.get(action, "")
		if key != "":
			if key_bindings.has(key):
				errors.append("Duplicate key binding: " + key + " (" + action + " and " + key_bindings[key] + ")")
			else:
				key_bindings[key] = action
	
	# Validate numeric ranges using new validation helpers
	var numeric_settings = [
		"height_step_size",
		"rotation_increment",
		"scale_increment",
		"position_increment",
		"grid_size",
		"snap_step",
		"preview_opacity",
		"smooth_transform_speed"
	]
	
	for setting_key in numeric_settings:
		if settings.has(setting_key):
			var validation = validate_setting(setting_key, settings[setting_key])
			if not validation["valid"]:
				errors.append(validation["error"])
	
	# Validate boolean settings exist and are boolean type
	var boolean_settings = [
		"snap_enabled",
		"snap_to_grid",
		"randomize_rotation",
		"randomize_scale",
		"show_grid",
		"show_overlay",
		"use_surface_normal",
		"auto_select_placed",
		"smooth_transforms"
	]
	
	for setting_key in boolean_settings:
		if settings.has(setting_key):
			var value = settings[setting_key]
			if not (value is bool):
				errors.append("%s must be a boolean (got %s)" % [setting_key, type_string(typeof(value))])
	
	# Log errors
	if errors.size() > 0:
		for error in errors:
			PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Settings validation: " + error)
		return false
	
	return true

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







