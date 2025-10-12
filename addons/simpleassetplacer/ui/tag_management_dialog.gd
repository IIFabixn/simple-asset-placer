@tool
extends Window

## Advanced Tag Management Dialog
## Provides bulk tag operations, statistics, and tag management capabilities

signal tags_modified()

var category_manager: CategoryManager
var all_assets: Array = []
var selected_asset_paths: Array = []

# UI Components
var asset_tree: Tree
var tag_list: ItemList
var stats_label: Label
var bulk_add_button: Button
var bulk_remove_button: Button
var rename_tag_button: Button
var merge_tags_button: Button
var delete_tag_button: Button
var search_line_edit: LineEdit
var tag_filter_line_edit: LineEdit

func _ready() -> void:
	title = "Advanced Tag Management"
	size = Vector2i(1000, 650)
	min_size = Vector2i(800, 500)
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	
	_build_ui()
	_connect_signals()

func setup(manager: CategoryManager, assets: Array) -> void:
	category_manager = manager
	all_assets = assets.duplicate()
	
	if is_node_ready():
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()

func _connect_dialog_with_action(dialog: Window, action: Callable) -> void:
	"""Connect dialog signals with proper disconnection before queue_free
	
	This prevents memory leaks by ensuring signals are disconnected before
	the dialog is freed. The action callable is executed before cleanup.
	
	Args:
		dialog: The dialog window to set up cleanup for
		action: The callable to execute when dialog is confirmed (can contain dialog.queue_free calls)
	"""
	var callbacks = {
		"confirmed": Callable(),
		"canceled": Callable()
	}
	
	callbacks["confirmed"] = func():
		# Execute the action (which might include queue_free)
		if action.is_valid():
			action.call()
		# Only disconnect if dialog still exists
		if is_instance_valid(dialog):
			if dialog.confirmed.is_connected(callbacks["confirmed"]):
				dialog.confirmed.disconnect(callbacks["confirmed"])
			if dialog.canceled.is_connected(callbacks["canceled"]):
				dialog.canceled.disconnect(callbacks["canceled"])
	
	callbacks["canceled"] = func():
		# Disconnect both signals
		if is_instance_valid(dialog):
			if dialog.confirmed.is_connected(callbacks["confirmed"]):
				dialog.confirmed.disconnect(callbacks["confirmed"])
			if dialog.canceled.is_connected(callbacks["canceled"]):
				dialog.canceled.disconnect(callbacks["canceled"])
			dialog.queue_free()
	
	dialog.confirmed.connect(callbacks["confirmed"])
	dialog.canceled.connect(callbacks["canceled"])

