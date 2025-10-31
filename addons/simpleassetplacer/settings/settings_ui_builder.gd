@tool
extends RefCounted

class_name SettingsUIBuilder

const SettingsDefinition = preload("res://addons/simpleassetplacer/settings/settings_definition.gd")

# Build the entire UI from settings definitions
static func build_settings_ui(container: Control, owner_node: Node, settings_data: Dictionary) -> Dictionary:
	var ui_controls = {}
	
	# Get settings grouped by section
	var sections = SettingsDefinition.get_settings_by_section()
	
	# Define section order and titles
	var section_config = {
		"basic": "Placement & Behavior",
		"keybinds": "Keybinds",
		"increments": "Adjustment Increments",
		"grid_snapping": "Grid & Snapping",
		"reset_behavior": "Reset Behavior",
		"debug": "Debug Options"
	}
	
	var first_section = true
	for section_key in section_config.keys():
		if not sections.has(section_key):
			continue
		
		# Add spacing before each section (except first)
		if not first_section:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(0, 2)
			container.add_child(spacer)
		first_section = false
		
		# Create collapsible section using Button + VBoxContainer
		var section_button = Button.new()
		section_button.text = "▶ " + section_config[section_key]
		section_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		section_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_button.flat = false
		section_button.toggle_mode = true
		section_button.button_pressed = false  # Collapsed by default
		section_button.add_theme_color_override("font_color", Color(0.875, 0.875, 0.875, 1.0))
		section_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		section_button.add_theme_color_override("font_pressed_color", Color(0.875, 0.875, 0.875, 1.0))
		
		# Custom button style to match Inspector categories
		var button_style = StyleBoxFlat.new()
		button_style.bg_color = Color(0.24, 0.26, 0.3, 1.0)
		button_style.set_content_margin(SIDE_LEFT, 8)
		button_style.set_content_margin(SIDE_RIGHT, 8)
		button_style.set_content_margin(SIDE_TOP, 6)
		button_style.set_content_margin(SIDE_BOTTOM, 6)
		button_style.corner_radius_top_left = 3
		button_style.corner_radius_top_right = 3
		
		var button_style_hover = button_style.duplicate()
		button_style_hover.bg_color = Color(0.28, 0.30, 0.34, 1.0)
		
		var button_style_pressed = button_style.duplicate()
		button_style_pressed.bg_color = Color(0.26, 0.28, 0.32, 1.0)
		
		section_button.add_theme_stylebox_override("normal", button_style)
		section_button.add_theme_stylebox_override("hover", button_style_hover)
		section_button.add_theme_stylebox_override("pressed", button_style_pressed)
		
		container.add_child(section_button)
		
		# Create panel container for section content
		var content_panel = PanelContainer.new()
		content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_panel.visible = false  # Hidden by default (collapsed)
		container.add_child(content_panel)
		
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.2, 0.22, 0.26, 1.0)  # Slightly darker than button
		panel_style.set_content_margin_all(8)
		panel_style.corner_radius_bottom_left = 3
		panel_style.corner_radius_bottom_right = 3
		panel_style.border_width_top = 1
		panel_style.border_color = Color(0.15, 0.17, 0.2, 1.0)
		content_panel.add_theme_stylebox_override("panel", panel_style)
		
		# Section content VBox
		var section_vbox = VBoxContainer.new()
		section_vbox.add_theme_constant_override("separation", 4)
		content_panel.add_child(section_vbox)
		
		# Connect toggle to show/hide content
		section_button.toggled.connect(func(pressed: bool):
			content_panel.visible = pressed
			section_button.text = ("▼ " if pressed else "▶ ") + section_config[section_key]
		)
		
		# Create appropriate container for the section
		if section_key == "basic":
			# Basic settings use individual controls
			_build_basic_section(section_vbox, sections[section_key], owner_node, settings_data, ui_controls)
		elif section_key == "reset_behavior":
			# Reset behavior uses checkboxes
			_build_checkbox_section(section_vbox, sections[section_key], owner_node, settings_data, ui_controls)
		else:
			# Other sections use grid layout
			_build_grid_section(section_vbox, sections[section_key], owner_node, settings_data, ui_controls)
	
	# Add utility section at the end
	_build_utility_section(container, owner_node, ui_controls)
	
	return ui_controls

