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
const PlacementStrategyManager = preload("res://addons/simpleassetplacer/placement/placement_strategy_manager.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")

func _ready() -> void:
	# Ensure proper setup
	visible = false
	
	# Set panel to pass mouse events through (no buttons to interact with anymore)
	if status_panel:
		status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var overlay_control = get_node_or_null("OverlayControl")
	if overlay_control:
		overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_transform_info(mode: int, node_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale_value: float = 1.0, height_offset: float = 0.0) -> void:
	"""Show unified transform overlay with all current transformation data"""
	if not mode_label or not position_label:
		return
	
	# Get current placement strategy for display
	var strategy_name = PlacementStrategyManager.get_active_strategy_name()
	var strategy_icon = "🎯" if PlacementStrategyManager.get_active_strategy_type() == "collision" else "📐"
	
	# Update mode label and color
	match mode:
		ModeStateMachine.Mode.PLACEMENT:
			mode_label.text = "🎯 PLACEMENT MODE"
			mode_label.add_theme_color_override("font_color", Color.YELLOW)
		ModeStateMachine.Mode.TRANSFORM:
			mode_label.text = "⚙️ TRANSFORM MODE"
			mode_label.add_theme_color_override("font_color", Color.CYAN)
		_:
			mode_label.text = "🔧 Asset Placer Active"
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
			var move_keys = "%s%s%s%s" % [
				settings.get("position_forward_key", "W"),
				settings.get("position_left_key", "A"),
				settings.get("position_back_key", "S"),
				settings.get("position_right_key", "D")
			]
			var height_up = settings.get("height_up_key", "Q")
			var height_down = settings.get("height_down_key", "E")
			var scale_up = settings.get("scale_up_key", "PageUp")
			var scale_down = settings.get("scale_down_key", "PageDown")
			var cycle_mode = settings.get("cycle_placement_mode_key", "P")
			
			# Show mode-specific keybinds with actual keys
			if mode == ModeStateMachine.Mode.PLACEMENT:
				keybinds_label.text = "%s (Move)  %s/%s (Height)  %s/%s (Scale)  Mouse (Rotate)  %s (Mode)" % [move_keys, height_up, height_down, scale_up, scale_down, cycle_mode]
			else:  # transform mode
				keybinds_label.text = "%s (Move)  %s/%s (Height)  %s/%s (Scale)  Mouse+X/Y/Z (Rotate)  %s (Mode)  CTRL/ALT (Modifiers)" % [move_keys, height_up, height_down, scale_up, scale_down, cycle_mode]
	
	visible = true

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