func _build_ui() -> void:
	# Main container - fills entire window
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)
	
	# Statistics panel at top
	var stats_panel = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _create_stats_style())
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(stats_panel)
	
	var stats_margin = MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 16)
	stats_margin.add_theme_constant_override("margin_top", 10)
	stats_margin.add_theme_constant_override("margin_right", 16)
	stats_margin.add_theme_constant_override("margin_bottom", 10)
	stats_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(stats_margin)
	
	stats_label = Label.new()
	stats_label.text = "📊 Loading statistics..."
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_margin.add_child(stats_label)
	
	# Main split container - fills remaining space
	var hsplit = HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hsplit)
	
	# Left side - Asset list with search
	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 8)
	left_margin.add_theme_constant_override("margin_top", 8)
	left_margin.add_theme_constant_override("margin_right", 4)
	left_margin.add_theme_constant_override("margin_bottom", 8)
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_margin)
	
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_margin.add_child(left_vbox)
	
	var asset_label = Label.new()
	asset_label.text = "Assets"
	asset_label.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(asset_label)
	
	search_line_edit = LineEdit.new()
	search_line_edit.placeholder_text = "Search assets..."
	search_line_edit.clear_button_enabled = true
	left_vbox.add_child(search_line_edit)
	
	asset_tree = Tree.new()
	asset_tree.hide_root = true
	asset_tree.select_mode = Tree.SELECT_MULTI  # Enable multi-selection
	asset_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_tree.columns = 2
	asset_tree.set_column_title(0, "Asset")
	asset_tree.set_column_title(1, "Tags")
	asset_tree.set_column_expand(0, true)
	asset_tree.set_column_expand(1, true)
	asset_tree.set_column_clip_content(0, true)
	asset_tree.set_column_clip_content(1, true)
	asset_tree.set_column_custom_minimum_width(0, 200)
	asset_tree.set_column_custom_minimum_width(1, 150)
	asset_tree.column_titles_visible = true
	asset_tree.allow_rmb_select = true
	left_vbox.add_child(asset_tree)
	
	var selection_info = Label.new()
	selection_info.name = "SelectionInfo"
	selection_info.text = "Tip: Ctrl+Click to multi-select, Shift+Click for range selection"
	selection_info.add_theme_font_size_override("font_size", 10)
	left_vbox.add_child(selection_info)
	
	# Right side - Tag management
	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 4)
	right_margin.add_theme_constant_override("margin_top", 8)
	right_margin.add_theme_constant_override("margin_right", 8)
	right_margin.add_theme_constant_override("margin_bottom", 8)
	right_margin.custom_minimum_size = Vector2(300, 0)
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_margin)
	
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(right_vbox)
	
	var tag_label = Label.new()
	tag_label.text = "Available Tags"
	tag_label.add_theme_font_size_override("font_size", 14)
	right_vbox.add_child(tag_label)
	
	tag_filter_line_edit = LineEdit.new()
	tag_filter_line_edit.placeholder_text = "Filter tags..."
	tag_filter_line_edit.clear_button_enabled = true
	right_vbox.add_child(tag_filter_line_edit)
	
	tag_list = ItemList.new()
	tag_list.select_mode = ItemList.SELECT_MULTI
	tag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_list.allow_rmb_select = true
	right_vbox.add_child(tag_list)
	
	# Create new tag button
	var create_tag_button = Button.new()
	create_tag_button.name = "CreateTagButton"
	create_tag_button.text = "➕ Create New Tag..."
	create_tag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_tag_button.custom_minimum_size = Vector2(0, 28)
	create_tag_button.tooltip_text = "Create a new custom tag"
	create_tag_button.pressed.connect(_on_create_new_tag)
	right_vbox.add_child(create_tag_button)
	
	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 8)
	right_vbox.add_child(spacer1)
	
	# Bulk operations section
	var bulk_label = Label.new()
	bulk_label.text = "━━ Bulk Operations ━━"
	bulk_label.add_theme_font_size_override("font_size", 12)
	bulk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(bulk_label)
	
	var bulk_vbox = VBoxContainer.new()
	bulk_vbox.add_theme_constant_override("separation", 4)
	right_vbox.add_child(bulk_vbox)
	
	bulk_add_button = Button.new()
	bulk_add_button.text = "➕ Add Tags to Selected Assets"
	bulk_add_button.disabled = true
	bulk_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk_add_button.custom_minimum_size = Vector2(0, 32)
	bulk_vbox.add_child(bulk_add_button)
	
	bulk_remove_button = Button.new()
	bulk_remove_button.text = "➖ Remove Tags from Selected Assets"
	bulk_remove_button.disabled = true
	bulk_remove_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk_remove_button.custom_minimum_size = Vector2(0, 32)
	bulk_vbox.add_child(bulk_remove_button)
	
	# Add spacing
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 12)
	right_vbox.add_child(spacer2)
	
	# Tag management section
	var tag_mgmt_label = Label.new()
	tag_mgmt_label.text = "━━ Tag Management ━━"
	tag_mgmt_label.add_theme_font_size_override("font_size", 12)
	tag_mgmt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(tag_mgmt_label)
	
	var tag_mgmt_grid = GridContainer.new()
	tag_mgmt_grid.columns = 3
	tag_mgmt_grid.add_theme_constant_override("h_separation", 4)
	tag_mgmt_grid.add_theme_constant_override("v_separation", 4)
	right_vbox.add_child(tag_mgmt_grid)
	
	rename_tag_button = Button.new()
	rename_tag_button.text = "✏️ Rename"
	rename_tag_button.disabled = true
	rename_tag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_tag_button.tooltip_text = "Rename selected tag (select exactly 1 tag)"
	tag_mgmt_grid.add_child(rename_tag_button)
	
	merge_tags_button = Button.new()
	merge_tags_button.text = "🔀 Merge"
	merge_tags_button.disabled = true
	merge_tags_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	merge_tags_button.tooltip_text = "Merge multiple tags into one (select 2+ tags)"
	tag_mgmt_grid.add_child(merge_tags_button)
	
	delete_tag_button = Button.new()
	delete_tag_button.text = "🗑️ Delete"
	delete_tag_button.disabled = true
	delete_tag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_tag_button.tooltip_text = "Delete selected tag(s)"
	tag_mgmt_grid.add_child(delete_tag_button)
	
	# Bottom buttons
	var bottom_margin = MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_left", 8)
	bottom_margin.add_theme_constant_override("margin_top", 4)
	bottom_margin.add_theme_constant_override("margin_right", 8)
	bottom_margin.add_theme_constant_override("margin_bottom", 8)
	main_vbox.add_child(bottom_margin)
	
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_END
	bottom_margin.add_child(bottom_hbox)
	
	var close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(100, 32)
	close_button.pressed.connect(hide)
	bottom_hbox.add_child(close_button)

