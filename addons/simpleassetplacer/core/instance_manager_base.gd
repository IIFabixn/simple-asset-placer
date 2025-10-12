@tool
extends RefCounted

class_name InstanceManagerBase

"""
INSTANCE MANAGER BASE CLASS
============================

PURPOSE: Base class for hybrid static/instance manager pattern during Phase 5.2 migration

RESPONSIBILITIES:
- Provide singleton instance management
- Enable hybrid static/instance access pattern
- Support gradual migration from static to instance-based architecture
- Allow backward compatibility during transition

ARCHITECTURE POSITION: Base class for all managers
- Managers extend this class to gain hybrid capabilities
- Main plugin creates instances and registers them
- Static code continues to work via property getters

MIGRATION PATTERN:
1. Manager extends InstanceManagerBase
2. Convert static vars to instance vars (with underscore prefix)
3. Add static property getters that forward to instance
4. Main plugin creates instance and calls _set_instance()
5. All existing static code continues to work unchanged

USAGE EXAMPLE:
```gdscript
@tool
class_name MyManager extends InstanceManagerBase

# Instance variables (real data storage)
var _my_data: Dictionary = {}
var _my_state: bool = false

# Static properties (backward compatibility via forwarding)
static var my_data: Dictionary:
    get: return _get_instance()._my_data if has_instance() else {}
    set(value): if has_instance(): _get_instance()._my_data = value

static var my_state: bool:
    get: return _get_instance()._my_state if has_instance() else false
    set(value): if has_instance(): _get_instance()._my_state = value

# Static functions (unchanged - use static properties internally)
static func do_something():
    my_data["key"] = "value"  # Uses static property getter
    my_state = true           # Uses static property setter
```

MAIN PLUGIN INITIALIZATION:
```gdscript
# In simpleassetplacer.gd _enter_tree():
var my_manager = MyManager.new()
MyManager._set_instance(my_manager)

# In simpleassetplacer.gd _exit_tree():
MyManager._set_instance(null)
my_manager = null
```

BENEFITS:
- Testability: Can create instances with dependency injection
- Memory Safety: Proper lifecycle management (no static leaks)
- Backward Compatibility: Existing static calls continue to work
- Incremental Migration: Can convert managers one at a time
- Multiple Instances: Can have multiple plugin instances

FUTURE:
After Phase 5.2 is stable, we can optionally remove the static property
getters and update all call sites to use instance methods directly.
"""

## SINGLETON INSTANCE MANAGEMENT

# CRITICAL: Each manager class MUST declare its own static _instance variable!
# DO NOT declare static var _instance in this base class - it would be shared by all subclasses!
# 
# WHY: In GDScript, static variables are bound to the class where they are declared.
#      If we put _instance in the base class, ALL manager classes would share the same
#      static variable, causing type errors and incorrect instance retrieval.
#
# REQUIRED IN EACH SUBCLASS:
#   static var _instance: YourManagerClass = null
#
#   static func _set_instance(instance: InstanceManagerBase) -> void:
#       _instance = instance as YourManagerClass
#
#   static func _get_instance() -> InstanceManagerBase:
#       return _instance
#
#   static func has_instance() -> bool:
#       return _instance != null and is_instance_valid(_instance)
#
# This ensures each manager has its own independent singleton instance.

static func _set_instance(instance: InstanceManagerBase) -> void:
	"""Set the singleton instance for this manager class
	
	MUST BE OVERRIDDEN in each subclass!
	
	Called by main plugin during initialization:
	  var coordinator = TransformationCoordinator.new()
	  TransformationCoordinator._set_instance(coordinator)
	
	Called by main plugin during cleanup:
	  TransformationCoordinator._set_instance(null)
	
	Args:
		instance: The instance to register, or null to clear
	"""
	push_error("InstanceManagerBase._set_instance() must be overridden in subclass!")

static func _get_instance() -> InstanceManagerBase:
	"""Get the singleton instance for this manager class
	
	MUST BE OVERRIDDEN in each subclass!
	
	Used internally by static property getters:
	  static var my_data: Dictionary:
	      get: return _get_instance()._my_data if has_instance() else {}
	
	Returns:
		InstanceManagerBase: The registered instance, or null if not set
	"""
	push_error("InstanceManagerBase._get_instance() must be overridden in subclass!")
	return null

static func has_instance() -> bool:
	"""Check if a singleton instance has been registered
	
	MUST BE OVERRIDDEN in each subclass!
	
	Used for null-safety in static property getters:
	  if has_instance():
	      return _get_instance()._my_data
	
	Returns:
		bool: True if instance is set and valid, false otherwise
	"""
	push_error("InstanceManagerBase.has_instance() must be overridden in subclass!")
	return false

## LIFECYCLE HOOKS (Optional)

func initialize() -> void:
	"""Override in subclass to perform initialization
	
	Called by main plugin after instance creation:
	  var overlay_mgr = OverlayManager.new()
	  overlay_mgr.initialize()
	"""
	pass

func cleanup() -> void:
	"""Override in subclass to perform cleanup
	
	Called by main plugin before clearing instance:
	  overlay_mgr.cleanup()
	  OverlayManager._set_instance(null)
	"""
	pass

## DEBUG HELPERS

static func get_instance_info() -> String:
	"""Get debug information about the instance state
	
	Returns:
		String: Human-readable instance status
	"""
	if not has_instance():
		return "No instance registered"
	
	var inst = _get_instance()
	return "Instance: %s (RefCount: %d)" % [
		inst.get_class(),
		inst.get_reference_count() if inst.has_method("get_reference_count") else -1
	]

## USAGE NOTES

# PATTERN 1: Simple State Variable
# --------------------------------
# Instance:  var _enabled: bool = true
# Static:    static var enabled: bool:
#                get: return _get_instance()._enabled if has_instance() else true
#                set(value): if has_instance(): _get_instance()._enabled = value

# PATTERN 2: Object Reference
# ---------------------------
# Instance:  var _overlay: Control = null
# Static:    static var overlay: Control:
#                get: return _get_instance()._overlay if has_instance() else null
#                set(value): if has_instance(): _get_instance()._overlay = value

# PATTERN 3: Dictionary/Array
# ---------------------------
# Instance:  var _data: Dictionary = {}
# Static:    static var data: Dictionary:
#                get: return _get_instance()._data if has_instance() else {}
#                set(value): if has_instance(): _get_instance()._data = value

# PATTERN 4: Read-Only Computed Property
# --------------------------------------
# Instance:  var _counter: int = 0
# Static:    static var counter: int:
#                get: return _get_instance()._counter if has_instance() else 0
#            # No setter - computed/read-only

# ANTI-PATTERN: Don't Mix Static and Instance Data
# ------------------------------------------------
# BAD:  static var static_cache: Dictionary = {}  # Static data
#       var _instance_data: Dictionary = {}      # Instance data
#       # This defeats the purpose! Pick one pattern.

# ANTI-PATTERN: Don't Store Instance in Static Var
# ------------------------------------------------
# BAD:  static var cached_result: Variant = null
#       # This creates memory leaks! Use instance vars only.
