@tool
extends RefCounted

class_name PluginConstants

"""
PLUGIN CONSTANTS
================

PURPOSE: Centralized location for all plugin constants to avoid magic numbers.

This file contains all hardcoded values used throughout the plugin,
making them easy to find, understand, and modify.
"""

## Thumbnail Settings
const DEFAULT_THUMBNAIL_SIZE: int = 64
const MIN_THUMBNAIL_SIZE: int = 64
const MAX_THUMBNAIL_SIZE: int = 128
const THUMBNAIL_VIEWPORT_SIZE: int = 256  # Internal rendering size for quality

## Thumbnail Cache Settings
const MAX_THUMBNAIL_CACHE_SIZE: int = 100  # Maximum thumbnails to keep in memory
const THUMBNAIL_CACHE_CLEANUP_THRESHOLD: int = 120  # Start cleanup at this size

## Grid Settings
const DEFAULT_GRID_SIZE: float = 1.0
const MIN_GRID_SIZE: float = 0.1
const MAX_GRID_SIZE: float = 1000.0
const DEFAULT_GRID_EXTENT: float = 20.0  # Visual grid radius in world units
const MIN_GRID_EXTENT: float = 5.0
const MAX_GRID_EXTENT: float = 100.0
const GRID_UPDATE_THRESHOLD: float = 5.0  # Update grid when object moves >5 units

## Input Settings
const TAP_GRACE_PERIOD: float = 0.15  # 150ms to distinguish tap from hold
const FOCUS_GRAB_FRAMES: int = 3  # Number of frames to grab viewport focus

## Rotation Settings
const DEFAULT_ROTATION_INCREMENT: float = 15.0  # Degrees
const FINE_ROTATION_INCREMENT: float = 5.0  # Degrees
const LARGE_ROTATION_INCREMENT: float = 90.0  # Degrees

## Scale Settings
const DEFAULT_SCALE_INCREMENT: float = 0.1
const FINE_SCALE_INCREMENT: float = 0.01
const LARGE_SCALE_INCREMENT: float = 0.5

## Height Adjustment Settings
const DEFAULT_HEIGHT_STEP: float = 0.1
const FINE_HEIGHT_INCREMENT: float = 0.01
const LARGE_HEIGHT_INCREMENT: float = 1.0

## Position Adjustment Settings (WASD keyboard movement)
const DEFAULT_POSITION_INCREMENT: float = 1.0  # Match typical grid snap size
const FINE_POSITION_INCREMENT: float = 0.1     # Precise adjustments with CTRL
const LARGE_POSITION_INCREMENT: float = 5.0    # Large movements with ALT

## Increment Modifiers (for keyboard-based transforms)
const FINE_SENSITIVITY_MULTIPLIER: float = 0.1  # CTRL modifier makes adjustments 10x more precise
const LARGE_SENSITIVITY_MULTIPLIER: float = 2.0  # ALT modifier makes adjustments 2x larger

## Preview Settings
const DEFAULT_PREVIEW_OPACITY: float = 0.6
const PREVIEW_VALID_COLOR: Color = Color(0.0, 1.0, 0.0, 0.6)  # Green, semi-transparent
const PREVIEW_INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6)  # Red, semi-transparent

## Camera Settings
const THUMBNAIL_CAMERA_FOV: float = 45.0
const THUMBNAIL_CAMERA_POSITION: Vector3 = Vector3(2, 2, 3)

## Lighting Settings
const THUMBNAIL_MAIN_LIGHT_ENERGY: float = 1.2
const THUMBNAIL_FILL_LIGHT_ENERGY: float = 0.4
const THUMBNAIL_AMBIENT_ENERGY: float = 0.3
const THUMBNAIL_BACKGROUND_COLOR: Color = Color(0.2, 0.2, 0.3, 1.0)

## UI Layout Settings
const DOCK_MIN_WIDTH: int = 200
const DOCK_MIN_HEIGHT: int = 400
const UI_MARGIN: int = 8
const UI_SEPARATION: int = 8
const GRID_H_SEPARATION: int = 12
const GRID_V_SEPARATION: int = 12

## File Extensions
const SUPPORTED_3D_EXTENSIONS: Array = ["obj", "fbx", "dae", "gltf", "glb", "blend"]
const SUPPORTED_SCENE_EXTENSIONS: Array = ["tscn", "scn"]
const SUPPORTED_RESOURCE_EXTENSIONS: Array = ["tres", "res"]
const SUPPORTED_MESHLIB_EXTENSIONS: Array = ["meshlib"]

