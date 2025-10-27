@tool
extends RefCounted

class_name ThumbnailGenerator

const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")

# LRU Cache implementation
static var thumbnail_cache: Dictionary = {}  # key -> texture
static var cache_access_order: Array = []  # LRU order (most recent at end)

static var viewport: SubViewport
static var camera: Camera3D
static var mesh_instance: MeshInstance3D
static var scene_container: Node3D  # Container for full scene instances
static var light: DirectionalLight3D
static var generation_mutex: Mutex = Mutex.new()
static var is_generating: bool = false

# Performance optimization constants
const MAX_AABB_DEPTH = 15  # Maximum recursion depth for AABB calculation
const MAX_NODES_PER_AABB = 200  # Maximum nodes to process in AABB calculation
const YIELD_INTERVAL = 10  # Yield control every N nodes to prevent UI freeze
static var _nodes_processed: int = 0  # Track nodes processed in current AABB calculation
static var _max_nodes_warning_logged: bool = false  # Track if we've logged the max nodes warning

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
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Failed to create SubViewport!")
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
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Failed to create hidden container!")
		viewport.queue_free()
		viewport = null
		return
	
	hidden_container.visible = false
	hidden_container.name = "ThumbnailGeneratorContainer"
	
	# Add to editor but in a way that's completely isolated
	# Note: EditorInterface is acceptable here as this is a specialized thumbnail utility
	# that needs direct editor access for viewport management
	var main_screen = EditorInterface.get_editor_main_screen()
	if not main_screen:
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Could not get editor main screen!")
		hidden_container.queue_free()
		viewport.queue_free()
		viewport = null
		return
	
	main_screen.add_child(hidden_container)
	hidden_container.add_child(viewport)
	
	# Create camera
	camera = Camera3D.new()
	if not camera:
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Failed to create Camera3D!")
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
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Failed to create MeshInstance3D!")
		return
	
	viewport.add_child(mesh_instance)
	
	# Create scene container for rendering full scene hierarchies
	scene_container = Node3D.new()
	scene_container.name = "SceneContainer"
	viewport.add_child(scene_container)
	
	# Create main directional light
	light = DirectionalLight3D.new()
	if not light:
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "Failed to create DirectionalLight3D!")
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
	
	# Don't clear cache on initialization - preserve cached thumbnails across panel visibility changes
	# Cache will only be cleared explicitly via clear_cache() or cleanup()
	
	# Validate initialization
	if not (viewport and camera and mesh_instance and light):
		PluginLogger.warning(PluginConstants.COMPONENT_THUMBNAIL, "Component initialization failed!")

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
	cache_access_order.clear()
	
	generation_mutex.unlock()

static func clear_cache():
	"""Clear all cached thumbnails"""
	thumbnail_cache.clear()
	cache_access_order.clear()
	PluginLogger.info(PluginConstants.COMPONENT_THUMBNAIL, "Thumbnail cache cleared")

## LRU Cache Management

static func _cache_get(key: String) -> ImageTexture:
	"""Get item from cache and mark as recently used"""
	if key in thumbnail_cache:
		# Move to end (most recent)
		cache_access_order.erase(key)
		cache_access_order.append(key)
		return thumbnail_cache[key]
	return null

static func _cache_put(key: String, texture: ImageTexture) -> void:
	"""Add item to cache with LRU eviction if needed"""
	# If already in cache, remove old entry from access order
	if key in thumbnail_cache:
		cache_access_order.erase(key)
	
	# Check if we need to evict old entries
	if thumbnail_cache.size() >= PluginConstants.MAX_THUMBNAIL_CACHE_SIZE:
		_evict_lru_entries()
	
	# Add new entry
	thumbnail_cache[key] = texture
	cache_access_order.append(key)

static func _evict_lru_entries() -> void:
	"""Evict least recently used entries when cache is full"""
	var entries_to_remove = thumbnail_cache.size() - PluginConstants.MAX_THUMBNAIL_CACHE_SIZE + 10
	
	if entries_to_remove <= 0:
		return
	
	PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, "Evicting " + str(entries_to_remove) + " LRU cache entries")
	
	# Remove oldest entries (from front of access order list)
	for i in range(entries_to_remove):
		if cache_access_order.is_empty():
			break
		
		var key_to_remove = cache_access_order.pop_front()
		thumbnail_cache.erase(key_to_remove)

static func get_cache_stats() -> Dictionary:
	"""Get cache statistics for debugging"""
	return {
		"size": thumbnail_cache.size(),
		"max_size": PluginConstants.MAX_THUMBNAIL_CACHE_SIZE,
		"usage_percent": (thumbnail_cache.size() * 100.0) / PluginConstants.MAX_THUMBNAIL_CACHE_SIZE
	}

