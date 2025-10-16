extends GutTest

const ControlModeState = preload("res://addons/simpleassetplacer/core/control_mode_state.gd")

func test_switch_without_activation_leaves_modal_inactive() -> void:
	var state := ControlModeState.new()
	state.reset()
	state.switch_to_position_mode(false)
	assert_false(state.is_modal_active(), "Modal should remain inactive when switch is non-activating")
	assert_eq(state.get_control_mode(), ControlModeState.ControlMode.POSITION)

func test_switch_with_activation_sets_modal() -> void:
	var state := ControlModeState.new()
	state.reset()
	state.switch_to_rotation_mode(true)
	assert_true(state.is_modal_active(), "Modal should activate when explicitly requested")
	assert_eq(state.get_control_mode(), ControlModeState.ControlMode.ROTATION)

func test_switch_with_false_deactivates_existing_modal() -> void:
	var state := ControlModeState.new()
	state.reset()
	state.switch_to_rotation_mode(true)
	assert_true(state.is_modal_active(), "Precondition: modal active after rotation switch")
	state.switch_to_position_mode(false)
	assert_false(state.is_modal_active(), "Switching with activate_modal=false should deactivate modal state")
	assert_eq(state.get_control_mode(), ControlModeState.ControlMode.POSITION)

func test_deactivate_modal_clears_axis_constraints() -> void:
	var state := ControlModeState.new()
	state.reset()
	state.switch_to_position_mode(true)
	state.process_axis_key_press("X", float(Time.get_ticks_msec()) / 1000.0, Vector3.ZERO)
	assert_true(state.has_axis_constraint(), "Axis constraint should be active before deactivation")
	state.deactivate_modal()
	assert_false(state.is_modal_active(), "Modal should be inactive after explicit deactivation")
	assert_false(state.has_axis_constraint(), "Axis constraints should clear when modal deactivates")
