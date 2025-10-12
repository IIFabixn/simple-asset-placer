@tool
extends RefCounted

class_name SettingsValidator

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")

const ISSUE_WARNING := "warning"
const ISSUE_ERROR := "error"

const EXTRA_NUMERIC_RULES := {
	"height_adjustment_step": {"min": 0.0001, "max": INF, "fallback": PluginConstants.DEFAULT_HEIGHT_STEP},
	"position_increment": {"min": 0.0001, "max": INF, "fallback": PluginConstants.DEFAULT_POSITION_INCREMENT},
	"rotation_increment": {"min": 0.0001, "max": 360.0, "fallback": PluginConstants.DEFAULT_ROTATION_INCREMENT},
	"scale_increment": {"min": 0.0001, "max": INF, "fallback": PluginConstants.DEFAULT_SCALE_INCREMENT},
	"snap_step": {"min": 0.0001, "max": 1000.0, "fallback": 1.0},
	"snap_rotation_step": {"min": 0.1, "max": 360.0, "fallback": 15.0},
	"snap_scale_step": {"min": 0.0001, "max": 10.0, "fallback": 0.1},
	"preview_opacity": {"min": 0.0, "max": 1.0, "fallback": PluginConstants.DEFAULT_PREVIEW_OPACITY},
	"smooth_transform_speed": {"min": 0.01, "max": 100.0, "fallback": 8.0},
	"fine_rotation_increment": {"min": 0.0001, "max": 360.0, "fallback": PluginConstants.FINE_ROTATION_INCREMENT},
	"large_rotation_increment": {"min": 0.0001, "max": 360.0, "fallback": PluginConstants.LARGE_ROTATION_INCREMENT},
	"fine_scale_increment": {"min": 0.00001, "max": 10.0, "fallback": PluginConstants.FINE_SCALE_INCREMENT},
	"large_scale_increment": {"min": 0.0001, "max": 10.0, "fallback": PluginConstants.LARGE_SCALE_INCREMENT},
	"fine_height_increment": {"min": 0.00001, "max": 10.0, "fallback": PluginConstants.FINE_HEIGHT_INCREMENT},
	"fine_position_increment": {"min": 0.00001, "max": 10.0, "fallback": PluginConstants.FINE_POSITION_INCREMENT},
	"large_position_increment": {"min": 0.0001, "max": 100.0, "fallback": PluginConstants.LARGE_POSITION_INCREMENT},
	"large_height_increment": {"min": 0.0001, "max": 100.0, "fallback": PluginConstants.LARGE_HEIGHT_INCREMENT}
}

const EXTRA_BOOLEAN_KEYS := [
	"randomize_rotation",
	"randomize_scale",
	"show_overlay",
	"continuous_placement_enabled",
	"auto_select_placed",
	"smooth_transforms",
	"snap_enabled",
	"snap_rotation_enabled",
	"snap_scale_enabled",
	"cursor_warp_enabled"
]

const EXTRA_KEY_BINDINGS := [
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
	"cycle_next_asset_key",
	"cycle_previous_asset_key",
	"confirm_action_key",
	"cycle_placement_mode_key"
]

static func validate(settings: Dictionary, auto_clamp: bool = true) -> Dictionary:
	var working := settings.duplicate(true)
	var issues: Array = []
	var mutations: Dictionary = {}

	_validate_definition_settings(working, auto_clamp, issues, mutations)
	_validate_extra_numeric_rules(working, auto_clamp, issues, mutations)
	_validate_extra_boolean_rules(working, auto_clamp, issues, mutations)
	_detect_key_conflicts(working, issues)

	var is_valid := true
	for issue in issues:
		if issue.get("severity", ISSUE_ERROR) == ISSUE_ERROR:
			is_valid = false
			break

	PluginLogger.debug(PluginConstants.COMPONENT_MAIN, "SettingsValidator: validate(auto_clamp=%s) -> issues=%d" % [str(auto_clamp), issues.size()])
	return {
		"is_valid": is_valid,
		"issues": issues,
		"settings": working,
		"mutations": mutations
	}

