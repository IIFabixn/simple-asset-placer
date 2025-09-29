@tool
extends RefCounted

class_name PlacementCore

# Import required managers
const PreviewManager = preload("res://addons/simpleassetplacer/preview_manager.gd")
const RotationManager = preload("res://addons/simpleassetplacer/rotation_manager.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")

signal mesh_placed(node: MeshInstance3D)

# Placement mode state
static var placement_mode: bool = false
static var placement_mesh: Mesh = null
static var placement_settings: Dictionary = {}
static var placement_meshlib: MeshLibrary = null
static var placement_item_id: int = -1
static var placement_asset_path: String = ""
static var is_meshlib_placement: bool = false
static var placement_end_callback: Callable
static var update_timer: Timer
static var dock_reference = null
static var left_was_pressed: bool = false

# Helper function to generate unique node names
static func generate_unique_name(base_name: String, parent: Node) -> String:
	var unique_name = base_name
	var counter = 1
	
	# Check if a node with this name already exists
	while parent.has_node(NodePath(unique_name)):
		counter += 1
		unique_name = base_name + "_" + str(counter)
	
	return unique_name

# Helper function to add nodes with undo/redo support  
static func add_node_with_undo_redo(node: Node, parent: Node, action_name: String):
	var undo_redo = EditorInterface.get_editor_undo_redo()
	
	if undo_redo:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(parent, "add_child", node)
		undo_redo.add_do_property(node, "owner", EditorInterface.get_edited_scene_root())
		undo_redo.add_undo_method(parent, "remove_child", node)
		undo_redo.commit_action()
	else:
		# Fallback if undo/redo is not available
		parent.add_child(node)
		node.owner = EditorInterface.get_edited_scene_root()

static func start_meshlib_placement(meshlib: MeshLibrary, item_id: int, settings: Dictionary = {}, dock_instance = null):
	"""Start placement mode for a MeshLibrary item"""
	# Store placement state
	placement_meshlib = meshlib
	placement_item_id = item_id
	placement_settings = settings
	placement_mesh = meshlib.get_item_mesh(item_id)
	placement_asset_path = ""
	is_meshlib_placement = true
	dock_reference = dock_instance
	
	# Clear selection for safety
	EditorInterface.get_selection().clear()
	print("PlacementCore: Cleared selection for safety")
	
	# Initialize managers
	PreviewManager.initialize()
	RotationManager.reset_rotation()
	ScaleManager.reset_scale()
	
	# Create preview
	PreviewManager.create_preview("", placement_mesh, placement_settings)
	
	# Create rotation overlay
	RotationManager.create_overlay()
	
	# Enter placement mode
	placement_mode = true
	
	# Start update timer for continuous input polling
	start_placement_updates()
	
	print("PlacementCore: Starting meshlib placement mode with item_id: ", item_id)

static func start_asset_placement(asset_path: String, settings: Dictionary = {}, dock_instance = null):
	"""Start placement mode for a direct asset file"""
	# Store placement state
	placement_asset_path = asset_path
	placement_settings = settings
	placement_meshlib = null  # Not a meshlib placement
	placement_item_id = -1
	placement_mesh = null
	is_meshlib_placement = false
	dock_reference = dock_instance
	
	# Clear selection for safety
	EditorInterface.get_selection().clear()
	print("PlacementCore: Cleared selection for safety")
	
	# Initialize managers
	PreviewManager.initialize()
	RotationManager.reset_rotation()
	ScaleManager.reset_scale()
	
	# Create preview
	PreviewManager.create_preview(asset_path, null, placement_settings)
	
	# Create rotation overlay
	RotationManager.create_overlay()
	
	# Enter placement mode
	placement_mode = true
	
	# Start update timer for continuous input polling
	start_placement_updates()
	
	print("PlacementCore: Starting asset placement mode with asset: ", asset_path)

