@tool
extends RefCounted

class_name ThumbnailGenerator

static var thumbnail_cache: Dictionary = {}
static var viewport: SubViewport
static var camera: Camera3D
static var mesh_instance: MeshInstance3D
static var light: DirectionalLight3D

static func initialize():
	if viewport:
		# Clean up previous mesh if any to prevent cross-contamination
		if mesh_instance and mesh_instance.mesh:
			mesh_instance.mesh = null
		return # Already initialized
	
	# Create viewport for thumbnail generation
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.disable_3d = false
	viewport.snap_2d_transforms_to_pixel = false
	viewport.snap_2d_vertices_to_pixel = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	
	# Add viewport to the scene tree first
	EditorInterface.get_editor_main_screen().add_child(viewport)
	
	# Create camera
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(1, 1, 1)
	viewport.add_child(camera)
	
	# Now that camera is in tree, we can use look_at
	camera.look_at(Vector3.ZERO, Vector3.UP)
	
	# Create mesh instance
	mesh_instance = MeshInstance3D.new()
	viewport.add_child(mesh_instance)
	
	# Create main directional light
	light = DirectionalLight3D.new()
	light.position = Vector3(2, 3, 2)
	light.light_energy = 1.2  # Moderate main lighting
	light.shadow_enabled = false
	viewport.add_child(light)
	
	# Now that light is in tree, we can use look_at
	light.look_at(Vector3.ZERO, Vector3.UP)
	
	# Add secondary fill light for better illumination
	var fill_light = DirectionalLight3D.new()
	fill_light.position = Vector3(-1, 1, -1)
	fill_light.light_energy = 0.4  # Softer fill lighting
	fill_light.light_color = Color(0.9, 0.95, 1.0)  # Slightly cool fill
	viewport.add_child(fill_light)
	fill_light.look_at(Vector3.ZERO, Vector3.UP)
	
	# Create professional environment with gradient background
	var environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.95, 0.95, 1.0)  # Light blue-white top
	sky_material.sky_horizon_color = Color(0.85, 0.9, 0.95)  # Slightly darker horizon
	sky_material.ground_bottom_color = Color(0.7, 0.75, 0.8)  # Neutral ground
	sky_material.ground_horizon_color = Color(0.8, 0.85, 0.9)  # Blend with horizon
	environment.sky.sky_material = sky_material
	
	# Enhanced ambient lighting for professional look
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.3  # Subtle ambient from sky
	camera.environment = environment

static func cleanup():
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
		viewport = null
		camera = null
		mesh_instance = null
		light = null

static func clear_cache():
	thumbnail_cache.clear()

static func generate_mesh_thumbnail(asset_path: String) -> ImageTexture:
	# Check cache first
	if asset_path in thumbnail_cache:
		return thumbnail_cache[asset_path]
	initialize()
	
	# Load the mesh resource
	var resource = load(asset_path)
	if not resource:
		print("ThumbnailGenerator: Failed to load resource for ", asset_path.get_file())
		return null
	
	var mesh: Mesh = null
	
	# Handle different resource types
	if resource is Mesh:
		mesh = resource
	elif resource is PackedScene:
		# Try to find a mesh in the scene and preserve its materials
		var scene_instance = resource.instantiate()
		var mesh_node = find_first_mesh_instance_node(scene_instance)
		
		if mesh_node:
			mesh = mesh_node.mesh
			# Copy materials from the original mesh instance
			if mesh_node.material_override:
				mesh_instance.material_override = mesh_node.material_override
			else:
				# Copy surface materials
				for i in range(mesh.get_surface_count()):
					var surface_material = mesh_node.get_surface_override_material(i)
					if surface_material:
						mesh_instance.set_surface_override_material(i, surface_material)
		else:
			# Fallback to other methods if no MeshInstance3D found
			mesh = find_mesh_by_property(scene_instance)
			if not mesh:
				mesh = extract_mesh_from_any_node(scene_instance)
		
		scene_instance.queue_free()
	
	if not mesh:
		return null
	
	# Set the mesh to our instance
	mesh_instance.mesh = mesh
	
	# Verify the mesh was set
	if mesh_instance.mesh != mesh:
		return null
	
	# Use the original materials from the mesh/scene - don't override unless necessary
	# Only add a fallback material if the mesh has no materials at all
	var has_any_material = false
	
	# Check if mesh instance already has materials from scene copying
	if mesh_instance.material_override:
		has_any_material = true
	else:
		# Check surface override materials
		for i in range(mesh.get_surface_count()):
			if mesh_instance.get_surface_override_material(i):
				has_any_material = true
				break
		
		# Check if the mesh itself has materials
		if not has_any_material:
			for i in range(mesh.get_surface_count()):
				var surface_material = mesh.surface_get_material(i)
				if surface_material:
					has_any_material = true
					break
	
	# Only apply fallback material if no materials found at all
	if not has_any_material:

		var fallback_material = StandardMaterial3D.new()
		fallback_material.albedo_color = Color(0.8, 0.8, 0.8, 1.0)  # Neutral gray
		fallback_material.metallic = 0.0
		fallback_material.roughness = 0.7
		mesh_instance.material_override = fallback_material
	else:
		pass
	
	# Use simple, consistent camera positioning to focus on shape differences
	_position_camera_simple(mesh)
	
	# Force viewport update
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame
	
	# Get the viewport texture
	var viewport_texture = viewport.get_texture()
	if not viewport_texture:
		return null
	
	# Create ImageTexture from viewport
	var image = viewport_texture.get_image()
	if not image:
		return null
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	
	# Cache the result with unique identifier
	thumbnail_cache[asset_path] = texture
	
	return texture