func _create_stats_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.25, 0.3, 0.4)
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.5, 0.6, 0.6)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style

func _connect_signals() -> void:
	search_line_edit.text_changed.connect(_on_asset_search_changed)
	tag_filter_line_edit.text_changed.connect(_on_tag_filter_changed)
	asset_tree.multi_selected.connect(_on_asset_selection_changed)
	asset_tree.nothing_selected.connect(_on_asset_nothing_selected)
	tag_list.item_selected.connect(_on_tag_selection_changed)
	tag_list.multi_selected.connect(_on_tag_selection_changed)
	bulk_add_button.pressed.connect(_on_bulk_add_tags)
	bulk_remove_button.pressed.connect(_on_bulk_remove_tags)
	rename_tag_button.pressed.connect(_on_rename_tag)
	merge_tags_button.pressed.connect(_on_merge_tags)
	delete_tag_button.pressed.connect(_on_delete_tag)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and not event.echo:
			hide()
			get_viewport().set_input_as_handled()

func _populate_asset_tree() -> void:
	asset_tree.clear()
	var root = asset_tree.create_item()
	
	var search_text = search_line_edit.text.to_lower() if search_line_edit else ""
	
	for asset_info in all_assets:
		var asset_identifier = _get_asset_identifier(asset_info)
		var asset_name = _get_asset_display_name(asset_info)
		
		# Apply search filter
		if search_text != "" and not asset_name.to_lower().contains(search_text):
			continue
		
		var item = asset_tree.create_item(root)
		item.set_text(0, asset_name)
		item.set_metadata(0, asset_identifier)
		item.set_tooltip_text(0, asset_identifier)
		
		# Make column 1 non-selectable so clicking it selects column 0 (whole row effect)
		item.set_selectable(1, false)
		
		# Show current tags
		var tags = category_manager.get_custom_tags(asset_identifier)
		if tags.size() > 0:
			item.set_text(1, ", ".join(tags))
		else:
			item.set_text(1, "(no tags)")
			item.set_custom_color(1, Color(0.6, 0.6, 0.6))

