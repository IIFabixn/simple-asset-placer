@tool
extends RefCounted

class_name SceneTreeContextMenuManager

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const SceneTreeContextMenu = preload("res://addons/simpleassetplacer/context_menu/scene_tree_context_menu.gd")

var _plugin: EditorPlugin
var _services
var _context_menu: SceneTreeContextMenu

func _init(plugin: EditorPlugin, services) -> void:
	_plugin = plugin
	_services = services


func setup(dock_reference) -> void:
	if _context_menu:
		return

	_context_menu = SceneTreeContextMenu.new()

	if _services and _services.settings_manager:
		_context_menu.set_settings_manager(_services.settings_manager)
	else:
		PluginLogger.warning(
			PluginConstants.COMPONENT_MAIN, "Settings manager not available for context menu"
		)

	if dock_reference:
		_context_menu.set_dock_reference(dock_reference)

	_context_menu.set_plugin_reference(_plugin)

	_plugin.add_context_menu_plugin(
		EditorContextMenuPlugin.ContextMenuSlot.CONTEXT_SLOT_SCENE_TREE,
		_context_menu
	)

	PluginLogger.info(
		PluginConstants.COMPONENT_MAIN,
		"Scene tree context menu setup complete"
	)


func update_dock_reference(dock_reference) -> void:
	if _context_menu and dock_reference:
		_context_menu.set_dock_reference(dock_reference)


func cleanup() -> void:
	if not _context_menu:
		return

	_plugin.remove_context_menu_plugin(_context_menu)
	_context_menu = null