static func generate_mesh_thumbnail(asset_path: String) -> ImageTexture:
	# Auto-initialize if not already done
	if not viewport or not is_instance_valid(viewport) or not mesh_instance or not is_instance_valid(mesh_instance):
		initialize()
	
	# Simple concurrency control - just use the mutex to protect the rendering process
	generation_mutex.lock()
	
	# Check cache first using LRU - return cached thumbnail if available
	var cached_texture = _cache_get(asset_path)
	if cached_texture:
		_cleanup_generation()
		return cached_texture

	# Clear any previous mesh and materials to prevent contamination
	if mesh_instance and is_instance_valid(mesh_instance):
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
	var use_full_scene = false
	if resource is Mesh:
		mesh = resource
	elif resource is PackedScene:
		# Instantiate the scene first to check its type
		var scene_instance = resource.instantiate()
		
		# Check if the root node is a Node3D (or derived type)
		if not scene_instance is Node3D:
			# Not a 3D scene - try to extract a mesh from it
			var mesh_node = find_first_mesh_instance_node(scene_instance)
			if mesh_node:
				mesh = mesh_node.mesh
				# Copy materials
				if mesh_node.material_override:
					mesh_instance.material_override = mesh_node.material_override
				else:
					for i in range(mesh.get_surface_count()):
						var surface_material = mesh_node.get_surface_override_material(i)
						if surface_material:
							mesh_instance.set_surface_override_material(i, surface_material)
			else:
				# No mesh found in non-3D scene
				mesh = find_mesh_by_property(scene_instance)
				if not mesh:
					mesh = extract_mesh_from_any_node(scene_instance)
			
			scene_instance.queue_free()
		else:
			# Valid 3D scene - render the complete scene for accurate thumbnails
			use_full_scene = true
			
			# Clear scene container
			if scene_container and is_instance_valid(scene_container):
				for child in scene_container.get_children():
					child.queue_free()
			
				# Add the complete scene to the container
				scene_container.add_child(scene_instance)
			else:
				PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "scene_container is null or invalid!")
				scene_container = null
				_cleanup_generation()
				return null
			
			# Hide the single mesh instance since we're using the full scene
			if mesh_instance and is_instance_valid(mesh_instance):
				mesh_instance.visible = false
			elif mesh_instance and not is_instance_valid(mesh_instance):
				mesh_instance = null
		
		# Wait a frame for the scene to be fully added to the tree
		await Engine.get_main_loop().process_frame
		
		# Validate scene_container after await - might have been freed during rapid enable/disable
		if not scene_container or not is_instance_valid(scene_container):
			PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, "scene_container became invalid after await (plugin disabled during generation)")
			scene_container = null
			_cleanup_generation()
			return null
		
		# Get the AABB of the entire scene container (includes all children)
		var scene_aabb = VisualInstance3D.new().get_aabb() if scene_container.get_child_count() == 0 else AABB()
		
		# Calculate AABB from all VisualInstance3D children (async for better performance)
		_nodes_processed = 0  # Reset node counter
		_max_nodes_warning_logged = false  # Reset warning flag
		var first = true
		if scene_container and is_instance_valid(scene_container):
			for child in scene_container.get_children():
				# Use async version for large scenes
				var child_aabb = await _get_node_aabb_recursive_async(child, 0)
				
				# Validate scene_container after await - might have been freed
				if not scene_container or not is_instance_valid(scene_container):
					PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, 
						"scene_container became invalid during AABB calculation (plugin disabled)")
					scene_container = null
					_cleanup_generation()
					return null
				
				if child_aabb.has_volume():
					if first:
						scene_aabb = child_aabb
						first = false
					else:
						scene_aabb = scene_aabb.merge(child_aabb)
		
		# Log AABB calculation stats
		if _nodes_processed > 0:
			var reached_limit = _nodes_processed > MAX_NODES_PER_AABB
		
		# Position camera to view the entire scene
		if scene_aabb.has_volume():
			_position_camera_for_aabb(scene_aabb)
		else:
			# Fallback if no valid AABB
			camera.position = Vector3(2, 2, 3)
			camera.look_at(Vector3.ZERO, Vector3.UP)
	
	if not mesh and not use_full_scene:
		_cleanup_generation()
		return null
	
	# Set the mesh to our instance (skip if using full scene mode)
	if not use_full_scene:
		if not mesh_instance or not is_instance_valid(mesh_instance):
			PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "mesh_instance is null or invalid!")
			_cleanup_generation()
			return null
		
		# Make sure mesh instance is visible
		mesh_instance.visible = true
		mesh_instance.mesh = mesh
		
		# Force the mesh instance to update its internal state
		mesh_instance.set_surface_override_material(0, null)  # Clear any surface material
		mesh_instance.force_update_transform()
	else:
		# Using full scene - ensure mesh_instance is hidden
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.visible = false
		elif mesh_instance and not is_instance_valid(mesh_instance):
			mesh_instance = null
	
	# Only do mesh-specific setup if not using full scene mode
	if not use_full_scene:
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
		
		# Apply a neutral material override only if the mesh has no materials
		# This ensures visibility while preserving actual asset materials when present
		var needs_material = true
		if mesh.get_surface_count() > 0:
			for i in range(mesh.get_surface_count()):
				if mesh.surface_get_material(i) != null:
					needs_material = false
					break
		
		if needs_material:
			# Only add material if mesh has no materials of its own
			var material = StandardMaterial3D.new()
			material.albedo_color = Color(0.8, 0.8, 0.8, 1.0)  # Neutral gray
			material.metallic = 0.2
			material.roughness = 0.6
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mesh_instance.material_override = material
		
		# Use simple, consistent camera positioning to focus on shape differences
		_position_camera_simple(mesh)
	
	# Clear viewport render cache and force complete re-render
	if viewport and is_instance_valid(viewport):
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		PluginLogger.error(PluginConstants.COMPONENT_THUMBNAIL, "viewport is null or invalid before rendering!")
		viewport = null
		_cleanup_generation()
		return null
	
	# Wait multiple frames to ensure complete re-render
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	
	# Check if viewport is still valid after awaits (could be cleaned up externally)
	if not viewport or not is_instance_valid(viewport):
		# This is normal during plugin disable or scene changes during async operations
		PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, "Viewport became invalid during generation for %s (likely plugin disabled or scene changed - this is safe)" % asset_path.get_file())
		_cleanup_generation()
		return null
	
	# Force one final render
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Get the viewport texture
	var viewport_texture = viewport.get_texture()
	if not viewport_texture:
		PluginLogger.warning(PluginConstants.COMPONENT_THUMBNAIL, "Failed to get viewport texture for " + str(asset_path.get_file()))
		return null

	# Create ImageTexture from viewport
	var image = viewport_texture.get_image()
	if not image:
		_cleanup_generation()
		return null

	var texture = ImageTexture.new()
	texture.set_image(image)
	
	# Cache the result using LRU cache
	_cache_put(asset_path, texture)
	
	# Always clear the mesh/scene after capturing to prevent leftover state
	if use_full_scene:
		# Clean up scene container
		if scene_container and is_instance_valid(scene_container):
			for child in scene_container.get_children():
				child.queue_free()
		elif scene_container and not is_instance_valid(scene_container):
			scene_container = null
	else:
		if mesh_instance and is_instance_valid(mesh_instance):
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