func _populate_tag_list() -> void:
	tag_list.clear()
	
	# Get all tags from tag_usage (includes tags with 0 usage)
	var tag_usage = category_manager.tag_usage
	var all_tags = tag_usage.keys()
	var filter_text = tag_filter_line_edit.text.to_lower() if tag_filter_line_edit else ""
	
	if all_tags.is_empty():
		tag_list.add_item("💡 No tags yet. Click 'Create New Tag...' below to start!")
		tag_list.set_item_disabled(0, true)
		tag_list.set_item_custom_fg_color(0, Color(0.7, 0.7, 0.7))
		return
	
	# Sort tags by usage count (most used first)
	var sorted_tags = all_tags.duplicate()
	sorted_tags.sort_custom(func(a, b):
		var usage_a = tag_usage.get(a, 0)
		var usage_b = tag_usage.get(b, 0)
		if usage_a != usage_b:
			return usage_a > usage_b
		return a < b
	)
	
	for tag in sorted_tags:
		# Apply filter
		if filter_text != "" and not tag.to_lower().contains(filter_text):
			continue
		
		var usage_count = tag_usage.get(tag, 0)
		var item_text = "🏷️ %s (%d)" % [tag, usage_count]
		tag_list.add_item(item_text)
		tag_list.set_item_metadata(tag_list.item_count - 1, tag)
		
		# Color code by usage
		var item_idx = tag_list.item_count - 1
		if usage_count >= 10:
			tag_list.set_item_custom_fg_color(item_idx, Color(0.4, 0.8, 0.4))  # Green for high usage
		elif usage_count >= 5:
			tag_list.set_item_custom_fg_color(item_idx, Color(0.6, 0.8, 1.0))  # Light blue for medium
		elif usage_count == 0:
			tag_list.set_item_custom_fg_color(item_idx, Color(0.6, 0.6, 0.6))  # Gray for unused

func _update_statistics() -> void:
	if not category_manager:
		return
	
	var total_assets = all_assets.size()
	var all_tags = category_manager.get_all_custom_tags()
	var total_tags = all_tags.size()
	
	# Count tagged vs untagged assets
	var tagged_count = 0
	for asset_info in all_assets:
		var asset_identifier = _get_asset_identifier(asset_info)
		var tags = category_manager.get_custom_tags(asset_identifier)
		if tags.size() > 0:
			tagged_count += 1
	
	var untagged_count = total_assets - tagged_count
	
	# Find most used tag
	var tag_usage = category_manager.tag_usage
	var most_used_tag = ""
	var most_used_count = 0
	for tag in all_tags:
		var count = tag_usage.get(tag, 0)
		if count > most_used_count:
			most_used_count = count
			most_used_tag = tag
	
	var stats_text = "📊 Assets: %d total  •  ✓ %d tagged  •  ○ %d untagged  •  🏷️ %d tags" % [
		total_assets, tagged_count, untagged_count, total_tags
	]
	
	if most_used_tag != "":
		stats_text += "  •  ⭐ Most used: '%s' (%d uses)" % [most_used_tag, most_used_count]
	
	stats_label.text = stats_text

func _on_asset_search_changed(_new_text: String) -> void:
	_populate_asset_tree()

func _on_tag_filter_changed(_new_text: String) -> void:
	_populate_tag_list()

func _on_asset_selection_changed(_item: TreeItem, _column: int, _selected: bool) -> void:
	_update_selected_assets()
	_update_button_states()

func _on_asset_nothing_selected() -> void:
	PluginLogger.debug("TagManagementDialog", "Nothing selected signal received")
	_update_selected_assets()
	_update_button_states()

func _on_tag_selection_changed(_index: int = -1, _selected: bool = true) -> void:
	_update_button_states()

func _has_tag(asset_path: String, tag: String) -> bool:
	var tags = category_manager.get_custom_tags(asset_path)
	return tag in tags

func _get_asset_identifier(asset_info: Dictionary) -> String:
	## Returns the unique identifier for an asset
	## For regular assets: returns the "path" key
	## For meshlib items: returns "meshlib_path:name"
	if asset_info.has("path"):
		return asset_info["path"]
	elif asset_info.has("meshlib_path") and asset_info.has("name"):
		return asset_info["meshlib_path"] + ":" + asset_info["name"]
	else:
		PluginLogger.error("TagManagementDialog", "Asset info missing required keys: " + str(asset_info.keys()))
		return ""

