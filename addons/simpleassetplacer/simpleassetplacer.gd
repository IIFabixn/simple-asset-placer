@tool
extends EditorPlugin

const AssetPlacerDock = preload("res://addons/simpleassetplacer/asset_placer_dock.gd")
const PlacementCore = preload("res://addons/simpleassetplacer/placement_core.gd")
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
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
	# Start input polling
	if input_poll_timer:
		input_poll_timer.start()
	print("Continuous placement started. Left-click to place multiple, Escape to exit.")

func handles(object) -> bool:
	# Debug what objects we're being asked to handle
	print("handles() called with object: ", object, ", placement_mode: ", PlacementCore.placement_mode)
	
	# Return true for the scene root when we're in placement mode
	if PlacementCore.placement_mode:
		var scene_root = EditorInterface.get_edited_scene_root()
		if object == scene_root:
			print("Handling scene root for placement mode")
			return true
	
	return false

func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var viewport = viewport_camera.get_viewport()
	
	# Check if there's an edited scene root
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	if PlacementCore.handle_placement_input(event, viewport, dock):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _on_meshlib_item_selected(meshlib: MeshLibrary, item_id: int, settings: Dictionary):
	print("Meshlib item selected: ", item_id)
	# Start interactive placement mode instead of immediate placement
	PlacementCore.start_meshlib_placement(meshlib, item_id, settings, dock)
	# Start input polling
	if input_poll_timer:
		print("Starting input polling timer for meshlib")
		input_poll_timer.start()
	else:
		print("ERROR: input_poll_timer is null for meshlib!")
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
	if not PlacementCore.placement_mode:
		print("Stopping input polling timer")
		input_poll_timer.stop()
		return
	
	# Get the 3D viewport
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if not viewport_3d:
		return
	
	# Check for rotation keys directly (bypasses event system issues)
	RotationManager.check_keys_direct(dock)
	
	# Since forward_3d_gui_input doesn't receive mouse motion consistently during placement, 
	# we need to update preview position in the polling loop
	if PlacementCore.placement_mode:
		# Get mouse position from the viewport directly
		var current_mouse_pos = viewport_3d.get_mouse_position()
		
		# Update preview position directly without creating synthetic events
		PreviewManager.update_position(viewport_3d, current_mouse_pos, dock)
	
	# Check for mouse button and key input
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not PlacementCore.left_was_pressed:
			var current_mouse_pos_for_click = viewport_3d.get_mouse_position()
			var click_event = InputEventMouseButton.new()
			click_event.button_index = MOUSE_BUTTON_LEFT
			click_event.pressed = true
			click_event.position = current_mouse_pos_for_click
			PlacementCore.handle_placement_input(click_event, viewport_3d, dock)
			PlacementCore.left_was_pressed = true
	else:
		PlacementCore.left_was_pressed = false
	
	# Check for escape key
	if Input.is_action_just_pressed("ui_cancel"):
		var key_event = InputEventKey.new()
		key_event.keycode = KEY_ESCAPE
		key_event.pressed = true
		PlacementCore.handle_placement_input(key_event, viewport_3d, dock)
	
	# Poll for all key inputs during placement
	for keycode in range(KEY_A, KEY_Z + 1):  # A-Z keys
		if Input.is_key_pressed(keycode):
			if not _key_was_pressed.get(keycode, false):  # Only on press, not hold
				var key_event = InputEventKey.new()
				key_event.keycode = keycode
				key_event.pressed = true
				key_event.ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
				PlacementCore.handle_placement_input(key_event, viewport_3d, dock)
			_key_was_pressed[keycode] = true
		else:
			_key_was_pressed[keycode] = false
	
	# Poll for special keys (Page Up, Page Down, Home, etc.)
	var special_keys = [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END, KEY_INSERT, KEY_DELETE]
	for keycode in special_keys:
		if Input.is_key_pressed(keycode):
			if not _key_was_pressed.get(keycode, false):  # Only on press, not hold
				var key_event = InputEventKey.new()
				key_event.keycode = keycode
				key_event.pressed = true
				key_event.ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
				PlacementCore.handle_placement_input(key_event, viewport_3d, dock)
			_key_was_pressed[keycode] = true
		else:
			_key_was_pressed[keycode] = false
