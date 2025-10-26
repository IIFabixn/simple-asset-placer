@tool
extends RefCounted

class_name TransformState

"""
UNIFIED TRANSFORM STATE (COMPOSITION PATTERN)
==============================================

PURPOSE: Compose focused state classes into unified interface.

RESPONSIBILITIES:
- Compose TransformValues, SnapConfiguration, SessionState, PlacementConfig
- Provide unified initialization and cleanup
- Delegate to appropriate sub-objects

ARCHITECTURE POSITION: Composition root for transform state
- No duplicate logic (delegates everything)
- Clean separation of concerns
- Each sub-object has single responsibility

REPLACES: 363-line god object with clean composition

USED BY: TransformationCoordinator, all transform managers
"""

# Import sub-components
const TransformValues = preload("res://addons/simpleassetplacer/core/transform_values.gd")
const SnapConfiguration = preload("res://addons/simpleassetplacer/core/snap_configuration.gd")
const SessionState = preload("res://addons/simpleassetplacer/core/session_state.gd")
const PlacementConfig = preload("res://addons/simpleassetplacer/core/placement_config.gd")

## COMPOSED COMPONENTS

var values: TransformValues
var snap: SnapConfiguration
var session: SessionState
var placement: PlacementConfig

## PREVIEW MANAGEMENT (not part of sub-components)

var preview_mesh: Node3D = null  # Active preview mesh node reference
var settings: Dictionary = {}  # Cached settings dictionary
var dock_reference = null  # Reference to dock UI instance

## CONSTRUCTOR

func _init() -> void:
	"""Initialize all sub-components"""
	values = TransformValues.new()
	snap = SnapConfiguration.new()
	session = SessionState.new()
	placement = PlacementConfig.new()


## CONVENIENCE DELEGATE METHODS (most commonly accessed)

# Transform values
func get_final_position() -> Vector3:
	return values.get_final_position()

func get_final_rotation() -> Vector3:
	return values.get_final_rotation()

func get_final_rotation_degrees() -> Vector3:
	return values.get_final_rotation_degrees()

func get_scale_vector() -> Vector3:
	return values.get_scale_vector()

# Session queries
func is_active() -> bool:
	return session.is_active()

func is_in_placement_mode() -> bool:
	return session.is_in_placement_mode()

func is_in_transform_mode() -> bool:
	return session.is_in_transform_mode()

# Preview management
func has_preview() -> bool:
	return preview_mesh != null and is_instance_valid(preview_mesh)

func get_preview_position() -> Vector3:
	if has_preview():
		return preview_mesh.global_position
	return values.position

func get_preview_rotation() -> Vector3:
	if has_preview():
		return preview_mesh.rotation
	return get_final_rotation()

func get_preview_scale() -> Vector3:
	if has_preview():
		return preview_mesh.scale
	return get_scale_vector()


## UNIFIED OPERATIONS

func reset_all() -> void:
	"""Reset all state to defaults (does NOT end session)"""
	values.reset_all()
	# Note: snap and placement config intentionally NOT reset
	# They preserve user settings across operations


func configure_from_settings(settings: Dictionary) -> void:
	"""Configure all sub-components from settings dictionary"""
	snap.configure_from_settings(settings)
	placement.configure_from_settings(settings)


func reset_for_new_placement(reset_height: bool = false, reset_position_offset: bool = false) -> void:
	"""Reset state for new placement with optional selective resets"""
	placement.reset_for_new_placement()
	values.position = Vector3.ZERO
	values.target_position = Vector3.ZERO
	
	if reset_height:
		values.manual_position_offset.y = 0.0
		values.base_position = Vector3.ZERO
	
	if reset_position_offset:
		values.manual_position_offset = Vector3.ZERO


func begin_session(mode_type: int, initial_settings: Dictionary = {}) -> void:
	"""Initialize session for a mode"""
	session.begin_session(mode_type, initial_settings)
	if not initial_settings.is_empty():
		configure_from_settings(initial_settings)
	reset_all()


func end_session() -> void:
	"""Clean up session data"""
	session.end_session()
	preview_mesh = null
	reset_all()


## SERIALIZATION

func to_dictionary() -> Dictionary:
	"""Serialize entire state to dictionary"""
	return {
		"values": values.to_dictionary(),
		"snap": snap.to_dictionary(),
		"session": session.to_dictionary(),
		"placement": placement.to_dictionary(),
	}


func from_dictionary(data: Dictionary) -> void:
	"""Deserialize entire state from dictionary"""
	if data.has("values"):
		values.from_dictionary(data["values"])
	if data.has("snap"):
		snap.from_dictionary(data["snap"])
	if data.has("session"):
		session.from_dictionary(data["session"])
	if data.has("placement"):
		placement.from_dictionary(data["placement"])







