@tool
extends RefCounted

class_name ToolbarManager

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const ToolbarButtonsScene = preload("res://addons/simpleassetplacer/ui/toolbar_buttons.tscn")

var _plugin: EditorPlugin
var _services
var _toolbar_buttons: Control
var _dock_manager

func _init(plugin: EditorPlugin, services) -> void:
	_plugin = plugin
	_services = services


func set_dock_manager(dock_manager) -> void:
	_dock_manager = dock_manager


func setup() -> void:
	if _toolbar_buttons:
		return

	if not ToolbarButtonsScene:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "Toolbar scene not found")
		return

	_toolbar_buttons = ToolbarButtonsScene.instantiate()

	if _toolbar_buttons.has_method("set_services"):
		_toolbar_buttons.set_services(_services)

	if _toolbar_buttons.has_method("set_transformation_coordinator") and _services:
		_toolbar_buttons.set_transformation_coordinator(_services.transformation_coordinator)

	_plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_buttons)

	call_deferred("_connect_placement_settings_to_toolbar")

	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Toolbar setup complete")


func cleanup() -> void:
	if _toolbar_buttons:
		_plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_buttons)
		_toolbar_buttons.queue_free()
		_toolbar_buttons = null

	if _services and _services.overlay_manager:
		_services.overlay_manager.set_toolbar_reference(null)

	_dock_manager = null


func set_transform_mode_active(is_active: bool) -> void:
	if _toolbar_buttons and _toolbar_buttons.has_method("set_transform_mode_active"):
		_toolbar_buttons.set_transform_mode_active(is_active)


func _connect_placement_settings_to_toolbar() -> void:
	if (
		not _toolbar_buttons
		or not _services
		or not _services.overlay_manager
	):
		return

	var dock = _dock_manager.get_dock() if _dock_manager else null

	if dock and dock.has_method("get_placement_settings_instance"):
		var placement_settings = dock.get_placement_settings_instance()
		if placement_settings and _toolbar_buttons.has_method("set_placement_settings"):
			_toolbar_buttons.set_placement_settings(placement_settings)
			_services.overlay_manager.set_toolbar_reference(_toolbar_buttons)
			PluginLogger.info(
				PluginConstants.COMPONENT_MAIN,
				"PlacementSettings reference connected to toolbar"
			)
