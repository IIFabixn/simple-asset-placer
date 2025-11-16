@tool
extends RefCounted

class_name ThumbnailService

const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const ThumbnailGenerator = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_generator.gd")
const ThumbnailCache = preload("res://addons/simpleassetplacer/thumbnails/thumbnail_cache.gd")

var _cache: ThumbnailCache
var _request_queue: Array = []
var _pending_requests: Dictionary = {}
var _inflight_keys: Dictionary = {}
var _is_processing: bool = false
var _request_id: int = 0


func _init(max_cache_size: int = PluginConstants.MAX_THUMBNAIL_CACHE_SIZE) -> void:
	_cache = ThumbnailCache.new(max_cache_size)
	ThumbnailGenerator.initialize()


func cleanup() -> void:
	clear_queue()
	_cache.clear()
	ThumbnailGenerator.cleanup()


func clear_cache() -> void:
	_cache.clear()


func get_cache_stats() -> Dictionary:
	return _cache.stats()


func request_asset_thumbnail(asset_path: String) -> ImageTexture:
	if asset_path == "":
		return null

	var cache_key = "asset:" + asset_path
	var cache_hit = _cache.lookup(cache_key)
	if cache_hit:
		return cache_hit

	return await _enqueue_request({
		"type": "asset",
		"key": cache_key,
		"asset_path": asset_path
	})


func request_meshlib_thumbnail(meshlib: MeshLibrary, item_id: int) -> ImageTexture:
	if not meshlib:
		return null

	var cache_key = "meshlib:" + str(meshlib.get_instance_id()) + ":" + str(item_id)
	var cache_hit = _cache.lookup(cache_key)
	if cache_hit:
		return cache_hit

	return await _enqueue_request({
		"type": "meshlib",
		"key": cache_key,
		"meshlib": meshlib,
		"item_id": item_id
	})


func clear_queue() -> void:
	_request_queue.clear()

	for request_id in _pending_requests.keys():
		var awaiter: SignalAwaiter = _pending_requests[request_id]
		awaiter.complete_with_result(null)

	_pending_requests.clear()
	_inflight_keys.clear()
	_is_processing = false


func _enqueue_request(payload: Dictionary) -> ImageTexture:
	var key: String = payload.get("key", "")

	if _inflight_keys.has(key):
		return await (_inflight_keys[key] as SignalAwaiter).wait_for_result()

	var request = _build_request(payload)
	_request_queue.append(request)
	_pending_requests[request.id] = request.awaiter
	_inflight_keys[key] = request.awaiter

	if not _is_processing:
		_process_queue()

	var result = await request.awaiter.wait_for_result()
	_pending_requests.erase(request.id)
	_inflight_keys.erase(key)
	return result


func _process_queue() -> void:
	if _request_queue.is_empty():
		_is_processing = false
		return

	_is_processing = true
	var request = _request_queue.pop_front()
	await _process_request(request)
	call_deferred("_process_queue")


func _build_request(payload: Dictionary) -> ThumbnailRequest:
	_request_id += 1
	return ThumbnailRequest.new(_request_id, payload)


func _process_request(request: ThumbnailRequest) -> void:
	var texture: ImageTexture = null

	match request.type:
		"asset":
			texture = await ThumbnailGenerator.generate_mesh_thumbnail(request.asset_path)
		"meshlib":
			texture = await ThumbnailGenerator.generate_meshlib_thumbnail(
				request.meshlib, request.item_id
			)
		_:
			PluginLogger.error(
				PluginConstants.COMPONENT_THUMBNAIL, "Unknown thumbnail request type: %s" % request.type
			)

	if request.cache_key != "" and texture:
		_cache.store(request.cache_key, texture)

	request.awaiter.complete_with_result(texture)


class ThumbnailRequest extends RefCounted:
	var id: int
	var type: String
	var cache_key: String
	var asset_path: String
	var meshlib: MeshLibrary
	var item_id: int
	var awaiter: SignalAwaiter

	func _init(p_id: int, payload: Dictionary) -> void:
		id = p_id
		type = payload.get("type", "")
		cache_key = payload.get("key", "")
		asset_path = payload.get("asset_path", "")
		meshlib = payload.get("meshlib")
		item_id = payload.get("item_id", -1)
		awaiter = SignalAwaiter.new()


class SignalAwaiter extends RefCounted:
	signal result_ready(texture: ImageTexture)
	var _completed: bool = false
	var _result: ImageTexture = null

	func wait_for_result() -> ImageTexture:
		if _completed:
			return _result
		await result_ready
		return _result

	func complete_with_result(texture: ImageTexture) -> void:
		if _completed:
			return
		_completed = true
		_result = texture
		result_ready.emit(texture)
