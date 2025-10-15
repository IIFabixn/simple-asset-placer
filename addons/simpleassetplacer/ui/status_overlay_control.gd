@tool
extends CanvasLayer

class_name StatusOverlayControl

## Status Overlay Controller
## Manages the status overlay UI scene
## Replaces the programmatic UI creation in overlay_manager.gd

@onready var status_panel: Panel = $OverlayControl/StatusPanel

# Title HBox labels
@onready var mode_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/ModeLabel
@onready var node_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/NodeLabel
@onready var strategy_label: Label = $OverlayControl/StatusPanel/ContentVBox/TitleHBox/StrategyLabel

# Transform HBox labels
@onready var position_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/PositionLabel
@onready var rotation_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/RotationLabel
@onready var scale_label: Label = $OverlayControl/StatusPanel/ContentVBox/TransformHBox/ScaleLabel

# Keybinds label
@onready var keybinds_label: Label = $OverlayControl/StatusPanel/ContentVBox/KeybindsLabel

# Forward reference to ModeStateMachine for Mode enum
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

var _placement_service: PlacementStrategyService = null

func set_placement_strategy_service(service: PlacementStrategyService) -> void:
	"""Inject placement strategy service so overlay mirrors live state"""
	_placement_service = service
	if not _placement_service:
		_placement_service = PlacementStrategyService.new()
		_placement_service.initialize()

func _ready() -> void:
	# Ensure proper setup
	visible = false
	
	# Set panel to pass mouse events through (no buttons to interact with anymore)
	if status_panel:
		status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var overlay_control = get_node_or_null("OverlayControl")
	if overlay_control:
		overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_transform_info(mode: int, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale_value: float = 1.0, height_offset: float = 0.0, control_mode_state = null) -> void:
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
			
			# Show modal control keybinds
			if mode == ModeStateMachine.Mode.PLACEMENT:
				keybinds_label.text = "%s (Position)  %s (Rotation)  %s (Scale)  %s/%s (Quick Height)  X/Y/Z (Axis)  Mouse Wheel (Adjust)  ENTER (Place)" % [g_key, r_key, l_key, height_up, height_down]
			else:  # transform mode
				keybinds_label.text = "%s (Position)  %s (Rotation)  %s (Scale)  %s/%s (Quick Height)  X/Y/Z (Axis)  Mouse Wheel (Adjust)  ENTER (Confirm)  CTRL/ALT (Fine/Large)" % [g_key, r_key, l_key, height_up, height_down]
	
	visible = true

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
	
	visible = true

func hide_overlay() -> void:
	"""Hide the overlay"""
	visible = false
	# Also hide deferred to ensure it stays hidden
	call_deferred("set_visible", false)