static func find_first_mesh_instance_node(node: Node) -> MeshInstance3D:
	# Check if this node is a MeshInstance3D with a mesh
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			return mesh_instance
	
	# Also check for ImporterMeshInstance3D (used during import process)
	if node.get_class() == "ImporterMeshInstance3D":
		if node.has_method("get_mesh") and node.get_mesh():
			# This is tricky - ImporterMeshInstance3D isn't a MeshInstance3D
			# We'll handle this in the calling code
			return null
	
	# Recursively search children
	for child in node.get_children():
		var mesh_node = find_first_mesh_instance_node(child)
		if mesh_node:
			return mesh_node
	
	return null

static func find_first_mesh_in_node(node: Node) -> Mesh:
	var all_mesh_candidates = []
	_collect_all_meshes_from_node(node, all_mesh_candidates)
	
	if all_mesh_candidates.size() == 0:
		return null
	
	# Sort by complexity (prefer meshes with more vertices/surfaces)
	all_mesh_candidates.sort_custom(func(a, b):
		var a_vertices = 0
		var b_vertices = 0
		if a.mesh.get_surface_count() > 0:
			a_vertices = a.mesh.surface_get_array_len(0)
		if b.mesh.get_surface_count() > 0:
			b_vertices = b.mesh.surface_get_array_len(0)
		
		# First priority: more surfaces
		if a.mesh.get_surface_count() != b.mesh.get_surface_count():
			return a.mesh.get_surface_count() > b.mesh.get_surface_count()
		# Second priority: more vertices
		return a_vertices > b_vertices
	)
	
	var selected = all_mesh_candidates[0]
	return selected.mesh

static func _position_camera_simple(mesh: Mesh):
	# Calculate mesh bounds
	var aabb = mesh.get_aabb()
	var center = aabb.get_center()
	var size = aabb.size
	var max_extent = max(max(size.x, size.y), size.z)
	
	# Position mesh at origin
	mesh_instance.position = -center
	
	if max_extent > 0:
		# Ensure reasonable size for tiny meshes
		var display_size = max(max_extent, 0.001)
		camera.size = display_size * 1.2  # Tighter framing for better detail
		
		# Use an attractive 3/4 view angle that shows depth and form well
		var distance = display_size * 2.8
		
		# Calculate camera position based on mesh proportions for best presentation
		var x_ratio = size.x / max_extent
		var y_ratio = size.y / max_extent
		var z_ratio = size.z / max_extent
		
		# Adjust camera angle based on mesh shape
		var cam_x = distance * (0.6 + x_ratio * 0.3)  # More side view for wider objects
		var cam_y = distance * (0.5 + y_ratio * 0.4)  # Higher for taller objects
		var cam_z = distance * (0.8 + z_ratio * 0.2)  # Slightly more front view
		
		camera.position = Vector3(cam_x, cam_y, cam_z)
		camera.look_at(Vector3.ZERO, Vector3.UP)



static func _collect_all_meshes_from_node(node: Node, collection: Array):
	# Check if this node is a MeshInstance3D with a mesh
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			collection.append({
				"mesh": mesh_instance.mesh,
				"node_name": node.name,
				"node_class": node.get_class(),
				"transform": mesh_instance.transform
			})
	
	# Also check for ImporterMeshInstance3D (used during import process)
	if node.get_class() == "ImporterMeshInstance3D":
		if node.has_method("get_mesh") and node.get_mesh():
			var mesh = node.get_mesh()
			collection.append({
				"mesh": mesh,
				"node_name": node.name,
				"node_class": node.get_class(),
				"transform": Transform3D.IDENTITY
			})
	
	# Recursively search children
	for child in node.get_children():
		_collect_all_meshes_from_node(child, collection)

