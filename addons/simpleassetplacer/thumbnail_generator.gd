@tool
extends RefCounted

class_name ThumbnailGenerator

static var thumbnail_cache: Dictionary = {}
static var viewport: SubViewport
static var camera: Camera3D
static var mesh_instance: MeshInstance3D
static var light: DirectionalLight3D
static var generation_mutex: Mutex = Mutex.new()
static var is_generating: bool = false

static func _cleanup_generation():
	generation_mutex.unlock()


static func initialize():
	# Only initialize if not already set up
	if viewport and is_instance_valid(viewport) and mesh_instance and is_instance_valid(mesh_instance):
		# Already initialized and valid, just clear previous mesh
		if mesh_instance.mesh:
			mesh_instance.mesh = null
		return
	
	# Clean up any invalid references first
	if viewport and not is_instance_valid(viewport):
		viewport = null
		camera = null
		mesh_instance = null
		light = null
	
	# Ensure we're starting clean
	viewport = null
	camera = null
	mesh_instance = null
	light = null
	
	# Create a completely isolated SubViewport for thumbnail generation
	# This viewport will have its own world and rendering context
	viewport = SubViewport.new()
	if not viewport:
		print("ThumbnailGenerator: ERROR - Failed to create SubViewport!")
		return
	
	viewport.size = Vector2i(256, 256)  # Increased size for better rendering
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.disable_3d = false
	viewport.snap_2d_transforms_to_pixel = false
	viewport.snap_2d_vertices_to_pixel = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	
	# CRITICAL: Create a new World3D to completely isolate from main scene
	viewport.world_3d = World3D.new()
	
	# Add viewport to a completely independent container
	# Create a hidden control container that's isolated from the main editor
	var hidden_container = Control.new()
	if not hidden_container:
		print("ThumbnailGenerator: ERROR - Failed to create hidden container!")
		viewport.queue_free()
		viewport = null
		return
	
	hidden_container.visible = false
	hidden_container.name = "ThumbnailGeneratorContainer"
	
	# Add to editor but in a way that's completely isolated
	var main_screen = EditorInterface.get_editor_main_screen()
	if not main_screen:
		print("ThumbnailGenerator: ERROR - Could not get editor main screen!")
		hidden_container.queue_free()
		viewport.queue_free()
		viewport = null
		return
	
	main_screen.add_child(hidden_container)
	hidden_container.add_child(viewport)
	
	# Create camera
	camera = Camera3D.new()
	if not camera:
		print("ThumbnailGenerator: ERROR - Failed to create Camera3D!")
		return
	
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 45.0
	camera.position = Vector3(2, 2, 3)
	viewport.add_child(camera)
	
	# Now that camera is in tree, we can use look_at
	camera.look_at(Vector3.ZERO, Vector3.UP)
	
	# Create mesh instance
	mesh_instance = MeshInstance3D.new()
	if not mesh_instance:
		print("ThumbnailGenerator: ERROR - Failed to create MeshInstance3D!")
		return
	
	viewport.add_child(mesh_instance)
	
	# Create main directional light
	light = DirectionalLight3D.new()
	if not light:
		print("ThumbnailGenerator: ERROR - Failed to create DirectionalLight3D!")
		return
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
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.2, 0.3, 1.0)  # Dark blue-gray background for contrast
	
	# Enhanced ambient lighting for professional look
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.3  # Subtle ambient from sky
	camera.environment = environment
	
	# Clear cache to ensure fresh thumbnails
	thumbnail_cache.clear()
	
	# Validate initialization
	if not (viewport and camera and mesh_instance and light):
		print("ThumbnailGenerator: WARNING - Component initialization failed!")

static func cleanup():
	"""Clean up all static resources when no longer needed"""
	generation_mutex.lock()
	
	# Wait for any ongoing generation to complete
	while is_generating:
		generation_mutex.unlock()
		await Engine.get_main_loop().process_frame
		generation_mutex.lock()
	
	# Clean up all static objects
	if viewport and is_instance_valid(viewport):
		# Clean up child objects first
		if camera:
			camera.queue_free()
			camera = null
		
		if mesh_instance:
			# Clear the mesh to free resources
			mesh_instance.mesh = null
			mesh_instance.queue_free()
			mesh_instance = null
			
		if light:
			light.queue_free()
			light = null
		
		# Clean up viewport and its hidden container
		var container = viewport.get_parent()
		viewport.queue_free()
		viewport = null
		
		# Also clean up the hidden container if it exists
		if container and is_instance_valid(container):
			container.queue_free()
	
	# Clear cache
	thumbnail_cache.clear()
	
	generation_mutex.unlock()

static func clear_cache():
	thumbnail_cache.clear()

