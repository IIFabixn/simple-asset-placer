@tool
extends RefCounted

class_name PreviewManager

# Import required managers
const ScaleManager = preload("res://addons/simpleassetplacer/scale_manager.gd")

# Preview mesh instances
static var preview_mesh: Node3D = null
static var placement_indicator: MeshInstance3D = null
static var preview_material: StandardMaterial3D = null

static func initialize():
	"""Initialize the preview system"""
	create_preview_material()

static func create_preview_material():
	"""Create a transparent material for previews that preserves original textures"""
	if preview_material:
		return
	
	preview_material = StandardMaterial3D.new()
	preview_material.flags_transparent = true
	preview_material.albedo_color = Color(1.0, 1.0, 1.0, 0.6)  # White with 60% opacity
	preview_material.no_depth_test = false
	preview_material.flags_do_not_use_vertex_lighting = true

static func create_preview(asset_path: String, mesh: Mesh = null, settings: Dictionary = {}):
	"""Create preview mesh for the given asset"""
	cleanup_preview()
	
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		print("PreviewManager: No scene available for preview")
		return
	
	print("PreviewManager: Creating preview mesh...")
	
	# If we have a direct mesh, use it
	if mesh:
		# Create preview mesh instance
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = preview_material
		mesh_instance.name = "PreviewMesh"
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.scale = Vector3.ONE
		mesh_instance.layers = 1
		preview_mesh = mesh_instance
	else:
		# For complex assets, instantiate the scene as-is
		# Note: If the preview appears offset from the placement indicator,
		# this is due to the asset's internal transforms/pivot points
		var resource = load(asset_path)
		if resource is PackedScene:
			preview_mesh = resource.instantiate()
			preview_mesh.name = "PreviewMesh"
			# Apply transparency to all MeshInstance3D nodes in the preview
			apply_transparency_to_all_meshes(preview_mesh)
		else:
			# Fallback to simple mesh
			var mesh_instance = MeshInstance3D.new()
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(1, 1, 1)
			mesh_instance.mesh = box_mesh
			mesh_instance.material_override = preview_material
			preview_mesh = mesh_instance
	
	# Store original scale for scale manager
	var base_scale = Vector3.ONE
	if settings.get("scale_multiplier", 1.0) != 1.0:
		base_scale *= settings.get("scale_multiplier", 1.0)
	
	preview_mesh.set_meta("original_scale", base_scale)
	preview_mesh.scale = base_scale
	
	# Apply current rotation to preview
	RotationManager.apply_rotation_to_node(preview_mesh)
	
	# Apply current scale to preview
	update_scale()
	
	# Add to scene
	current_scene.add_child(preview_mesh)
	
	# Create placement indicator - a small bright sphere to show exact placement position
	create_placement_indicator()
	
	# Position it at a reasonable initial location in front of the camera
	var initial_position = get_initial_position()
	preview_mesh.global_position = initial_position
	preview_mesh.visible = true
	
	print("PreviewManager: Preview mesh created and positioned at: ", initial_position)

static func apply_transparency_to_all_meshes(node: Node):
	"""Apply transparency to all MeshInstance3D nodes while preserving original materials"""
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# If the mesh has original materials, make them transparent
		if mesh_instance.get_surface_override_material_count() > 0 or mesh_instance.mesh.get_surface_count() > 0:
			# Apply transparency to each surface
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var original_material = mesh_instance.get_surface_override_material(surface_idx)
				if not original_material:
					original_material = mesh_instance.mesh.surface_get_material(surface_idx)
				
				if original_material:
					# Create a transparent version of the original material
					var transparent_material = original_material.duplicate()
					if transparent_material is StandardMaterial3D:
						transparent_material.flags_transparent = true
						transparent_material.albedo_color.a = 0.6  # 60% opacity
					mesh_instance.set_surface_override_material(surface_idx, transparent_material)
				else:
					# No original material, use our preview material
					mesh_instance.set_surface_override_material(surface_idx, preview_material)
		else:
			# No materials at all, use our preview material
			mesh_instance.material_override = preview_material
	
	for child in node.get_children():
		apply_transparency_to_all_meshes(child)

static func create_placement_indicator():
	"""Create the yellow placement indicator sphere"""
	if placement_indicator:
		placement_indicator.queue_free()
		placement_indicator = null
	
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		return
	
	placement_indicator = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	placement_indicator.mesh = sphere
	placement_indicator.name = "PlacementIndicator"
	placement_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	placement_indicator.layers = 1
	
	# Create bright material for visibility
	var indicator_material = StandardMaterial3D.new()
	indicator_material.albedo_color = Color.YELLOW
	indicator_material.emission = Color.YELLOW * 0.5
	indicator_material.flags_unshaded = true
	placement_indicator.material_override = indicator_material
	
	current_scene.add_child(placement_indicator)

