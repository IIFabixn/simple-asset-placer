@tool
extends RefCounted

class_name ThumbnailQueueManager

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

"""
LEGACY THUMBNAIL QUEUE MANAGER
==============================

This class is retained for backwards compatibility with older saved scenes or scripts
that may still reference `ThumbnailQueueManager`. New code should depend on
`ThumbnailService` instead.

All methods delegate to the global ThumbnailService instance registered through the
ServiceRegistry. When the service is unavailable we return null results.
"""

var _thumbnail_service: ThumbnailService = null


func _init(thumbnail_service: ThumbnailService = null) -> void:
	_thumbnail_service = thumbnail_service
	PluginLogger.warning(
		PluginConstants.COMPONENT_THUMBNAIL,
		"ThumbnailQueueManager is deprecated. Use ThumbnailService instead."
	)


func request_asset_thumbnail(asset_path: String) -> ImageTexture:
	if _ensure_service():
		return await _thumbnail_service.request_asset_thumbnail(asset_path)
	return null


func request_meshlib_thumbnail(meshlib: MeshLibrary, item_id: int = -1) -> ImageTexture:
	if _ensure_service():
		return await _thumbnail_service.request_meshlib_thumbnail(meshlib, item_id)
	return null


func clear_queue() -> void:
	if _ensure_service():
		_thumbnail_service.clear_queue()


func get_queue_size() -> int:
	return 0


func cleanup() -> void:
	pass


func _ensure_service() -> bool:
	if _thumbnail_service:
		return true
	PluginLogger.error(
		PluginConstants.COMPONENT_THUMBNAIL,
		"ThumbnailQueueManager has no ThumbnailService reference"
	)
	return false
