@tool
extends RefCounted

class_name SettingsPersistence

"""
SETTINGS PERSISTENCE (INSTANCE-BASED)
==================================

PURPOSE: Handle persistence of settings to/from EditorSettings and UI

ARCHITECTURE: Pure instance-based (no static methods)
- Created once during plugin initialization via ServiceRegistry
- Injected to UI components that need settings I/O
- All methods are instance methods

USED BY: PlacementSettings UI component
DEPENDS ON: SettingsDefinition
"""

const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")

## Initialization

func _init() -> void:
	"""Initialize the settings persistence handler"""
	pass

## Settings Persistence

func save_settings(owner_node: Node) -> void:
	"""Save all settings to EditorSettings"""
	var editor_settings = EditorInterface.get_editor_settings()
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		var value = owner_node.get(setting.id)
		if value != null:
			editor_settings.set_setting(setting.editor_key, value)

func load_settings(owner_node: Node) -> void:
	"""Load all settings from EditorSettings"""
	var editor_settings = EditorInterface.get_editor_settings()
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		if editor_settings.has_setting(setting.editor_key):
			var value = editor_settings.get_setting(setting.editor_key)
			owner_node.set(setting.id, value)
		else:
			# Use default value if setting doesn't exist
			owner_node.set(setting.id, setting.default_value)

func reset_to_defaults(owner_node: Node) -> void:
	"""Reset all settings to defaults"""
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		owner_node.set(setting.id, setting.default_value)

func get_settings_dict(owner_node: Node) -> Dictionary:
	"""Get all settings as a dictionary"""
	var result = {}
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		var value = owner_node.get(setting.id)
		if value != null:
			result[setting.id] = value
	
	return result

## UI Synchronization

func update_ui_from_settings(ui_controls: Dictionary, owner_node: Node) -> void:
	"""Update UI controls from current settings"""
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		if not ui_controls.has(setting.id):
			# Special case for vector3 grid offset
			if setting.id == "snap_offset":
				var offset: Vector3 = owner_node.get(setting.id)
				if ui_controls.has("grid_offset_x"):
					ui_controls["grid_offset_x"].value = offset.x
				if ui_controls.has("grid_offset_z"):
					ui_controls["grid_offset_z"].value = offset.z
			continue
		
		var control = ui_controls[setting.id]
		var value = owner_node.get(setting.id)
		
		match setting.type:
			SettingsDefinition.SettingType.BOOL:
				if control is CheckBox and value != null:
					control.button_pressed = value
			SettingsDefinition.SettingType.FLOAT:
				if control is SpinBox and value != null:
					control.value = value
			SettingsDefinition.SettingType.KEY_BINDING:
				if control is Button and value != null:
					control.text = str(value)
			SettingsDefinition.SettingType.OPTION:
				if control is OptionButton and value != null:
					var selected_index = setting.options.find(value)
					if selected_index >= 0:
						control.selected = selected_index

func read_ui_to_settings(ui_controls: Dictionary, owner_node: Node) -> void:
	"""Read settings from UI controls back to properties"""
	var all_settings = SettingsDefinition.get_all_settings()
	
	for setting in all_settings:
		if not ui_controls.has(setting.id):
			# Special case for vector3 grid offset
			if setting.id == "snap_offset":
				if ui_controls.has("grid_offset_x") and ui_controls.has("grid_offset_z"):
					var current: Vector3 = owner_node.get(setting.id)
					var new_offset = Vector3(
						ui_controls["grid_offset_x"].value,
						current.y,
						ui_controls["grid_offset_z"].value
					)
					owner_node.set(setting.id, new_offset)
			continue
		
		var control = ui_controls[setting.id]
		
		match setting.type:
			SettingsDefinition.SettingType.BOOL:
				if control is CheckBox:
					owner_node.set(setting.id, control.button_pressed)
			SettingsDefinition.SettingType.FLOAT:
				if control is SpinBox:
					owner_node.set(setting.id, control.value)
			SettingsDefinition.SettingType.OPTION:
				if control is OptionButton:
					var selected_index = control.selected
					if selected_index >= 0 and selected_index < setting.options.size():
						owner_node.set(setting.id, setting.options[selected_index])
			SettingsDefinition.SettingType.KEY_BINDING:
				if control is Button:
					owner_node.set(setting.id, control.text)