static func validate_single(key: String, value, auto_clamp: bool = true) -> Dictionary:
	var result := validate({key: value}, auto_clamp)
	var filtered_issues: Array = []
	var valid := true
	var error_message := ""

	for issue in result["issues"]:
		if issue.get("key", "") != key:
			continue

		filtered_issues.append(issue)
		if issue.get("severity", ISSUE_ERROR) == ISSUE_ERROR and error_message == "":
			error_message = issue.get("message", "")
			valid = false

	if filtered_issues.is_empty():
		valid = true
		error_message = ""

	return {
		"valid": valid,
		"error": error_message,
		"clamped_value": result["settings"].get(key, value),
		"issues": filtered_issues
	}

static func _validate_definition_settings(settings: Dictionary, auto_clamp: bool, issues: Array, mutations: Dictionary) -> void:
	for setting_meta in SettingsDefinition.get_all_settings():
		if not settings.has(setting_meta.id):
			continue

		var value = settings[setting_meta.id]
		match setting_meta.type:
			SettingsDefinition.SettingType.BOOL:
				if value is bool:
					continue
				elif auto_clamp and (value is int or value is float):
					settings[setting_meta.id] = bool(value)
					mutations[setting_meta.id] = settings[setting_meta.id]
					issues.append(_issue(setting_meta.id, "Coerced non-boolean value to bool", ISSUE_WARNING, "type"))
				else:
					issues.append(_issue(setting_meta.id, "%s must be a boolean (got %s)" % [setting_meta.id, type_string(typeof(value))], ISSUE_ERROR, "type"))
			SettingsDefinition.SettingType.FLOAT:
				if not (value is float or value is int):
					issues.append(_issue(setting_meta.id, "%s must be numeric (got %s)" % [setting_meta.id, type_string(typeof(value))], ISSUE_ERROR, "type"))
					continue

				var numeric_value := float(value)
				if (value is int) and auto_clamp:
					settings[setting_meta.id] = numeric_value
					mutations[setting_meta.id] = numeric_value

				if numeric_value < setting_meta.min_value or numeric_value > setting_meta.max_value:
					if auto_clamp:
						var clamped_value := clampf(numeric_value, setting_meta.min_value, setting_meta.max_value)
						settings[setting_meta.id] = clamped_value
						mutations[setting_meta.id] = clamped_value
						issues.append(_issue(setting_meta.id, "%s clamped to %s" % [setting_meta.id, str(clamped_value)], ISSUE_WARNING, "range"))
					else:
						issues.append(_issue(setting_meta.id, "%s must be between %s and %s (got %s)" % [setting_meta.id, str(setting_meta.min_value), str(setting_meta.max_value), str(numeric_value)], ISSUE_ERROR, "range"))
			SettingsDefinition.SettingType.KEY_BINDING, SettingsDefinition.SettingType.STRING:
				if value is String:
					continue
				elif auto_clamp:
					settings[setting_meta.id] = str(value)
					mutations[setting_meta.id] = settings[setting_meta.id]
					issues.append(_issue(setting_meta.id, "Coerced value to string", ISSUE_WARNING, "type"))
				else:
					issues.append(_issue(setting_meta.id, "%s must be a string (got %s)" % [setting_meta.id, type_string(typeof(value))], ISSUE_ERROR, "type"))
			SettingsDefinition.SettingType.OPTION:
				if not (value is String):
					if auto_clamp:
						settings[setting_meta.id] = str(value)
						value = settings[setting_meta.id]
						mutations[setting_meta.id] = value
						issues.append(_issue(setting_meta.id, "Coerced option value to string", ISSUE_WARNING, "type"))
					else:
						issues.append(_issue(setting_meta.id, "%s must be a string option (got %s)" % [setting_meta.id, type_string(typeof(value))], ISSUE_ERROR, "type"))
					continue

				if setting_meta.options.size() > 0 and not setting_meta.options.has(value):
					if auto_clamp:
						settings[setting_meta.id] = setting_meta.default_value
						mutations[setting_meta.id] = setting_meta.default_value
						issues.append(_issue(setting_meta.id, "Reset to default option %s" % str(setting_meta.default_value), ISSUE_WARNING, "option"))
					else:
						issues.append(_issue(setting_meta.id, "%s must be one of %s (got %s)" % [setting_meta.id, str(setting_meta.options), str(value)], ISSUE_ERROR, "option"))
			SettingsDefinition.SettingType.VECTOR3:
				if value is Vector3:
					continue
				elif auto_clamp and value is Dictionary:
					var vec := Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
					settings[setting_meta.id] = vec
					mutations[setting_meta.id] = vec
					issues.append(_issue(setting_meta.id, "Converted dictionary to Vector3", ISSUE_WARNING, "type"))
				else:
					issues.append(_issue(setting_meta.id, "%s must be a Vector3 (got %s)" % [setting_meta.id, type_string(typeof(value))], ISSUE_ERROR, "type"))

