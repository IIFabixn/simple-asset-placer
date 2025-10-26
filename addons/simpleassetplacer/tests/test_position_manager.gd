@tool
extends GutTest

const TransformState = preload("res://addons/simpleassetplacer/core/transform_state.gd")
const PositionManager = preload("res://addons/simpleassetplacer/managers/position_manager.gd")
const ServiceRegistry = preload("res://addons/simpleassetplacer/core/service_registry.gd")
const PlacementStrategyService = preload("res://addons/simpleassetplacer/placement/placement_strategy_service.gd")

var services: ServiceRegistry
var state: TransformState
var position_manager: PositionManager

func before_all():
	services = ServiceRegistry.new()
	services.placement_strategy_service = PlacementStrategyService.new()
	services.placement_strategy_service.initialize()
	position_manager = PositionManager.new(services)
	state = TransformState.new()

func after_all():
	services = null
	state = null
	position_manager = null

func test_configure_applies_settings():
	var cfg = {
		"snap_enabled": true,
		"snap_step": 2.0,
		"snap_offset": Vector3(1,0,1),
		"height_adjustment_step": 0.25,
		"align_with_normal": true
	}
	position_manager.configure(state, cfg)
	assert_true(state.snap.snap_enabled, "snap_enabled applied")
	assert_eq(state.snap.snap_step, 2.0, "snap_step applied")
	assert_eq(state.snap_offset, Vector3(1,0,1), "snap_offset applied")
	assert_eq(state.height_adjustment_step, 0.25, "height_adjustment_step applied to state")
	assert_true(state.align_with_normal, "align_with_normal applied directly")

func test_half_step_in_state_only():
	state.snap.use_half_step = true
	var pos = Vector3(3.9, 0, 3.1)
	state.snap.snap_enabled = true
	state.snap.snap_step = 2.0
	var snapped = position_manager._apply_grid_snap(state, pos)
	# Half step -> effective step is 1.0
	assert_eq(snapped.x, snappedf(pos.x - state.snap.snap_offset.x, 1.0) + state.snap.snap_offset.x, "X snapped using half step")

func test_y_offset_adjustment_uses_state_step():
	state.placement.height_adjustment_step = 0.5
	var initial = state.values.manual_position_offset
	position_manager.increase_offset_normal(state)
	# For XZ plane (default), normal is UP (Y axis)
	assert_eq(state.values.manual_position_offset.y, initial.y + 0.5, "Normal offset increased by state height_adjustment_step")