static func _build_basic_section(container: Control, settings: Array, owner_node: Node, settings_data: Dictionary, ui_controls: Dictionary):
	# First pass: build all controls
	for setting in settings:
		var control_container = null  # Container to show/hide for dependent settings
		
		match setting.type:
			SettingsDefinition.SettingType.BOOL:
				var checkbox = CheckBox.new()
				checkbox.text = setting.ui_label
				checkbox.button_pressed = settings_data.get(setting.id, setting.default_value)
				checkbox.tooltip_text = setting.ui_tooltip
				container.add_child(checkbox)
				ui_controls[setting.id] = checkbox
				control_container = checkbox
			
			SettingsDefinition.SettingType.OPTION:
				var hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 8)
				
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(label)
				
				var option_button = OptionButton.new()
				option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				option_button.tooltip_text = setting.ui_tooltip
				
				# Add options to dropdown
				for option in setting.options:
					option_button.add_item(_format_option_label(option))
				
				# Set current value
				var current_value = settings_data.get(setting.id, setting.default_value)
				var selected_index = setting.options.find(current_value)
				if selected_index >= 0:
					option_button.selected = selected_index
				
				hbox.add_child(option_button)
				container.add_child(hbox)
				ui_controls[setting.id] = option_button
				control_container = hbox
			
			SettingsDefinition.SettingType.FLOAT:
				var hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 8)
				
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(label)
				
				var spinbox = SpinBox.new()
				spinbox.min_value = setting.min_value
				spinbox.max_value = setting.max_value
				spinbox.step = setting.step
				spinbox.value = settings_data.get(setting.id, setting.default_value)
				spinbox.custom_minimum_size.x = 80
				spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spinbox.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				spinbox.tooltip_text = setting.ui_tooltip
				hbox.add_child(spinbox)
				
				container.add_child(hbox)
				ui_controls[setting.id] = spinbox
				control_container = hbox
			
			SettingsDefinition.SettingType.STRING:
				var hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 8)
				
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(label)
				
				# Check if this is a node path setting that needs special handling
				var is_node_path = setting.id == "custom_parent_path"
				
				if is_node_path:
					# Create input container with browse button
					var input_container = HBoxContainer.new()
					input_container.add_theme_constant_override("separation", 4)
					input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					
					var line_edit = LineEdit.new()
					line_edit.text = settings_data.get(setting.id, setting.default_value)
					line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					line_edit.placeholder_text = "e.g., World/Objects"
					input_container.add_child(line_edit)
					
					# Browse button
					var browse_btn = Button.new()
					browse_btn.text = "..."
					browse_btn.custom_minimum_size.x = 32
					browse_btn.tooltip_text = "Select node from scene tree"
					browse_btn.pressed.connect(_on_browse_node_path.bind(line_edit))
					input_container.add_child(browse_btn)
					
					# Connect validation on text change (updates tooltip only)
					line_edit.text_changed.connect(_validate_node_path_tooltip.bind(line_edit))
					
					# Initial validation
					_validate_node_path_tooltip(line_edit.text, line_edit)
					
					hbox.add_child(input_container)
					ui_controls[setting.id] = line_edit
				else:
					# Standard string input
					var line_edit = LineEdit.new()
					line_edit.text = settings_data.get(setting.id, setting.default_value)
					line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					line_edit.tooltip_text = setting.ui_tooltip
					line_edit.placeholder_text = "Enter text..."
					hbox.add_child(line_edit)
					ui_controls[setting.id] = line_edit
				
				container.add_child(hbox)
				control_container = hbox
		
		# Handle conditional visibility
		if not setting.depends_on.is_empty() and control_container:
			# Store metadata for visibility updates
			control_container.set_meta("setting_id", setting.id)
			control_container.set_meta("depends_on", setting.depends_on)
			control_container.set_meta("depends_on_value", setting.depends_on_value)
			
			# Set initial visibility based on parent setting value
			var parent_value = settings_data.get(setting.depends_on, null)
			control_container.visible = setting.should_be_visible(parent_value)
	
	# Second pass: connect signals for dynamic visibility updates
	for setting in settings:
		if setting.type == SettingsDefinition.SettingType.OPTION and ui_controls.has(setting.id):
			var option_button = ui_controls[setting.id] as OptionButton
			if option_button:
				# Connect to update dependent controls when this option changes
				option_button.item_selected.connect(func(index: int):
					var selected_value = setting.options[index] if index < setting.options.size() else ""
					_update_dependent_visibility(container, setting.id, selected_value)
				)

static func _update_dependent_visibility(parent_container: Control, parent_id: String, parent_value) -> void:
	"""Update visibility of controls that depend on a parent setting (searches recursively)"""
	_update_dependent_visibility_recursive(parent_container, parent_id, parent_value)

