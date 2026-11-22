extends MarginContainer
## "Mod" tab added by the mod loader to Settings (main menu and pause menu).
## Lists every installed mod with an On/Off selector. Changes are saved right
## away and applied the next time the game starts.
##
## To look like the rest of the game it copies the layout of the "Video" tab
## and clones its widgets (section headers and option rows like "Fog").
## The GitHub button sits on top of that layout, in the bottom-right corner.

const COLOR_DISABLED := Color(1, 1, 1, 0.55)
const COLOR_ERROR := Color(1.0, 0.55, 0.5)
const COLOR_CREDITS := Color(1, 1, 1, 0.75)
const GITHUB_TEXT_SCALE := 0.75

## GitHub mark (Octicons "mark-github", MIT license), white: the button tints it.
const GITHUB_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="#ffffff" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>"""

var loader: Node
var _list: VBoxContainer
var _header_template: Control
var _row_template: Control
var _hint: Label
var _restart_btn: Button
var _github_btn: Button


func setup(p_loader: Node, video_tab: Control) -> void:
	loader = p_loader
	name = loader.MODS_TAB_NAME
	for side: String in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, 0)

	# Same layout as the Video tab: an HBoxContainer with a ScrollContainer.
	var page := HBoxContainer.new()
	add_child(page)
	var src_scroll: ScrollContainer = null
	var src_list: Container = null
	if video_tab:
		if video_tab is BoxContainer:
			page.alignment = video_tab.alignment
		size_flags_horizontal = video_tab.size_flags_horizontal
		size_flags_vertical = video_tab.size_flags_vertical
		src_scroll = _first_child_of_type(video_tab, "ScrollContainer")
		if src_scroll:
			src_list = _first_child_of_type(src_scroll, "Container")

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if src_scroll:
		scroll.custom_minimum_size = src_scroll.custom_minimum_size
		scroll.size_flags_horizontal = src_scroll.size_flags_horizontal
		scroll.size_flags_vertical = src_scroll.size_flags_vertical
		scroll.horizontal_scroll_mode = src_scroll.horizontal_scroll_mode
		scroll.vertical_scroll_mode = src_scroll.vertical_scroll_mode
	else:
		scroll.custom_minimum_size = Vector2(650, 0)
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	if src_list:
		_list.size_flags_horizontal = src_list.size_flags_horizontal
		_list.size_flags_vertical = src_list.size_flags_vertical
		if src_list.has_theme_constant_override(&"separation"):
			_list.add_theme_constant_override(&"separation", src_list.get_theme_constant(&"separation"))
		_header_template = _find_header(src_list)
		_row_template = _find_option_row(src_list)
	# Fill the whole panel height, so the credits can sit at the bottom.
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_build()
	_add_github_button()


func _ready() -> void:
	visibility_changed.connect(_refresh_hint)
	_refresh_hint()
	_style_github_button()


## Small button in the bottom-right corner that opens the project page.
func _add_github_button() -> void:
	_github_btn = Button.new()
	_github_btn.name = "GitHub"
	_github_btn.text = "GitHub"
	_github_btn.tooltip_text = loader.PROJECT_URL
	_github_btn.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED  # a name: nothing to translate
	_github_btn.size_flags_horizontal = SIZE_SHRINK_END
	_github_btn.size_flags_vertical = SIZE_SHRINK_END
	_github_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_github_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP  # logo above the text
	_github_btn.pressed.connect(loader.open_project_page)
	add_child(_github_btn)


## Smaller text than the other buttons (it must fit between the scroll bar and the
## panel's edge) and the logo drawn to match it. Needs the theme: call when in the tree.
func _style_github_button() -> void:
	if _github_btn == null:
		return
	var font_size := roundi(_github_btn.get_theme_font_size(&"font_size") * GITHUB_TEXT_SCALE)
	_github_btn.add_theme_font_size_override(&"font_size", font_size)
	var font := _github_btn.get_theme_font(&"font")
	var px := font.get_height(font_size) * 1.2 if font else 20.0
	var image := Image.new()
	if image.load_svg_from_string(GITHUB_ICON_SVG, px / 16.0) == OK:
		_github_btn.icon = ImageTexture.create_from_image(image)


func _build() -> void:
	_list.add_child(_make_header("- Mods -"))
	var all: Array[Dictionary] = loader.get_mod_list()
	if all.is_empty():
		_list.add_child(_make_text(
			"No mods installed.\nPut them in the \"mods\" folder next to the game."))
	for info: Dictionary in all:
		_list.add_child(_make_row(info))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_list.add_child(spacer)
	_hint = _make_text("")
	_list.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	var open_btn := Button.new()
	open_btn.text = "Open mods folder"
	open_btn.pressed.connect(loader.open_mods_folder)
	buttons.add_child(open_btn)
	_restart_btn = Button.new()
	_restart_btn.text = "Restart now"
	_restart_btn.pressed.connect(loader.restart_game)
	buttons.add_child(_restart_btn)
	_list.add_child(buttons)

	# Credits at the bottom of the panel (text from modloader/credits.txt).
	var credits_text: String = loader.get_credits_text()
	if credits_text:
		var push := Control.new()
		push.custom_minimum_size = Vector2(0, 24)
		push.size_flags_vertical = SIZE_EXPAND_FILL  # pushes the credits down
		_list.add_child(push)
		_list.add_child(_make_header("- Credits -"))
		var credits := _make_text(credits_text)
		credits.modulate = COLOR_CREDITS
		_list.add_child(credits)
		var bottom := Control.new()
		bottom.custom_minimum_size = Vector2(0, 16)
		_list.add_child(bottom)


func _make_row(info: Dictionary) -> Control:
	var row: Control = null
	var label: Label = null
	var option: OptionButton = null
	if _row_template:
		row = _row_template.duplicate(0)  # no scripts, signals or groups
		var labels := row.find_children("*", "Label", true, false)
		var options := row.find_children("*", "OptionButton", true, false)
		if labels.is_empty() or options.is_empty():
			row.free()
			row = null
		else:
			label = labels[0]
			option = options[0]
	if row == null:  # fallback if the game's layout changes
		row = PanelContainer.new()
		var h := HBoxContainer.new()
		row.add_child(h)
		label = Label.new()
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(label)
		option = OptionButton.new()
		h.add_child(option)

	row.name = info.id
	row.visible = true
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = _tooltip(info)
	label.text = "%s  v%s" % [info.name, info.version]
	label.set_meta(&"mod_id", info.id)

	option.clear()
	option.add_item("On", 1)
	option.add_item("Off", 0)
	option.select(0 if info.enabled else 1)
	option.item_selected.connect(func(index: int) -> void:
		loader.set_mod_enabled(info.id, option.get_item_id(index) == 1)
		_color_label(label, info)
		_refresh_hint()
	)
	_color_label(label, info)
	return row


func _color_label(label: Label, info: Dictionary) -> void:
	if not info.enabled:
		label.modulate = COLOR_DISABLED
	elif info.status == loader.STATUS_ERROR:
		label.modulate = COLOR_ERROR
	else:
		label.modulate = Color.WHITE


func _tooltip(info: Dictionary) -> String:
	var lines: PackedStringArray = []
	if info.description:
		lines.append(info.description)
		lines.append("")
	if info.author:
		lines.append("Author: " + info.author)
	lines.append("Version: " + info.version)
	if info.dependencies:
		lines.append("Requires: " + ", ".join(info.dependencies))
	lines.append("Source: " + info.source)
	if info.status == loader.STATUS_ERROR:
		lines.append("Status: NOT loaded — " + info.error)
	elif info.status == loader.STATUS_DISABLED:
		lines.append("Status: disabled")
	else:
		lines.append("Status: loaded")
	return "\n".join(lines)


func _refresh_hint() -> void:
	if _hint == null or not is_inside_tree():
		return
	var lines: PackedStringArray = []
	# Warn about enabled mods that need a disabled one.
	for info: Dictionary in loader.get_mod_list():
		if not info.enabled:
			continue
		for dep: String in info.dependencies:
			if not loader.is_mod_enabled(dep):
				lines.append("\"%s\" requires \"%s\", which is off or missing." % [info.name, dep])

	var pending: bool = loader.has_pending_changes()
	var can_restart: bool = loader.can_restart()
	if pending and can_restart:
		lines.append("Restart the game to apply the changes.")
	elif pending:
		lines.append("Quit to the main menu and restart the game to apply the changes.")
	else:
		lines.append("Changes are applied after restarting the game.")
	_hint.text = "\n".join(lines)
	_hint.modulate = Color.WHITE if pending else COLOR_DISABLED
	_restart_btn.visible = pending and can_restart


func _make_header(text: String) -> Control:
	if _header_template:
		var header: Control = _header_template.duplicate(0)
		header.visible = true
		var labels := header.find_children("*", "Label", true, false)
		if not labels.is_empty():
			labels[0].text = text
			return header
		header.free()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_FILL
	return label


static func _first_child_of_type(node: Node, type: String) -> Node:
	for c: Node in node.get_children():
		if c.is_class(type):
			return c
	return null


## Section header: a MarginContainer with a "- Something -" Label (e.g. "- Video -").
static func _find_header(list: Node) -> Control:
	for c: Node in list.get_children():
		if c is MarginContainer and c.visible and c.get_child_count() > 0 \
				and c.get_child(0) is Label and c.get_child(0).text.begins_with("-"):
			return c
	return null


## Option row: a PanelContainer that contains an OptionButton (e.g. "Fog").
static func _find_option_row(list: Node) -> Control:
	for c: Node in list.get_children():
		if c is PanelContainer and c.visible \
				and not c.find_children("*", "OptionButton", true, false).is_empty():
			return c
	return null
