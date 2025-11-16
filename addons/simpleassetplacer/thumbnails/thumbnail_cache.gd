@tool
extends RefCounted

class_name ThumbnailCache

var _max_size: int
var _cache: Dictionary = {}
var _usage_order: Array[String] = []


func _init(max_size: int) -> void:
	_max_size = max(1, max_size)


func lookup(key: String) -> ImageTexture:
	if key in _cache:
		_usage_order.erase(key)
		_usage_order.append(key)
		return _cache[key]
	return null


func store(key: String, texture: ImageTexture) -> void:
	if key in _cache:
		_usage_order.erase(key)
	else:
		if _cache.size() >= _max_size:
			_evict()
	_cache[key] = texture
	_usage_order.append(key)


func clear() -> void:
	_cache.clear()
	_usage_order.clear()


func stats() -> Dictionary:
	return {
		"size": _cache.size(),
		"max_size": _max_size,
		"usage_percent": float(_cache.size()) / float(_max_size) * 100.0
	}


func _evict() -> void:
	if _usage_order.is_empty():
		return
	var oldest = _usage_order.pop_front()
	_cache.erase(oldest)
