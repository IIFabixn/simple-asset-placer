extends Node
class_name ErrorHandler

## Error Handler
## Provides user-friendly error reporting with visual feedback
## Integrates with PluginLogger for detailed logging

# Import utilities
const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")

## Error Severity Levels

enum Severity {
	INFO,      # Informational message (green)
	WARNING,   # Warning that doesn't stop operation (yellow)
	ERROR,     # Error that stops current operation (red)
	CRITICAL   # Critical error requiring attention (dark red)
}

## User Feedback

static var _editor_interface: EditorInterface = null

static func initialize(editor_interface: EditorInterface) -> void:
	"""Initialize error handler with editor interface"""
	_editor_interface = editor_interface
	PluginLogger.info(PluginConstants.COMPONENT_MAIN, "ErrorHandler initialized")

## Dialog Cleanup Helper

static func _connect_dialog_cleanup(dialog: Window) -> void:
	"""Connect dialog signals with proper disconnection before queue_free
	
	This prevents memory leaks by ensuring signals are disconnected before
	the dialog is freed. Without disconnection, signal connections can linger
	in memory even after the dialog is destroyed.
	
	Args:
		dialog: The dialog window to set up cleanup for
	"""
	# Store references to the callables so we can disconnect them
	var callbacks = {
		"confirmed": Callable(),
		"canceled": Callable()
	}
	
	callbacks["confirmed"] = func():
		# Disconnect both signals before freeing
		if dialog.confirmed.is_connected(callbacks["confirmed"]):
			dialog.confirmed.disconnect(callbacks["confirmed"])
		if dialog.canceled.is_connected(callbacks["canceled"]):
			dialog.canceled.disconnect(callbacks["canceled"])
		dialog.queue_free()
	
	callbacks["canceled"] = func():
		# Disconnect both signals before freeing
		if dialog.confirmed.is_connected(callbacks["confirmed"]):
			dialog.confirmed.disconnect(callbacks["confirmed"])
		if dialog.canceled.is_connected(callbacks["canceled"]):
			dialog.canceled.disconnect(callbacks["canceled"])
		dialog.queue_free()
	
	dialog.confirmed.connect(callbacks["confirmed"])
	dialog.canceled.connect(callbacks["canceled"])

static func _connect_dialog_with_callbacks(dialog: Window, on_confirm: Callable, on_cancel: Callable) -> void:
	"""Connect dialog with user callbacks and proper cleanup
	
	This is similar to _connect_dialog_cleanup but also calls user-provided
	callbacks before disconnecting and freeing the dialog.
	
	Args:
		dialog: The dialog window to set up
		on_confirm: User callback for confirmed signal (can be invalid)
		on_cancel: User callback for canceled signal (can be invalid)
	"""
	var callbacks = {
		"confirmed": Callable(),
		"canceled": Callable()
	}
	
	callbacks["confirmed"] = func():
		# Call user callback first
		if on_confirm.is_valid():
			on_confirm.call()
		# Then disconnect and cleanup
		if dialog.confirmed.is_connected(callbacks["confirmed"]):
			dialog.confirmed.disconnect(callbacks["confirmed"])
		if dialog.canceled.is_connected(callbacks["canceled"]):
			dialog.canceled.disconnect(callbacks["canceled"])
		dialog.queue_free()
	
	callbacks["canceled"] = func():
		# Call user callback first
		if on_cancel.is_valid():
			on_cancel.call()
		# Then disconnect and cleanup
		if dialog.confirmed.is_connected(callbacks["confirmed"]):
			dialog.confirmed.disconnect(callbacks["confirmed"])
		if dialog.canceled.is_connected(callbacks["canceled"]):
			dialog.canceled.disconnect(callbacks["canceled"])
		dialog.queue_free()
	
	dialog.confirmed.connect(callbacks["confirmed"])
	dialog.canceled.connect(callbacks["canceled"])

## User-Facing Error Messages