static func generate_mesh_thumbnail(asset_path: String) -> ImageTexture:
	# Auto-initialize if not already done
	if not viewport or not is_instance_valid(viewport) or not mesh_instance or not is_instance_valid(mesh_instance):
		initialize()
	
	# Simple concurrency control - just use the mutex to protect the rendering process
	generation_mutex.lock()
	
	# Temporarily clear cache to force regeneration with new settings
	# TODO: Remove this after testing - this forces fresh thumbnails with new materials/camera
	thumbnail_cache.clear()
	
	# Check cache first (will be empty due to clear above, but keeping for future)
	if asset_path in thumbnail_cache:
		_cleanup_generation()
		return thumbnail_cache[asset_path]
	initialize()

	# Clear any previous mesh and materials to prevent contamination
	if mesh_instance:
		# First clear the mesh to reset the surface count
		var old_mesh = mesh_instance.mesh
		mesh_instance.mesh = null
		mesh_instance.material_override = null
		
		# Only clear surface materials if there was a previous mesh
		if old_mesh:
			for i in range(old_mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(i, null)
		
		# Ensure isolated world is completely clean
		if viewport and viewport.world_3d:
			# The isolated World3D should only contain our camera, lights, and mesh_instance
			# No additional cleanup needed as it's completely separate from main scene
			pass
		
		# Force the viewport to render a blank frame to clear previous state
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await Engine.get_main_loop().process_frame

	# Load the mesh resource
	var resource = load(asset_path)
	if not resource:
		_cleanup_generation()
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
		_cleanup_generation()
		return null
	
	# Set the mesh to our instance
	if not mesh_instance or not is_instance_valid(mesh_instance):
		print("ThumbnailGenerator: ERROR - mesh_instance is null or invalid!")
		_cleanup_generation()
		return null
	
	mesh_instance.mesh = mesh
	
	# Force the mesh instance to update its internal state
	mesh_instance.set_surface_override_material(0, null)  # Clear any surface material
	mesh_instance.force_update_transform()
	
	# Debug mesh info
	var vertex_count = 0
	var first_vertex = Vector3.ZERO
	if mesh.get_surface_count() > 0:
		var arrays = mesh.surface_get_arrays(0)
		if arrays and arrays.size() > 0 and arrays[0]:
			vertex_count = arrays[0].size()
			if vertex_count > 0:
				first_vertex = arrays[0][0]
	
	# Verify the mesh was set
	if mesh_instance.mesh != mesh:
		_cleanup_generation()
		return null	# Use the original materials from the mesh/scene - don't override unless necessary
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
	
	# ALWAYS apply a material to ensure visibility and proper coloring
	var material = StandardMaterial3D.new()
	
	# Use different colors based on vertex count and shape to make shapes distinguishable
	var mesh_vertex_count = 0
	if mesh.get_surface_count() > 0:
		var arrays = mesh.surface_get_arrays(0)
		if arrays and arrays.size() > 0 and arrays[0]:
			mesh_vertex_count = arrays[0].size()
	
	# Color based on vertex count and name
	var asset_name = asset_path.get_file().to_lower()
	if mesh_vertex_count > 100 or "cone" in asset_name:
		material.albedo_color = Color(0.9, 0.6, 0.4, 1.0)  # Orange for cones (higher vertex count)
	elif mesh_vertex_count < 50 or "cube" in asset_name:
		material.albedo_color = Color(0.4, 0.7, 0.9, 1.0)  # Blue for cubes (lower vertex count)
	else:
		material.albedo_color = Color(0.7, 0.8, 0.6, 1.0)  # Green for others
	
	material.metallic = 0.1
	material.roughness = 0.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	
	# Add a subtle texture to help differentiate shapes
	if mesh_vertex_count > 100:
		material.roughness = 0.3  # Smoother for high poly (cones)
	else:
		material.roughness = 0.8  # Rougher for low poly (cubes)
	
	# Apply the material to the mesh instance
	mesh_instance.material_override = material
	
	# Use simple, consistent camera positioning to focus on shape differences
	_position_camera_simple(mesh)
	
	# Clear viewport render cache and force complete re-render
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# Wait multiple frames to ensure complete re-render
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	
	# Force one final render
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Get the viewport texture
	var viewport_texture = viewport.get_texture()
	if not viewport_texture:
		print("ThumbnailGenerator: Failed to get viewport texture for ", asset_path.get_file())
		return null

	# Create ImageTexture from viewport
	var image = viewport_texture.get_image()
	if not image:
		_cleanup_generation()
		return null

	var texture = ImageTexture.new()
	texture.set_image(image)
	
	# Cache the result with unique identifier
	thumbnail_cache[asset_path] = texture
	
	# Always clear the mesh after capturing to prevent leftover state
	if mesh_instance:
		# Clear surface materials safely before clearing mesh
		var current_mesh = mesh_instance.mesh
		if current_mesh:
			var surface_count = current_mesh.get_surface_count()
			for i in range(surface_count):
				mesh_instance.set_surface_override_material(i, null)
		
		# Clear the mesh and material override
		mesh_instance.mesh = null
		mesh_instance.material_override = null
	
	# Mark generation as complete
	_cleanup_generation()
	
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
		
		# Use an attractive 3/4 view angle that shows depth and form well
		var distance = display_size * 3.5  # Further back for perspective view
		
		# Use a more dramatic angle to better show shape differences
		# Position camera at a 3/4 view that emphasizes the top and sides
		var cam_x = distance * 0.8  # Strong side angle
		var cam_y = distance * 0.9  # High angle to see the top
		var cam_z = distance * 0.6  # Moderate front view
		
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
	
	# Auto-initialize if not already done
	if not viewport or not is_instance_valid(viewport) or not mesh_instance or not is_instance_valid(mesh_instance):
		initialize()
	
	# If no specific item, use the first available item
	if item_id == -1:
		var ids = meshlib.get_item_list()
		if ids.size() == 0:
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