@tool
extends EditorPlugin

const AssetPlacerDock = preload("res://addons/simpleassetplacer/asset_placer_dock.gd")
const PlacementCore = preload("res://addons/simpleassetplacer/placement_core.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnail_generator.gd")
var dock: AssetPlacerDock
var input_overlay: Control
var input_poll_timer: Timer
var _key_was_pressed: Dictionary = {}  # Track key states for edge detection


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func handles(object) -> bool:
	# We want to handle input when in placement mode
	return PlacementCore.placement_mode

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	
	# Enable always-on input forwarding for reliable input handling
	set_input_event_forwarding_always_enabled()
	
	dock = AssetPlacerDock.new()
	dock.name = "Asset Placer"
	dock.asset_selected.connect(_on_asset_selected)
	dock.meshlib_item_selected.connect(_on_meshlib_item_selected)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Set up input polling timer as fallback
	input_poll_timer = Timer.new()
	input_poll_timer.wait_time = 0.016  # ~60 FPS
	input_poll_timer.autostart = false
	get_tree().root.add_child(input_poll_timer)
	input_poll_timer.timeout.connect(_poll_input)


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	ThumbnailGenerator.cleanup()
	if PlacementCore.placement_mode:
		PlacementCore.exit_placement_mode()
	if input_overlay:
		input_overlay.queue_free()
	if dock:
		remove_control_from_docks(dock)
	if input_poll_timer:
		input_poll_timer.queue_free()

func _on_asset_selected(asset_path: String, mesh_resource: Resource, settings: Dictionary):
	# Start interactive placement mode instead of immediate placement
	PlacementCore.start_asset_placement(asset_path, settings, dock)
	# Input polling is now handled in _process function
	print("Continuous placement started. Left-click to place multiple, Escape to exit.")

func _process(delta: float) -> void:
	# Handle all input during placement mode with precise timing
	if PlacementCore.placement_mode:
		# Handle rotation keys
		RotationManager.process_key_input(delta, dock)
		
		# Handle mouse motion for preview positioning (unless in rotation mode)
		var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
		if viewport_3d:
			var current_mouse_pos = viewport_3d.get_mouse_position()
			
			# Check if rotation manager wants to handle mouse motion first
			var rotation_handled = RotationManager.handle_mouse_polling(current_mouse_pos, dock)
			
			# Only update preview position if not in rotation mode
			if not rotation_handled:
				PreviewManager.update_position(viewport_3d, current_mouse_pos, dock)
		
		# Handle mouse clicks
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not PlacementCore.left_was_pressed:
				PlacementCore.place_at_preview_position()
				PlacementCore.left_was_pressed = true
		else:
			PlacementCore.left_was_pressed = false
		
		# Handle configurable cancel key
		_handle_cancel_input()
		
		# Handle height adjustment keys
		_handle_height_input()
		
		# Handle scale keys directly
		_handle_scale_input()

func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var viewport = viewport_camera.get_viewport()
	
	# Check if there's an edited scene root
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Only handle specific events that aren't handled in _process
	# Mouse clicks for placement are now handled in _process
	# This function now only handles events that need immediate processing
	if PlacementCore.placement_mode and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Left click handled in _process for better timing
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	print("Meshlib item selected: ", item_id)
	# Start interactive placement mode instead of immediate placement
	PlacementCore.start_meshlib_placement(meshlib, item_id, settings, dock)
	# Input polling is now handled in _process function
	print("Interactive placement started. Move mouse to position, left-click to place, ESC to cancel.")

func _can_drop_data(position: Vector2, data) -> bool:
	if data is Dictionary:
		if data.has("asset_path") or data.has("type"):
			return true
	return false

func _drop_data(position: Vector2, data):
	if data is Dictionary:
		if data.has("asset_path"):
			# Start placement mode for dragged asset
			PlacementCore.start_asset_placement(data.asset_path, {}, dock)
		elif data.get("type") == "meshlib_item":
			# Start placement mode for dragged meshlib item
			PlacementCore.start_meshlib_placement(data.meshlib, data.item_id, {}, dock)

func _poll_input():
	# This function is no longer needed as all input is handled in _process
	if not PlacementCore.placement_mode:
		print("Stopping input polling timer")
		input_poll_timer.stop()

