extends Node
## Example translation — template to translate Type III into any language.
##
## 1. Set "language" in manifest.json (fr, de, es, pt_BR...). While it is empty
##    this mod does nothing at all.
## 2. Write the translated text in each msgstr "" of translation.po.
##    An empty msgstr keeps the English text, so a partial translation is fine.
##
## How the texts are applied:
## - no msgctxt (interface): Godot's TranslationServer translates every Label,
##   Button, tab, option and description whose text matches the msgid exactly;
## - msgctxt "item name": shown in the item tooltip (only on screen, never saved
##   into the worlds, so disabling the mod brings the English names back);
## - msgctxt "stat name" / "stat description": item stats shown in the tooltip.
##
## While you play, interface texts / items / stats that are not in translation.po
## yet are added at the end of the file (with an empty msgstr) when the game closes.
##
## Enable only one translation mod at a time: the last one sets the language.

const PO_FILE := "translation.po"
const TOOLTIP_SCRIPT := "res://UI/HUD/tooltip.gd"
const STATS_DIR := "res://Resources/DisplayStat/DisplayStats/"
const MAX_NEW_ENTRIES := 300
## Placeholders that the game always replaces before showing them.
const IGNORE := ["-- DEBUG TEXT --", "Option name", "[b]Title[/b]", "<player name>"]

var dir: String = get_script().resource_path.get_base_dir()
## Language code from manifest.json ("language"). Empty = translation off.
var language := ""

var _loader: Node
var _translations := {}  # context -> {msgid: msgstr} (only translated entries)
var _known := {}         # every msgid in the .po, translated or not
var _new: Array[Dictionary] = []
var _mutex := Mutex.new()
var _record := false
var _held: Array = []
var _translation: Translation
var _re_digit := RegEx.create_from_string("[0-9]")
var _re_two_letters := RegEx.create_from_string("[A-Za-z].*[A-Za-z]")
var _re_node_name := RegEx.create_from_string("^[A-Za-z]*[a-z][A-Z][A-Za-z]*$")  # e.g. SettingsMenu


func _mod_init(loader: Node) -> void:
	_loader = loader
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))
	if manifest is Dictionary:
		language = str(manifest.get("language", "")).strip_edges()
	if language.is_empty():
		loader.log_info("[%s] no \"language\" in manifest.json: translation off" % name)
		return
	_load_po()
	_translation = ModTranslation.new()
	_translation.mod = self
	_translation.locale = language
	TranslationServer.add_translation(_translation)
	TranslationServer.set_locale(language)
	# The headless local server must not write the .po at the same time as the game.
	_record = DisplayServer.get_name() != "headless"