static func _update_dependent_visibility_recursive(node: Node, parent_id: String, parent_value) -> int:
	"""Recursively search for dependent controls and return count found"""
	var found_count = 0
	
	for child in node.get_children():
		if child.has_meta("depends_on") and child.get_meta("depends_on") == parent_id:
			found_count += 1
			var depends_on_value = child.get_meta("depends_on_value")
			var should_show = false
			
			# Check if parent value matches required value(s)
			if depends_on_value is Array:
				should_show = parent_value in depends_on_value
			else:
				should_show = parent_value == depends_on_value
			
			child.visible = should_show
		
		# Recursively search children
		if child.get_child_count() > 0:
			found_count += _update_dependent_visibility_recursive(child, parent_id, parent_value)
	
	return found_count

static func _build_checkbox_section(container: Control, settings: Array, owner_node: Node, settings_data: Dictionary, ui_controls: Dictionary):
	for setting in settings:
		var checkbox = CheckBox.new()
		checkbox.text = setting.ui_label
		checkbox.button_pressed = settings_data.get(setting.id, setting.default_value)
		checkbox.tooltip_text = setting.ui_tooltip
		container.add_child(checkbox)
		ui_controls[setting.id] = checkbox

static func _build_grid_section(container: Control, settings: Array, owner_node: Node, settings_data: Dictionary, ui_controls: Dictionary):
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	container.add_child(grid)
	
	for setting in settings:
		match setting.type:
			SettingsDefinition.SettingType.KEY_BINDING:
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(label)
				
				var button = Button.new()
				button.text = settings_data.get(setting.id, setting.default_value)
				button.custom_minimum_size.x = 80
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.tooltip_text = setting.ui_tooltip
				grid.add_child(button)
				ui_controls[setting.id] = button
			
			SettingsDefinition.SettingType.FLOAT:
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(label)
				
				var spinbox = SpinBox.new()
				spinbox.min_value = setting.min_value
				spinbox.max_value = setting.max_value
				spinbox.step = setting.step
				spinbox.value = settings_data.get(setting.id, setting.default_value)
				spinbox.custom_minimum_size.x = 80
				spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spinbox.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				spinbox.tooltip_text = setting.ui_tooltip
				grid.add_child(spinbox)
				ui_controls[setting.id] = spinbox
			
			SettingsDefinition.SettingType.BOOL:
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(label)
				
				var checkbox = CheckBox.new()
				checkbox.button_pressed = settings_data.get(setting.id, setting.default_value)
				checkbox.tooltip_text = setting.ui_tooltip
				grid.add_child(checkbox)
				ui_controls[setting.id] = checkbox
			
			SettingsDefinition.SettingType.OPTION:
				var option_label = Label.new()
				option_label.text = setting.ui_label + ":"
				option_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(option_label)

				var option_button = OptionButton.new()
				option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				option_button.tooltip_text = setting.ui_tooltip

				for option in setting.options:
					option_button.add_item(_format_option_label(option))

				var option_value = settings_data.get(setting.id, setting.default_value)
				var option_index = setting.options.find(option_value)
				if option_index >= 0:
					option_button.selected = option_index

				grid.add_child(option_button)
				ui_controls[setting.id] = option_button
			
			SettingsDefinition.SettingType.STRING:
				var label = Label.new()
				label.text = setting.ui_label + ":"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(label)
				
				var line_edit = LineEdit.new()
				line_edit.text = settings_data.get(setting.id, setting.default_value)
				line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line_edit.tooltip_text = setting.ui_tooltip
				line_edit.placeholder_text = "Enter path..."
				grid.add_child(line_edit)
				ui_controls[setting.id] = line_edit
			
			SettingsDefinition.SettingType.VECTOR3:
				# Handle Vector3 separately (for snap_offset with X/Z spinboxes)
				if setting.id == "snap_offset":
					var offset_val: Vector3 = settings_data.get(setting.id, setting.default_value)
					
					# X offset
					var label_x = Label.new()
					label_x.text = "Grid Offset X:"
					label_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					grid.add_child(label_x)
					
					var spinbox_x = SpinBox.new()
					spinbox_x.min_value = -100.0
					spinbox_x.max_value = 100.0
					spinbox_x.step = 0.1
					spinbox_x.value = offset_val.x
					spinbox_x.custom_minimum_size.x = 80
					spinbox_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					spinbox_x.alignment = HORIZONTAL_ALIGNMENT_RIGHT
					grid.add_child(spinbox_x)
					ui_controls["grid_offset_x"] = spinbox_x
					
					# Z offset
					var label_z = Label.new()
					label_z.text = "Grid Offset Z:"
					label_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					grid.add_child(label_z)
					
					var spinbox_z = SpinBox.new()
					spinbox_z.min_value = -100.0
					spinbox_z.max_value = 100.0
					spinbox_z.step = 0.1
					spinbox_z.value = offset_val.z
					spinbox_z.custom_minimum_size.x = 80
					spinbox_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					spinbox_z.alignment = HORIZONTAL_ALIGNMENT_RIGHT
					grid.add_child(spinbox_z)
					ui_controls["grid_offset_z"] = spinbox_z