static func _get_node_aabb_recursive(node: Node) -> AABB:
	"""Recursively calculate the combined AABB of a node and all its children"""
	var combined_aabb = AABB()
	var first = true
	
	# Check if this node has a visual representation
	if node is VisualInstance3D:
		var visual = node as VisualInstance3D
		var local_aabb = visual.get_aabb()
		
		if local_aabb.has_volume():
			# Transform AABB to global space
			var transform = visual.global_transform
			var corners = [
				transform * (local_aabb.position),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, 0, 0)),
				transform * (local_aabb.position + Vector3(0, local_aabb.size.y, 0)),
				transform * (local_aabb.position + Vector3(0, 0, local_aabb.size.z)),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, local_aabb.size.y, 0)),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, 0, local_aabb.size.z)),
				transform * (local_aabb.position + Vector3(0, local_aabb.size.y, local_aabb.size.z)),
				transform * (local_aabb.position + local_aabb.size)
			]
			
			combined_aabb = AABB(corners[0], Vector3.ZERO)
			for corner in corners:
				combined_aabb = combined_aabb.expand(corner)
			first = false
	
	# Process children recursively
	for child in node.get_children():
		var child_aabb = _get_node_aabb_recursive(child)
		if child_aabb.has_volume():
			if first:
				combined_aabb = child_aabb
				first = false
			else:
				combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb


