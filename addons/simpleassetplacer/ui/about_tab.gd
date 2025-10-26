@tool
extends Control

class_name AboutTab

const PLUGIN_CONFIG_PATH := "res://addons/simpleassetplacer/plugin.cfg"
const README_URL := "https://github.com/IIFabixn/simple-asset-placer#readme"

var _initialized := false
var _version_label: Label
var _content_label: RichTextLabel

func _ready():
	ensure_ready()

func ensure_ready() -> void:
	if _initialized:
		return
	_build_layout()
	_populate_content()
	_initialized = true

func get_version_text() -> String:
	return _version_label.text if _version_label else ""

func _build_layout() -> void:
	name = "About"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(root_vbox)

	# Header section with inspector-like panel
	var header_panel := PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(header_panel)
	
	# Use editor's category background style
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.24, 0.26, 0.3, 1.0)  # Inspector category background
	header_style.set_content_margin_all(8)
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	header_panel.add_child(header)

	var title_label := Label.new()
	title_label.text = "Simple Asset Placer"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	header.add_child(title_label)

	_version_label = Label.new()
	_version_label.text = "Version Unknown"
	_version_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	_version_label.add_theme_font_size_override("font_size", 12)
	header.add_child(_version_label)

	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 8)
	root_vbox.add_child(spacer1)

	# Content sections
	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(content_vbox)

	_content_label = RichTextLabel.new()
	_content_label.bbcode_enabled = true
	_content_label.fit_content = true
	_content_label.scroll_active = false
	_content_label.selection_enabled = true
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content_label.add_theme_color_override("default_color", Color(0.875, 0.875, 0.875, 1.0))
	content_vbox.add_child(_content_label)

	# Spacer before link
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	content_vbox.add_child(spacer2)

	# Documentation link in a panel
	var link_panel := PanelContainer.new()
	link_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(link_panel)
	
	var link_style := StyleBoxFlat.new()
	link_style.bg_color = Color(0.24, 0.26, 0.3, 1.0)
	link_style.set_content_margin_all(8)
	link_style.corner_radius_top_left = 3
	link_style.corner_radius_top_right = 3
	link_style.corner_radius_bottom_left = 3
	link_style.corner_radius_bottom_right = 3
	link_panel.add_theme_stylebox_override("panel", link_style)

	var docs_link := LinkButton.new()
	docs_link.text = "Open full documentation"
	docs_link.uri = README_URL
	docs_link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	link_panel.add_child(docs_link)

func _populate_content() -> void:
	var version := _load_plugin_version()
	_version_label.text = "Version %s" % version

	var sections := [
		{
			"title": "Placement Workflow",
			"items": [
				"Pick assets from the 3D Models or MeshLibraries tabs.",
				"Click an asset to send it to the viewport preview.",
				"Left-click to place, or press ESC to exit placement."
			]
		},
		{
			"title": "Transform Workflow",
			"items": [
				"Select one or more Node3D objects in the scene.",
				"Press TAB to enter transform mode, then drag in the viewport.",
				"Use ENTER to confirm or ESC to cancel modal tweaks."
			]
		},
		{
			"title": "Essential Controls",
			"items": [
				"G/R/L switch between position, rotation, and scale while modal is active.",
				"Hold CTRL for fine steps, ALT for large steps, and SHIFT to reverse wheel input.",
				"Numeric input: press axis keys then type '=value' or '+offset' and hit ENTER."
			]
		},
		{
			"title": "Settings & Focus Tips",
			"items": [
				"Use the Settings tab for cursor warp, placement strategy, and sensitivity options.",
				"Dock text fields keep keyboard focus; click the viewport to resume placement controls.",
				"Toolbar toggles mirror these settings for quick changes while working in the viewport."
			]
		}
	]

	var bbcode := ""
	for section in sections:
		# Section title with inspector-like styling
		bbcode += "[color=#A5B1C2][b]%s[/b][/color]\n" % section.title
		# Items with subtle indentation
		for item in section.items:
			bbcode += "  • %s\n" % item
		bbcode += "\n"

	_content_label.bbcode_text = bbcode.strip_edges()

func _load_plugin_version() -> String:
	var config := ConfigFile.new()
	var err := config.load(PLUGIN_CONFIG_PATH)
	if err == OK:
		return str(config.get_value("plugin", "version", "Unknown"))
	return "Unknown"