func _get_asset_display_name(asset_info: Dictionary) -> String:
	## Returns a display name for the asset
	if asset_info.has("path"):
		return asset_info["path"].get_file()
	elif asset_info.has("name"):
		return asset_info["name"]
	else:
		return "Unknown Asset"

func _update_selected_assets() -> void:
	selected_asset_paths.clear()
	
	var next_item = asset_tree.get_root().get_first_child() if asset_tree.get_root() else null
	while next_item:
		# Column 0 is the only selectable column (column 1 is set to non-selectable)
		# This gives us row-selection behavior while keeping multi-select capability
		if next_item.is_selected(0):
			selected_asset_paths.append(next_item.get_metadata(0))
		next_item = next_item.get_next()
	
	# Update selection info label
	var selection_info = get_node_or_null("%SelectionInfo")
	if selection_info:
		if selected_asset_paths.size() > 0:
			selection_info.text = "✓ Selected: %d asset(s)" % selected_asset_paths.size()
			selection_info.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
		else:
			selection_info.text = "💡 Tip: Ctrl+Click to multi-select, Shift+Click for range selection"
			selection_info.remove_theme_color_override("font_color")

func _update_button_states() -> void:
	var has_selected_assets = selected_asset_paths.size() > 0
	var has_selected_tags = tag_list.get_selected_items().size() > 0
	var selected_tag_count = tag_list.get_selected_items().size()
	
	bulk_add_button.disabled = not (has_selected_assets and has_selected_tags)
	bulk_remove_button.disabled = not (has_selected_assets and has_selected_tags)
	rename_tag_button.disabled = not (selected_tag_count == 1)
	merge_tags_button.disabled = not (selected_tag_count >= 2)
	delete_tag_button.disabled = not has_selected_tags

func _on_bulk_add_tags() -> void:
	# Ensure selected_asset_paths is up-to-date before operation
	_update_selected_assets()
	
	var selected_tags = _get_selected_tags()
	PluginLogger.info("TagManagementDialog", "Bulk add: %d tags to %d assets" % [selected_tags.size(), selected_asset_paths.size()])
	if selected_tags.is_empty() or selected_asset_paths.is_empty():
		return
	
	var changes_made = false
	for asset_path in selected_asset_paths:
		for tag in selected_tags:
			if not _has_tag(asset_path, tag):
				category_manager.add_tag(asset_path, tag)
				changes_made = true
	
	if changes_made:
		category_manager.save_config_file()
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()
		tags_modified.emit()
		
		# Show confirmation
		var msg = "Added %d tag(s) to %d asset(s)" % [selected_tags.size(), selected_asset_paths.size()]
		_show_notification(msg)

func _on_bulk_remove_tags() -> void:
	# Ensure selected_asset_paths is up-to-date before operation
	_update_selected_assets()
	
	var selected_tags = _get_selected_tags()
	PluginLogger.info("TagManagementDialog", "Bulk remove: %d tags from %d assets" % [selected_tags.size(), selected_asset_paths.size()])
	if selected_tags.is_empty() or selected_asset_paths.is_empty():
		return
	
	var changes_made = false
	for asset_path in selected_asset_paths:
		for tag in selected_tags:
			if _has_tag(asset_path, tag):
				category_manager.remove_tag(asset_path, tag)
				changes_made = true
	
	if changes_made:
		category_manager.save_config_file()
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()
		tags_modified.emit()
		
		# Show confirmation
		var msg = "Removed %d tag(s) from %d asset(s)" % [selected_tags.size(), selected_asset_paths.size()]
		_show_notification(msg)