static func _validate_extra_numeric_rules(settings: Dictionary, auto_clamp: bool, issues: Array, mutations: Dictionary) -> void:
	for key in EXTRA_NUMERIC_RULES.keys():
		if not settings.has(key):
			continue

		var rule = EXTRA_NUMERIC_RULES[key]
		var value = settings[key]
		if not (value is float or value is int):
			issues.append(_issue(key, "%s must be numeric (got %s)" % [key, type_string(typeof(value))], ISSUE_ERROR, "type"))
			continue

		var numeric := float(value)
		if (value is int) and auto_clamp:
			settings[key] = numeric
			mutations[key] = numeric

		var min_value = rule.get("min", -INF)
		var max_value = rule.get("max", INF)
		if numeric < min_value or numeric > max_value:
			if auto_clamp:
				var fallback = rule.get("fallback", clampf(numeric, min_value, max_value))
				var clamped := clampf(numeric, min_value, max_value)
				var replacement = clamped
				if fallback != null and (fallback >= min_value and fallback <= max_value):
					replacement = fallback
				settings[key] = replacement
				mutations[key] = replacement
				issues.append(_issue(key, "%s adjusted to %s" % [key, str(replacement)], ISSUE_WARNING, "range"))
			else:
				issues.append(_issue(key, "%s must be between %s and %s (got %s)" % [key, str(min_value), str(max_value), str(numeric)], ISSUE_ERROR, "range"))

static func _validate_extra_boolean_rules(settings: Dictionary, auto_clamp: bool, issues: Array, mutations: Dictionary) -> void:
	for key in EXTRA_BOOLEAN_KEYS:
		if not settings.has(key):
			continue

		var value = settings[key]
		if value is bool:
			continue
		elif auto_clamp and (value is int or value is float):
			settings[key] = bool(value)
			mutations[key] = settings[key]
			issues.append(_issue(key, "Coerced non-boolean value to bool", ISSUE_WARNING, "type"))
		else:
			issues.append(_issue(key, "%s must be a boolean (got %s)" % [key, type_string(typeof(value))], ISSUE_ERROR, "type"))

static func _detect_key_conflicts(settings: Dictionary, issues: Array) -> void:
	var key_ids: Array = []
	for setting_meta in SettingsDefinition.get_all_settings():
		if setting_meta.type == SettingsDefinition.SettingType.KEY_BINDING:
			key_ids.append(setting_meta.id)

	for extra_id in EXTRA_KEY_BINDINGS:
		if not key_ids.has(extra_id):
			key_ids.append(extra_id)

	var seen: Dictionary = {}
	for key in key_ids:
		if not settings.has(key):
			continue

		var value = settings[key]
		if not (value is String) or value.is_empty():
			continue

		if seen.has(value):
			var previous = seen[value]
			issues.append(_issue(key, "Duplicate key binding: %s (%s and %s)" % [value, key, previous], ISSUE_ERROR, "duplicate"))
		else:
			seen[value] = key

static func _issue(key: String, message: String, severity: String, issue_type: String) -> Dictionary:
	return {
		"key": key,
		"message": message,
		"severity": severity,
		"type": issue_type
	}
