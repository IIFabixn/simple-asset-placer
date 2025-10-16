extends GutTest

const TransformCommand = preload("res://addons/simpleassetplacer/core/transform_command.gd")

func test_modal_position_overrides_other_sources() -> void:
	var direct_cmd := TransformCommand.new()
	direct_cmd.set_position_delta(Vector3(1, 0, 0), TransformCommand.SOURCE_KEY_DIRECT)

	var numeric_cmd := TransformCommand.new()
	numeric_cmd.set_position_delta(Vector3(2, 0, 0), TransformCommand.SOURCE_NUMERIC)

	var modal_cmd := TransformCommand.from_modal_input({
		"position_delta": Vector3(3, 0, 0)
	})

	direct_cmd.merge(numeric_cmd)
	direct_cmd.merge(modal_cmd)

	assert_eq(direct_cmd.position_delta, Vector3(3, 0, 0), "Modal value should win over numeric and direct inputs")
	assert_true(direct_cmd.source_flags.get(TransformCommand.SOURCE_KEY_DIRECT, false))
	assert_true(direct_cmd.source_flags.get(TransformCommand.SOURCE_NUMERIC, false))
	assert_true(direct_cmd.source_flags.get(TransformCommand.SOURCE_MOUSE_MODAL, false))

func test_numeric_rotation_overrides_direct() -> void:
	var base_cmd := TransformCommand.new()
	base_cmd.set_rotation_delta(Vector3(5, 0, 0), TransformCommand.SOURCE_KEY_DIRECT)

	var numeric_cmd := TransformCommand.new()
	numeric_cmd.set_rotation_delta(Vector3(10, 0, 0), TransformCommand.SOURCE_NUMERIC)

	base_cmd.merge(numeric_cmd)

	assert_eq(base_cmd.rotation_delta, Vector3(10, 0, 0))
	assert_true(base_cmd.source_flags.get(TransformCommand.SOURCE_NUMERIC, false))

func test_cancel_overrides_confirm() -> void:
	var confirm_cmd := TransformCommand.new()
	confirm_cmd.set_confirm(true)

	var cancel_cmd := TransformCommand.new()
	cancel_cmd.set_cancel(true)

	confirm_cmd.merge(cancel_cmd)

	assert_true(confirm_cmd.cancel, "Cancel intent should override confirm")
	assert_false(confirm_cmd.confirm, "Confirm should be cleared when canceling")

func test_metadata_merges_without_reference_leaks() -> void:
	var base_cmd := TransformCommand.new()
	base_cmd.merge_metadata({"mode": "placement"})

	var incoming := TransformCommand.new()
	incoming.merge_metadata({
		"mode": "transform",
		"tags": ["modal"]
	})

	base_cmd.merge(incoming)
	assert_eq(base_cmd.metadata["mode"], "transform")
	incoming.metadata["tags"].append("numeric")
	assert_eq(base_cmd.metadata["tags"].size(), 1, "Metadata should be duplicated on merge")

func test_clear_resets_state() -> void:
	var cmd := TransformCommand.new()
	cmd.set_position_delta(Vector3(1, 2, 3), TransformCommand.SOURCE_NUMERIC)
	cmd.set_axis_constraints_from_dict({"X": true}, TransformCommand.SOURCE_NUMERIC)
	cmd.set_confirm(true)
	cmd.metadata["example"] = "value"

	cmd.clear()

	assert_eq(cmd.position_delta, Vector3.ZERO)
	assert_false(cmd.axis_constraints["X"])
	assert_false(cmd.confirm)
	assert_true(cmd.metadata.is_empty())
	assert_true(cmd.source_flags.is_empty())
