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
		"basic": "Basic Settings",
		"advanced_grid": "Advanced Grid Settings",
		"reset_behavior": "Reset Behavior",
		"rotation": "Rotation Controls",
		"scale": "Scale Controls",
		"height": "Height Adjustment",
		"position": "Position Adjustment (XZ Manual Movement)",
		"modifiers": "Modifier Keys",
		"control": "Control Keys"
	}
	
	var first_section = true
	for section_key in section_config.keys():
		if not sections.has(section_key):
			continue
		
		# Add separator before each section (except first)
		if not first_section:
			var separator = HSeparator.new()
			separator.add_theme_constant_override("separation", 8)
			container.add_child(separator)
		first_section = false
		
		# Add section label
		var section_label = Label.new()
		section_label.text = section_config[section_key]
		section_label.add_theme_font_size_override("font_size", 14)
		section_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
		container.add_child(section_label)
		
		# Create appropriate container for the section
		if section_key == "basic":
			# Basic settings use individual controls
			_build_basic_section(container, sections[section_key], owner_node, settings_data, ui_controls)
		elif section_key == "reset_behavior":
			# Reset behavior uses checkboxes
			_build_checkbox_section(container, sections[section_key], owner_node, settings_data, ui_controls)
		else:
			# Other sections use grid layout
			_build_grid_section(container, sections[section_key], owner_node, settings_data, ui_controls)
	
	# Add utility section at the end
	_build_utility_section(container, owner_node)
	
	return ui_controls

static func _build_basic_section(container: Control, settings: Array, owner_node: Node, settings_data: Dictionary, ui_controls: Dictionary):
	for setting in settings:
		match setting.type:
			SettingsDefinition.SettingType.BOOL:
				var checkbox = CheckBox.new()
				checkbox.text = setting.ui_label
				checkbox.button_pressed = settings_data.get(setting.id, setting.default_value)
				checkbox.tooltip_text = setting.ui_tooltip
				container.add_child(checkbox)
				ui_controls[setting.id] = checkbox
			
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
					option_button.add_item(option.capitalize())
				
				# Set current value
				var current_value = settings_data.get(setting.id, setting.default_value)
				var selected_index = setting.options.find(current_value)
				if selected_index >= 0:
					option_button.selected = selected_index
				
				hbox.add_child(option_button)
				container.add_child(hbox)
				ui_controls[setting.id] = option_button
			
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

static func _build_utility_section(container: Control, owner_node: Node):
	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	container.add_child(separator)
	
	# Section label
	var utility_label = Label.new()
	utility_label.text = "Utilities"
	utility_label.add_theme_font_size_override("font_size", 14)
	utility_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	container.add_child(utility_label)
	
	# Reset all settings button
	var reset_button = Button.new()
	reset_button.text = "Reset All Settings to Defaults"
	reset_button.tooltip_text = "Reset all plugin settings to their default values"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.custom_minimum_size.y = 32
	reset_button.set_meta("action", "reset_settings")
	container.add_child(reset_button)
	
	# Small spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	container.add_child(spacer)
	
	# Clear cache button
	var clear_cache_button = Button.new()
	clear_cache_button.text = "Clear Thumbnail Cache"
	clear_cache_button.tooltip_text = "Clear cached thumbnails and regenerate them"
	clear_cache_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_cache_button.custom_minimum_size.y = 32
	clear_cache_button.set_meta("action", "clear_cache")
	container.add_child(clear_cache_button)
	
	# Final spacer
	var final_spacer = Control.new()
	final_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(final_spacer)







