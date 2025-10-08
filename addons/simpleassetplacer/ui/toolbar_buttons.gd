@tool
extends HBoxContainer

class_name ToolbarButtons

## Toolbar Buttons Controller
## Manages the toolbar buttons in the 3D viewport menu
## Provides quick access to placement settings

@onready var placement_mode_button: Button = $PlacementModeButton
@onready var grid_snap_button: Button = $GridSnapButton
@onready var grid_overlay_button: Button = $GridOverlayButton
@onready var random_rotation_button: Button = $RandomRotationButton

# Forward reference to managers
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const PlacementSettings = preload("res://addons/simpleassetplacer/ui/placement_settings.gd")
const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")

# Reference to PlacementSettings (set externally)
var placement_settings_ref: PlacementSettings = null

func _ready() -> void:
	# Connect button signals
	if placement_mode_button:
		placement_mode_button.pressed.connect(_on_placement_mode_pressed)
	if grid_snap_button:
		grid_snap_button.toggled.connect(_on_grid_snap_toggled)
	if grid_overlay_button:
		grid_overlay_button.toggled.connect(_on_grid_overlay_toggled)
	if random_rotation_button:
		random_rotation_button.toggled.connect(_on_random_rotation_toggled)
	
	# Initialize button states from current settings (deferred to ensure managers are ready)
	call_deferred("_update_button_states")

## Button Handlers

func _on_placement_mode_pressed() -> void:
	"""Cycle through placement strategies"""
	# Let PlacementSettings handle the cycling and persistence
	if placement_settings_ref:
		var new_strategy = placement_settings_ref.cycle_placement_strategy()
		# Update button icon based on strategy
		_update_placement_mode_button()
	else:
		# Fallback if reference not set
		PlacementStrategyManager.cycle_strategy()
		_update_placement_mode_button()

func _on_grid_snap_toggled(toggled_on: bool) -> void:
	"""Toggle grid snapping"""
	# Let PlacementSettings handle everything
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_snap(toggled_on)

func _on_grid_overlay_toggled(toggled_on: bool) -> void:
	"""Toggle grid overlay visibility"""
	# Let PlacementSettings handle everything
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_overlay(toggled_on)
	
	# Update the overlay manager's grid visibility
	if toggled_on:
		OverlayManager.show_grid_overlay()
	else:
		OverlayManager.hide_grid_overlay()

func _on_random_rotation_toggled(toggled_on: bool) -> void:
	"""Toggle random Y rotation on placement"""
	# Let PlacementSettings handle everything
	if placement_settings_ref:
		placement_settings_ref.toggle_random_rotation(toggled_on)

## Button State Updates

func _update_button_states() -> void:
	"""Update all button states from current settings"""
	_update_placement_mode_button()
	_update_grid_snap_button()
	_update_grid_overlay_button()
	_update_random_rotation_button()

func _update_placement_mode_button() -> void:
	"""Update placement mode button icon"""
	if not placement_mode_button:
		return
	
	var strategy_type = PlacementStrategyManager.get_active_strategy_type()
	
	# Update icon based on strategy type
	if strategy_type == "collision":
		placement_mode_button.text = "🎯"
	else:
		placement_mode_button.text = "📐"

func _update_grid_snap_button() -> void:
	"""Update grid snap button state"""
	if not grid_snap_button:
		return
	
	var settings = SettingsManager.get_combined_settings()
	var enabled = settings.get("snap_enabled", false)
	
	grid_snap_button.set_pressed_no_signal(enabled)  # Don't trigger toggled signal
	# Icon remains "📏" - no text update needed

func _update_grid_overlay_button() -> void:
	"""Update grid overlay button state"""
	if not grid_overlay_button:
		return
	
	var settings = SettingsManager.get_combined_settings()
	var enabled = settings.get("show_grid", true)
	
	grid_overlay_button.set_pressed_no_signal(enabled)  # Don't trigger toggled signal
	# Icon remains "🔲" - no text update needed

func _update_random_rotation_button() -> void:
	"""Update random rotation button state"""
	if not random_rotation_button:
		return
	
	var settings = SettingsManager.get_combined_settings()
	var enabled = settings.get("randomize_rotation", false)
	
	random_rotation_button.set_pressed_no_signal(enabled)  # Don't trigger toggled signal
	# Icon remains "🔄" - no text update needed

func refresh_button_states() -> void:
	"""Public method to refresh button states (called from overlay_manager)"""
	_update_button_states()

## Helper Methods

func set_placement_settings(settings: PlacementSettings) -> void:
	"""Set the PlacementSettings reference (called externally)"""
	placement_settings_ref = settings
	# Update button states now that we have the reference
	_update_button_states()
