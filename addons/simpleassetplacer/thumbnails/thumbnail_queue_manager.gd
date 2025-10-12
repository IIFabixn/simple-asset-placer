@tool
extends RefCounted

class_name ThumbnailQueueManager

"""
THUMBNAIL QUEUE MANAGER (INSTANCE-BASED)
=======================================

PURPOSE: Manages asynchronous thumbnail generation requests

ARCHITECTURE: Pure instance-based (no static singletons)
- Created once during plugin initialization via ServiceRegistry
- Injected to UI components that need thumbnails
- All state is instance state, not static

USED BY: UI components (AssetThumbnailItem, browsers)
DEPENDS ON: ThumbnailGenerator (static methods for viewport management)
"""

# Queue management (instance state only)
var request_queue: Array = []
var is_processing: bool = false
var current_request_id: int = 0

# Request tracking
var pending_requests: Dictionary = {}
# Track what's already queued/processing to avoid duplicates
# Key format: "asset:<path>" or "meshlib:<resource_id>:<item_id>"
var queued_items: Dictionary = {}

# Request data structure
class ThumbnailRequest:
	var id: int
	var asset_path: String
	var meshlib: MeshLibrary = null
	var item_id: int = -1
	var request_type: String # "asset" or "meshlib"
	var callback: Callable
	
	func _init(p_id: int, p_asset_path: String = "", p_meshlib: MeshLibrary = null, p_item_id: int = -1, p_type: String = "asset"):
		id = p_id
		asset_path = p_asset_path
		meshlib = p_meshlib
		item_id = p_item_id
		request_type = p_type

## Initialization

func _init() -> void:
	"""Initialize the queue manager"""
	# Initialize the thumbnail generator
	ThumbnailGenerator.initialize()

# Submit a request for asset thumbnail generation
func request_asset_thumbnail(asset_path: String) -> ImageTexture:
	var queue_key = "asset:" + asset_path
	
	# Check if already queued or processing
	if queued_items.has(queue_key):
		# Wait for the existing request to complete
		var existing_awaiter = queued_items[queue_key]
		var result = await existing_awaiter.wait_for_result()
		return result
	
	var request_id = _generate_request_id()
	
	var request = ThumbnailRequest.new(request_id, asset_path, null, -1, "asset")
	
	# Create a signal awaiter for this request
	var signal_awaiter = SignalAwaiter.new()
	pending_requests[request_id] = signal_awaiter
	queued_items[queue_key] = signal_awaiter
	
	# Add to queue
	request_queue.append(request)
	
	# Start processing if not already running
	if not is_processing:
		_process_queue()
	
	# Wait for the result
	var result = await signal_awaiter.wait_for_result()
	
	# Clean up
	pending_requests.erase(request_id)
	queued_items.erase(queue_key)
	
	return result

# Submit a request for meshlib thumbnail generation
func request_meshlib_thumbnail(meshlib: MeshLibrary, item_id: int = -1) -> ImageTexture:
	var queue_key = "meshlib:" + str(meshlib.get_instance_id()) + ":" + str(item_id)
	
	# Check if already queued or processing
	if queued_items.has(queue_key):
		# Wait for the existing request to complete
		var existing_awaiter = queued_items[queue_key]
		var result = await existing_awaiter.wait_for_result()
		return result
	
	var request_id = _generate_request_id()
	
	var request = ThumbnailRequest.new(request_id, "", meshlib, item_id, "meshlib")
	
	# Create a signal awaiter for this request
	var signal_awaiter = SignalAwaiter.new()
	pending_requests[request_id] = signal_awaiter
	queued_items[queue_key] = signal_awaiter
	
	# Add to queue
	request_queue.append(request)
	
	# Start processing if not already running
	if not is_processing:
		_process_queue()
	
	# Wait for the result
	var result = await signal_awaiter.wait_for_result()
	
	# Clean up
	pending_requests.erase(request_id)
	queued_items.erase(queue_key)
	
	return result

func _process_queue():
	if request_queue.is_empty():
		is_processing = false
		return
		
	is_processing = true
	var request = request_queue.pop_front()
	
	var result: ImageTexture = null
	
	# Process based on request type
	if request.request_type == "asset":
		result = await ThumbnailGenerator.generate_mesh_thumbnail(request.asset_path)
	elif request.request_type == "meshlib":
		result = await ThumbnailGenerator.generate_meshlib_thumbnail(request.meshlib, request.item_id)
	
	# Notify the awaiter
	var signal_awaiter = pending_requests.get(request.id)
	if signal_awaiter:
		signal_awaiter.complete_with_result(result)
	
	# Continue processing next item
	call_deferred("_process_queue")

func _generate_request_id() -> int:
	current_request_id += 1
	return current_request_id

func clear_queue():
	request_queue.clear()
	
	# Complete any pending requests with null
	for request_id in pending_requests.keys():
		var signal_awaiter = pending_requests[request_id]
		signal_awaiter.complete_with_result(null)
	
	pending_requests.clear()
	is_processing = false

func get_queue_size() -> int:
	return request_queue.size()

# Helper class for awaiting results
class SignalAwaiter:
	signal result_ready(texture: ImageTexture)
	var completed: bool = false
	var result_texture: ImageTexture = null
	
	func wait_for_result() -> ImageTexture:
		if completed:
			return result_texture
			
		await result_ready
		return result_texture
	
	func complete_with_result(texture: ImageTexture):
		if completed:
			return
			
		completed = true
		result_texture = texture
		result_ready.emit(texture)

## Cleanup

func cleanup():
	"""Clean up queue and resources"""
	clear_queue()


