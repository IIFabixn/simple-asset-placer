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
@onready var transform_mode_button: Button = $TransformModeButton
@onready var reset_transforms_button: Button = $ResetTransformsButton

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
	if transform_mode_button:
		transform_mode_button.toggled.connect(_on_transform_mode_toggled)
	if reset_transforms_button:
		reset_transforms_button.pressed.connect(_on_reset_transforms_pressed)
	
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

func _on_transform_mode_toggled(toggled_on: bool) -> void:
	"""Toggle transform mode"""
	# Import TransformationManager for mode control
	const TransformationManager = preload("res://addons/simpleassetplacer/core/transformation_manager.gd")
	
	if toggled_on:
		# Button was pressed - try to enter transform mode
		# Check if we have selected Node3D objects
		var selection = EditorInterface.get_selection()
		var selected_nodes = selection.get_selected_nodes()
		
		var node3d_nodes = []
		for node in selected_nodes:
			if node is Node3D:
				node3d_nodes.append(node)
		
		if node3d_nodes.is_empty():
			# No Node3D selected - show message and unpress button
			if SettingsManager:
				var OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
				OverlayManager.show_status_message("Select a Node3D to enter Transform Mode", Color.YELLOW, 2.0)
			transform_mode_button.set_pressed_no_signal(false)
			return
		
		# Start transform mode with selected nodes
		TransformationManager.start_transform_mode(node3d_nodes)
	else:
		# Button was unpressed - exit transform mode (confirm changes)
		if TransformationManager.is_transform_mode():
			TransformationManager.exit_transform_mode(true)

func _on_reset_transforms_pressed() -> void:
	"""Reset all transform offsets"""
	# Import managers for reset operations
	const TransformationManager = preload("res://addons/simpleassetplacer/core/transformation_manager.gd")
	const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")
	const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
	const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
	const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
	
	# Only reset if we're in a mode
	if not TransformationManager.is_any_mode_active():
		OverlayManager.show_status_message("No active mode. Enter placement or transform mode first.", Color.YELLOW, 2.0)
		return
	
	# Get the transform state from TransformationManager
	var transform_state = TransformationManager.transform_state
	if not transform_state:
		return
	
	# Reset all transforms
	PositionManager.reset_height(transform_state)
	PositionManager.reset_position(transform_state)
	RotationManager.reset_all_rotation(transform_state)
	ScaleManager.reset_scale(transform_state)
	
	# Show feedback
	OverlayManager.show_status_message("All transforms reset", Color.GREEN, 1.5)

## Button State Updates

func _update_button_states() -> void:
	"""Update all button states from current settings"""
	_update_placement_mode_button()
	_update_grid_snap_button()
	_update_grid_overlay_button()
	_update_random_rotation_button()
	_update_transform_mode_button()
	_update_button_tooltips()
	# Note: Reset button doesn't have state (it's a momentary action)

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

func _update_transform_mode_button() -> void:
	"""Update transform mode button state"""
	if not transform_mode_button:
		return
	
	# Transform mode state will be synced from the main plugin
	# For now, button state defaults to unpressed
	# Icon remains "🔧" - no text update needed

func _update_button_tooltips() -> void:
	"""Update button tooltips with current keybinds from settings"""
	# Read directly from placement_settings_ref for most up-to-date values
	# Fall back to SettingsManager if placement_settings_ref is not available
	var placement_key = "P"
	var transform_key = "TAB"
	
	if placement_settings_ref:
		# Read directly from the PlacementSettings instance (source of truth)
		placement_key = placement_settings_ref.cycle_placement_mode_key
		transform_key = placement_settings_ref.transform_mode_key
	else:
		# Fallback to SettingsManager
		var settings = SettingsManager.get_combined_settings()
		placement_key = settings.get("cycle_placement_mode_key", "P")
		transform_key = settings.get("transform_mode_key", "TAB")
	
	# Update Placement Mode tooltip with actual keybind
	if placement_mode_button:
		placement_mode_button.tooltip_text = "Cycle Placement Strategy (%s)\n🎯 Collision-based\n📐 Plane-based" % placement_key
	
	# Update Transform Mode tooltip with actual keybind
	if transform_mode_button:
		transform_mode_button.tooltip_text = "Transform Mode (%s)\nEdit placed objects\nPosition, Rotation, Scale" % transform_key

func refresh_button_states() -> void:
	"""Public method to refresh button states (called from overlay_manager)"""
	_update_button_states()

## Helper Methods

func set_placement_settings(settings: PlacementSettings) -> void:
	"""Set the PlacementSettings reference (called externally)"""
	# Disconnect old signal if we had a previous reference
	if placement_settings_ref and placement_settings_ref.settings_changed.is_connected(_on_settings_changed):
		placement_settings_ref.settings_changed.disconnect(_on_settings_changed)
	
	placement_settings_ref = settings
	
	# Connect to settings changed signal to update tooltips when keybinds change
	if placement_settings_ref:
		placement_settings_ref.settings_changed.connect(_on_settings_changed)
	
	# Update button states now that we have the reference
	_update_button_states()

func _on_settings_changed() -> void:
	"""Called when settings change - update button states and tooltips"""
	# Defer the update to ensure SettingsManager has loaded the new settings
	call_deferred("_update_button_states")

func set_transform_mode_active(active: bool) -> void:
	"""Update transform mode button state from external source"""
	if transform_mode_button:
		transform_mode_button.set_pressed_no_signal(active)
