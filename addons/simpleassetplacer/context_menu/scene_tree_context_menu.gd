@tool
extends EditorContextMenuPlugin

"""
SCENE TREE CONTEXT MENU PLUGIN
================================

PURPOSE: Add custom context menu option to set parent placement target from scene tree

WORKFLOW:
1. Right-click a node in the scene tree
2. Select "Set as Asset Parent"
3. Custom parent path is automatically updated in settings
4. Parent placement mode is switched to "custom"

USED BY: Main plugin (registered as context menu plugin)
"""

const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PickupHandler = preload("res://addons/simpleassetplacer/utils/pickup_handler.gd")

# Dependencies
var _settings_manager
var _dock  # Reference to AssetPlacerDock to refresh UI
var _plugin  # Reference to main plugin for triggering pickup mode


func set_settings_manager(settings_manager) -> void:
	"""Inject settings manager dependency"""
	_settings_manager = settings_manager


func set_dock_reference(dock) -> void:
	"""Inject dock reference for UI refresh"""
	_dock = dock


func set_plugin_reference(plugin) -> void:
	"""Inject main plugin reference for pickup mode"""
	_plugin = plugin


func _popup_menu(paths: PackedStringArray) -> void:
	"""Called when scene tree context menu is opened
	
	Args:
		paths: Array containing node paths of selected nodes
	"""
	if paths.is_empty():
		return

	# Get selected nodes
	var selected_nodes: Array = []
	for path in paths:
		var node = _get_node_from_path(path)
		if node:
			selected_nodes.append(node)

	if selected_nodes.is_empty():
		return

	# Add "Set as Asset Parent" only for single selection
	if paths.size() == 1:
		add_context_menu_item("Set as Asset Parent", _on_set_as_parent, null)

	# Add "Pickup for Placement" if nodes can be picked up
	if PickupHandler.can_pickup_nodes(selected_nodes):
		add_context_menu_item("Pickup for Placement", _on_pickup_for_placement, null)


func _on_set_as_parent(paths: PackedStringArray) -> void:
	"""Callback when user clicks 'Set as Asset Parent'
	
	Args:
		paths: Array containing the selected node paths
	"""
	if paths.size() != 1:
		return

	# Get the selected node from the path
	var node_path = paths[0]
	var selected_node = _get_node_from_path(node_path)
	if not selected_node or not is_instance_valid(selected_node):
		PluginLogger.warning("SceneTreeContextMenu", "Selected node is not valid")
		return

	# Get scene root to calculate relative path
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		PluginLogger.warning("SceneTreeContextMenu", "No scene is currently open")
		return

	# Calculate path relative to scene root
	var relative_path: String
	if selected_node == scene_root:
		# If root is selected, use empty string (which means "use root")
		relative_path = ""
	else:
		relative_path = str(scene_root.get_path_to(selected_node))

	# Update settings
	if _settings_manager:
		# Set the custom parent path
		_settings_manager.set_plugin_setting("custom_parent_path", relative_path)

		# Switch mode to "custom" so it's actually used
		_settings_manager.set_plugin_setting(
			"parent_placement_mode", PluginConstants.PARENT_MODE_CUSTOM
		)

		# Save to EditorSettings
		_settings_manager.save_plugin_settings_to_editor()

		# Refresh the UI to show the updated settings
		if _dock and _dock.has_method("refresh_placement_settings_ui"):
			_dock.refresh_placement_settings_ui()

		var node_name = selected_node.name if selected_node != scene_root else "Scene Root"
		PluginLogger.info(
			"SceneTreeContextMenu",
			"Asset parent set to: %s (path: '%s')" % [node_name, relative_path]
		)
	else:
		PluginLogger.error("SceneTreeContextMenu", "Settings manager not available")


func _on_pickup_for_placement(paths: PackedStringArray) -> void:
	"""Callback when user clicks 'Pickup for Placement'
	
	Args:
		paths: Array containing the selected node paths
	"""
	if paths.is_empty():
		return

	# Get selected nodes
	var selected_nodes: Array = []
	for path in paths:
		var node = _get_node_from_path(path)
		if node:
			selected_nodes.append(node)

	if selected_nodes.is_empty():
		PluginLogger.warning("SceneTreeContextMenu", "No valid nodes selected for pickup")
		return

	# Trigger pickup mode via main plugin
	if _plugin and _plugin.has_method("trigger_pickup_mode"):
		_plugin.trigger_pickup_mode(selected_nodes)
	else:
		PluginLogger.error(
			"SceneTreeContextMenu", "Cannot trigger pickup mode - plugin reference not set"
		)


func _get_node_from_path(node_path_str: String) -> Node:
	"""Get node instance from path string
	
	Args:
		node_path_str: String representation of node path from editor (relative to scene root)
	
	Returns:
		Node instance or null if not found
	"""
	# Get the scene root
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		PluginLogger.warning("SceneTreeContextMenu", "No scene root found")
		return null

	# If the path is just the root name, return the root
	if node_path_str == scene_root.name:
		return scene_root

	# Otherwise, get the node relative to scene root
	var node = scene_root.get_node_or_null(NodePath(node_path_str))
	return node
