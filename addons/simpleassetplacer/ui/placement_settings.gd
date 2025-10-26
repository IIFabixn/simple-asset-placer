@tool
extends Control

class_name PlacementSettings

"""
PLACEMENT SETTINGS (UI COMPONENT)
=================================

PURPOSE: Manages placement mode configuration UI

ARCHITECTURE: Instance-based with dependency injection
- Receives SettingsPersistence and ThumbnailQueueManager via set_* methods
- All service calls use injected instances

USED BY: AssetPlacerDock
DEPENDS ON: SettingsPersistence, ThumbnailQueueManager
"""

# Refactored PlacementSettings - Reduced from 2178 lines to ~300 lines using data-driven architecture

const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_generator.gd")
const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")
const SettingsUIBuilder = preload("res://addons/simpleassetplacer/settings/settings_ui_builder.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

# Dependency injection
var _settings_persistence: SettingsPersistence
var _thumbnail_queue_manager: ThumbnailQueueManager
var _settings_manager: SettingsManager  # ADDED: For reloading EditorSettings changes

signal settings_changed()
signal cache_cleared()

## Dependency Injection

func set_settings_persistence(settings_persistence: SettingsPersistence) -> void:
	"""Inject the settings persistence handler"""
	_settings_persistence = settings_persistence

func set_thumbnail_queue_manager(queue_manager: ThumbnailQueueManager) -> void:
	"""Inject the thumbnail queue manager"""
	_thumbnail_queue_manager = queue_manager

func set_settings_manager(settings_manager: SettingsManager) -> void:
	"""Inject the settings manager"""
	_settings_manager = settings_manager

# UI Controls dictionary - stores all generated controls
var ui_controls: Dictionary = {}

# Key binding capture state
var listening_button: Button = null
var pressed_keys: Array = []
var pressed_modifiers: Dictionary = {"ctrl": false, "alt": false, "shift": false, "meta": false}
var pressed_non_modifier_keys: Array = []

# Settings properties - dynamically loaded from SettingsDefinition
# Basic Settings
var placement_strategy: String = "collision"
var align_with_normal: bool = false
var snap_enabled: bool = false
var snap_step: float = 1.0
var show_grid: bool = false
var grid_extent: float = 20.0
var random_rotation: bool = false
var scale_multiplier: float = 1.0
var smooth_transforms: bool = true
var smooth_transform_speed: float = 8.0
var continuous_placement_enabled: bool = true
var auto_select_placed: bool = true
var cursor_warp_enabled: bool = true

# Advanced Grid Settings
var snap_offset: Vector3 = Vector3.ZERO
var snap_y_enabled: bool = false
var snap_y_step: float = 1.0
var snap_center_x: bool = false
var snap_center_y: bool = false
var snap_center_z: bool = false
var snap_rotation_enabled: bool = false
var snap_rotation_step: float = 15.0
var snap_scale_enabled: bool = false
var snap_scale_step: float = 0.1

# Reset Behavior
var reset_height_on_exit: bool = false
var reset_scale_on_exit: bool = false
var reset_rotation_on_exit: bool = false
var reset_position_on_exit: bool = false

# Rotation Settings
var rotate_y_key: String = "Y"
var rotate_x_key: String = "X"
var rotate_z_key: String = "Z"
var reset_rotation_key: String = "T"
var rotation_increment: float = 15.0
var fine_rotation_increment: float = 5.0
var large_rotation_increment: float = 90.0

# Scale Settings
var scale_up_key: String = "PAGE_UP"
var scale_down_key: String = "PAGE_DOWN"
var scale_reset_key: String = "HOME"
var scale_increment: float = 0.1
var fine_scale_increment: float = 0.01
var large_scale_increment: float = 0.5

# Height Adjustment Settings
var height_up_key: String = "Q"
var height_down_key: String = "E"
var reset_height_key: String = "R"
var height_adjustment_step: float = 0.1
var fine_height_increment: float = 0.01
var large_height_increment: float = 1.0

# Position Adjustment Settings
var position_left_key: String = "A"
var position_right_key: String = "D"
var position_forward_key: String = "W"
var position_backward_key: String = "S"
var reset_position_key: String = "G"
var position_increment: float = 1.0
var fine_position_increment: float = 0.1
var large_position_increment: float = 5.0

# Modifier Key Settings
var reverse_modifier_key: String = "SHIFT"
var large_increment_modifier_key: String = "ALT"
var fine_increment_modifier_key: String = "CTRL"

# Control Settings
var cancel_key: String = "ESCAPE"
var transform_mode_key: String = "TAB"
var cycle_placement_mode_key: String = "P"

# Asset Cycling Settings
var cycle_next_asset_key: String = "BRACKETRIGHT"
var cycle_previous_asset_key: String = "BRACKETLEFT"

# Debug Settings
var debug_commands: bool = false
var log_level: String = "info"

var _placement_service: PlacementStrategyService = null

func set_placement_strategy_service(service: PlacementStrategyService) -> void:
	"""Inject placement strategy service for instance-based operations"""
	_placement_service = service
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()

func _ready():
	# Ensure this control expands to fill available space
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(200, 400)  # Minimum size to ensure visibility
	
	load_settings()
	
	# Defer UI setup to allow proper layout
	call_deferred("setup_ui")

func setup_ui():
	# Create scroll container
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	
	# Create margin container
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(margin)
	
	# Create main vertical container
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	
	# Build entire UI from settings definitions
	var current_settings = _settings_persistence.get_settings_dict(self) if _settings_persistence else {}
	ui_controls = SettingsUIBuilder.build_settings_ui(vbox, self, current_settings)
	
	# Connect all signals
	_connect_all_signals()

func _connect_all_signals():
	# Connect signals for all UI controls
	for control_id in ui_controls:
		var control = ui_controls[control_id]
		
		if control is CheckBox:
			control.toggled.connect(_on_setting_changed)
		elif control is SpinBox:
			control.value_changed.connect(_on_setting_changed)
		elif control is OptionButton:
			control.item_selected.connect(_on_option_selected.bind(control_id))
		elif control is Button:
			# Check if it's a key binding button or utility button
			if control.has_meta("action"):
				match control.get_meta("action"):
					"reset_settings":
						control.pressed.connect(_on_reset_settings_pressed)
					"clear_cache":
						control.pressed.connect(_on_clear_cache_pressed)
			else:
				# It's a key binding button
				control.pressed.connect(_on_key_binding_button_pressed.bind(control, control_id))

func _on_setting_changed(value = null):
	# Read all UI values back to properties
	if _settings_persistence:
		_settings_persistence.read_ui_to_settings(ui_controls, self)
	save_settings()
	
	# Apply logging level change immediately
	_apply_log_level()
	
	settings_changed.emit()

func _apply_log_level():
	"""Apply the current log level to the PluginLogger"""
	const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
	
	match log_level.to_lower():
		"debug":
			PluginLogger.current_level = PluginLogger.LogLevel.DEBUG
		"info":
			PluginLogger.current_level = PluginLogger.LogLevel.INFO
		"warning":
			PluginLogger.current_level = PluginLogger.LogLevel.WARNING
		"error":
			PluginLogger.current_level = PluginLogger.LogLevel.ERROR
		_:
			PluginLogger.current_level = PluginLogger.LogLevel.INFO

func _on_option_selected(index: int, control_id: String):
	# Handle option button selection
	var option_button = ui_controls[control_id] as OptionButton
	if option_button:
		# Get the setting meta to find the options array
		var setting_meta = SettingsDefinition.get_setting_meta(control_id)
		if setting_meta and index < setting_meta.options.size():
			# Set the property value to the selected option string
			set(control_id, setting_meta.options[index])
			save_settings()
			
			# Apply logging level change immediately
			_apply_log_level()
			
			settings_changed.emit()

func _on_key_binding_button_pressed(button: Button, key_property: String):
	listening_button = button
	button.text = "Press any key..."
	button.modulate = Color.YELLOW
	
	# Reset key capture tracking
	pressed_keys.clear()
	pressed_non_modifier_keys.clear()
	pressed_modifiers = {"ctrl": false, "alt": false, "shift": false, "meta": false}
	
	button.set_meta("key_property", key_property)

func _input(event: InputEvent):
	if listening_button == null:
		return
	
	if event is InputEventKey:
		# Allow ESC to cancel
		if event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_key_binding()
			get_viewport().set_input_as_handled()
			return
		
		var key_property = listening_button.get_meta("key_property")
		var is_modifier_key = event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
		var allow_pure_modifiers = key_property in ["reverse_modifier_key", "large_increment_modifier_key", "fine_increment_modifier_key"]
		
		# Record keys on press
		if event.pressed:
			if event.keycode == KEY_CTRL:
				pressed_modifiers["ctrl"] = true
			elif event.keycode == KEY_ALT:
				pressed_modifiers["alt"] = true
			elif event.keycode == KEY_SHIFT:
				pressed_modifiers["shift"] = true
			elif event.keycode == KEY_META:
				pressed_modifiers["meta"] = true
			else:
				if event.keycode not in pressed_non_modifier_keys:
					pressed_non_modifier_keys.append(event.keycode)
			
			if event.keycode not in pressed_keys:
				pressed_keys.append(event.keycode)
			
			get_viewport().set_input_as_handled()
			return
		
		# Handle key release
		if not event.pressed:
			if event.keycode in pressed_keys:
				pressed_keys.erase(event.keycode)
			
			# Check if all keys released
			if pressed_keys.is_empty():
				# Determine final key combination
				var has_non_modifiers = not pressed_non_modifier_keys.is_empty()
				var key_string = ""
				
				if allow_pure_modifiers or has_non_modifiers:
					# Build key string
					var modifiers = []
					if pressed_modifiers["ctrl"]:
						modifiers.append("CTRL")
					if pressed_modifiers["alt"]:
						modifiers.append("ALT")
					if pressed_modifiers["shift"]:
						modifiers.append("SHIFT")
					if pressed_modifiers["meta"]:
						modifiers.append("META")
					
					if has_non_modifiers:
						var primary_key = OS.get_keycode_string(pressed_non_modifier_keys[0])
						if modifiers.is_empty():
							key_string = primary_key
						else:
							key_string = "+".join(modifiers) + "+" + primary_key
					else:
						# Pure modifier (only for allowed properties)
						key_string = modifiers[0] if not modifiers.is_empty() else ""
					
					# Update the property and UI
					if not key_string.is_empty():
						set(key_property, key_string)
						listening_button.text = key_string
						save_settings()
						settings_changed.emit()
				
				# Reset
				listening_button.modulate = Color.WHITE
				listening_button = null
				pressed_keys.clear()
				pressed_non_modifier_keys.clear()
				pressed_modifiers = {"ctrl": false, "alt": false, "shift": false, "meta": false}
				
				get_viewport().set_input_as_handled()

func _cancel_key_binding():
	if listening_button == null:
		return
	
	var key_property = listening_button.get_meta("key_property")
	listening_button.text = get(key_property)
	listening_button.modulate = Color.WHITE
	listening_button = null

func _on_reset_settings_pressed():
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Are you sure you want to reset ALL settings to their default values?\n\nThis will reset:\n• All key bindings\n• All increments and steps\n• All checkboxes and options\n\nThis action cannot be undone."
	confirm_dialog.title = "Reset All Settings"
	confirm_dialog.ok_button_text = "Reset"
	confirm_dialog.cancel_button_text = "Cancel"
	
	add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(_perform_reset_settings)
	confirm_dialog.close_requested.connect(confirm_dialog.queue_free)
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	confirm_dialog.confirmed.connect(confirm_dialog.queue_free)
	confirm_dialog.popup_centered()

func _perform_reset_settings():
	if _settings_persistence:
		_settings_persistence.reset_to_defaults(self)
		_settings_persistence.update_ui_from_settings(ui_controls, self)
	save_settings()
	settings_changed.emit()
	PluginLogger.info("PlacementSettings", "Settings reset to defaults")

func _on_clear_cache_pressed():
	ThumbnailGenerator.clear_cache()
	cache_cleared.emit()

func get_placement_settings() -> Dictionary:
	return _settings_persistence.get_settings_dict(self) if _settings_persistence else {}

func save_settings():
	if _settings_persistence:
		_settings_persistence.save_settings(self)
	
	# CRITICAL FIX: Update SettingsManager so it picks up the new EditorSettings values
	# We need to reload from EditorSettings AND update dock settings to match
	if _settings_manager:
		_settings_manager.reload_from_editor_settings()
		
		# Also update dock settings to match the new plugin settings
		# This ensures dock settings don't override the values we just saved
		var current_settings = _settings_persistence.get_settings_dict(self) if _settings_persistence else {}
		for key in current_settings.keys():
			_settings_manager.set_dock_setting(key, current_settings[key])

func save_settings_without_signal():
	"""Save settings without emitting the settings_changed signal.
	Used when updating UI from programmatic changes to prevent cascading updates."""
	if _settings_persistence:
		_settings_persistence.save_settings(self)

func load_settings():
	if _settings_persistence:
		_settings_persistence.load_settings(self)
		if ui_controls.size() > 0:
			_settings_persistence.update_ui_from_settings(ui_controls, self)
	
	# Apply the loaded log level
	_apply_log_level()
	
	# CRITICAL FIX: Sync loaded settings to SettingsManager's dock settings
	# This ensures that when entering transform mode, SettingsManager.get_combined_settings()
	# returns the correct values from EditorSettings instead of stale dock overrides
	if _settings_manager and _settings_persistence:
		# Reload plugin settings from EditorSettings to ensure they're current
		_settings_manager.reload_from_editor_settings()
		
		# Update dock settings to match what we just loaded
		# This ensures dock settings don't override with stale values
		var current_settings = _settings_persistence.get_settings_dict(self)
		_settings_manager.update_dock_settings(current_settings)

## Public toggle methods for external controls (e.g., status overlay buttons)

func toggle_grid_snap(enabled: bool) -> void:
	"""Toggle grid snapping on/off"""
	snap_enabled = enabled
	if ui_controls.has("snap_enabled"):
		ui_controls["snap_enabled"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func toggle_grid_overlay(enabled: bool) -> void:
	"""Toggle grid overlay visibility"""
	show_grid = enabled
	if ui_controls.has("show_grid"):
		ui_controls["show_grid"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func toggle_random_rotation(enabled: bool) -> void:
	"""Toggle random rotation on placement"""
	random_rotation = enabled
	if ui_controls.has("random_rotation"):
		ui_controls["random_rotation"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func toggle_surface_alignment(enabled: bool) -> void:
	"""Toggle surface alignment (align to surface normal)"""
	align_with_normal = enabled
	if ui_controls.has("align_with_normal"):
		ui_controls["align_with_normal"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func toggle_smooth_transforms(enabled: bool) -> void:
	"""Toggle smooth transform interpolation"""
	smooth_transforms = enabled
	if ui_controls.has("smooth_transforms"):
		ui_controls["smooth_transforms"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func toggle_cursor_warp(enabled: bool) -> void:
	"""Toggle cursor warp preference"""
	cursor_warp_enabled = enabled
	if ui_controls.has("cursor_warp_enabled"):
		ui_controls["cursor_warp_enabled"].set_pressed_no_signal(enabled)
	save_settings()
	settings_changed.emit()

func cycle_placement_strategy() -> String:
	"""Cycle through placement strategies (collision/plane)"""
	# Cycle the strategy
	var new_strategy = _get_service().cycle_strategy()
	
	# Update our property to match
	placement_strategy = new_strategy
	
	# Update the UI control if it exists
	if ui_controls.has("placement_strategy"):
		var option_button = ui_controls["placement_strategy"] as OptionButton
		if option_button:
			# Find the index of the new strategy
			var strategies = ["auto", "collision", "plane"]
			var index = strategies.find(new_strategy)
			if index >= 0:
				option_button.selected = index
	
	# Save and notify
	save_settings()
	settings_changed.emit()
	
	return new_strategy

func _get_service() -> PlacementStrategyService:
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	return _placement_service







