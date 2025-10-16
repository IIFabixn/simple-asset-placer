@tool
extends CanvasLayer

class_name StatusOverlayControl

## Status Overlay Controller
## Manages the status overlay UI scene
## Replaces the programmatic UI creation in overlay_manager.gd

@onready var status_panel: Panel = $OverlayControl/StatusPanel
@onready var content_vbox: VBoxContainer = $OverlayControl/StatusPanel/ContentVBox

# Title HBox labels
@onready var mode_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/ModeLabel
@onready var node_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/NodeLabel
@onready var strategy_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/StrategyLabel

# Transform HBox labels
@onready var position_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/PositionLabel
@onready var rotation_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/RotationLabel
@onready var scale_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/ScaleLabel

# State badges (optional nodes to maintain backward compatibility)
var grid_badge_label: Label
var y_snap_badge_label: Label
var rotation_snap_badge_label: Label
var scale_snap_badge_label: Label
var half_step_badge_label: Label
var surface_align_badge_label: Label
var smooth_badge_label: Label

# Modifier badges
var fine_modifier_label: Label
var large_modifier_label: Label
var reverse_modifier_label: Label

# Numeric input display
var numeric_container: HBoxContainer
var numeric_glyph_label: Label
var numeric_action_label: Label
var numeric_value_label: Label

# Keybinds label
@onready var keybinds_label: Label = $OverlayControl/StatusPanel/ContentVBox/KeybindsLabel

# Forward reference to ModeStateMachine for Mode enum
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

var _placement_service: PlacementStrategyService = null
var _services
var _panel_bottom_margin: float = 12.0
var _panel_vertical_padding: float = 16.0

func set_placement_strategy_service(service: PlacementStrategyService) -> void:
	"""Inject placement strategy service so overlay mirrors live state"""
	_placement_service = service
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()

func set_services(services) -> void:
	_services = services

func _ready() -> void:
	# Ensure proper setup
	visible = false
	
	# Set panel to pass mouse events through (no buttons to interact with anymore)
	if status_panel:
		status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel_bottom_margin = abs(status_panel.offset_bottom)
	if node_label:
		node_label.clip_text = true
	if strategy_label:
		strategy_label.clip_text = true
	
	var overlay_control = get_node_or_null("OverlayControl")
	if overlay_control:
		overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_assign_optional_nodes()
	_cache_panel_padding()
	_refresh_panel_size_deferred()

	if numeric_container:
		numeric_container.visible = false

func _assign_optional_nodes() -> void:
	grid_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/GridBadgeLabel") as Label
	y_snap_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/YSnapBadgeLabel") as Label
	rotation_snap_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/RotationSnapBadgeLabel") as Label
	scale_snap_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/ScaleSnapBadgeLabel") as Label
	half_step_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/HalfStepBadgeLabel") as Label
	surface_align_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/SurfaceAlignBadgeLabel") as Label
	smooth_badge_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/StateBadgeHBox/SmoothBadgeLabel") as Label

	fine_modifier_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/ModifierBadgeHBox/FineModifierLabel") as Label
	large_modifier_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/ModifierBadgeHBox/LargeModifierLabel") as Label
	reverse_modifier_label = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/ModifierBadgeHBox/ReverseModifierLabel") as Label

	numeric_container = get_node_or_null("OverlayControl/StatusPanel/ContentVBox/NumericHBox") as HBoxContainer
	if numeric_container:
		numeric_glyph_label = numeric_container.get_node_or_null("NumericGlyphLabel") as Label
		numeric_action_label = numeric_container.get_node_or_null("NumericActionLabel") as Label
		numeric_value_label = numeric_container.get_node_or_null("NumericValueLabel") as Label

