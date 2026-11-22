extends HBoxContainer
## "Mod" tab added by the mod loader to Settings (main menu and pause menu).
## Lists every installed mod with an On/Off selector. Changes are saved right
## away and applied the next time the game starts.
##
## To look like the rest of the game it copies the layout of the "Video" tab
## and clones its widgets (section headers and option rows like "Fog").

const COLOR_DISABLED := Color(1, 1, 1, 0.55)
const COLOR_ERROR := Color(1.0, 0.55, 0.5)
const COLOR_CREDITS := Color(1, 1, 1, 0.75)

var loader: Node
var _list: VBoxContainer
var _header_template: Control
var _row_template: Control
var _hint: Label
var _restart_btn: Button


func setup(p_loader: Node, video_tab: Control) -> void:
	loader = p_loader
	name = loader.MODS_TAB_NAME

	var src_scroll: ScrollContainer = null
	var src_list: Container = null
	if video_tab:
		if video_tab is BoxContainer:
			alignment = video_tab.alignment
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
	add_child(scroll)

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


func _ready() -> void:
	visibility_changed.connect(_refresh_hint)
	_refresh_hint()


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
