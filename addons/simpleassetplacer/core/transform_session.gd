@tool
extends RefCounted

class_name TransformSession

const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")

# Indicates which high-level workflow is currently active.
var mode: int = ModeStateMachine.Mode.NONE

# Shared state object used by placement/transform workflows.
var transform_state: TransformState = null

# Ad-hoc payloads maintained by the individual mode handlers.
var placement_data: Dictionary = {}
var transform_data: Dictionary = {}

# Cached settings snapshot used when the session started or was last updated.
var settings: Dictionary = {}

# UI references that need to follow the active session.
var dock_reference = null

# Optional callbacks for lifecycle notifications.
var placement_end_callback: Callable = Callable()
var mesh_placed_callback: Callable = Callable()

# Remaining frames we should force focus on the 3D viewport.
var focus_grab_frames: int = 0

# True when an editor UI control currently owns focus and should suppress
# viewport shortcut processing.
var ui_focus_locked: bool = false


func is_active() -> bool:
	return mode != ModeStateMachine.Mode.NONE


func reset() -> void:
	mode = ModeStateMachine.Mode.NONE
	transform_state = null
	placement_data.clear()
	transform_data.clear()
	settings.clear()
	dock_reference = null
	focus_grab_frames = 0
	ui_focus_locked = false


func begin(mode_type: int, initial_settings: Dictionary = {}) -> void:
	mode = mode_type
	if initial_settings.is_empty():
		settings = {}
	else:
		settings = initial_settings.duplicate(true)
	transform_state = TransformState.new()
	if not settings.is_empty():
		transform_state.configure_from_settings(settings)
	# Clear per-mode payloads for the new run.
	placement_data.clear()
	transform_data.clear()
	dock_reference = null
	focus_grab_frames = 0
	ui_focus_locked = false


func ensure_state(initial_settings: Dictionary = {}) -> TransformState:
	if not transform_state:
		transform_state = TransformState.new()
		var config_source = initial_settings
		if config_source.is_empty() and not settings.is_empty():
			config_source = settings
		if not config_source.is_empty():
			transform_state.configure_from_settings(config_source)
	return transform_state