static func _validate_node_path_tooltip(path_text: String, line_edit: LineEdit) -> void:
	"""Validate node path and update tooltip with feedback"""
	if path_text.is_empty():
		line_edit.tooltip_text = "Empty = uses scene root"
		return
	
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		line_edit.tooltip_text = "No scene currently open"
		return
	
	# Check if path exists
	if scene_root.has_node(NodePath(path_text)):
		var target_node = scene_root.get_node(NodePath(path_text))
		line_edit.tooltip_text = "✓ Valid - Node: " + target_node.name
	else:
		line_edit.tooltip_text = "⚠ Path not found (will use scene root as fallback)"

static func _on_browse_node_path(line_edit: LineEdit) -> void:
	"""Open a simple prompt to select from scene tree or use current selection"""
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		push_warning("No scene is currently open")
		return
	
	# Check if user has a node selected in the scene tree
	var selection = EditorInterface.get_selection()
	var selected_nodes = selection.get_selected_nodes()
	
	if selected_nodes.size() > 0:
		var selected_node = selected_nodes[0]
		# Get path relative to scene root
		var relative_path = scene_root.get_path_to(selected_node)
		line_edit.text = str(relative_path)
		line_edit.text_changed.emit(line_edit.text)
	else:
		# No selection - show info to user
		push_warning("Please select a node in the scene tree first, then click the browse button")
		# Could alternatively open a custom tree dialog here

static func _format_option_label(option: String) -> String:
	var cleaned := option.replace("_", " ")
	var parts := cleaned.split(" ")
	for i in range(parts.size()):
		var part: String = parts[i]
		if part.is_empty():
			continue
		parts[i] = part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return " ".join(parts)

static func _build_utility_section(container: Control, owner_node: Node, ui_controls: Dictionary):
	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	container.add_child(spacer)
	
	# Create a regular panel (not collapsible) for utilities
	var utility_panel = PanelContainer.new()
	utility_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(utility_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.24, 0.26, 0.3, 1.0)
	panel_style.set_content_margin_all(8)
	panel_style.corner_radius_top_left = 3
	panel_style.corner_radius_top_right = 3
	panel_style.corner_radius_bottom_left = 3
	panel_style.corner_radius_bottom_right = 3
	utility_panel.add_theme_stylebox_override("panel", panel_style)
	
	var utility_vbox = VBoxContainer.new()
	utility_vbox.add_theme_constant_override("separation", 6)
	utility_panel.add_child(utility_vbox)
	
	# Section label (non-interactive)
	var utility_label = Label.new()
	utility_label.text = "Utilities"
	utility_label.add_theme_font_size_override("font_size", 13)
	utility_label.add_theme_color_override("font_color", Color(0.875, 0.875, 0.875, 1.0))
	utility_vbox.add_child(utility_label)
	
	# Small separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 1)
	utility_vbox.add_child(separator)
	
	# Reset all settings button
	var reset_button = Button.new()
	reset_button.text = "Reset All Settings to Defaults"
	reset_button.tooltip_text = "Reset all plugin settings to their default values"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.custom_minimum_size.y = 28
	reset_button.set_meta("action", "reset_settings")
	utility_vbox.add_child(reset_button)
	ui_controls["reset_settings"] = reset_button
	
	# Clear cache button
	var clear_cache_button = Button.new()
	clear_cache_button.text = "Clear Thumbnail Cache"
	clear_cache_button.tooltip_text = "Clear cached thumbnails and regenerate them"
	clear_cache_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_cache_button.custom_minimum_size.y = 28
	clear_cache_button.set_meta("action", "clear_cache")
	utility_vbox.add_child(clear_cache_button)
	ui_controls["clear_cache"] = clear_cache_button