static func update_position(viewport: Viewport, mouse_pos: Vector2, dock_instance = null):
	"""Update preview position based on mouse position"""
	if not preview_mesh:
		return
	
	var camera = viewport.get_camera_3d()
	if not camera:
		return
	
	# Raycast from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var direction = camera.project_ray_normal(mouse_pos)
	var to = from + direction * 1000.0
	
	var position = Vector3.ZERO
	var hit_geometry = false
	
	if viewport.world_3d and viewport.world_3d.direct_space_state:
		var space_state = viewport.world_3d.direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		var result = space_state.intersect_ray(query)
		
		if result:
			position = result.position
			hit_geometry = true
			# Apply configurable height adjustment
			_apply_height_adjustment(position, dock_instance)
	
	if not hit_geometry:
		# No geometry hit, intersect with ground plane (Y = 0)
		if abs(direction.y) > 0.001:  # Avoid division by zero
			var t = -from.y / direction.y  # Distance to Y=0 plane
			if t > 0:  # Ray pointing towards ground
				position = from + direction * t
				# Apply configurable height adjustment
				_apply_height_adjustment(position, dock_instance)
			else:
				# Fallback: place at a default distance from camera
				position = from + direction * 10.0
		else:
			# Fallback: place at a default distance from camera
			position = from + direction * 10.0
	
	# Apply snapping using placement settings
	var snapped_position = apply_editor_snapping(position, dock_instance)
	
	preview_mesh.global_position = snapped_position
	preview_mesh.visible = true
	
	# Update placement indicator to show exact placement position
	if placement_indicator:
		placement_indicator.global_position = snapped_position
		placement_indicator.visible = true

static func apply_editor_snapping(position: Vector3, dock_instance = null) -> Vector3:
	"""Apply editor snapping to position"""
	if dock_instance and dock_instance.has_method("get_placement_settings"):
		var settings = dock_instance.get_placement_settings()
		var snap_enabled = settings.get("snap_enabled", false)
		var snap_size = settings.get("snap_size", 1.0)
		
		if snap_enabled and snap_size > 0.0:
			# Snap to grid
			position.x = round(position.x / snap_size) * snap_size
			position.z = round(position.z / snap_size) * snap_size
	
	return position

static func get_initial_position() -> Vector3:
	"""Get initial position for preview mesh in front of camera"""
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0)
	if viewport_3d:
		var camera = viewport_3d.get_camera_3d()
		if camera:
			# Place the preview 5 units in front of the camera
			var forward = -camera.global_transform.basis.z
			return camera.global_position + forward * 5.0
	
	# Fallback position
	return Vector3(0, 1, 0)

static func update_rotation():
	"""Update preview rotation to match current rotation state"""
	if preview_mesh:
		RotationManager.apply_rotation_to_node(preview_mesh)

static func update_scale():
	"""Update preview scale to match current scale state"""
	if preview_mesh:
		# Get the original scale stored in metadata
		var base_scale = preview_mesh.get_meta("original_scale", Vector3.ONE)
		# Get current scale from the scale manager
		var scale_multiplier = get_current_scale_multiplier()
		preview_mesh.scale = base_scale * scale_multiplier

static func get_current_scale_multiplier() -> float:
	"""Get current scale multiplier from ScaleManager"""
	return ScaleManager.get_scale()

static func get_current_position() -> Vector3:
	"""Get current preview position"""
	if preview_mesh:
		return preview_mesh.global_position
	return Vector3.ZERO

static func cleanup_preview():
	"""Clean up preview mesh and indicator"""
	if preview_mesh and is_instance_valid(preview_mesh):
		preview_mesh.queue_free()
	
	if placement_indicator and is_instance_valid(placement_indicator):
		placement_indicator.queue_free()
	
	preview_mesh = null
	placement_indicator = null

static func find_first_mesh_instance(node: Node) -> MeshInstance3D:
	"""Find the first MeshInstance3D node in the tree"""
	if node is MeshInstance3D:
		return node as MeshInstance3D
	
	# Recursively search children
	for child in node.get_children():
		var found = find_first_mesh_instance(child)
		if found:
			return found
	
	return null

static func _apply_height_adjustment(position: Vector3, dock_instance = null):
	"""Apply configurable height adjustment to position"""
	if not dock_instance:
		return
		
	var settings = {}
	if dock_instance.has_method("get_placement_settings"):
		settings = dock_instance.get_placement_settings()
	
	# Get configured height adjustment keys
	var height_up_key = settings.get("height_up_key", "Q")
	var height_down_key = settings.get("height_down_key", "E")
	var height_step = settings.get("height_adjustment_step", 0.1)
	
	# Convert to keycodes
	var height_up_keycode = string_to_keycode(height_up_key)
	var height_down_keycode = string_to_keycode(height_down_key)
	
	# Apply height adjustment
	if Input.is_key_pressed(height_up_keycode):
		position.y += height_step
	elif Input.is_key_pressed(height_down_keycode):
		position.y -= height_step

static func string_to_keycode(key_string: String) -> Key:
	"""Convert string representation to Key enum"""
	match key_string.to_upper():
		"Q": return KEY_Q
		"E": return KEY_E
		"W": return KEY_W
		"A": return KEY_A
		"S": return KEY_S
		"D": return KEY_D
		"R": return KEY_R
		"F": return KEY_F
		"T": return KEY_T
		"G": return KEY_G
		"Y": return KEY_Y
		"H": return KEY_H
		"U": return KEY_U
		"J": return KEY_J
		"I": return KEY_I
		"K": return KEY_K
		"O": return KEY_O
		"L": return KEY_L
		"P": return KEY_P
		"Z": return KEY_Z
		"X": return KEY_X
		"C": return KEY_C
		"V": return KEY_V
		"B": return KEY_B
		"N": return KEY_N
		"M": return KEY_M
		_: return KEY_NONE