static func show_error(component: String, title: String, message: String, details: String = "") -> void:
	"""Show error dialog to user and log error"""
	PluginLogger.error(component, message)
	
	if _editor_interface:
		var dialog = AcceptDialog.new()
		dialog.title = title
		dialog.dialog_text = message
		
		if details != "":
			dialog.dialog_text += "\n\nDetails: " + details
		
		# Add to editor main screen to ensure visibility
		var base = _editor_interface.get_base_control()
		if base:
			base.add_child(dialog)
			dialog.popup_centered(Vector2i(400, 200))
			# Cleanup when closed - properly disconnect signals to prevent memory leaks
			_connect_dialog_cleanup(dialog)
	
	# Also push to Godot's error system
	push_error("[" + component + "] " + message)

static func show_warning(component: String, title: String, message: String, details: String = "") -> void:
	"""Show warning dialog to user and log warning"""
	PluginLogger.warning(component, message)
	
	if _editor_interface:
		var dialog = AcceptDialog.new()
		dialog.title = title
		dialog.dialog_text = message
		
		if details != "":
			dialog.dialog_text += "\n\nDetails: " + details
		
		var base = _editor_interface.get_base_control()
		if base:
			base.add_child(dialog)
			dialog.popup_centered(Vector2i(400, 200))
			_connect_dialog_cleanup(dialog)
	
	push_warning("[" + component + "] " + message)

static func show_info(component: String, title: String, message: String) -> void:
	"""Show info dialog to user and log info"""
	PluginLogger.info(component, message)
	
	if _editor_interface:
		var dialog = AcceptDialog.new()
		dialog.title = title
		dialog.dialog_text = message
		
		var base = _editor_interface.get_base_control()
		if base:
			base.add_child(dialog)
			dialog.popup_centered(Vector2i(350, 150))
			_connect_dialog_cleanup(dialog)

## Quick Feedback (No Dialog)

static func log_and_notify(component: String, message: String, severity: Severity = Severity.INFO) -> void:
	"""Log message and optionally show brief notification (no blocking dialog)"""
	match severity:
		Severity.INFO:
			PluginLogger.info(component, message)
		Severity.WARNING:
			PluginLogger.warning(component, message)
			push_warning("[" + component + "] " + message)
		Severity.ERROR:
			PluginLogger.error(component, message)
			push_error("[" + component + "] " + message)
		Severity.CRITICAL:
			PluginLogger.error(component, "CRITICAL: " + message)
			push_error("[" + component + "] CRITICAL: " + message)

## Resource Loading Errors

static func handle_resource_load_error(component: String, path: String, error_code: int = -1) -> void:
	"""Handle resource loading failure with user feedback"""
	var error_msg = "Failed to load resource: " + path
	
	if error_code != -1:
		error_msg += " (Error code: " + str(error_code) + ")"
	
	var details = _get_resource_error_details(path, error_code)
	
	show_error(component, "Resource Load Failed", error_msg, details)

static func _get_resource_error_details(path: String, error_code: int) -> String:
	"""Get detailed error information for resource loading"""
	var details = ""
	
	# Check if file exists
	if not FileAccess.file_exists(path):
		details += "File does not exist at path.\n"
	
	# Check file extension
	var ext = path.get_extension().to_lower()
	if ext == "":
		details += "File has no extension.\n"
	
	# Common error codes
	match error_code:
		ERR_FILE_NOT_FOUND:
			details += "File not found in filesystem.\n"
		ERR_FILE_CANT_OPEN:
			details += "Cannot open file (permissions issue?).\n"
		ERR_PARSE_ERROR:
			details += "File format is invalid or corrupted.\n"
	
	if details == "":
		details = "Unknown error occurred during loading."
	
	return details

## Asset Validation Errors

static func handle_invalid_asset(component: String, asset_path: String, reason: String) -> void:
	"""Handle invalid asset with user feedback"""
	var message = "Invalid asset: " + asset_path.get_file()
	var details = "Reason: " + reason + "\n\nPath: " + asset_path
	
	show_warning(component, "Invalid Asset", message, details)

static func handle_no_mesh_in_asset(component: String, asset_path: String) -> void:
	"""Handle asset with no mesh data"""
	handle_invalid_asset(component, asset_path, "Asset contains no mesh data")

## Placement Errors

static func handle_placement_error(component: String, reason: String) -> void:
	"""Handle placement failure with user feedback"""
	var message = "Cannot place asset: " + reason
	
	log_and_notify(component, message, Severity.WARNING)