static func _get_node_aabb_recursive_async(node: Node, depth: int = 0) -> AABB:
	"""
	Asynchronously calculate the combined AABB of a node and all its children.
	Yields control periodically to prevent UI freezing on large scenes.
	
	Performance limits:
	- MAX_AABB_DEPTH: Maximum recursion depth (prevents infinite loops)
	- MAX_NODES_PER_AABB: Maximum nodes to process (prevents excessive processing)
	- YIELD_INTERVAL: Yield every N nodes (keeps UI responsive)
	"""
	var combined_aabb = AABB()
	var first = true
	
	# Early exit: Check depth limit
	if depth > MAX_AABB_DEPTH:
		PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, 
			"AABB calculation reached max depth: %d" % MAX_AABB_DEPTH)
		return combined_aabb
	
	# Early exit: Check node count limit
	if _nodes_processed > MAX_NODES_PER_AABB:
		# Only log once per thumbnail generation to avoid spam
		if not _max_nodes_warning_logged:
			_max_nodes_warning_logged = true
			PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, 
				"AABB calculation reached max nodes: %d (this is normal for complex scenes)" % MAX_NODES_PER_AABB)
		return combined_aabb
	
	# Increment node counter
	_nodes_processed += 1
	
	# Yield control periodically to keep UI responsive
	if _nodes_processed % YIELD_INTERVAL == 0:
		await Engine.get_main_loop().process_frame
		
		# Validate node after await - might have been freed
		if not NodeUtils.is_valid(node):
			PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, 
				"Node became invalid during async AABB calculation")
			return combined_aabb
	
	# Check if this node has a visual representation
	if node is VisualInstance3D:
		var visual = node as VisualInstance3D
		var local_aabb = visual.get_aabb()
		
		if local_aabb.has_volume():
			# Transform AABB to global space
			var transform = visual.global_transform
			var corners = [
				transform * (local_aabb.position),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, 0, 0)),
				transform * (local_aabb.position + Vector3(0, local_aabb.size.y, 0)),
				transform * (local_aabb.position + Vector3(0, 0, local_aabb.size.z)),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, local_aabb.size.y, 0)),
				transform * (local_aabb.position + Vector3(local_aabb.size.x, 0, local_aabb.size.z)),
				transform * (local_aabb.position + Vector3(0, local_aabb.size.y, local_aabb.size.z)),
				transform * (local_aabb.position + local_aabb.size)
			]
			
			combined_aabb = AABB(corners[0], Vector3.ZERO)
			for corner in corners:
				combined_aabb = combined_aabb.expand(corner)
			first = false
	
	# Process children recursively
	for child in node.get_children():
		# Validate child before processing
		if not child or not is_instance_valid(child):
			continue
			
		var child_aabb = await _get_node_aabb_recursive_async(child, depth + 1)
		if child_aabb.has_volume():
			if first:
				combined_aabb = child_aabb
				first = false
			else:
				combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb

static func _position_camera_for_aabb(aabb: AABB):
	"""Position camera to view the entire AABB"""
	if not camera or not is_instance_valid(camera):
		if camera and not is_instance_valid(camera):
			camera = null
		return
	
	var center = aabb.get_center()
	var size = aabb.size
	var max_size = max(size.x, max(size.y, size.z))
	
	# Calculate camera distance to fit the entire object
	var fov_rad = deg_to_rad(camera.fov)
	var distance = (max_size / 2.0) / tan(fov_rad / 2.0) * 2  # 2 for padding
	
	# Position camera at an angle (adjusted to view from front-diagonal)
	# Using negative Z to view from the front, positive Y for height, slight X for angle
	var camera_offset = Vector3(1, 1, -1).normalized() * distance
	camera.position = center + camera_offset
	camera.look_at(center, Vector3.UP)

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
	# Validate instances first
	if not mesh_instance or not is_instance_valid(mesh_instance):
		if mesh_instance and not is_instance_valid(mesh_instance):
			mesh_instance = null
		return
	
	if not camera or not is_instance_valid(camera):
		if camera and not is_instance_valid(camera):
			camera = null
		return
	
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
		if camera and is_instance_valid(camera):
			camera.size = max_extent * 1.5
			var distance = max_extent * 2.5
			camera.position = Vector3(distance * 0.7, distance * 0.5, distance * 0.7)
			camera.look_at(Vector3.ZERO, Vector3.UP)
			
			# Update light position relative to camera
			if light and is_instance_valid(light):
				light.position = camera.position + Vector3(1, 2, 1)
				light.look_at(Vector3.ZERO, Vector3.UP)
			elif light and not is_instance_valid(light):
				light = null
		elif camera and not is_instance_valid(camera):
			camera = null
	
	# Force viewport update

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Wait for multiple frames to ensure rendering is complete
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame
	await viewport.get_tree().process_frame
	
	# Check if viewport is still valid after awaits
	if not viewport or not is_instance_valid(viewport):
		# This is normal during plugin disable or scene changes during async operations
		PluginLogger.debug(PluginConstants.COMPONENT_THUMBNAIL, "Viewport became invalid during meshlib generation (likely plugin disabled or scene changed - this is safe)")
		return null
	
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







