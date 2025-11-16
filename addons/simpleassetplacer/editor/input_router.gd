@tool
extends RefCounted

class_name InputRouter

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

var _plugin: EditorPlugin
var _services


func _init(plugin: EditorPlugin, services) -> void:
	_plugin = plugin
	_services = services


func update_services(services) -> void:
	_services = services


func handles(object) -> bool:
	var coordinator = _get_coordinator()
	return coordinator != null and coordinator.is_any_mode_active()


func process_input(event: InputEvent) -> void:
	if not _has_core_services():
		return

	var coordinator = _get_coordinator()
	var settings_manager = _get_settings_manager()

	if event is InputEventMouseButton and coordinator.is_any_mode_active():
		if _is_mouse_wheel(event.button_index):
			if coordinator.handle_mouse_wheel_input(event):
				_consume_viewport_event()
				return

	if event is InputEventKey and event.pressed:
		var signature = _extract_key_signature(event)
		if _matches_setting(signature, settings_manager.get_setting("transform_mode_key", "TAB")):
			_consume_transform_key()
		elif _matches_setting(signature, _get_pickup_key()):
			# Pickup is handled later in forward_3d_gui_input to ensure viewport context
			pass
		elif _is_plugin_key(signature):
			_consume_viewport_event()


func process_shortcut(event: InputEvent) -> void:
	if not _has_core_services():
		return

	var coordinator = _get_coordinator()
	var settings_manager = _get_settings_manager()
	if not coordinator:
		return

	if event is InputEventKey and event.pressed:
		var signature = _extract_key_signature(event)
		if _matches_setting(signature, settings_manager.get_setting("transform_mode_key", "TAB")):
			_consume_viewport_event()
			return

		if coordinator.is_any_mode_active() and _is_plugin_key(signature):
			if _matches_setting(signature, _get_pickup_key()):
				return
			_consume_viewport_event()


func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _has_core_services():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var coordinator = _get_coordinator()
	var settings_manager = _get_settings_manager()
	if not coordinator:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var placement_service = _services.placement_strategy_service if _services else null

	if event is InputEventMouseMotion and coordinator.is_any_mode_active():
		coordinator.handle_mouse_motion(viewport_camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and coordinator.is_any_mode_active():
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			if placement_service and placement_service.get_active_strategy_type() == "plane":
				var current_pos = Vector3.ZERO
				if _services.preview_manager:
					current_pos = _services.preview_manager.get_preview_position()
				var plane_name = placement_service.cycle_plane(current_pos, event.position)
				if plane_name:
					PluginLogger.info(PluginConstants.COMPONENT_MAIN, "Plane cycled to: " + plane_name)
				event.set_canceled(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _is_mouse_wheel(event.button_index):
			if coordinator.handle_mouse_wheel_input(event):
				event.set_canceled(true)
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventKey and event.pressed:
		var signature = _extract_key_signature(event)
		if _matches_setting(signature, _get_pickup_key()) and _trigger_pickup_mode():
			_consume_viewport_event()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		if _matches_setting(signature, settings_manager.get_setting("transform_mode_key", "TAB")):
			_consume_viewport_event()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		if not coordinator.is_any_mode_active():
			return EditorPlugin.AFTER_GUI_INPUT_PASS

		if _is_plugin_key(signature):
			_consume_viewport_event()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _has_core_services():
		return false

	var coordinator = _get_coordinator()
	if not coordinator or not coordinator.is_any_mode_active():
		return false

	if event is InputEventKey and event.pressed:
		var signature = _extract_key_signature(event)
		if _is_plugin_key(signature):
			return true

	return false


func cleanup() -> void:
	_services = null


func _has_core_services() -> bool:
	return _services and _get_settings_manager() and _get_coordinator()


func _get_settings_manager():
	return _services.settings_manager if _services else null


func _get_coordinator():
	return _services.transformation_coordinator if _services else null


func _consume_viewport_event() -> void:
	var viewport = _plugin.get_viewport() if _plugin else null
	if viewport:
		viewport.set_input_as_handled()


func _consume_transform_key() -> void:
	var selection = _services.editor_interface.get_selection() if _services else null
	if not selection:
		_consume_viewport_event()
		return

	var selected_nodes = selection.get_selected_nodes()
	for node in selected_nodes:
		if node is Node3D:
			_consume_viewport_event()
			return

	_consume_viewport_event()


func _trigger_pickup_mode() -> bool:
	var selection = _services.editor_interface.get_selection() if _services else null
	if not selection:
		return false

	var selected_nodes = selection.get_selected_nodes()
	if selected_nodes.is_empty():
		return false

	if _plugin and _plugin.has_method("trigger_pickup_mode"):
		_plugin.trigger_pickup_mode(selected_nodes)
	return true


func _is_plugin_key(signature: Dictionary) -> bool:
	var settings_manager = _get_settings_manager()
	if not settings_manager:
		return false

	var settings = settings_manager.get_combined_settings()
	if not settings:
		return false

	var plugin_key_names = [
		"cancel_key",
		"transform_mode_key",
		"pickup_mode_key",
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

	for key_name in plugin_key_names:
		if _matches_setting(signature, settings.get(key_name, "")):
			return true

	return false


func _get_pickup_key() -> String:
	var settings_manager = _get_settings_manager()
	return settings_manager.get_setting("pickup_mode_key", "SHIFT+TAB") if settings_manager else "SHIFT+TAB"


func _extract_key_signature(event: InputEventKey) -> Dictionary:
	var key_string = OS.get_keycode_string(event.keycode).to_upper()
	var modifier_tokens: Array[String] = []
	var is_meta_key = key_string == "META"
	var is_ctrl_key = key_string == "CTRL"
	var is_alt_key = key_string == "ALT"
	var is_shift_key = key_string == "SHIFT"

	if event.meta_pressed and not is_meta_key:
		modifier_tokens.append("META")
	if event.ctrl_pressed and not is_ctrl_key:
		modifier_tokens.append("CTRL")
	if event.alt_pressed and not is_alt_key:
		modifier_tokens.append("ALT")
	if event.shift_pressed and not is_shift_key:
		modifier_tokens.append("SHIFT")

	var has_modifiers = not modifier_tokens.is_empty()
	var parts = modifier_tokens.duplicate()
	parts.append(key_string)

	return {
		"base": key_string,
		"full": "+".join(parts),
		"has_modifiers": has_modifiers,
		"modifiers": {
			"meta": event.meta_pressed,
			"ctrl": event.ctrl_pressed,
			"alt": event.alt_pressed,
			"shift": event.shift_pressed,
		}
	}

func _matches_setting(signature: Dictionary, configured_key: String) -> bool:
	if configured_key == "":
		return false

	var normalized_key = configured_key.to_upper().strip_edges()
	var configured_parts = normalized_key.split("+")
	var configured_has_modifiers = configured_parts.size() > 1

	if configured_has_modifiers:
		return signature.full == normalized_key

	return (not signature.get("has_modifiers", false)) and signature.base == normalized_key


func _is_mouse_wheel(button_index: int) -> bool:
	return (
		button_index == MOUSE_BUTTON_WHEEL_UP
		or button_index == MOUSE_BUTTON_WHEEL_DOWN
	)
