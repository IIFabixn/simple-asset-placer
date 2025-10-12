@tool
extends RefCounted

class_name SessionState

"""
SESSION STATE
=============

PURPOSE: Track mode session lifecycle and per-mode data.

RESPONSIBILITIES:
- Track current mode (NONE, PLACEMENT, TRANSFORM)
- Store per-mode data dictionaries (placement_data, transform_data)
- Track session frame counters
- Store callbacks for mode events
- Manage UI focus state
- Session lifecycle (begin/end)

ARCHITECTURE POSITION: Pure state management
- No mode transition logic (delegates to ModeStateMachine)
- No transform calculations
- Just tracks session-related state

USED BY: TransformState (composition), TransformationCoordinator, ModeStateMachine
"""

const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")

## MODE STATE

var mode: int = 0  # ModeStateMachine.Mode enum value

## PER-MODE DATA

var placement_data: Dictionary = {}  # Placement mode data (mesh, asset_path, etc.)
var transform_data: Dictionary = {}  # Transform mode data (nodes, original_transforms, etc.)

## REFERENCES

var dock_reference = null  # Reference to the dock UI (weak)
var settings: Dictionary = {}  # Current session settings

## SESSION TRACKING

var frames_since_mode_start: int = 0
var focus_grab_frames: int = 0
var ui_focus_locked: bool = false

## CALLBACKS

var placement_end_callback: Callable = Callable()
var mesh_placed_callback: Callable = Callable()

## STATE QUERIES

func is_active() -> bool:
	"""Check if a session is currently active"""
	return mode != 0  # ModeStateMachine.Mode.NONE


func is_in_placement_mode() -> bool:
	"""Check if in placement mode"""
	return mode == 1  # ModeStateMachine.Mode.PLACEMENT


func is_in_transform_mode() -> bool:
	"""Check if in transform mode"""
	return mode == 2  # ModeStateMachine.Mode.TRANSFORM


## SESSION LIFECYCLE

func begin_session(mode_type: int, initial_settings: Dictionary = {}) -> void:
	"""Initialize session for a mode"""
	mode = mode_type
	
	if initial_settings.is_empty():
		settings = {}
	else:
		settings = initial_settings.duplicate(true)
	
	# Clear per-mode payloads for the new session
	placement_data.clear()
	transform_data.clear()
	dock_reference = null
	focus_grab_frames = 0
	ui_focus_locked = false
	frames_since_mode_start = 0


func end_session() -> void:
	"""Clean up session data"""
	mode = 0
	placement_data.clear()
	transform_data.clear()
	settings.clear()
	dock_reference = null
	focus_grab_frames = 0
	ui_focus_locked = false
	frames_since_mode_start = 0
	placement_end_callback = Callable()
	mesh_placed_callback = Callable()


func reset() -> void:
	"""Alias for end_session"""
	end_session()


## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize session state to dictionary (minimal - no callbacks/references)"""
	return {
		"mode": mode,
		"frames_since_mode_start": frames_since_mode_start,
		"focus_grab_frames": focus_grab_frames,
		"ui_focus_locked": ui_focus_locked,
	}


func from_dictionary(data: Dictionary) -> void:
	"""Deserialize session state from dictionary"""
	mode = data.get("mode", 0)
	frames_since_mode_start = data.get("frames_since_mode_start", 0)
	focus_grab_frames = data.get("focus_grab_frames", 0)
	ui_focus_locked = data.get("ui_focus_locked", false)
