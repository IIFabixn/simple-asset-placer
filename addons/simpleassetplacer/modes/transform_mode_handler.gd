@tool
extends RefCounted

class_name TransformModeHandler

const PluginLogger = preload("res://addons/simpleassetplacer/utils/plugin_logger.gd")
const PluginConstants = preload("res://addons/simpleassetplacer/utils/plugin_constants.gd")
const NodeUtils = preload("res://addons/simpleassetplacer/utils/node_utils.gd")
const UndoRedoHelper = preload("res://addons/simpleassetplacer/utils/undo_redo_helper.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const SettingsManager = preload("res://addons/simpleassetplacer/settings/settings_manager.gd")
const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const ModeStateMachine = preload("res://addons/simpleassetplacer/core/mode_state_machine.gd")
const ScaleManager = preload("res://addons/simpleassetplacer/managers/scale_manager.gd")
const NumericInputManager = preload("res://addons/simpleassetplacer/managers/numeric_input_manager.gd")

var _services: ServiceRegistry

func _init(services: ServiceRegistry) -> void:
	_services = services

func enter_transform_mode(target_nodes: Variant, settings: Dictionary, transform_state: TransformState, undo_redo: EditorUndoRedoManager = null) -> Dictionary:
	if target_nodes is Node3D:
		target_nodes = [target_nodes]
	elif not target_nodes is Array:
		return {}
	if target_nodes.is_empty():
		return {}
	var valid_nodes = []
	for node in target_nodes:
		if NodeUtils.validate_node3d(node):
			valid_nodes.append(node)
	if valid_nodes.is_empty():
		PluginLogger.warning("TransformModeHandler", "No valid Node3D objects to transform")
		return {}
	var original_transforms = {}
	for node in valid_nodes:
		if is_instance_valid(node):
			original_transforms[node] = node.transform
	var center_pos = get_transform_center(valid_nodes)
	if center_pos == Vector3.ZERO:
		PluginLogger.error("TransformModeHandler", "No nodes in tree to transform")
		return {}
	var node_offsets = _calculate_node_offsets(valid_nodes, center_pos)
	_services.position_manager.configure(transform_state, settings)
	transform_state.position = center_pos
	transform_state.base_height = center_pos.y
	
	# Start in Position control mode (G) by default
	if _services.control_mode_state:
		_services.control_mode_state.switch_to_position_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Auto-activated Position control (G) on transform mode entry")
	
	var transform_data = {
		"target_nodes": valid_nodes,
		"original_transforms": original_transforms,
		"center_position": center_pos,
		"node_offsets": node_offsets,
		"settings": settings,
		"undo_redo": undo_redo,
		"accumulated_y_delta": 0.0,
		"manual_position_offset": Vector3.ZERO
	}
	_services.overlay_manager.initialize_overlays()
	_services.overlay_manager.set_mode(2)
	update_overlays(transform_data)
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Started transform mode for " + str(valid_nodes.size()) + " node(s)")
	return transform_data

func exit_transform_mode(transform_data: Dictionary, transform_state: TransformState, confirm_changes: bool, settings: Dictionary) -> void:
	if not confirm_changes:
		restore_original_state(transform_data)
	_reset_transforms_on_exit(transform_state, settings)
	_services.overlay_manager.hide_transform_overlay()
	_services.overlay_manager.set_mode(0)
	_services.overlay_manager.remove_grid_overlay()
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Exited transform mode")

func process_input(camera: Camera3D, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary, delta: float) -> void:
	if not camera:
		return
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	
	# Process control mode transitions (G/R/L keys) and axis constraints (X/Y/Z keys)
	_process_control_mode_input(transform_data, transform_state)
	
	# Get control mode state to determine input routing
	var control_mode = _services.control_mode_state
	var modal_active = control_mode.is_modal_active() if control_mode else false
	
	# Get input dictionaries (InputHandler already suppresses numeric taps when modal active)
	var position_input = _services.input_handler.get_position_input()
	var rotation_input = _services.input_handler.get_rotation_input()
	var scale_input = _services.input_handler.get_scale_input()
	var numeric_input = _services.input_handler.get_numeric_input()
	var numeric_mgr = _services.numeric_input_manager
	
	# === INPUT ROUTING ===
	# Simple rule: If modal active (G/R/L pressed), skip keyboard input tracking
	# Otherwise, process keyboard input for numeric system and direct controls
	
	if not modal_active:
		# Track action key presses for numeric input system
		_track_action_for_numeric_input(rotation_input, scale_input, position_input)
		
		# Process numeric input keys
		_process_numeric_input(numeric_input, numeric_mgr)
	
	# Check for numeric input confirmation and application
	var numeric_was_confirmed = false
	if numeric_mgr.is_confirmed():
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Applying numeric input...")
		_apply_numeric_input(transform_data, transform_state, settings)
		numeric_mgr.reset()
		numeric_was_confirmed = true
	
	# Update numeric input overlay if active
	if numeric_mgr.is_active() and numeric_mgr.is_within_grace_period():
		var action_name = numeric_mgr.get_action_display_name()
		var input_string = numeric_mgr.get_input_string()
		_services.overlay_manager.show_numeric_input(action_name, input_string)
	
	# If numeric input is active, skip normal input processing (except mouse/position tracking)
	var skip_normal_input = numeric_mgr.is_active() and not numeric_mgr.is_confirmed()
	
	# Set half-step mode based on configured fine increment modifier
	var fine_modifier_held = position_input.fine_increment_modifier_held
	_services.position_manager.set_use_half_step(fine_modifier_held)
	transform_state.use_half_step = fine_modifier_held
	
	# Process height input (Q/E for quick vertical adjustments)
	if not skip_normal_input:
		_process_height_input(position_input, transform_data, transform_state, settings)
	
	# Get mouse position for modal control processing
	var mouse_pos = position_input.get("mouse_position", Vector2.ZERO)
	
	# === MODAL CONTROL PROCESSING ===
	# Process modal controls (G/R/L + mouse) when modal is active
	const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")
	if modal_active:
		match control_mode.get_control_mode():
			ControlModeState.ControlMode.POSITION:
				# G mode: Mouse controls position
				# Store previous center position for axis constraint
				var prev_center = transform_data.get("center_position", transform_state.position)
				
				# Calculate new position based on axis constraints
				var center_pos = Vector3.ZERO
				
				if control_mode.has_axis_constraint():
					# Use plane intersection for constrained movement
					center_pos = _calculate_constrained_position(camera, mouse_pos, prev_center, control_mode)
				else:
					# No constraints: Use raycast for precise surface-based positioning
					# This gives better control by snapping to actual geometry in the scene
					center_pos = _services.position_manager.update_position_from_mouse(
						transform_state, camera, mouse_pos, 1, false, target_nodes
					)
				
				# Apply grid snapping if enabled (for modal G mode positioning)
				# Pass fine modifier state for half-step sub-grid
				const TransformApplicator = preload("res://addons/simpleassetplacer/core/transform_applicator.gd")
				if transform_state.snap_enabled or transform_state.snap_y_enabled:
					var use_half_step = position_input.get("fine_increment_modifier_held", false)
					center_pos = TransformApplicator.apply_grid_snap(center_pos, transform_state, use_half_step)
				
				transform_state.position = center_pos
				transform_data["center_position"] = center_pos
				
				# Apply position immediately to nodes (bypass smooth transforms during modal control)
				var node_offsets = transform_data.get("node_offsets", {})
				for node in target_nodes:
					if node and node.is_inside_tree():
						var offset = node_offsets.get(node, Vector3.ZERO)
						node.global_position = center_pos + offset
			
			ControlModeState.ControlMode.ROTATION:
				# R mode: Mouse controls rotation
				if not skip_normal_input:
					_process_mouse_rotation(camera, mouse_pos, transform_data, transform_state, settings)
			
			ControlModeState.ControlMode.SCALE:
				# L mode: Mouse controls scale
				if not skip_normal_input:
					_process_mouse_scale(mouse_pos, transform_data, transform_state, settings)
	
	# Handle confirm action (left click or Enter key)
	if position_input.get("confirm_action", false):
		# If numeric input is active or was just confirmed, don't exit
		if numeric_mgr.is_active() or numeric_was_confirmed:
			if numeric_mgr.is_active():
				numeric_mgr.confirm_action()
			# Don't exit - numeric input takes priority
			# Continue processing to apply the value
		else:
			transform_data["_confirm_exit"] = true
			return
	
	# If numeric input was just confirmed, don't exit - let user continue transforming
	if skip_normal_input:
		return
	
	# Apply group transformation (for smooth position updates)
	_apply_group_transformation(transform_data, transform_state)
	
	update_overlays(transform_data)

func _process_height_input(position_input: Dictionary, transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	var height_up = position_input.get("height_up_pressed", false)
	var height_down = position_input.get("height_down_pressed", false)
	var reset_height = position_input.get("reset_height_pressed", false)
	
	if reset_height:
		_services.position_manager.reset_height(transform_state)
		var center_pos = Vector3(transform_state.position.x, transform_state.base_height + transform_state.height_offset, transform_state.position.z)
		transform_state.position = center_pos
		transform_data["center_position"] = center_pos
		return
	
	if not (height_up or height_down):
		return
	
	# Determine height step based on modifiers (use proper settings)
	var height_step: float
	if position_input.get("large_increment_modifier_held", false):
		height_step = settings.get("large_height_increment", 1.0)
	elif position_input.get("fine_increment_modifier_held", false):
		height_step = settings.get("fine_height_increment", 0.01)
	else:
		height_step = settings.get("height_adjustment_step", 0.1)
	
	var reverse_modifier = position_input.get("reverse_modifier_held", false)
	
	if height_up:
		var height_change = height_step if not reverse_modifier else -height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	elif height_down:
		var height_change = -height_step if not reverse_modifier else height_step
		_services.position_manager.adjust_height(transform_state, height_change)
	
	# CRITICAL: Update actual position.y to base_height + height_offset
	var center_pos = Vector3(transform_state.position.x, transform_state.base_height + transform_state.height_offset, transform_state.position.z)
	transform_state.position = center_pos
	transform_data["center_position"] = center_pos

func _process_mouse_rotation(
	camera: Camera3D,
	mouse_pos: Vector2,
	transform_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process mouse movement for rotation control (R mode)
	
	Uses horizontal mouse movement to rotate the group around the constrained axis,
	or around Y-axis if no constraint is active.
	"""
	if not camera:
		return
	
	# Get viewport for cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	
	# Store previous mouse position for delta calculation
	if not transform_data.has("_prev_mouse_pos"):
		transform_data["_prev_mouse_pos"] = mouse_pos
		return
	
	var prev_mouse_pos = transform_data.get("_prev_mouse_pos")
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Cursor warping: If mouse is near screen edges, warp to center
	# This allows infinite rotation without hitting screen boundaries
	if viewport:
		var viewport_rect = viewport.get_visible_rect()
		var viewport_size = viewport_rect.size
		var warp_margin = 50  # pixels from edge before warping
		var should_warp = false
		var warp_target_local = mouse_pos
		
		if mouse_pos.x < warp_margin or mouse_pos.x > viewport_size.x - warp_margin:
			warp_target_local.x = viewport_size.x / 2
			should_warp = true
		if mouse_pos.y < warp_margin or mouse_pos.y > viewport_size.y - warp_margin:
			warp_target_local.y = viewport_size.y / 2
			should_warp = true
		
		if should_warp:
			# Convert viewport-local position to global screen position
			# SubViewport doesn't have get_screen_position(), so we use get_screen_transform()
			var viewport_screen_transform = viewport.get_screen_transform()
			var warp_target_global = viewport_screen_transform * warp_target_local
			
			# Warp cursor using global screen coordinates
			Input.warp_mouse(warp_target_global)
			
			transform_data["_prev_mouse_pos"] = warp_target_local
		else:
			transform_data["_prev_mouse_pos"] = mouse_pos
	else:
		transform_data["_prev_mouse_pos"] = mouse_pos
	
	# Determine which axis to rotate around
	# In rotation mode, axis constraints specify which axis to rotate around
	# If multiple axes are constrained, use the first one (X > Y > Z priority)
	# If no constraint, rotate around Y axis (default)
	var control_mode = _services.control_mode_state
	var rotation_axis = ""
	
	if control_mode.has_axis_constraint():
		# Priority: X > Y > Z (if multiple constraints, use first one)
		if control_mode.is_x_constrained():
			rotation_axis = "X"
		elif control_mode.is_y_constrained():
			rotation_axis = "Y"
		elif control_mode.is_z_constrained():
			rotation_axis = "Z"
	else:
		# No constraint: Rotate around Y axis (default)
		rotation_axis = "Y"
	
	# Calculate rotation based on horizontal mouse movement
	var rotation_sensitivity = settings.get("mouse_rotation_sensitivity", 0.5)
	var rotation_amount = -mouse_delta.x * rotation_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler.is_fine_increment_modifier_held():
		# Fine modifier: More precise control (default 0.1x)
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= fine_multiplier
	elif input_handler.is_large_increment_modifier_held():
		# Large modifier: Faster control (default 2.0x)
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		rotation_amount *= large_multiplier
	
	# Apply rotation snapping if enabled
	if transform_state.snap_rotation_enabled:
		# Prepare accumulated rotation cache with raw + snapped totals per axis
		if not transform_data.has("_accumulated_rotation"):
			transform_data["_accumulated_rotation"] = {}
		var accumulated = transform_data["_accumulated_rotation"]
		if not accumulated.has(rotation_axis) or not (accumulated[rotation_axis] is Dictionary):
			accumulated[rotation_axis] = {
				"raw": 0.0,
				"snapped": 0.0
			}

		var axis_state: Dictionary = accumulated[rotation_axis]
		axis_state["raw"] = axis_state.get("raw", 0.0) + rotation_amount
		var last_snapped: float = axis_state.get("snapped", 0.0)

		# Apply snapping with half-step support using raw accumulation
		var snap_step = transform_state.snap_rotation_step
		if transform_state.use_half_step:
			snap_step = snap_step / 2.0
		
		# Snap to nearest increment
		var snapped_rotation_deg = round(axis_state["raw"] / snap_step) * snap_step
		
		# Calculate actual step to apply (difference from last snapped value)
		var actual_step = snapped_rotation_deg - last_snapped
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "RotSnap axis:%s delta:%.3f raw:%.3f snap_step:%.3f snapped:%.3f prev:%.3f apply:%.3f half:%s" % [rotation_axis, rotation_amount, axis_state["raw"], snap_step, snapped_rotation_deg, last_snapped, actual_step, transform_state.use_half_step])
		
		# Store the new accumulated rotation
		axis_state["snapped"] = snapped_rotation_deg
		accumulated[rotation_axis] = axis_state
		transform_data["_accumulated_rotation"] = accumulated
		
		# Apply the snapped rotation step
		rotate_group_by_step(rotation_axis, actual_step, transform_data, transform_state)
	else:
		# No snapping - apply rotation directly (rotation_step expects degrees)
		rotate_group_by_step(rotation_axis, rotation_amount, transform_data, transform_state)

func _process_mouse_scale(
	mouse_pos: Vector2,
	transform_data: Dictionary,
	transform_state: TransformState,
	settings: Dictionary
) -> void:
	"""Process mouse movement for scale control (L mode)
	
	Uses vertical mouse movement to adjust scale for the group.
	"""
	# Get viewport for cursor warping
	var viewport = _services.editor_facade.get_editor_viewport_3d(0)
	
	# Store previous mouse position for delta calculation
	if not transform_data.has("_prev_mouse_pos_scale"):
		transform_data["_prev_mouse_pos_scale"] = mouse_pos
		return
	
	var prev_mouse_pos = transform_data.get("_prev_mouse_pos_scale")
	var mouse_delta = mouse_pos - prev_mouse_pos
	
	# Cursor warping: If mouse is near screen edges, warp to center
	# This allows infinite scaling without hitting screen boundaries
	if viewport:
		var viewport_rect = viewport.get_visible_rect()
		var viewport_size = viewport_rect.size
		var warp_margin = 50  # pixels from edge before warping
		var should_warp = false
		var warp_target_local = mouse_pos
		
		if mouse_pos.x < warp_margin or mouse_pos.x > viewport_size.x - warp_margin:
			warp_target_local.x = viewport_size.x / 2
			should_warp = true
		if mouse_pos.y < warp_margin or mouse_pos.y > viewport_size.y - warp_margin:
			warp_target_local.y = viewport_size.y / 2
			should_warp = true
		
		if should_warp:
			# Convert viewport-local position to global screen position
			# SubViewport doesn't have get_screen_position(), so we use get_screen_transform()
			var viewport_screen_transform = viewport.get_screen_transform()
			var warp_target_global = viewport_screen_transform * warp_target_local
			
			# Warp cursor using global screen coordinates
			Input.warp_mouse(warp_target_global)
			
			transform_data["_prev_mouse_pos_scale"] = warp_target_local
		else:
			transform_data["_prev_mouse_pos_scale"] = mouse_pos
	else:
		transform_data["_prev_mouse_pos_scale"] = mouse_pos
	
	# Calculate scale change based on vertical mouse movement
	var scale_sensitivity = settings.get("mouse_scale_sensitivity", 0.01)
	var scale_delta = -mouse_delta.y * scale_sensitivity
	
	# Apply fine/large increment modifiers
	var input_handler = _services.input_handler
	if input_handler.is_fine_increment_modifier_held():
		# Fine modifier: More precise control (default 0.1x)
		var fine_multiplier = settings.get("fine_sensitivity_multiplier", PluginConstants.FINE_SENSITIVITY_MULTIPLIER)
		scale_delta *= fine_multiplier
	elif input_handler.is_large_increment_modifier_held():
		# Large modifier: Faster control (default 2.0x)
		var large_multiplier = settings.get("large_sensitivity_multiplier", PluginConstants.LARGE_SENSITIVITY_MULTIPLIER)
		scale_delta *= large_multiplier
	
	# Check for axis constraints (L + X/Y/Z for per-axis scaling)
	var control_mode = _services.control_mode_state
	var has_constraint = control_mode.has_axis_constraint()
	
	var scale_vector: Vector3
	if has_constraint:
		# Per-axis scaling: Apply delta only to constrained axes
		var current_scale_vector = _services.scale_manager.get_scale_vector(transform_state)
		scale_vector = current_scale_vector
		
		if control_mode.is_x_constrained():
			scale_vector.x = current_scale_vector.x + scale_delta
		if control_mode.is_y_constrained():
			scale_vector.y = current_scale_vector.y + scale_delta
		if control_mode.is_z_constrained():
			scale_vector.z = current_scale_vector.z + scale_delta
		
		# Apply scale snapping if enabled (per-axis)
		if transform_state.snap_scale_enabled:
			var snap_step = transform_state.snap_scale_step
			if transform_state.use_half_step:
				snap_step = snap_step / 2.0
			var pre_snap = scale_vector
			if control_mode.is_x_constrained():
				scale_vector.x = round(scale_vector.x / snap_step) * snap_step
			if control_mode.is_y_constrained():
				scale_vector.y = round(scale_vector.y / snap_step) * snap_step
			if control_mode.is_z_constrained():
				scale_vector.z = round(scale_vector.z / snap_step) * snap_step
			PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "ScaleSnap axis per pre:%s post:%s step:%.4f half:%s" % [pre_snap, scale_vector, snap_step, transform_state.use_half_step])
		
		# Clamp to reasonable values
		scale_vector.x = clamp(scale_vector.x, 0.01, 100.0)
		scale_vector.y = clamp(scale_vector.y, 0.01, 100.0)
		scale_vector.z = clamp(scale_vector.z, 0.01, 100.0)
		
		_services.scale_manager.set_non_uniform_multiplier(transform_state, scale_vector)
	else:
		# Uniform scaling: Apply delta to all axes equally
		var current_scale = _services.scale_manager.get_scale(transform_state)
		var new_scale = current_scale + scale_delta
		
		# Apply scale snapping if enabled (uniform)
		if transform_state.snap_scale_enabled:
			var snap_step = transform_state.snap_scale_step
			if transform_state.use_half_step:
				snap_step = snap_step / 2.0
			var pre_snap = new_scale
			# Snap to nearest increment
			new_scale = round(new_scale / snap_step) * snap_step
			PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "ScaleSnap uniform pre:%.4f post:%.4f step:%.4f half:%s" % [pre_snap, new_scale, snap_step, transform_state.use_half_step])
		
		# Clamp to reasonable values
		new_scale = clamp(new_scale, 0.01, 100.0)
		_services.scale_manager.set_scale_multiplier(transform_state, new_scale)
		scale_vector = Vector3(new_scale, new_scale, new_scale)
	
	# Apply to all nodes in group immediately (bypass smooth transforms during modal control)
	var target_nodes = transform_data.get("target_nodes", [])
	for node in target_nodes:
		if node and node.is_inside_tree():
			# Prevent negative or zero scale
			var safe_scale = Vector3(
				max(0.01, scale_vector.x),
				max(0.01, scale_vector.y),
				max(0.01, scale_vector.z)
			)
			node.scale = safe_scale

func rotate_group_by_step(axis: String, rotation_step: float, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Helper function to rotate group by a specific step amount (used by mouse wheel)"""
	if axis == "" or rotation_step == 0.0:
		return
	
	var target_nodes = transform_data.get("target_nodes", [])
	var center = transform_data.get("center_position", Vector3.ZERO)
	
	# CRITICAL: Recalculate node offsets from current positions
	var node_offsets = {}
	for node in target_nodes:
		if node and node.is_inside_tree():
			node_offsets[node] = node.global_position - center
	
	# Create rotation basis for the specified axis
	var rotation_radians = deg_to_rad(rotation_step)
	var rotation_axis_vector = Vector3.ZERO
	match axis:
		"X":
			rotation_axis_vector = Vector3(1, 0, 0)
		"Y":
			rotation_axis_vector = Vector3(0, 1, 0)
		"Z":
			rotation_axis_vector = Vector3(0, 0, 1)
	
	var rotation_basis = Basis(rotation_axis_vector, rotation_radians)
	var rotated_offsets = {}
	
	for node in target_nodes:
		if not node or not node.is_inside_tree():
			continue
		
		var offset = node_offsets.get(node, Vector3.ZERO)
		var rotated_offset = rotation_basis * offset
		rotated_offsets[node] = rotated_offset
		
		var new_position = center + rotated_offset
		var new_basis = rotation_basis * node.global_transform.basis
		
		node.global_position = new_position
		node.global_transform.basis = new_basis
	
	# Update the stored offsets for next rotation
	transform_data["node_offsets"] = rotated_offsets

func _apply_group_transformation(transform_data: Dictionary, transform_state: TransformState) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	var center = transform_data.get("center_position", Vector3.ZERO)
	var node_offsets = transform_data.get("node_offsets", {})
	for node in target_nodes:
		if node and node.is_inside_tree():
			var offset = node_offsets.get(node, Vector3.ZERO)
			var new_pos = center + offset
			node.global_position = new_pos

func _apply_scale_to_node(transform_state: TransformState, node: Node3D, original_scale: Vector3) -> void:
	if not node or not is_instance_valid(node):
		return
	
	var scale_mult = _services.scale_manager.get_scale(transform_state)
	
	# For numeric input: Use the multiplier as absolute scene scale (mult 1.0 = scene scale 1.0)
	# Ignore original_scale when applying numeric scale - treat multiplier as the target scene scale
	var new_scale = Vector3(scale_mult, scale_mult, scale_mult)
	
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Setting node %s scale from %s to %s (mult: %s)" % [node.name, original_scale, new_scale, scale_mult])
	
	# Prevent negative or zero scale
	new_scale.x = max(0.01, new_scale.x)
	new_scale.y = max(0.01, new_scale.y)
	new_scale.z = max(0.01, new_scale.z)
	
	node.scale = new_scale

func get_transform_center(target_nodes: Array) -> Vector3:
	if target_nodes.is_empty():
		return Vector3.ZERO
	var valid_nodes = []
	for node in target_nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			valid_nodes.append(node)
	if valid_nodes.is_empty():
		return Vector3.ZERO
	var sum = Vector3.ZERO
	for node in valid_nodes:
		sum += node.global_position
	return sum / valid_nodes.size()

func capture_original_state(nodes: Array) -> Dictionary:
	var state = {}
	for node in nodes:
		if is_instance_valid(node):
			state[node] = node.transform
	return state

func restore_original_state(transform_data: Dictionary) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	for node in target_nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			var original_transform = original_transforms.get(node)
			if original_transform:
				node.transform = original_transform

func _calculate_node_offsets(nodes: Array, center: Vector3) -> Dictionary:
	var offsets = {}
	for node in nodes:
		if node and is_instance_valid(node) and node.is_inside_tree():
			offsets[node] = node.global_position - center
	return offsets

## CONTROL MODE MANAGEMENT

func _process_control_mode_input(transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Process control mode transitions (G/R/L) and axis constraints (X/Y/Z)
	
	This handles Blender-style modal controls:
	- G = Position control mode
	- R = Rotation control mode
	- L = Scale control mode
	- X/Y/Z = Axis constraint toggle (double-tap to disable)
	"""
	var control_input = _services.input_handler.get_control_mode_input()
	var control_mode = _services.control_mode_state
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle control mode transitions
	if control_input.position_control_pressed:
		control_mode.switch_to_position_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Position control (G)")
	elif control_input.rotation_control_pressed:
		control_mode.switch_to_rotation_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Rotation control (R)")
	elif control_input.scale_control_pressed:
		control_mode.switch_to_scale_mode()
		PluginLogger.debug(PluginConstants.COMPONENT_TRANSFORM, "Switched to Scale control (L)")
	
	# Handle axis constraints (X/Y/Z keys)
	# Pass current center position so it can be stored as constraint origin
	var center_pos = transform_data.get("center_position", transform_state.position)
	if control_input.axis_x_pressed:
		control_mode.process_axis_key_press("X", current_time, center_pos)
	elif control_input.axis_y_pressed:
		control_mode.process_axis_key_press("Y", current_time, center_pos)
	elif control_input.axis_z_pressed:
		control_mode.process_axis_key_press("Z", current_time, center_pos)

## Numeric Input Integration

func _track_action_for_numeric_input(rotation_input: Dictionary, scale_input: Dictionary, position_input: Dictionary) -> void:
	"""Track when action keys are TAPPED (not held) to set context for numeric input.
	The numeric input will only activate when user actually types a number.
	
	IMPORTANT CONTEXT-AWARE ROUTING:
	- In Position mode (G): X/Y/Z are axis constraints ONLY (no numeric input)
	- In Rotation mode (R): X/Y/Z trigger numeric rotation input (+ axis constraints)
	- In Scale mode (L): X/Y/Z trigger numeric scale input (+ axis constraints)
	- When no modal active: X/Y/Z trigger rotation numeric input
	"""
	var numeric_mgr = _services.numeric_input_manager
	if not numeric_mgr:
		return
	
	# Check current control mode to determine X/Y/Z behavior
	var control_mode = _services.control_mode_state
	var is_position_mode = control_mode.is_position_mode() if control_mode else false
	
	# Import ActionType enum
	var ActionType = NumericInputManager.ActionType
	
	# Track rotation actions (only on tap, not on hold/repeat)
	# X/Y/Z keys for numeric input - BUT skip in Position mode (they're pure axis constraints there)
	if not is_position_mode:
		if rotation_input.get("x_tapped", false):
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "X key tapped - setting ROTATE_X context")
			numeric_mgr.set_action_context(ActionType.ROTATE_X)
		elif rotation_input.get("y_tapped", false):
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Y key tapped - setting ROTATE_Y context")
			numeric_mgr.set_action_context(ActionType.ROTATE_Y)
		elif rotation_input.get("z_tapped", false):
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Z key tapped - setting ROTATE_Z context")
			numeric_mgr.set_action_context(ActionType.ROTATE_Z)
	
	# Track scale actions (only on tap, not on hold/repeat)
	elif scale_input.get("up_tapped", false) or scale_input.get("down_tapped", false):
		PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "PageUp/PageDown tapped - setting SCALE context")
		numeric_mgr.set_action_context(ActionType.SCALE)
	
	# Track height actions (only on tap, not on hold/repeat)
	elif position_input.get("height_up_tapped", false) or position_input.get("height_down_tapped", false):
		numeric_mgr.set_action_context(ActionType.HEIGHT)
	
	# Track position actions (only on tap, not on hold/repeat)
	elif position_input.get("position_forward_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_FORWARD)
	elif position_input.get("position_backward_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_BACKWARD)
	elif position_input.get("position_left_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_LEFT)
	elif position_input.get("position_right_tapped", false):
		numeric_mgr.set_action_context(ActionType.POSITION_RIGHT)

func _process_numeric_input(numeric_input: Dictionary, numeric_mgr: NumericInputManager) -> void:
	"""Process numeric input keys from InputHandler polling"""
	if not numeric_mgr:
		return
	
	# Process digit keys
	var digit = numeric_input.get("digit_pressed", -1)
	if digit >= 0:
		var digit_str = str(digit)
		numeric_mgr.process_numeric_key(digit_str)
	
	# Process special keys (don't use elif - allow multiple keys in one frame)
	if numeric_input.get("decimal_pressed", false):
		numeric_mgr.process_decimal_key()
	if numeric_input.get("minus_pressed", false):
		numeric_mgr.process_minus_key()
	if numeric_input.get("plus_pressed", false):
		numeric_mgr.process_plus_key()
	if numeric_input.get("equals_pressed", false):
		numeric_mgr.process_equals_key()
	if numeric_input.get("backspace_pressed", false):
		numeric_mgr.process_backspace()
	if numeric_input.get("enter_pressed", false):
		if numeric_mgr.is_active():
			numeric_mgr.confirm_action()
	if numeric_input.get("escape_pressed", false):
		if numeric_mgr.is_active():
			numeric_mgr.cancel_action()

func _apply_numeric_input(transform_data: Dictionary, transform_state: TransformState, settings: Dictionary) -> void:
	"""Apply the confirmed numeric input value to the transformation"""
	var numeric_mgr = _services.numeric_input_manager
	if not numeric_mgr or not numeric_mgr.is_active():
		return
	
	var action = numeric_mgr.get_active_action()
	var ActionType = NumericInputManager.ActionType
	
	var target_nodes = transform_data.get("target_nodes", [])
	var original_transforms = transform_data.get("original_transforms", {})
	
	match action:
		ActionType.ROTATE_X, ActionType.ROTATE_Y, ActionType.ROTATE_Z:
			_apply_numeric_rotation(action, numeric_mgr, transform_data, transform_state)
		
		ActionType.SCALE:
			_apply_numeric_scale(numeric_mgr, transform_data, transform_state)
		
		ActionType.HEIGHT:
			_apply_numeric_height(numeric_mgr, transform_data, transform_state)
		
		ActionType.POSITION_FORWARD, ActionType.POSITION_BACKWARD, ActionType.POSITION_LEFT, ActionType.POSITION_RIGHT:
			_apply_numeric_position(action, numeric_mgr, transform_data, transform_state)

func _apply_numeric_rotation(action, numeric_mgr, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Apply numeric input to rotation"""
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Applying numeric rotation for action: %s" % action)
	var ActionType = NumericInputManager.ActionType
	var axis = ""
	match action:
		ActionType.ROTATE_X:
			axis = "X"
		ActionType.ROTATE_Y:
			axis = "Y"
		ActionType.ROTATE_Z:
			axis = "Z"
	
	if axis == "":
		return
	
	# Get current rotation of first node
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	
	var first_node = target_nodes[0]
	var current_rotation_deg = rad_to_deg(first_node.rotation[axis.to_lower()])
	
	# Apply numeric value
	var new_rotation_deg = numeric_mgr.apply_to_value(current_rotation_deg)
	var rotation_step = new_rotation_deg - current_rotation_deg
	
	# Apply the rotation
	rotate_group_by_step(axis, rotation_step, transform_data, transform_state)

func _apply_numeric_scale(numeric_mgr, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Apply numeric input to scale
	Scale input uses actual scale values (1.0 = normal size, 2.0 = double size, 0.5 = half size)
	Absolute mode (=): Set to exact scale value
	Relative mode (+/-): Add to current scale"""
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Applying numeric scale")
	
	var input_value = numeric_mgr.get_numeric_value()
	var is_absolute = numeric_mgr.is_absolute_mode()
	
	# Apply to all nodes directly based on absolute/relative mode
	var target_nodes = transform_data.get("target_nodes", [])
	for node in target_nodes:
		if node and node.is_inside_tree():
			var current_scene_scale = node.scale
			var new_scene_scale: Vector3
			
			if is_absolute:
				# Absolute: Set to exact value (=1 means scale 1.0 in scene)
				new_scene_scale = Vector3(input_value, input_value, input_value)
			else:
				# Relative: Add to current scale (+0.5 adds 0.5 to each axis)
				var scale_change = numeric_mgr.apply_to_value(0.0)  # Get the delta
				new_scene_scale = current_scene_scale + Vector3(scale_change, scale_change, scale_change)
			
			PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Scale node %s: current=%s, input=%.3f, is_absolute=%s, new=%s" % [
				node.name, current_scene_scale, input_value, is_absolute, new_scene_scale
			])
			
			# Prevent negative or zero scale
			new_scene_scale.x = max(0.01, new_scene_scale.x)
			new_scene_scale.y = max(0.01, new_scene_scale.y)
			new_scene_scale.z = max(0.01, new_scene_scale.z)
			
			_services.smooth_transform_manager.set_target_scale(node, new_scene_scale)

func _apply_numeric_height(numeric_mgr, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Apply numeric input to height"""
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Applying numeric height...")
	var current_height = transform_state.height_offset
	var new_height = numeric_mgr.apply_to_value(current_height)
	
	# Set height offset directly
	transform_state.height_offset = new_height
	
	# Update center position
	var center_pos = Vector3(transform_state.position.x, transform_state.base_height + transform_state.height_offset, transform_state.position.z)
	transform_state.position = center_pos
	transform_data["center_position"] = center_pos

func _apply_numeric_position(action, numeric_mgr, transform_data: Dictionary, transform_state: TransformState) -> void:
	"""Apply numeric input to position offset"""
	PluginLogger.info(PluginConstants.COMPONENT_TRANSFORM, "Applying numeric position for action: %s" % action)
	var ActionType = NumericInputManager.ActionType
	var manual_offset = transform_data.get("manual_position_offset", Vector3.ZERO)
	
	var value = numeric_mgr.get_numeric_value()
	if numeric_mgr.get_prefix_mode() == NumericInputManager.PrefixMode.ABSOLUTE:
		# Absolute positioning
		match action:
			ActionType.POSITION_FORWARD, ActionType.POSITION_BACKWARD:
				manual_offset.z = -value if action == ActionType.POSITION_FORWARD else value
			ActionType.POSITION_LEFT, ActionType.POSITION_RIGHT:
				manual_offset.x = -value if action == ActionType.POSITION_LEFT else value
	else:
		# Relative positioning
		var delta = value
		if numeric_mgr.get_prefix_mode() == NumericInputManager.PrefixMode.RELATIVE_SUB:
			delta = -delta
		
		match action:
			ActionType.POSITION_FORWARD:
				manual_offset.z -= delta
			ActionType.POSITION_BACKWARD:
				manual_offset.z += delta
			ActionType.POSITION_LEFT:
				manual_offset.x -= delta
			ActionType.POSITION_RIGHT:
				manual_offset.x += delta
	
	transform_data["manual_position_offset"] = manual_offset

func update_overlays(transform_data: Dictionary) -> void:
	var target_nodes = transform_data.get("target_nodes", [])
	if target_nodes.is_empty():
		return
	var center = transform_data.get("center_position", Vector3.ZERO)
	var first_node = target_nodes[0] if target_nodes.size() > 0 else null
	var node_name = first_node.name if first_node else ""
	var position = center
	var rotation = first_node.rotation if first_node else Vector3.ZERO
	var scale_val = first_node.scale.x if first_node else 1.0
	_services.overlay_manager.show_transform_overlay(1, node_name, position, rotation, scale_val, 0.0)

func _reset_transforms_on_exit(transform_state: TransformState, settings: Dictionary) -> void:
	var reset_rotation = settings.get("reset_rotation_on_exit", false)
	var reset_scale = settings.get("reset_scale_on_exit", false)
	if reset_rotation and transform_state:
		_services.rotation_manager.reset_all_rotation(transform_state)
	if reset_scale and transform_state:
		_services.scale_manager.reset_scale(transform_state)

## AXIS CONSTRAINT HELPERS

func _calculate_constrained_position(camera: Camera3D, mouse_pos: Vector2, current_pos: Vector3, control_mode) -> Vector3:
	"""Calculate position with axis constraints using plane intersection
	
	Projects the mouse ray onto a plane/line defined by the constrained axes.
	Uses the constraint origin (position when first axis was activated) as the reference point.
	
	Args:
		camera: The 3D camera
		mouse_pos: Mouse position in viewport
		current_pos: Current object position (fallback if no constraint origin)
		control_mode: ControlModeState with axis constraints
		
	Returns:
		New constrained position
	"""
	# Use constraint origin if available, otherwise fall back to current position
	var constraint_origin = current_pos
	if control_mode.has_constraint_origin():
		constraint_origin = control_mode.get_constraint_origin()
	
	# Create ray from camera through mouse
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# Validate ray direction
	if ray_direction.length_squared() < 0.0001:
		PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, "Invalid ray direction in constraint calculation")
		return constraint_origin
	
	var x_constrained = control_mode.is_x_constrained()
	var y_constrained = control_mode.is_y_constrained()
	var z_constrained = control_mode.is_z_constrained()
	
	# Count constrained axes
	var constraint_count = 0
	if x_constrained: constraint_count += 1
	if y_constrained: constraint_count += 1
	if z_constrained: constraint_count += 1
	
	var result_pos = constraint_origin
	
	if constraint_count == 0:
		# No constraints - shouldn't happen, but return constraint origin
		result_pos = constraint_origin
	elif constraint_count == 1:
		# Single axis constraint - use line projection
		result_pos = _project_to_line(ray_origin, ray_direction, constraint_origin, x_constrained, y_constrained, z_constrained)
	elif constraint_count == 2:
		# Two axes constrained - use plane intersection
		# Plane normal is the axis that's NOT constrained
		var plane_normal = Vector3.ZERO
		if not x_constrained:
			plane_normal = Vector3.RIGHT  # YZ plane (normal points along X)
		elif not y_constrained:
			plane_normal = Vector3.UP  # XZ plane (normal points along Y)
		else:  # not z_constrained
			plane_normal = Vector3.FORWARD  # XY plane (normal points along Z) - Changed from BACK
		
		# Check if ray is nearly parallel to plane (dot product near 0)
		var ray_plane_dot = abs(ray_direction.dot(plane_normal))
		if ray_plane_dot < 0.0001:
			# Ray is parallel to plane, can't intersect properly
			return constraint_origin
		
		# Intersect ray with plane
		var plane = Plane(plane_normal, constraint_origin.dot(plane_normal))
		var intersection = plane.intersects_ray(ray_origin, ray_direction)
		
		if intersection != null:
			result_pos = intersection
		else:
			result_pos = constraint_origin
	else:
		# All three axes constrained - no movement possible
		result_pos = constraint_origin
	
	# Safety check: Ensure result is reasonable distance from constraint origin
	# This prevents extreme values from calculation errors
	var max_distance = 100000.0  # Maximum total allowed distance from origin
	var distance = result_pos.distance_to(constraint_origin)
	if distance > max_distance:
		PluginLogger.warning(PluginConstants.COMPONENT_TRANSFORM, 
			"Constraint calculation produced extreme value (distance from origin: %.2f), clamping" % distance)
		# Clamp to max distance from origin
		var direction = (result_pos - constraint_origin).normalized()
		result_pos = constraint_origin + direction * max_distance
	
	return result_pos

func _project_to_line(ray_origin: Vector3, ray_direction: Vector3, line_point: Vector3, x_axis: bool, y_axis: bool, z_axis: bool) -> Vector3:
	"""Project mouse ray onto a constrained line (single axis)
	
	Args:
		ray_origin: Ray origin from camera
		ray_direction: Ray direction
		line_point: Point on the line (current position)
		x_axis: True if X is the constrained axis
		y_axis: True if Y is the constrained axis
		z_axis: True if Z is the constrained axis
		
	Returns:
		Closest point on the line to the ray
	"""
	# Determine line direction based on constrained axis
	# Note: Using Godot's standard axis directions
	# X = RIGHT (1, 0, 0) → Positive X is to the right
	# Y = UP (0, 1, 0) → Positive Y is up
	# Z = FORWARD (0, 0, -1) → Positive Z is away from camera (Godot uses -Z as forward)
	var line_direction = Vector3.ZERO
	if x_axis:
		line_direction = Vector3.RIGHT  # (1, 0, 0)
	elif y_axis:
		line_direction = Vector3.UP  # (0, 1, 0)
	else:  # z_axis
		line_direction = Vector3.FORWARD  # (0, 0, -1) - Changed from BACK to FORWARD
	
	# Simpler approach: Find where ray intersects a plane perpendicular to constraint axis,
	# then project that point onto the constraint line
	
	# Create two perpendicular vectors to the line direction (for the perpendicular plane)
	# We'll use the plane that the camera ray is most aligned with
	var perp1 = Vector3.ZERO
	var perp2 = Vector3.ZERO
	
	if abs(line_direction.x) < 0.9:
		perp1 = Vector3.RIGHT.cross(line_direction).normalized()
	else:
		perp1 = Vector3.UP.cross(line_direction).normalized()
	perp2 = line_direction.cross(perp1).normalized()
	
	# Choose the perpendicular vector most aligned with the ray direction
	var plane_normal = perp1 if abs(ray_direction.dot(perp1)) > abs(ray_direction.dot(perp2)) else perp2
	
	# Check if ray is nearly parallel to our perpendicular plane
	var ray_plane_dot = abs(ray_direction.dot(plane_normal))
	if ray_plane_dot < 0.01:
		# Ray is parallel, can't get good intersection
		return line_point
	
	# Intersect ray with plane perpendicular to constraint axis
	var plane = Plane(plane_normal, line_point.dot(plane_normal))
	var intersection = plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection == null:
		return line_point
	
	# Project the intersection point onto the constraint line
	# This is simple: just take the component along the line direction
	var offset_from_origin = intersection - line_point
	var distance_along_line = offset_from_origin.dot(line_direction)
	
	# Safety check: Clamp to reasonable values
	var max_distance = 100000.0
	if abs(distance_along_line) > max_distance:
		distance_along_line = clamp(distance_along_line, -max_distance, max_distance)
	
	var result = line_point + line_direction * distance_along_line
	
	# Additional safety: Ensure result is reasonable
	# If result is astronomically far, return current position (silent fallback)
	if result.length() > 1000000.0:  # More than 1 million units from origin
		return line_point
	
	return result
