@tool
extends HBoxContainer

class_name ToolbarButtons

## Toolbar Buttons Controller
## Manages the toolbar buttons in the 3D viewport menu
## Provides quick access to placement settings

@onready var placement_mode_button: Button = $PlacementModeButton
@onready var grid_snap_button: Button = $GridSnapButton
@onready var grid_overlay_button: Button = $GridOverlayButton
var surface_align_button: Button
var smooth_transforms_button: Button
var cursor_warp_button: Button
@onready var random_rotation_button: Button = $RandomRotationButton
@onready var transform_mode_button: Button = $TransformModeButton
@onready var reset_transforms_button: Button = $ResetTransformsButton

# Forward reference to managers
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const PlacementSettings = preload("res://addons/simpleassetplacer/ui/placement_settings.gd")
const PositionManager = preload("res://addons/simpleassetplacer/managers/position_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/managers/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const TransformationCoordinator = preload("res://addons/simpleassetplacer/core/transformation_coordinator.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")

# Reference to PlacementSettings (set externally)
var placement_settings_ref: PlacementSettings = null

# Reference to TransformationCoordinator (instance-based)
var _coordinator: TransformationCoordinator = null

# ServiceRegistry instance (injected)
var _services: ServiceRegistry = null
var _placement_service: PlacementStrategyService = null

func set_services(services: ServiceRegistry) -> void:
	"""Inject ServiceRegistry for access to manager instances"""
	_services = services
	if services and services.placement_strategy_service:
		_placement_service = services.placement_strategy_service
	else:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	
	# After services are set, initialize buttons with correct state
	call_deferred("_initialize_buttons")

func _ready() -> void:
	# Initialize button references ONLY - don't set states yet
	_assign_optional_buttons()
	# Don't call _initialize_buttons here - it will be called after services are injected

func _assign_optional_buttons() -> void:
	surface_align_button = get_node_or_null("SurfaceAlignButton") as Button
	smooth_transforms_button = get_node_or_null("SmoothTransformsButton") as Button
	cursor_warp_button = get_node_or_null("CursorWarpButton") as Button

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
		_get_service().cycle_strategy()
		_update_placement_mode_button()

func _on_grid_snap_toggled(toggled_on: bool) -> void:
	"""Toggle grid snapping"""
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_snap(toggled_on)
	
	# Refresh overlay to show updated state
	if _coordinator:
		_coordinator.refresh_overlay()
	
	# Show feedback message if not in active mode
	if _services and _services.overlay_manager:
		if not _coordinator or not _coordinator.is_any_mode_active():
			var status := "Grid snap %s" % ("enabled" if toggled_on else "disabled")
			var color := Color(0.4, 0.85, 0.4) if toggled_on else Color(0.9, 0.45, 0.45)
			_services.overlay_manager.show_status_message(status, color, 1.5)
		_services.overlay_manager.refresh_overlay_buttons()

func _on_grid_overlay_toggled(toggled_on: bool) -> void:
	"""Toggle grid overlay visibility"""
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_grid_overlay(toggled_on)
	
	# Update the overlay manager's grid visibility
	if _services and _services.overlay_manager:
		if toggled_on:
			_services.overlay_manager.show_grid_overlay()
		else:
			_services.overlay_manager.hide_grid_overlay()

func _on_random_rotation_toggled(toggled_on: bool) -> void:
	"""Toggle random Y rotation"""
	# This is a USER click - always apply it
	if placement_settings_ref:
		placement_settings_ref.toggle_random_rotation(toggled_on)
	
	# Refresh overlay to show updated state
	if _coordinator:
		_coordinator.refresh_overlay()
	
	# Show feedback message if not in active mode
	if _services and _services.overlay_manager:
		if not _coordinator or not _coordinator.is_any_mode_active():
			var status := "Random rotation %s" % ("enabled" if toggled_on else "disabled")
			var color := Color(0.4, 0.85, 0.4) if toggled_on else Color(0.9, 0.45, 0.45)
			_services.overlay_manager.show_status_message(status, color, 1.5)
		_services.overlay_manager.refresh_overlay_buttons()

func _on_transform_mode_toggled(toggled_on: bool) -> void:
	"""Toggle transform mode"""
	# This is a USER click - always apply it
	
	if not _coordinator:
		transform_mode_button.set_pressed_no_signal(false)
		return
	
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
			if _services and _services.overlay_manager:
				_services.overlay_manager.show_status_message("Select a Node3D to enter Transform Mode", Color.YELLOW, 2.0)
			transform_mode_button.set_pressed_no_signal(false)
			return
		
		# Start transform mode with selected nodes
		_coordinator.start_transform_mode(node3d_nodes)
	else:
		# Button was unpressed - exit transform mode (confirm changes)
		if _coordinator.is_transform_mode():
			_coordinator.exit_transform_mode(true)

func _on_reset_transforms_pressed() -> void:
	"""Reset all transform offsets"""
	if not _coordinator:
		return
	
	# Only reset if we're in a mode
	if not _coordinator.is_any_mode_active():
		if _services and _services.overlay_manager:
			_services.overlay_manager.show_status_message("No active mode. Enter placement or transform mode first.", Color.YELLOW, 2.0)
		return
	
	# Request reset through coordinator
	_coordinator.reset_transforms()

## Button State Updates

func _update_button_states() -> void:
	"""Update all button states from current settings"""
	_update_placement_mode_button()
	_update_grid_snap_button()
	_update_grid_overlay_button()
	_update_surface_align_button()
	_update_smooth_transforms_button()
	_update_cursor_warp_button()
	_update_random_rotation_button()
	_update_transform_mode_button()
	_update_button_tooltips()
	# Note: Reset button doesn't have state (it's a momentary action)

func _update_surface_align_button() -> void:
	"""Sync surface alignment toggle"""
	if not surface_align_button:
		return
	var enabled := false
	if placement_settings_ref:
		enabled = placement_settings_ref.align_with_normal
	else:
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
		enabled = settings.get("align_with_normal", false)
	if surface_align_button.button_pressed != enabled:
		var was_connected = surface_align_button.toggled.is_connected(_on_surface_align_toggled)
		if was_connected:
			surface_align_button.toggled.disconnect(_on_surface_align_toggled)
		surface_align_button.button_pressed = enabled
		if was_connected:
			surface_align_button.toggled.connect(_on_surface_align_toggled)
	
	# Apply visual styling
	_apply_toggle_button_style(surface_align_button, enabled)

func _update_smooth_transforms_button() -> void:
	"""Sync smooth transforms toggle"""
	if not smooth_transforms_button:
		return
	var enabled := true
	if placement_settings_ref:
		enabled = placement_settings_ref.smooth_transforms
	else:
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
		enabled = settings.get("smooth_transforms", true)
	if smooth_transforms_button.button_pressed != enabled:
		var was_connected = smooth_transforms_button.toggled.is_connected(_on_smooth_transforms_toggled)
		if was_connected:
			smooth_transforms_button.toggled.disconnect(_on_smooth_transforms_toggled)
		smooth_transforms_button.button_pressed = enabled
		if was_connected:
			smooth_transforms_button.toggled.connect(_on_smooth_transforms_toggled)
	
	# Apply visual styling
	_apply_toggle_button_style(smooth_transforms_button, enabled)

func _update_cursor_warp_button() -> void:
	"""Sync cursor warp toggle"""
	if not cursor_warp_button:
		return
	var enabled := true
	if placement_settings_ref:
		enabled = placement_settings_ref.cursor_warp_enabled
	else:
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
		enabled = settings.get("cursor_warp_enabled", true)
	if cursor_warp_button.button_pressed != enabled:
		var was_connected = cursor_warp_button.toggled.is_connected(_on_cursor_warp_toggled)
		if was_connected:
			cursor_warp_button.toggled.disconnect(_on_cursor_warp_toggled)
		cursor_warp_button.button_pressed = enabled
		if was_connected:
			cursor_warp_button.toggled.connect(_on_cursor_warp_toggled)
	
	# Apply visual styling
	_apply_toggle_button_style(cursor_warp_button, enabled)

func _update_placement_mode_button() -> void:
	"""Update placement mode button icon"""
	if not placement_mode_button:
		return
	
	var strategy_type = _get_service().get_active_strategy_type()
	
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
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
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
	
	# Apply visual styling
	_apply_toggle_button_style(grid_snap_button, enabled)

func _update_grid_overlay_button() -> void:
	"""Update grid overlay button state from settings"""
	if not grid_overlay_button:
		return
	
	# Read from PlacementSettings (source of truth), fallback to SettingsManager
	var enabled = true
	if placement_settings_ref:
		enabled = placement_settings_ref.show_grid
	else:
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
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
	
	# Apply visual styling
	_apply_toggle_button_style(grid_overlay_button, enabled)

func _update_random_rotation_button() -> void:
	"""Update random rotation button state from settings"""
	if not random_rotation_button:
		return
	
	# Read from PlacementSettings (source of truth), fallback to SettingsManager
	var enabled = false
	if placement_settings_ref:
		enabled = placement_settings_ref.random_rotation
	else:
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
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
	
	# Apply visual styling
	_apply_toggle_button_style(random_rotation_button, enabled)

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
		var settings = _services.settings_manager.get_combined_settings() if _services else {}
		placement_key = settings.get("cycle_placement_mode_key", "P")
		transform_key = settings.get("transform_mode_key", "TAB")
	
	# Update Placement Mode tooltip with actual keybind
	if placement_mode_button:
		placement_mode_button.tooltip_text = "Cycle Placement Strategy (%s)\n🎯 Collision-based\n📐 Plane-based" % placement_key
	
	# Update Transform Mode tooltip with actual keybind
	if transform_mode_button:
		transform_mode_button.tooltip_text = "Transform Mode (%s)\nEdit placed objects\nPosition, Rotation, Scale" % transform_key

	if surface_align_button:
		surface_align_button.tooltip_text = "Toggle Surface Alignment\nAlign placement rotation to surface normals\nCurrent: %s" % ("On" if surface_align_button.button_pressed else "Off")

	if smooth_transforms_button:
		smooth_transforms_button.tooltip_text = "Toggle Smooth Transforms\nLerp preview and transform updates\nCurrent: %s" % ("On" if smooth_transforms_button.button_pressed else "Off")

	if cursor_warp_button:
		cursor_warp_button.tooltip_text = "Toggle Cursor Warp\nKeep mouse centered during transforms\nCurrent: %s" % ("On" if cursor_warp_button.button_pressed else "Off")

func refresh_button_states() -> void:
	"""Public method to refresh button states (called from overlay_manager)"""
	_update_button_states()

## Helper Methods

func set_transformation_coordinator(coordinator: TransformationCoordinator) -> void:
	"""Set the TransformationCoordinator reference (called externally)"""
	_coordinator = coordinator

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
	if surface_align_button:
		surface_align_button.toggled.connect(_on_surface_align_toggled)
	if smooth_transforms_button:
		smooth_transforms_button.toggled.connect(_on_smooth_transforms_toggled)
	if random_rotation_button:
		random_rotation_button.toggled.connect(_on_random_rotation_toggled)
	if transform_mode_button:
		transform_mode_button.toggled.connect(_on_transform_mode_toggled)
	if reset_transforms_button:
		reset_transforms_button.pressed.connect(_on_reset_transforms_pressed)
	if cursor_warp_button:
		cursor_warp_button.toggled.connect(_on_cursor_warp_toggled)

func _on_surface_align_toggled(toggled_on: bool) -> void:
	"""Toggle surface alignment preference"""
	if placement_settings_ref:
		placement_settings_ref.toggle_surface_alignment(toggled_on)
	else:
		if _services and _services.settings_manager:
			_services.settings_manager.set_dock_setting("align_with_normal", toggled_on)
			_services.settings_manager.set_plugin_setting("align_with_normal", toggled_on)
	
	# Refresh overlay to show updated state
	if _coordinator:
		_coordinator.refresh_overlay()
	
	# Show feedback message if not in active mode
	if _services and _services.overlay_manager:
		if not _coordinator or not _coordinator.is_any_mode_active():
			var status := "Surface align %s" % ("enabled" if toggled_on else "disabled")
			var color := Color(0.4, 0.85, 0.4) if toggled_on else Color(0.9, 0.45, 0.45)
			_services.overlay_manager.show_status_message(status, color, 1.5)
		_services.overlay_manager.refresh_overlay_buttons()

func _on_smooth_transforms_toggled(toggled_on: bool) -> void:
	"""Toggle smooth transform interpolation"""
	if placement_settings_ref:
		placement_settings_ref.toggle_smooth_transforms(toggled_on)
	else:
		if _services and _services.settings_manager:
			_services.settings_manager.set_dock_setting("smooth_transforms", toggled_on)
			_services.settings_manager.set_plugin_setting("smooth_transforms", toggled_on)
	
	# Refresh overlay to show updated state
	if _coordinator:
		_coordinator.refresh_overlay()
	
	# Show feedback message if not in active mode
	if _services and _services.overlay_manager:
		if not _coordinator or not _coordinator.is_any_mode_active():
			var status := "Smooth transforms %s" % ("enabled" if toggled_on else "disabled")
			var color := Color(0.4, 0.85, 0.4) if toggled_on else Color(0.9, 0.45, 0.45)
			_services.overlay_manager.show_status_message(status, color, 1.5)
		_services.overlay_manager.refresh_overlay_buttons()

func _on_cursor_warp_toggled(toggled_on: bool) -> void:
	"""Toggle cursor warp preference"""
	if placement_settings_ref:
		placement_settings_ref.toggle_cursor_warp(toggled_on)
	else:
		if _services and _services.settings_manager:
			_services.settings_manager.set_dock_setting("cursor_warp_enabled", toggled_on)
			_services.settings_manager.set_plugin_setting("cursor_warp_enabled", toggled_on)
	
	# Refresh overlay to show updated state
	if _coordinator:
		_coordinator.refresh_overlay()
	
	if _services and _services.overlay_manager:
		var status := "Cursor warp %s" % ("enabled" if toggled_on else "disabled")
		var color := Color(0.4, 0.85, 0.4) if toggled_on else Color(0.9, 0.45, 0.45)
		_services.overlay_manager.show_status_message(status, color, 1.5)

func _get_service() -> PlacementStrategyService:
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	return _placement_service

func _apply_toggle_button_style(button: Button, active: bool) -> void:
	"""Apply visual styling to a toggle button based on its active state"""
	if not button:
		return
	
	# Create style box for button background
	var style_box = StyleBoxFlat.new()
	if active:
		# Darker background when ON
		style_box.bg_color = Color(0.25, 0.3, 0.35, 0.9)
		style_box.border_color = Color(0.45, 0.55, 0.65, 1.0)
	else:
		# Default/lighter background when OFF
		style_box.bg_color = Color(0.18, 0.18, 0.22, 0.6)
		style_box.border_color = Color(0.3, 0.3, 0.35, 0.7)
	
	style_box.border_width_left = 1
	style_box.border_width_top = 1
	style_box.border_width_right = 1
	style_box.border_width_bottom = 1
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_right = 3
	style_box.corner_radius_bottom_left = 3
	
	# Apply the style to the pressed state
	button.add_theme_stylebox_override("pressed", style_box)
	
	# Also update modulate for visual feedback
	button.modulate = Color(1, 1, 1, 1) if active else Color(0.85, 0.85, 0.85, 0.85)