## Default Key Bindings
const DEFAULT_KEY_CANCEL: String = "ESCAPE"
const DEFAULT_KEY_TRANSFORM_MODE: String = "TAB"
const DEFAULT_KEY_HEIGHT_UP: String = "Q"
const DEFAULT_KEY_HEIGHT_DOWN: String = "E"
const DEFAULT_KEY_RESET_HEIGHT: String = "R"
const DEFAULT_KEY_POSITION_LEFT: String = "A"
const DEFAULT_KEY_POSITION_RIGHT: String = "D"
const DEFAULT_KEY_POSITION_FORWARD: String = "W"
const DEFAULT_KEY_POSITION_BACKWARD: String = "S"
const DEFAULT_KEY_RESET_POSITION: String = "G"
const DEFAULT_KEY_ROTATE_X: String = "X"
const DEFAULT_KEY_ROTATE_Y: String = "Y"
const DEFAULT_KEY_ROTATE_Z: String = "Z"
const DEFAULT_KEY_RESET_ROTATION: String = "T"
const DEFAULT_KEY_SCALE_UP: String = "PAGE_UP"
const DEFAULT_KEY_SCALE_DOWN: String = "PAGE_DOWN"
const DEFAULT_KEY_SCALE_RESET: String = "HOME"
const DEFAULT_KEY_REVERSE_MODIFIER: String = "SHIFT"
const DEFAULT_KEY_LARGE_INCREMENT_MODIFIER: String = "ALT"

## Collision Settings
const DEFAULT_COLLISION_MASK: int = 1
const DEFAULT_RAYCAST_DISTANCE: float = 1000.0

## Status Messages
const STATUS_MESSAGE_DURATION_SHORT: float = 2.0
const STATUS_MESSAGE_DURATION_MEDIUM: float = 3.0
const STATUS_MESSAGE_DURATION_LONG: float = 5.0

const STATUS_COLOR_SUCCESS: Color = Color.GREEN
const STATUS_COLOR_INFO: Color = Color.CYAN
const STATUS_COLOR_WARNING: Color = Color.YELLOW
const STATUS_COLOR_ERROR: Color = Color.RED

## Component Names (for logging)
const COMPONENT_MAIN: String = "AssetPlacer"
const COMPONENT_DOCK: String = "AssetPlacerDock"
const COMPONENT_INPUT: String = "InputHandler"
const COMPONENT_POSITION: String = "PositionManager"
const COMPONENT_ROTATION: String = "RotationManager"
const COMPONENT_SCALE: String = "ScaleManager"
const COMPONENT_PREVIEW: String = "PreviewManager"
const COMPONENT_OVERLAY: String = "OverlayManager"
const COMPONENT_TRANSFORM: String = "TransformationManager"
const COMPONENT_THUMBNAIL: String = "ThumbnailGenerator"
const COMPONENT_UTILITY: String = "UtilityManager"
const COMPONENT_MESHLIB: String = "MeshLibBrowser"
const COMPONENT_MODELLIB: String = "ModelLibBrowser"

## Helper Functions

static func get_all_supported_extensions() -> Array:
	"""Get all supported file extensions"""
	var all_extensions = []
	all_extensions.append_array(SUPPORTED_3D_EXTENSIONS)
	all_extensions.append_array(SUPPORTED_SCENE_EXTENSIONS)
	all_extensions.append_array(SUPPORTED_RESOURCE_EXTENSIONS)
	all_extensions.append_array(SUPPORTED_MESHLIB_EXTENSIONS)
	return all_extensions

static func is_3d_model_extension(extension: String) -> bool:
	"""Check if extension is a 3D model format"""
	return extension.to_lower() in SUPPORTED_3D_EXTENSIONS

static func is_scene_extension(extension: String) -> bool:
	"""Check if extension is a scene format"""
	return extension.to_lower() in SUPPORTED_SCENE_EXTENSIONS

static func is_resource_extension(extension: String) -> bool:
	"""Check if extension is a resource format"""
	return extension.to_lower() in SUPPORTED_RESOURCE_EXTENSIONS

static func is_meshlib_extension(extension: String) -> bool:
	"""Check if extension is a MeshLibrary format"""
	return extension.to_lower() in SUPPORTED_MESHLIB_EXTENSIONS