func show_transform_info(mode: int, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale_value: float = 1.0, height_offset: float = 0.0, control_mode_state = null, extra_state: Dictionary = {}) -> void:
	"""Show unified transform overlay with all current transformation data
	
	Args:
		mode: Base mode (PLACEMENT or TRANSFORM)
		node_name: Name of the node being transformed
		position: Current position
		rotation: Current rotation in radians
		scale_value: Current scale multiplier
		height_offset: Current height offset
		control_mode_state: ControlModeState instance for displaying G/R/L mode and axis constraints
	"""
	if not mode_label or not position_label:
		return
	
	# Get current placement strategy for display
	var strategy_service = _get_service()
	var strategy_type = strategy_service.get_active_strategy_type()
	var strategy_name = strategy_service.get_active_strategy_name()
	var strategy_icon = "🎯" if strategy_type == "collision" else "📐"
	
	# Get control mode info if available - ONLY show when modal is actually active
	var control_mode_text = ""
	var axis_constraint_text = ""
	if control_mode_state and control_mode_state.is_modal_active():
		var ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
		match control_mode_state.get_control_mode():
			ControlModeState.ControlMode.POSITION:
				control_mode_text = " [G:Position]"
			ControlModeState.ControlMode.ROTATION:
				control_mode_text = " [R:Rotation]"
			ControlModeState.ControlMode.SCALE:
				control_mode_text = " [L:Scale]"
		
		if control_mode_state.has_axis_constraint():
			axis_constraint_text = " | Axis: " + control_mode_state.get_axis_constraint_string()
	
	# Update mode label and color
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			mode_label.text = "🎯 PLACEMENT MODE" + control_mode_text + axis_constraint_text
			mode_label.add_theme_color_override("font_color", Color.YELLOW)
		ModeStateMachine.Mode.TRANSFORM:
			mode_label.text = "⚙️ TRANSFORM MODE" + control_mode_text + axis_constraint_text
			mode_label.add_theme_color_override("font_color", Color.CYAN)
		_:
			mode_label.text = "🔧 Asset Placer Active" + control_mode_text + axis_constraint_text
			mode_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Update node name label
	if node_label:
		if node_name != "":
			node_label.text = "- " + node_name
			node_label.visible = true
		else:
			node_label.text = ""
			node_label.visible = false
	
	# Update strategy label
	if strategy_label:
		strategy_label.text = strategy_icon + " " + strategy_name
	
	# Update transform values
	if position_label:
		position_label.text = "Pos: X: %.2f  Y: %.2f  Z: %.2f" % [position.x, position.y, position.z]
	
	if rotation_label:
		rotation_label.text = "Rot: X: %.1f°  Y: %.1f°  Z: %.1f°" % [rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z)]
	
	if scale_label:
		scale_label.text = "Scale: %.2fx" % scale_value
	
	# Update keybinds
	if keybinds_label:
		if height_offset != 0.0:
			keybinds_label.text = "Height Offset: %.2f" % height_offset
		else:
			# Get actual keybinds from settings
			var settings = SettingsManager.get_combined_settings()
			var g_key = settings.get("position_control_key", "G")
			var r_key = settings.get("rotation_control_key", "R")
			var l_key = settings.get("scale_control_key", "L")
			var height_up = settings.get("height_up_key", "Q")
			var height_down = settings.get("height_down_key", "E")
			var reverse_key = settings.get("reverse_modifier_key", "SHIFT")
			var fine_key = settings.get("fine_increment_modifier_key", "CTRL")
			var large_key = settings.get("large_increment_modifier_key", "ALT")
			var wheel_hint = "Mouse Wheel (Adjust; %s reverse, %s fine, %s large)" % [reverse_key, fine_key, large_key]
			
			# Show modal control keybinds
			if mode == ModeStateMachine.Mode.PLACEMENT:
				keybinds_label.text = "%s (Position)  %s (Rotation)  %s (Scale)\n%s/%s (Quick Height)  X/Y/Z (Axis)  %s  ENTER (Place)" % [g_key, r_key, l_key, height_up, height_down, wheel_hint]
			else:  # transform mode
				keybinds_label.text = "%s (Position)  %s (Rotation)  %s (Scale)\n%s/%s (Quick Height)  X/Y/Z (Axis)  %s  ENTER (Confirm)" % [g_key, r_key, l_key, height_up, height_down, wheel_hint]

	_update_snap_badges(extra_state.get("snap_state", {}), extra_state.get("smooth_enabled", false))
	_update_modifier_badges(extra_state.get("modifier_state", {}))
	_update_numeric_state_from_extra(extra_state.get("numeric_state", {}))
	
	visible = true
	_refresh_panel_size_deferred()

func _get_service() -> PlacementStrategyService:
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()
	return _placement_service

func show_status_message(message: String, color: Color = Color.GREEN) -> void:
	"""Show a simple status message"""
	if not mode_label:
		return
	
	# Update mode label with message
	mode_label.text = message
	mode_label.add_theme_color_override("font_color", color)
	
	# Hide node label
	if node_label:
		node_label.visible = false
	
	# Clear strategy label
	if strategy_label:
		strategy_label.text = ""
	
	# Clear transform info
	if position_label:
		position_label.text = ""
	if rotation_label:
		rotation_label.text = ""
	if scale_label:
		scale_label.text = ""
	if keybinds_label:
		keybinds_label.text = ""
	_update_snap_badges({}, false)
	_update_modifier_badges({})
	clear_numeric_state()
	
	visible = true
	_refresh_panel_size_deferred()

