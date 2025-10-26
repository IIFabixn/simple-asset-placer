@tool
extends RefCounted

class_name PluginLogger

"""
CENTRALIZED LOGGING SYSTEM
==========================

PURPOSE: Provides consistent logging with configurable levels to replace scattered print statements.

FEATURES:
- Multiple log levels (DEBUG, INFO, WARNING, ERROR)
- Configurable output level
- Automatic prefixing with component names
- Color-coded output for better readability
- Easy to disable debug logging in production

USAGE:
	PluginLogger.debug("Component", "Debug message")
	PluginLogger.info("Component", "Info message")
	PluginLogger.warning("Component", "Warning message")
	PluginLogger.error("Component", "Error message")
"""

enum LogLevel {
	DEBUG,    # Detailed debugging information
	INFO,     # General informational messages
	WARNING,  # Warning messages for potential issues
	ERROR     # Error messages for failures
}

# Current log level - messages below this level won't be printed
static var current_level: LogLevel = LogLevel.INFO

# Whether to include timestamps in logs
static var include_timestamp: bool = false

# Whether to use color coding (disable for file output)
static var use_colors: bool = true

# Color codes for different log levels
const COLOR_DEBUG = "gray"
const COLOR_INFO = "white"
const COLOR_WARNING = "yellow"
const COLOR_ERROR = "red"

## Core Logging Functions

static func debug(component: String, message: String) -> void:
	"""Log a debug message (only shown when current_level is DEBUG)"""
	if current_level <= LogLevel.DEBUG:
		_log(LogLevel.DEBUG, component, message)

static func info(component: String, message: String) -> void:
	"""Log an informational message"""
	if current_level <= LogLevel.INFO:
		_log(LogLevel.INFO, component, message)

static func warning(component: String, message: String) -> void:
	"""Log a warning message"""
	if current_level <= LogLevel.WARNING:
		_log(LogLevel.WARNING, component, message)

static func error(component: String, message: String) -> void:
	"""Log an error message - always shown"""
	_log(LogLevel.ERROR, component, message)

## Configuration

static func set_log_level(level: LogLevel) -> void:
	"""Set the minimum log level to display"""
	current_level = level

static func set_log_level_from_string(level_string: String) -> void:
	"""Set log level from string (DEBUG, INFO, WARNING, ERROR)"""
	match level_string.to_upper():
		"DEBUG":
			current_level = LogLevel.DEBUG
		"INFO":
			current_level = LogLevel.INFO
		"WARNING":
			current_level = LogLevel.WARNING
		"ERROR":
			current_level = LogLevel.ERROR
		_:
			push_warning("Invalid log level: " + level_string + ", using INFO")
			current_level = LogLevel.INFO

static func enable_debug_mode() -> void:
	"""Convenience function to enable debug logging"""
	current_level = LogLevel.DEBUG
	_log(LogLevel.INFO, "PluginLogger", "=== DEBUG MODE ENABLED ===")

static func enable_production_mode() -> void:
	"""Convenience function to show only warnings and errors"""
	current_level = LogLevel.WARNING
	_log(LogLevel.INFO, "PluginLogger", "=== PRODUCTION MODE ENABLED ===")

## Internal Implementation

static func _log(level: LogLevel, component: String, message: String) -> void:
	"""Internal logging implementation"""
	var level_string = _get_level_string(level)
	var timestamp_string = ""
	
	if include_timestamp:
		timestamp_string = "[" + Time.get_time_string_from_system() + "] "
	
	var log_message = timestamp_string + "[" + level_string + "] [" + component + "] " + message
	
	# Use appropriate Godot logging function based on level
	match level:
		LogLevel.ERROR:
			printerr(log_message)
		LogLevel.WARNING:
			push_warning(log_message)
		LogLevel.DEBUG, LogLevel.INFO:
			# Use color coding if enabled for debug/info
			if use_colors and OS.has_feature("editor"):
				var color = _get_level_color(level)
				print_rich("[color=" + color + "]" + log_message + "[/color]")
			else:
				print(log_message)

static func _get_level_string(level: LogLevel) -> String:
	"""Get string representation of log level"""
	match level:
		LogLevel.DEBUG:
			return "DEBUG"
		LogLevel.INFO:
			return "INFO"
		LogLevel.WARNING:
			return "WARN"
		LogLevel.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN"

static func _get_level_color(level: LogLevel) -> String:
	"""Get color for log level"""
	match level:
		LogLevel.DEBUG:
			return COLOR_DEBUG
		LogLevel.INFO:
			return COLOR_INFO
		LogLevel.WARNING:
			return COLOR_WARNING
		LogLevel.ERROR:
			return COLOR_ERROR
		_:
			return COLOR_INFO

## Helper Functions

static func log_separator() -> void:
	"""Print a visual separator line"""
	if current_level <= LogLevel.INFO:
		print("=" + "=".repeat(79))

static func log_section(section_name: String) -> void:
	"""Print a section header"""
	if current_level <= LogLevel.INFO:
		log_separator()
		info("System", section_name)
		log_separator()

## Status Reporting

static func log_initialization(component: String) -> void:
	"""Log component initialization"""
	info(component, "Initializing...")

static func log_initialization_complete(component: String) -> void:
	"""Log successful initialization"""
	info(component, "Initialization complete")

static func log_cleanup(component: String) -> void:
	"""Log component cleanup"""
	info(component, "Cleaning up...")

static func log_cleanup_complete(component: String) -> void:
	"""Log successful cleanup"""
	info(component, "Cleanup complete")