func _on_rename_tag() -> void:
	var selected_indices = tag_list.get_selected_items()
	if selected_indices.size() != 1:
		return
	
	var old_tag = tag_list.get_item_metadata(selected_indices[0])
	
	var dialog = AcceptDialog.new()
	dialog.title = "Rename Tag"
	dialog.dialog_text = "Rename tag '%s' to:" % old_tag
	dialog.size = Vector2i(400, 120)
	
	var line_edit = LineEdit.new()
	line_edit.text = old_tag
	line_edit.select_all()
	dialog.add_child(line_edit)
	
	# Connect with proper signal cleanup
	var rename_action = func():
		var new_tag = line_edit.text.strip_edges()
		if new_tag.is_empty() or new_tag == old_tag:
			return
		
		if category_manager.get_all_custom_tags().has(new_tag):
			_show_error("Tag '%s' already exists!" % new_tag)
			return
		
		# Rename tag for all assets
		var assets_with_tag = []
		for asset_info in all_assets:
			var asset_identifier = _get_asset_identifier(asset_info)
			if _has_tag(asset_identifier, old_tag):
				assets_with_tag.append(asset_identifier)
		
		for asset_path in assets_with_tag:
			category_manager.remove_tag(asset_path, old_tag)
			category_manager.add_tag(asset_path, new_tag)
		
		category_manager.save_config_file()
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()
		tags_modified.emit()
		
		_show_notification("Renamed tag '%s' to '%s' (%d assets)" % [old_tag, new_tag, assets_with_tag.size()])
		dialog.queue_free()
	
	_connect_dialog_with_action(dialog, rename_action)
	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()

func _on_merge_tags() -> void:
	var selected_indices = tag_list.get_selected_items()
	if selected_indices.size() < 2:
		return
	
	var tags_to_merge = []
	for idx in selected_indices:
		tags_to_merge.append(tag_list.get_item_metadata(idx))
	
	var dialog = AcceptDialog.new()
	dialog.title = "Merge Tags"
	dialog.size = Vector2i(450, 180)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Merge these tags into:"
	vbox.add_child(label)
	
	var tags_label = Label.new()
	tags_label.text = "  • " + "\n  • ".join(tags_to_merge)
	tags_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(tags_label)
	
	var target_label = Label.new()
	target_label.text = "\nTarget tag name:"
	vbox.add_child(target_label)
	
	var line_edit = LineEdit.new()
	line_edit.text = tags_to_merge[0]
	line_edit.select_all()
	vbox.add_child(line_edit)
	
	# Connect with proper signal cleanup
	var merge_action = func():
		var target_tag = line_edit.text.strip_edges()
		if target_tag.is_empty():
			return
		
		# Merge all tags into target
		var affected_assets = 0
		for asset_info in all_assets:
			var asset_identifier = _get_asset_identifier(asset_info)
			var has_any_merge_tag = false
			for tag in tags_to_merge:
				if _has_tag(asset_identifier, tag):
					has_any_merge_tag = true
					if tag != target_tag:
						category_manager.remove_tag(asset_identifier, tag)
			
			if has_any_merge_tag:
				if not _has_tag(asset_identifier, target_tag):
					category_manager.add_tag(asset_identifier, target_tag)
				affected_assets += 1
		
		category_manager.save_config_file()
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()
		tags_modified.emit()
		
		_show_notification("Merged %d tags into '%s' (%d assets affected)" % [tags_to_merge.size(), target_tag, affected_assets])
		dialog.queue_free()
	
	_connect_dialog_with_action(dialog, merge_action)
	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()