static func exit_placement_mode():
	"""Exit placement mode and clean up"""
	placement_mode = false
	
	# Clean up previews
	PreviewManager.cleanup_preview()
	
	# Hide overlays
	RotationManager.hide_overlay()
	ScaleManager.hide_scale_overlay()
	
	# Stop updates
	stop_placement_updates()
	
	# Call the callback if set
	if placement_end_callback.is_valid():
		placement_end_callback.call()
	
	# Reset state
	placement_mesh = null
	placement_meshlib = null
	placement_item_id = -1
	placement_asset_path = ""
	is_meshlib_placement = false
	placement_settings.clear()
	placement_end_callback = Callable()
	
	# Reset rotation state
	RotationManager.reset_rotation()
	RotationManager.last_key_states.clear()
	
	print("PlacementCore: Placement mode cancelled.")

static func place_at_preview_position():
	"""Place the asset at the current preview position"""
	var position = PreviewManager.get_current_position()
	
	# Update placement settings with current scale
	var current_settings = placement_settings.duplicate()
	current_settings["scale_multiplier"] = ScaleManager.get_scale()
	
	var placed_node = null
	if is_meshlib_placement:
		placed_node = place_meshlib_item_in_scene(placement_meshlib, placement_item_id, position, current_settings)
	else:
		placed_node = place_asset_in_scene(placement_asset_path, position, current_settings)
	
	if placed_node:
		print("Asset placed at: ", position, " with rotation: ", RotationManager.get_display_text(), " - ready for next placement")
		
		# Update preview rotation for next placement
		PreviewManager.update_rotation()
		
		# Update rotation overlay
		RotationManager.update_overlay()

static func place_asset_in_scene(asset_path: String, position: Vector3 = Vector3.ZERO, settings: Dictionary = {}) -> Node:
	"""Place an asset (scene or mesh) from file into the scene"""
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		print("PlacementCore: No scene available for placement")
		return null
	
	var resource = load(asset_path)
	var placed_node = null
	
	if resource is PackedScene:
		# Instantiate the complete scene (for FBX files, etc.)
		var scene_instance = resource.instantiate()
		scene_instance.name = generate_unique_name(asset_path.get_file().get_basename(), current_scene)
		
		# Add to scene first
		add_node_with_undo_redo(scene_instance, current_scene, "Place " + asset_path.get_file())
		
		# Apply transforms after adding to tree
		scene_instance.global_position = position
		RotationManager.apply_rotation_to_node(scene_instance)
		
		# Apply scale
		if settings.get("scale_multiplier", 1.0) != 1.0:
			scene_instance.scale *= settings.get("scale_multiplier", 1.0)
		
		placed_node = scene_instance
		print("PlacementCore: Placed scene: ", asset_path.get_file())
		
	elif resource is Mesh:
		# Create a MeshInstance3D for direct mesh resources
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = resource
		mesh_instance.name = generate_unique_name(asset_path.get_file().get_basename(), current_scene)
		
		# Add to scene first
		add_node_with_undo_redo(mesh_instance, current_scene, "Place " + asset_path.get_file())
		
		# Apply transforms after adding to tree
		mesh_instance.global_position = position
		RotationManager.apply_rotation_to_node(mesh_instance)
		
		# Apply scale
		if settings.get("scale_multiplier", 1.0) != 1.0:
			mesh_instance.scale *= settings.get("scale_multiplier", 1.0)
		
		placed_node = mesh_instance
		print("PlacementCore: Placed mesh: ", asset_path.get_file())
		
	else:
		print("PlacementCore: Unsupported asset type: ", asset_path, " (", resource.get_class(), ")")
	
	return placed_node

