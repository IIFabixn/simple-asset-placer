@tool
extends RefCounted

class_name DockManager

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const AssetPlacerDock = preload("res://addons/simpleassetplacer/ui/asset_placer_dock.gd")

var _plugin: EditorPlugin
var _services
var _dock: AssetPlacerDock

func _init(plugin: EditorPlugin, services) -> void:
	_plugin = plugin
	_services = services


func setup() -> void:
	if _dock:
		return

	_dock = AssetPlacerDock.new()
	_dock.name = "Asset Placer"

	if _dock.has_method("set_services"):
		_dock.set_services(_services)

	if _services and _services.category_manager:
		_dock.category_manager = _services.category_manager
		_services.category_manager.load_config_file()

	_dock.asset_selected.connect(Callable(_plugin, "_on_asset_selected"))
	_dock.meshlib_item_selected.connect(Callable(_plugin, "_on_meshlib_item_selected"))

	_plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

	if _services and _services.transformation_coordinator:
		_services.transformation_coordinator.set_dock_reference(_dock)

	call_deferred("_connect_placement_settings_to_overlay")
	call_deferred("_maybe_show_about_tab")
	_schedule_asset_discovery()

	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "Dock setup complete")


func cleanup() -> void:
	if not _dock:
		return

	_plugin.remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null

	if _services and _services.transformation_coordinator:
		_services.transformation_coordinator.set_dock_reference(null)


func get_dock() -> AssetPlacerDock:
	return _dock


func is_ready() -> bool:
	return _dock != null


func _schedule_asset_discovery() -> void:
	if not (_services and _services.category_manager and _dock):
		return

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.1
	_plugin.add_child(timer)
	timer.timeout.connect(
		func():
			if _dock and _dock.has_method("discover_assets"):
				_dock.discover_assets()
			timer.queue_free()
	)
	timer.start()


func _connect_placement_settings_to_overlay() -> void:
	if (
		not _dock
		or not _dock.has_method("get_placement_settings_instance")
		or not _services
		or not _services.overlay_manager
	):
		return

	var placement_settings = _dock.get_placement_settings_instance()
	if placement_settings:
		_services.overlay_manager.set_placement_settings_reference(placement_settings)
		PluginLogger.info(
			PluginConstants.COMPONENT_DOCK,
			"PlacementSettings reference connected to overlay"
		)


func _maybe_show_about_tab() -> void:
	if not _dock or not _dock.has_method("show_about_tab"):
		return

	var editor_settings := _plugin.get_editor_interface().get_editor_settings()
	if not editor_settings:
		return

	const ABOUT_TAB_SEEN_KEY := "simpleassetplacer/ui/about_tab_seen"

	if editor_settings.has_setting(ABOUT_TAB_SEEN_KEY) and editor_settings.get_setting(ABOUT_TAB_SEEN_KEY):
		return

	_dock.call_deferred("show_about_tab")

	if (not editor_settings.has_setting(ABOUT_TAB_SEEN_KEY)) or not editor_settings.get_setting(ABOUT_TAB_SEEN_KEY):
		editor_settings.set_setting(ABOUT_TAB_SEEN_KEY, true)
		if editor_settings.has_method("save"):
			editor_settings.save()

	PluginLogger.info(PluginConstants.COMPONENT_DOCK, "About tab displayed for first-time setup")