func _mod_ready(loader: Node) -> void:
	if language.is_empty():
		return
	_apply_stats()
	loader.get_tree().node_added.connect(_on_node_added)
	# After every mod is ready, so items added by other mods are found too.
	loader.game_ready.connect(_find_new_items, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation.mod = null
	_write_new_entries()


# --------------------------------------------------------------------------
# Applying the translation
# --------------------------------------------------------------------------

## Called by Godot (through ModTranslation) for every text it shows.
func lookup(src: StringName, context: StringName) -> StringName:
	var text: String = _translations.get(String(context), {}).get(String(src), "")
	if text:
		return StringName(text)
	if context == &"":
		_note_missing(String(src))
	return &""


func _apply_stats() -> void:
	for file: String in ResourceLoader.list_directory(STATS_DIR):
		var stat: Resource = load(STATS_DIR + file)
		if stat == null:
			continue
		_held.append(stat)  # keeps the translated stat in the resource cache
		var note := "Stat: " + file.get_basename()
		# The game shows the name as name.replace("_", " ").capitalize().
		var name_en := String(stat.name).replace("_", " ").capitalize()
		_check_known("stat name", name_en, note)
		var name_it := _get_text("stat name", name_en)
		if name_it:
			stat.name = StringName(name_it)
		if stat.description:
			_check_known("stat description", stat.description, note)
			var desc_it := _get_text("stat description", stat.description)
			if desc_it:
				stat.description = desc_it


func _on_node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script and script.resource_path == TOOLTIP_SCRIPT:
		_loader.extend_node_script(node, dir.path_join("tooltip_ext.gd"))


func _get_text(context: String, msgid: String) -> String:
	return _translations.get(context, {}).get(msgid, "")


# --------------------------------------------------------------------------
# Finding texts that are not in the .po yet
# --------------------------------------------------------------------------

func _find_new_items() -> void:
	var items: Dictionary = _loader.get_game().item_manager._loaded_items
	var ids: Array = items.keys()
	ids.sort()
	for id: String in ids:
		var item: Resource = items[id]
		var note := "Item: " + id + ("" if item.resource_path else " (added by a mod)")
		var name_en := String(item.item_name_override) if item.item_name_override \
				else String(item.item_id).capitalize().replace("_", " ")
		_check_known("item name", name_en, note)
		if item.description:
			_check_known("", item.description, "Item description: " + id)


func _check_known(context: String, msgid: String, note: String) -> void:
	if not _record or _re_two_letters.search(msgid) == null:
		return  # nothing to translate (e.g. "??", "//")
	_mutex.lock()
	var key := context + "\u0004" + msgid
	if not _known.has(key) and _new.size() < MAX_NEW_ENTRIES:
		_known[key] = true
		_new.append({"context": context, "msgid": msgid, "note": note})
	_mutex.unlock()


func _note_missing(text: String) -> void:
	if not _record or text.length() > 1000:
		return
	# Skip numbers, coordinates, BBCode-built texts and other dynamic texts.
	if text.contains("[") or _re_digit.search(text) or text in IGNORE \
			or _re_node_name.search(text):
		return
	_check_known("", text, "Found while playing (could also be a name or a dynamic text)")


func _write_new_entries() -> void:
	if not _record or _new.is_empty():
		return
	var path := dir.path_join(PO_FILE)
	# Re-read the file: it may have been edited (e.g. in Poedit) while playing.
	var on_disk := {}
	if FileAccess.file_exists(path):
		for e: Dictionary in _parse_po(FileAccess.get_file_as_string(path)):
			on_disk[e.context + "\u0004" + e.msgid] = true
	var out := ""
	for e: Dictionary in _new:
		if on_disk.has(e.context + "\u0004" + e.msgid):
			continue
		out += "\n#. %s\n" % e.note
		if e.context:
			out += "msgctxt %s\n" % _quote(e.context)
		out += "msgid %s\nmsgstr \"\"\n" % _quote(e.msgid)
	if out.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_loader.log_error("[%s] cannot write %s" % [name, path])
		return
	f.seek_end()
	f.store_string(out)
	f.close()
	_loader.log_info("[%s] %d new texts added to %s" % [name, _new.size(), PO_FILE])
	_new.clear()


# --------------------------------------------------------------------------
# .po file
# --------------------------------------------------------------------------

func _load_po() -> void:
	var path := dir.path_join(PO_FILE)
	if not FileAccess.file_exists(path):
		_loader.log_warn("[%s] %s not found" % [name, path])
		return
	var count := 0
	for e: Dictionary in _parse_po(FileAccess.get_file_as_string(path)):
		if e.msgid.is_empty():
			continue  # header
		_known[e.context + "\u0004" + e.msgid] = true
		if e.msgstr.is_empty():
			continue
		if not _translations.has(e.context):
			_translations[e.context] = {}
		_translations[e.context][e.msgid] = _keep_padding(e.msgid, e.msgstr)
		count += 1
	_loader.log_info("[%s] %d/%d texts translated (%s)" % [name, count, _known.size(), language])


## Returns [{context, msgid, msgstr}] from the text of a .po file.
static func _parse_po(text: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var cur := {}
	var field := ""
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			if line.is_empty() and cur.has("msgid"):
				_add_entry(entries, cur)
				cur = {}
				field = ""
			continue
		var value := ""
		if line.begins_with("msgid_plural"):
			field = ""  # plural forms are not used by the game
			continue
		if line.begins_with("msgctxt ") or line.begins_with("msgid ") or line.begins_with("msgstr "):
			var keyword := line.get_slice(" ", 0)
			if keyword != "msgstr" and cur.has("msgstr"):
				_add_entry(entries, cur)  # new entry without a blank line before it
				cur = {}
			field = keyword
			value = line.substr(keyword.length() + 1)
		elif line.begins_with("msgstr["):  # plural forms: use the first one
			field = "msgstr" if line.begins_with("msgstr[0]") else ""
			value = line.substr(line.find(" ") + 1)
		elif line.begins_with("\"") and field:
			value = line
		else:
			continue
		if field:
			cur[field] = cur.get(field, "") + _unquote(value)
	if cur.has("msgid"):
		_add_entry(entries, cur)
	return entries


static func _add_entry(entries: Array[Dictionary], cur: Dictionary) -> void:
	entries.append({
		"context": cur.get("msgctxt", ""),
		"msgid": cur.get("msgid", ""),
		"msgstr": cur.get("msgstr", ""),
	})


static func _unquote(s: String) -> String:
	s = s.strip_edges()
	if s.length() < 2 or not s.begins_with("\"") or not s.ends_with("\""):
		return ""
	s = s.substr(1, s.length() - 2)
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			i += 1
			match s[i]:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				_: out += s[i]  # \" and \\
		else:
			out += c
		i += 1
	return out


static func _quote(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") + "\""


## "   Create   " translated as "Crea" becomes "   Crea   " (same layout).
static func _keep_padding(msgid: String, msgstr: String) -> String:
	if msgstr != msgstr.strip_edges():
		return msgstr  # the translator chose the spaces
	var left := msgid.length() - msgid.lstrip(" \t\n").length()
	var right := msgid.length() - msgid.rstrip(" \t\n").length()
	return msgid.left(left) + msgstr + msgid.right(right)


## Godot asks this object for the translation of every text it shows.
class ModTranslation extends Translation:
	var mod: Object

	func _get_message(src_message: StringName, context: StringName) -> StringName:
		if mod == null:
			return &""
		return mod.lookup(src_message, context)