static func place_meshlib_item_in_scene(meshlib: MeshLibrary, item_id: int, position: Vector3, settings: Dictionary = {}) -> MeshInstance3D:
	"""Place a MeshLibrary item into the scene"""
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		print("PlacementCore: No scene available for placement")
		return null
	
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		print("PlacementCore: No mesh found for item_id: ", item_id)
		return null
	
	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = generate_unique_name(meshlib.get_item_name(item_id), current_scene)
	
	# Add to scene first
	add_node_with_undo_redo(mesh_instance, current_scene, "Place " + meshlib.get_item_name(item_id))
	
	# Apply transforms after adding to tree
	mesh_instance.global_position = position
	RotationManager.apply_rotation_to_node(mesh_instance)
	
	# Apply scale
	if settings.get("scale_multiplier", 1.0) != 1.0:
		mesh_instance.scale *= settings.get("scale_multiplier", 1.0)
	
	print("Place ", meshlib.get_item_name(item_id))
	
	return mesh_instance

static func handle_placement_input(event: InputEvent, viewport: Viewport, dock_instance = null) -> bool:
	"""Handle input events during placement mode"""
	if not placement_mode:
		return false
	
	# Handle mouse motion for accurate preview positioning
	if event is InputEventMouseMotion:
		PreviewManager.update_position(viewport, event.position, dock_instance)
		return true
	
	# Handle mouse button events for placement and rotation
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				# Confirm placement
				place_at_preview_position()
				return true
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				# Handle mouse wheel for rotation
				var handled = RotationManager.handle_wheel_input(event, dock_instance)
				if handled:
					PreviewManager.update_rotation()
					return true
	
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			# Cancel placement with Escape key
			exit_placement_mode()
			return true
		
		# Handle rotation keys
		if event.pressed:
			var handled = RotationManager.handle_key_input(event, dock_instance)
			if handled:
				PreviewManager.update_rotation()
				return true
		
		# Handle scaling keys
		if event.pressed:
			var handled = ScaleManager.handle_key_input(event, placement_settings)
			if handled:
				PreviewManager.update_scale()
				return true
		
		# Check for ui_cancel action (typically Escape key)
		if event.is_action_pressed("ui_cancel"):
			exit_placement_mode()
			return true
	
	# No input was handled
	return false

static func start_placement_updates():
	"""Start the update timer for continuous input polling"""
	# Stop any existing timer
	stop_placement_updates()
	
	# Create and configure timer
	update_timer = Timer.new()
	update_timer.wait_time = 1.0 / 60.0  # 60 FPS
	update_timer.timeout.connect(_on_update_timer_timeout)
	
	# Add timer to scene tree
	var current_scene = EditorInterface.get_edited_scene_root()
	if current_scene:
		current_scene.add_child(update_timer)
		update_timer.start()
		print("PlacementCore: Timer started successfully")
	else:
		print("PlacementCore: ERROR - Could not add timer to scene")

static func stop_placement_updates():
	"""Stop the update timer"""
	if update_timer and is_instance_valid(update_timer):
		print("PlacementCore: Stopping input polling timer")
		update_timer.stop()
		update_timer.queue_free()
	update_timer = null

static func _on_update_timer_timeout():
	"""Handle timer timeout for continuous input polling"""
	if not placement_mode:
		return
	
	# Check for rotation keys directly (bypasses event system issues)
	RotationManager.check_keys_direct(dock_reference)
	
	# Since forward_3d_gui_input doesn't receive mouse motion consistently during placement, 
	# we need to update preview position in the polling loop
	if placement_mode:
		# Get mouse position from the viewport directly
		var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
		if viewport_3d:
			var current_mouse_pos = viewport_3d.get_mouse_position()
			
			# Update preview position directly
			PreviewManager.update_position(viewport_3d, current_mouse_pos, dock_reference)

static func show_scene_lost_warning():
	"""Show warning when scene root is lost"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = "Warning: The current scene root was deleted or lost during placement mode. Placement has been cancelled to prevent errors."
	dialog.title = "Scene Lost"
	
	# Add to the main editor window
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	
	# Clean up dialog after closing
	dialog.connect("confirmed", dialog.queue_free)