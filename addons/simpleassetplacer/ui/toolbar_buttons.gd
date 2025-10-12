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
	# Initialize button states FIRST before connecting signals (prevents spurious toggle events)
	call_deferred("_initialize_buttons")

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
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_snap(toggled_on)

func _on_grid_overlay_toggled(toggled_on: bool) -> void:
	"""Toggle grid overlay visibility"""
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_overlay(toggled_on)
	
	# Update the overlay manager's grid visibility
	if toggled_on:
		OverlayManager.show_grid_overlay()
	else:
		OverlayManager.hide_grid_overlay()

func _on_random_rotation_toggled(toggled_on: bool) -> void:
	"""Toggle random Y rotation"""
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_random_rotation(toggled_on)

func _on_transform_mode_toggled(toggled_on: bool) -> void:
	"""Toggle transform mode"""
	# This is a USER click - always apply it
	
	# Import TransformationCoordinator for mode control
	const TransformationCoordinator = preload("res://addons/simpleassetplacer/core/transformation_coordinator.gd")
	
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
		TransformationCoordinator.start_transform_mode(node3d_nodes)
	else:
		# Button was unpressed - exit transform mode (confirm changes)
		if TransformationCoordinator.is_transform_mode():
			TransformationCoordinator.exit_transform_mode(true)

func _on_reset_transforms_pressed() -> void:
	"""Reset all transform offsets"""
	# Import managers for reset operations
	const TransformationCoordinator = preload("res://addons/simpleassetplacer/core/transformation_coordinator.gd")
	const PositionManager = preload("res://addons/simpleassetplacer/core/position_manager.gd")
	const RotationManager = preload("res://addons/simpleassetplacer/core/rotation_manager.gd")
	const ScaleManager = preload("res://addons/simpleassetplacer/core/scale_manager.gd")
	const OverlayManager = preload("res://addons/simpleassetplacer/managers/overlay_manager.gd")
	
	# Only reset if we're in a mode
	if not TransformationCoordinator.is_any_mode_active():
		OverlayManager.show_status_message("No active mode. Enter placement or transform mode first.", Color.YELLOW, 2.0)
		return
	
	# Get the transform state from TransformationCoordinator
	var transform_state = TransformationCoordinator.transform_state
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
	"""Update grid snap button state from settings"""
	if not grid_snap_button:
		return
	
	# Read from PlacementSettings (source of truth), fallback to SettingsManager
	var enabled = false
	if placement_settings_ref:
		enabled = placement_settings_ref.snap_enabled
	else:
		var settings = SettingsManager.get_combined_settings()
		enabled = settings.get("snap_enabled", false)
	
	# Only update if the button state doesn't match settings
	if grid_snap_button.button_pressed != enabled:
		# Disconnect signal, update, then reconnect
		var was_connected = grid_snap_button.toggled.is_connected(_on_grid_snap_toggled)
		if was_connected:
			grid_snap_button.toggled.disconnect(_on_grid_snap_toggled)
		
		grid_snap_button.button_pressed = enabled
		
		if was_connected:
			grid_snap_button.toggled.connect(_on_grid_snap_toggled)

func _update_grid_overlay_button() -> void:
	"""Update grid overlay button state from settings"""
	if not grid_overlay_button:
		return
	
	# Read from PlacementSettings (source of truth), fallback to SettingsManager
	var enabled = true
	if placement_settings_ref:
		enabled = placement_settings_ref.show_grid
	else:
		var settings = SettingsManager.get_combined_settings()
		enabled = settings.get("show_grid", true)
	
	# Only update if the button state doesn't match settings
	if grid_overlay_button.button_pressed != enabled:
		# CRITICAL: Disconnect signal, update, then reconnect
		# set_pressed_no_signal() does NOT work for toggle buttons in Godot!
		var was_connected = grid_overlay_button.toggled.is_connected(_on_grid_overlay_toggled)
		if was_connected:
			grid_overlay_button.toggled.disconnect(_on_grid_overlay_toggled)
		
		grid_overlay_button.button_pressed = enabled
		
		if was_connected:
			grid_overlay_button.toggled.connect(_on_grid_overlay_toggled)

func _update_random_rotation_button() -> void:
	"""Update random rotation button state from settings"""
	if not random_rotation_button:
		return
	
	# Read from PlacementSettings (source of truth), fallback to SettingsManager
	var enabled = false
	if placement_settings_ref:
		enabled = placement_settings_ref.random_rotation
	else:
		var settings = SettingsManager.get_combined_settings()
		enabled = settings.get("random_rotation", false)
	
	# Only update if the button state doesn't match settings
	if random_rotation_button.button_pressed != enabled:
		# Disconnect signal, update, then reconnect
		var was_connected = random_rotation_button.toggled.is_connected(_on_random_rotation_toggled)
		if was_connected:
			random_rotation_button.toggled.disconnect(_on_random_rotation_toggled)
		
		random_rotation_button.button_pressed = enabled
		
		if was_connected:
			random_rotation_button.toggled.connect(_on_random_rotation_toggled)

func _update_transform_mode_button() -> void:
	"""Update transform mode button state"""
	if not transform_mode_button:
		return
	
	# Transform mode state will be synced from the main plugin via set_transform_mode_active()
	# No need to update here since it's handled externally
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
	# Defer the update to next frame
	call_deferred("_update_button_states")

func set_transform_mode_active(active: bool) -> void:
	"""Update transform mode button state from external source (e.g., ESC key pressed)"""
	if transform_mode_button:
		# Only update if the button state doesn't match the desired state
		if transform_mode_button.button_pressed != active:
			# Disconnect signal, update, then reconnect
			var was_connected = transform_mode_button.toggled.is_connected(_on_transform_mode_toggled)
			if was_connected:
				transform_mode_button.toggled.disconnect(_on_transform_mode_toggled)
			
			transform_mode_button.button_pressed = active
			
			if was_connected:
				transform_mode_button.toggled.connect(_on_transform_mode_toggled)

func _initialize_buttons() -> void:
	"""Initialize button states then connect signals (prevents spurious events)"""
	# First, set all button states from settings
	_update_button_states()
	
	# THEN connect the signals (this prevents initial state changes from triggering handlers)
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
