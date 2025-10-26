@tool
extends RefCounted

class_name EditorFacade

"""
EDITOR FACADE
=============

PURPOSE: Centralized wrapper for all EditorInterface operations

RESPONSIBILITIES:
- Provide safe, typed access to EditorInterface functionality
- Handle null checks and error cases
- Centralize editor dependency in one place
- Make testing easier by isolating editor calls

ARCHITECTURE POSITION: Utility/Facade layer
- Injected into managers that need editor access
- No static state
- Pure delegation pattern

USED BY: All managers that need editor access
USES: EditorInterface (Godot built-in)
"""

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

# The wrapped editor interface
var _editor_interface: EditorInterface

## Initialization

func _init(editor_interface: EditorInterface) -> void:
	"""Initialize the facade with an EditorInterface instance
	
	Args:
		editor_interface: The EditorInterface from the plugin
	"""
	assert(editor_interface != null, "EditorInterface cannot be null")
	_editor_interface = editor_interface

## Scene Access

func get_edited_scene_root() -> Node:
	"""Get the root node of the currently edited scene
	
	Returns:
		Node: The scene root, or null if no scene is open
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_edited_scene_root()

func get_selection() -> EditorSelection:
	"""Get the editor selection manager
	
	Returns:
		EditorSelection: The selection manager
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_selection()

## Viewport Access

func get_editor_viewport_3d(idx: int = 0) -> SubViewport:
	"""Get a 3D viewport by index
	
	Args:
		idx: Viewport index (default: 0)
		
	Returns:
		SubViewport: The viewport, or null if not found
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_editor_viewport_3d(idx)

func get_editor_main_screen() -> VBoxContainer:
	"""Get the main editor screen container
	
	Returns:
		VBoxContainer: The main screen container
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_editor_main_screen()

## Settings Access

func get_editor_settings() -> EditorSettings:
	"""Get the editor settings
	
	Returns:
		EditorSettings: The editor settings object
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_editor_settings()

## Theme Access

func get_editor_theme() -> Theme:
	"""Get the editor theme
	
	Returns:
		Theme: The editor theme, or null if not available
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_editor_theme()

## Inspector Access

func inspect_object(obj: Object) -> void:
	"""Inspect an object in the inspector
	
	Args:
		obj: The object to inspect
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return
	_editor_interface.inspect_object(obj)

## File System Access

func get_resource_filesystem() -> EditorFileSystem:
	"""Get the resource filesystem
	
	Returns:
		EditorFileSystem: The filesystem manager
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_resource_filesystem()

func get_resource_previewer() -> EditorResourcePreview:
	"""Get the resource previewer
	
	Returns:
		EditorResourcePreview: The previewer
	"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, "EditorInterface not available")
		return null
	return _editor_interface.get_resource_previewer()

## Editor Interface Access

func get_editor_interface() -> EditorInterface:
	"""Get the raw EditorInterface (for undo_redo and other direct access)
	
	Returns:
		EditorInterface: The wrapped editor interface
	"""
	return _editor_interface

## Validation

func is_valid() -> bool:
	"""Check if the facade has a valid EditorInterface
	
	Returns:
		bool: True if the EditorInterface is valid
	"""
	return _editor_interface != null