func _handle_scale_input():
	"""Handle scale input keys in _process function"""
	# Get current settings from dock
	var settings = {}
	if dock and dock.has_method("get_placement_settings"):
		settings = dock.get_placement_settings()
	
	# Get configured scale keys from settings
	var scale_up_key = settings.get("scale_up_key", "PAGE_UP")
	var scale_down_key = settings.get("scale_down_key", "PAGE_DOWN")
	var scale_reset_key = settings.get("scale_reset_key", "HOME")
	
	# Convert to keycodes
	var scale_up_keycode = ScaleManager.string_to_keycode(scale_up_key)
	var scale_down_keycode = ScaleManager.string_to_keycode(scale_down_key)
	var scale_reset_keycode = ScaleManager.string_to_keycode(scale_reset_key)
	
	# Check each configured key
	var scale_keys = [scale_up_keycode, scale_down_keycode, scale_reset_keycode]
	for key in scale_keys:
		if key != KEY_NONE and Input.is_key_pressed(key):
			if not _key_was_pressed.get(key, false):  # Only on first press
				var key_event = InputEventKey.new()
				key_event.keycode = key
				key_event.pressed = true
				key_event.alt_pressed = Input.is_key_pressed(KEY_ALT)
				
				var scale_handled = ScaleManager.handle_key_input(key_event, settings)
				if scale_handled:
					PreviewManager.update_scale()
			_key_was_pressed[key] = true
		else:
			_key_was_pressed[key] = false

func _handle_cancel_input():
	"""Handle configurable cancel key input"""
	# Get current settings from dock
	var settings = {}
	if dock and dock.has_method("get_placement_settings"):
		settings = dock.get_placement_settings()
	
	# Get configured cancel key
	var cancel_key_string = settings.get("cancel_key", "ESCAPE")
	var cancel_keycode = _string_to_keycode_simple(cancel_key_string)
	
	# Check for cancel input (both ui_cancel action and configured key)
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(cancel_keycode):
		PlacementCore.exit_placement_mode()

func _handle_height_input():
	"""Handle configurable height adjustment input with edge detection"""
	# Get current settings from dock
	var settings = {}
	if dock and dock.has_method("get_placement_settings"):
		settings = dock.get_placement_settings()
	
	# Get configured height adjustment keys
	var height_up_key = settings.get("height_up_key", "Q")
	var height_down_key = settings.get("height_down_key", "E")
	var height_step = settings.get("height_adjustment_step", 0.1)
	
	print("DEBUG: Height keys from settings: UP='", height_up_key, "' DOWN='", height_down_key, "'")
	
	# Convert to keycodes
	var height_up_keycode = PreviewManager.string_to_keycode(height_up_key)
	var height_down_keycode = PreviewManager.string_to_keycode(height_down_key)
	
	print("DEBUG: Converted to keycodes: UP=", height_up_keycode, " DOWN=", height_down_keycode)
	
	# Edge detection for height up key
	var height_up_pressed = Input.is_key_pressed(height_up_keycode)
	var height_up_key_name = "height_up"
	if height_up_pressed and not _key_was_pressed.get(height_up_key_name, false):
		PreviewManager.height_offset += height_step
		print("HEIGHT ADJUSTED UP by ", height_step, " (total offset: ", PreviewManager.height_offset, ")")
	_key_was_pressed[height_up_key_name] = height_up_pressed
	
	# Edge detection for height down key
	var height_down_pressed = Input.is_key_pressed(height_down_keycode)
	var height_down_key_name = "height_down"
	if height_down_pressed and not _key_was_pressed.get(height_down_key_name, false):
		PreviewManager.height_offset -= height_step
		print("HEIGHT ADJUSTED DOWN by ", height_step, " (total offset: ", PreviewManager.height_offset, ")")
	_key_was_pressed[height_down_key_name] = height_down_pressed

func _string_to_keycode_simple(key_string: String) -> Key:
	"""Simple keycode conversion for main plugin"""
	match key_string.to_upper():
		"ESCAPE": return KEY_ESCAPE
		"TAB": return KEY_TAB
		"ENTER": return KEY_ENTER
		"SPACE": return KEY_SPACE
		"BACKSPACE": return KEY_BACKSPACE
		"DELETE": return KEY_DELETE
		_: return KEY_ESCAPE  # Default fallback