func _on_delete_tag() -> void:
	var selected_tags = _get_selected_tags()
	if selected_tags.is_empty():
		return
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "Delete Tags"
	dialog.dialog_text = "Delete %d tag(s)?\n\n%s\n\nThis will remove these tags from all assets." % [
		selected_tags.size(),
		"  • " + "\n  • ".join(selected_tags)
	]
	dialog.size = Vector2i(400, 200)
	
	dialog.confirmed.connect(func():
		var affected_assets = 0
		for asset_info in all_assets:
			var asset_identifier = _get_asset_identifier(asset_info)
			for tag in selected_tags:
				if _has_tag(asset_identifier, tag):
					category_manager.remove_tag(asset_identifier, tag)
					affected_assets += 1
		
		category_manager.save_config_file()
		_populate_asset_tree()
		_populate_tag_list()
		_update_statistics()
		tags_modified.emit()
		
		_show_notification("Deleted %d tag(s) from %d asset(s)" % [selected_tags.size(), affected_assets])
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _on_create_new_tag() -> void:
	# Ensure selected_asset_paths is up-to-date before creating tag
	_update_selected_assets()
	
	# Debug: Print current selection state
	PluginLogger.debug("TagManagementDialog", "Creating new tag with %d assets selected" % selected_asset_paths.size())
	if selected_asset_paths.size() > 0:
		PluginLogger.debug("TagManagementDialog", "Selected assets: " + str(selected_asset_paths))
	
	var dialog = AcceptDialog.new()
	dialog.title = "Create New Tag"
	dialog.size = Vector2i(400, 140)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter new tag name:"
	vbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "e.g., medieval, props, outdoor..."
	vbox.add_child(line_edit)
	
	var hint_label = Label.new()
	hint_label.text = "💡 Tip: Use lowercase, keep it concise (1-2 words)"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint_label)
	
	dialog.confirmed.connect(func():
		var new_tag = line_edit.text.strip_edges().to_lower()
		
		# Validate tag name
		if new_tag.is_empty():
			_show_error("Tag name cannot be empty!")
			dialog.queue_free()
			return
		
		# Check if tag already exists
		if category_manager.get_all_custom_tags().has(new_tag):
			_show_error("Tag '%s' already exists!" % new_tag)
			dialog.queue_free()
			return
		
		# Validate tag name (alphanumeric, underscore, hyphen only)
		var regex = RegEx.new()
		regex.compile("^[a-z0-9_-]+$")
		if not regex.search(new_tag):
			_show_error("Tag name can only contain lowercase letters, numbers, hyphens, and underscores!")
			dialog.queue_free()
			return
		
		# Add the tag to all selected assets (if any) or just initialize it
		if not selected_asset_paths.is_empty():
			PluginLogger.info("TagManagementDialog", "Assigning tag '%s' to %d selected assets" % [new_tag, selected_asset_paths.size()])
			# Add to ALL selected assets, not just the first one
			for asset_path in selected_asset_paths:
				PluginLogger.debug("TagManagementDialog", "  - Adding to: " + asset_path)
				category_manager.add_tag(asset_path, new_tag)
			category_manager.save_config_file()
			_populate_asset_tree()
			_populate_tag_list()
			_update_statistics()
			tags_modified.emit()
			
			# Show success message
			var success_dialog = AcceptDialog.new()
			success_dialog.title = "Tag Created"
			success_dialog.dialog_text = "✅ Tag '%s' created and added to %d asset(s)!\n\nYou can now select more assets and tags to perform bulk operations." % [new_tag, selected_asset_paths.size()]
			success_dialog.size = Vector2i(450, 160)
			add_child(success_dialog)
			success_dialog.popup_centered()
			success_dialog.confirmed.connect(func():
				success_dialog.queue_free()
			)
		else:
			PluginLogger.info("TagManagementDialog", "No assets selected, initializing tag '%s' in system only" % new_tag)
			# Initialize the tag with 0 usage count so it appears in the tag list
			# This is stored in tag_usage and persisted to the config file
			if not category_manager.tag_usage.has(new_tag):
				category_manager.tag_usage[new_tag] = 0
			category_manager.save_config_file()
			_populate_tag_list()
			_update_statistics()
			
			# Don't show a popup - just let the user see the new tag in the list and continue working
			PluginLogger.info("TagManagementDialog", "Tag '%s' now visible in tag list with 0 usage, ready to assign" % new_tag)
		
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()

func _get_selected_tags() -> Array:
	var tags = []
	for idx in tag_list.get_selected_items():
		tags.append(tag_list.get_item_metadata(idx))
	return tags

func _show_notification(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.size = Vector2i(400, 100)
	add_child(dialog)
	dialog.popup_centered()
	
	# Auto-close after 2 seconds
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(dialog):
			dialog.hide()
			dialog.queue_free()
	)

func _show_error(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Error"
	dialog.dialog_text = message
	dialog.size = Vector2i(400, 100)
	add_child(dialog)
	dialog.popup_centered()







