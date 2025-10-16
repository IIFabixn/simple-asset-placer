@tool
extends RefCounted

class_name FrameInputOrchestrator

const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")

var _services
var _owner


func _init(services, owner):
	_services = services
	_owner = owner


func process(session, camera: Camera3D, input_settings: Dictionary, delta: float) -> void:
	if not camera or not is_instance_valid(camera):
		return

	var previous_settings: Dictionary = {}
	if session.settings is Dictionary:
		previous_settings = session.settings.duplicate(true)

	if not input_settings.is_empty():
		session.settings = input_settings.duplicate(true)

	var viewport_3d = _services.editor_facade.get_editor_viewport_3d(0)
	if not viewport_3d:
		return

	_services.input_handler.update_input_state(input_settings, viewport_3d)
	_owner._process_navigation_input()

	var combined_source = SettingsManager.get_combined_settings()
	var combined_settings = combined_source.duplicate(true)
	var settings_changed = previous_settings != combined_settings
	session.settings = combined_settings

	var state_was_null := session.transform_state == null
	var state = session.ensure_state(combined_settings)
	if state and (settings_changed or state_was_null):
		state.configure_from_settings(combined_settings)
	if state:
		_services.position_manager.configure(state, combined_settings)
	_owner._configure_smooth_transforms(combined_settings)

	if session.focus_grab_frames > 0:
		session.focus_grab_frames -= 1
		_owner._grab_3d_viewport_focus()

	var mode = _services.mode_state_machine.get_current_mode()
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			_services.placement_mode_handler.process_input(camera, session.placement_data, state, combined_settings, delta)
			if session.placement_data.get("_confirm_exit", false):
				session.placement_data.erase("_confirm_exit")
				_owner.exit_placement_mode()
				return
		ModeStateMachine.Mode.TRANSFORM:
			_services.transform_mode_handler.process_input(camera, session.transform_data, state, combined_settings, delta)
			if session.transform_data.get("_confirm_exit", false):
				session.transform_data.erase("_confirm_exit")
				_owner.exit_transform_mode(true)
				return

	_services.preview_manager.update_smooth_transforms(delta)
	_services.smooth_transform_manager.update_smooth_transforms(delta)
	if mode != ModeStateMachine.Mode.NONE:
		var placement_center = _services.position_manager.get_base_position(state) if state else Vector3.ZERO
		var target_nodes = session.transform_data.get("target_nodes", []) if mode == ModeStateMachine.Mode.TRANSFORM else []
		_services.grid_manager.update_grid_overlay(mode, combined_settings, state, placement_center, target_nodes)