func hide_overlay() -> void:
	"""Hide the overlay"""
	visible = false
	# Also hide deferred to ensure it stays hidden
	call_deferred("set_visible", false)

func update_numeric_state(action_name: String, input_string: String) -> void:
	if not numeric_container or not numeric_action_label or not numeric_value_label or not numeric_glyph_label:
		return
	var has_value := action_name.strip_edges() != "" or input_string.strip_edges() != ""
	numeric_container.visible = has_value
	if has_value:
		numeric_action_label.text = action_name.strip_edges()
		numeric_value_label.text = input_string.strip_edges() if input_string.strip_edges() != "" else "_"
		_set_numeric_highlight(true)
	else:
		numeric_action_label.text = ""
		numeric_value_label.text = ""
		_set_numeric_highlight(false)

func clear_numeric_state() -> void:
	update_numeric_state("", "")

func _update_numeric_state_from_extra(numeric_state: Dictionary) -> void:
	if numeric_state.is_empty():
		return
	update_numeric_state(numeric_state.get("action_name", ""), numeric_state.get("input_string", ""))

func _update_snap_badges(snap_state: Dictionary, smooth_enabled: bool) -> void:
	_set_toggle_badge(grid_badge_label, "Grid", snap_state.get("position", false))
	_set_toggle_badge(y_snap_badge_label, "Y Snap", snap_state.get("snap_y", false))
	_set_toggle_badge(rotation_snap_badge_label, "Rot Snap", snap_state.get("rotation", false))
	_set_toggle_badge(scale_snap_badge_label, "Scale Snap", snap_state.get("scale", false))
	_set_toggle_badge(half_step_badge_label, "Half Step", snap_state.get("half_step", false))
	_set_toggle_badge(surface_align_badge_label, "Surface Align", snap_state.get("align", false))
	_set_toggle_badge(smooth_badge_label, "Smooth", smooth_enabled)

func _update_modifier_badges(modifier_state: Dictionary) -> void:
	_set_modifier_badge(fine_modifier_label, "Fine", modifier_state.get("fine", false))
	_set_modifier_badge(large_modifier_label, "Large", modifier_state.get("large", false))
	_set_modifier_badge(reverse_modifier_label, "Reverse", modifier_state.get("reverse", false))

func _set_toggle_badge(label: Label, name: String, active: bool) -> void:
	if not label:
		return
	label.text = "%s %s" % [name, "ON" if active else "off"]
	var active_color := Color(0.85, 0.95, 1.0, 1.0)
	var inactive_color := Color(0.6, 0.6, 0.6, 0.7)
	label.add_theme_color_override("font_color", active_color if active else inactive_color)
	label.self_modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.5)

func _set_modifier_badge(label: Label, name: String, active: bool) -> void:
	if not label:
		return
	label.text = name
	var active_color := Color(1.0, 0.8, 0.45, 1.0)
	var inactive_color := Color(0.6, 0.6, 0.6, 0.7)
	label.add_theme_color_override("font_color", active_color if active else inactive_color)
	label.self_modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.4)

func _set_numeric_highlight(active: bool) -> void:
	if not numeric_glyph_label:
		return
	var glyph_color := Color(0.6, 0.85, 1.0, 1.0)
	var inactive_color := Color(0.5, 0.5, 0.5, 0.6)
	numeric_glyph_label.add_theme_color_override("font_color", glyph_color if active else inactive_color)
	numeric_action_label.add_theme_color_override("font_color", glyph_color if active else inactive_color)
	numeric_value_label.add_theme_color_override("font_color", glyph_color if active else inactive_color)

func _cache_panel_padding() -> void:
	if not content_vbox:
		return
	var top_padding := content_vbox.offset_top
	var bottom_padding := abs(content_vbox.offset_bottom)
	_panel_vertical_padding = top_padding + bottom_padding

func _refresh_panel_size_deferred() -> void:
	call_deferred("_refresh_panel_size")

func _refresh_panel_size() -> void:
	if not status_panel:
		return
	var content_height := 0.0
	if content_vbox:
		content_height = content_vbox.get_combined_minimum_size().y
	var total_height := max(content_height + _panel_vertical_padding, 64.0)
	status_panel.offset_bottom = -_panel_bottom_margin
	status_panel.offset_top = -(_panel_bottom_margin + total_height)