static func find_mesh_by_property(node: Node) -> Mesh:
	# Try to access mesh property directly (works for various mesh node types)
	if node.has_method("get_mesh"):
		var mesh = node.get_mesh()
		if mesh:
			return mesh
	
	# Try accessing mesh property directly
	if "mesh" in node and node.mesh:
		return node.mesh
	
	# Recursively search children
	for child in node.get_children():
		var mesh = find_mesh_by_property(child)
		if mesh:
			return mesh
	
	return null

static func extract_mesh_from_any_node(node: Node) -> Mesh:
	# Find all meshes in the scene and prioritize the best one
	var all_meshes = []
	var nodes_to_check = []
	collect_all_nodes(node, nodes_to_check)
	
	for n in nodes_to_check:
		var mesh = null
		var mesh_source = ""
		
		# Check for various node types that might contain meshes
		if n.has_method("get_mesh"):
			mesh = n.call("get_mesh")
			mesh_source = "get_mesh()"
		elif "mesh" in n and n.mesh is Mesh:
			mesh = n.mesh
			mesh_source = "mesh property"
		elif n.has_method("get_meshes"):
			var meshes = n.call("get_meshes")
			if meshes and meshes.size() > 0:
				mesh = meshes[0]
				mesh_source = "get_meshes()[0]"
		
		if mesh is Mesh:
			var mesh_info = {
				"mesh": mesh,
				"node": n,
				"node_name": n.name,
				"node_class": n.get_class(),
				"source": mesh_source,
				"surface_count": mesh.get_surface_count(),
				"vertex_count": 0
			}
			
			# Get vertex count if possible
			if mesh.get_surface_count() > 0:
				mesh_info["vertex_count"] = mesh.surface_get_array_len(0)
			
			all_meshes.append(mesh_info)
	
	if all_meshes.size() == 0:
		return null
	
	# Prioritize meshes by criteria (more surfaces and vertices = more detailed)
	all_meshes.sort_custom(func(a, b): 
		# First priority: more surfaces
		if a["surface_count"] != b["surface_count"]:
			return a["surface_count"] > b["surface_count"]
		# Second priority: more vertices
		return a["vertex_count"] > b["vertex_count"]
	)
	
	var best_mesh = all_meshes[0]
	return best_mesh["mesh"]

static func collect_all_nodes(node: Node, collection: Array):
	collection.append(node)
	for child in node.get_children():
		collect_all_nodes(child, collection)

static func generate_meshlib_thumbnail(meshlib: MeshLibrary, item_id: int = -1) -> ImageTexture:
	if not meshlib:
		return null
	
	initialize()
	
	# If no specific item, use the first available item
	if item_id == -1:
		var ids = meshlib.get_item_list()
		if ids.size() == 0:
			print("ThumbnailGenerator: No items in MeshLibrary")
			return null
		item_id = ids[0]
	
	# Get the mesh from the MeshLibrary
	var mesh = meshlib.get_item_mesh(item_id)
	if not mesh:
		return null
	
	# Set the mesh to our instance
	mesh_instance.mesh = mesh
	
	# Ensure mesh instance has a material for visibility
	if not mesh_instance.get_surface_override_material(0):
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.WHITE
		material.metallic = 0.0
		material.roughness = 0.8
		mesh_instance.set_surface_override_material(0, material)

	
	# Calculate optimal camera position
	var aabb = mesh.get_aabb()
	
	# Center the mesh at origin
	mesh_instance.position = -aabb.get_center()
	
	var max_extent = max(max(aabb.size.x, aabb.size.y), aabb.size.z)
	
	if max_extent > 0:
		camera.size = max_extent * 1.5
		var distance = max_extent * 2.5
		camera.position = Vector3(distance * 0.7, distance * 0.5, distance * 0.7)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		
		# Update light position relative to camera
		light.position = camera.position + Vector3(1, 2, 1)
		light.look_at(Vector3.ZERO, Vector3.UP)
	
	# Force viewport update

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Wait for multiple frames to ensure rendering is complete
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame
	
	# Get the viewport texture
	var viewport_texture = viewport.get_texture()
	if not viewport_texture:
		return null
	
	# Create ImageTexture from viewport
	var image = viewport_texture.get_image()
	if not image:
		return null
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	
	return texture