static func handle_collision_error(component: String, details: String = "") -> void:
	"""Handle collision detection error"""
	var message = "Collision detection failed"
	if details != "":
		message += ": " + details
	
	log_and_notify(component, message, Severity.WARNING)

## Scene/Node Errors

static func handle_scene_error(component: String, operation: String, details: String = "") -> void:
	"""Handle scene manipulation error"""
	var message = "Scene operation failed: " + operation
	
	show_error(component, "Scene Error", message, details)

static func handle_node_error(component: String, node_name: String, operation: String) -> void:
	"""Handle node manipulation error"""
	var message = "Failed to " + operation + " node: " + node_name
	
	log_and_notify(component, message, Severity.ERROR)

## Input/Key Binding Errors

static func handle_key_conflict(component: String, key: String, action1: String, action2: String) -> void:
	"""Handle key binding conflict"""
	var message = "Key binding conflict detected for '" + key + "'"
	var details = "Both '" + action1 + "' and '" + action2 + "' are assigned to the same key.\n\n"
	details += "Please change one of the key bindings in the plugin settings."
	
	show_warning(component, "Key Binding Conflict", message, details)

static func handle_invalid_key_binding(component: String, action: String, key: String) -> void:
	"""Handle invalid key binding"""
	var message = "Invalid key binding for '" + action + "': " + key
	var details = "The key '" + key + "' is not recognized or cannot be used.\n\n"
	details += "Please choose a different key."
	
	show_warning(component, "Invalid Key Binding", message, details)

## Thumbnail Generation Errors

static func handle_thumbnail_error(component: String, asset_path: String, reason: String = "") -> void:
	"""Handle thumbnail generation failure"""
	var message = "Failed to generate thumbnail for: " + asset_path.get_file()
	
	if reason != "":
		PluginLogger.error(component, message + " - " + reason)
	else:
		PluginLogger.error(component, message)
	
	# Don't show dialog for thumbnail errors (too many potential failures)
	# Just log them

## Settings Errors

static func handle_settings_error(component: String, operation: String, details: String = "") -> void:
	"""Handle settings save/load error"""
	var message = "Settings operation failed: " + operation
	
	show_error(component, "Settings Error", message, details)

static func handle_invalid_setting_value(component: String, setting_name: String, value: String, constraint: String) -> void:
	"""Handle invalid setting value"""
	var message = "Invalid value for '" + setting_name + "': " + value
	var details = "Constraint: " + constraint + "\n\n"
	details += "The setting has been reset to its default value."
	
	show_warning(component, "Invalid Setting", message, details)

## Confirmation Dialogs

static func show_confirmation(title: String, message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	"""Show confirmation dialog with callbacks"""
	if not _editor_interface:
		PluginLogger.warning(PluginConstants.COMPONENT_MAIN, 
			"Cannot show confirmation dialog: EditorInterface not initialized")
		return
	
	var dialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	
	var base = _editor_interface.get_base_control()
	if base:
		base.add_child(dialog)
		
		# Connect callbacks with proper cleanup
		_connect_dialog_with_callbacks(dialog, on_confirm, on_cancel)
		
		dialog.popup_centered(Vector2i(400, 150))

## Recovery Suggestions

static func suggest_recovery(component: String, problem: String, suggestions: Array[String]) -> void:
	"""Show error with recovery suggestions"""
	var message = problem + "\n\nSuggested solutions:"
	
	for i in range(suggestions.size()):
		message += "\n" + str(i + 1) + ". " + suggestions[i]
	
	show_error(component, "Error - Recovery Suggestions", message)

## Validation

static func validate_file_path(path: String) -> bool:
	"""Validate file path and return true if valid"""
	if path == "":
		return false
	
	if not path.begins_with("res://") and not path.begins_with("user://"):
		return false
	
	return true

static func validate_node(node: Node) -> bool:
	"""Validate node is valid and in tree"""
	if not node:
		return false
	
	if not is_instance_valid(node):
		return false
	
	return true

## Debug

static func get_error_handler_status() -> Dictionary:
	"""Get status of error handler"""
	return {
		"initialized": _editor_interface != null,
		"can_show_dialogs": _editor_interface != null
	}







