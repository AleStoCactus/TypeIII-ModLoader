extends Node
## Type III Mod Loader
##
## Injected through `override.cfg` ([autoload_prepend]), so its `_init()` runs
## BEFORE the game loads its own autoloads (Game, Console…).
## This lets mods replace scripts and resources before they are used.
##
## Mod lifecycle (mods/<folder>/mod_main.gd):
##   _mod_init(loader)   -> right away, before the game: script extensions, overrides
##   _mod_ready(loader)  -> the game is ready (main menu): items, recipes, commands
##   _world_ready(world) -> a world has been loaded
##
## Mods can be enabled/disabled from Settings > Mod (saved in modloader/mod_config.json).
## Changes are applied on the next launch.
##
## NOTE: this script must not reference the game's class_names (ItemManager,
## World…) statically, otherwise they would be loaded before mods can extend them.

signal mods_initialized
signal game_ready
signal world_loaded(world: Node)
signal mod_toggled(id: String, enabled: bool)

const LOADER_VERSION := "0.2.2"
const MODS_DIR_NAME := "mods"
const MANIFEST_FILE := "manifest.json"
const MAIN_SCRIPT := "mod_main.gd"
const CONFIG_FILE := "modloader/mod_config.json"
const LOG_FILE := "modloader/modloader.log"
const CREDITS_FILE := "modloader/credits.txt"

const RECIPES_CRAFTING := "res://Resources/Crafting Recipes/Lists/player_default.tres"
const RECIPES_SMELTING := "res://Resources/Crafting Recipes/Lists/player_default_smelting.tres"
const SETTINGS_MENU_SCENE := "res://UI/Menus/settings_menu.tscn"
const MAIN_MENU_SCENE := "res://UI/Menus/main_menu_new.tscn"
const MODS_TAB_NAME := "Mod"
const _ITEM_RESOURCE_SCRIPT := "res://Items/item_resource.gd"
const _CRAFTING_RECIPE_SCRIPT := "res://Resources/Crafting Recipes/crafting_recipe.gd"
const _ITEM_MANAGER_EXT := "res://modloader/extensions/item_manager_ext.gd"
const _MODS_TAB_SCRIPT := "res://modloader/ui/mods_tab.gd"

const STATUS_LOADED := "loaded"
const STATUS_DISABLED := "disabled"
const STATUS_ERROR := "error"

var game_dir: String = ""
var mods_dir: String = ""
var game_version: String = ""
## id -> Dictionary with the info of EVERY installed mod (enabled or not)
var mods: Dictionary = {}
## Final load order (mods actually loaded in this session)
var load_order: Array[String] = []

var _disabled_ids: Array[String] = []
var _enabled_at_start: Dictionary = {}
var _instances: Dictionary = {}
var _extensions: Array[Dictionary] = []
var _held: Array = []  # strong refs: keeps modified resources alive in the cache
var _item_icons: Dictionary = {}
var _pending_items: Array[Resource] = []
var _is_game_ready := false
var _log: FileAccess


# --------------------------------------------------------------------------
# Startup
# --------------------------------------------------------------------------

func _init() -> void:
	game_dir = OS.get_executable_path().get_base_dir()
	mods_dir = game_dir.path_join(MODS_DIR_NAME)
	game_version = str(ProjectSettings.get_setting("application/config/version", "?"))
	_log = FileAccess.open(game_dir.path_join(LOG_FILE), FileAccess.WRITE)
	log_info("Type III Mod Loader v%s (game v%s, Godot %s)" % [
		LOADER_VERSION, game_version, Engine.get_version_info().string])

	_load_config()
	_discover_mods()
	_resolve_load_order()
	_mount_archives()
	_init_mods()
	for id: String in mods:
		_enabled_at_start[id] = mods[id].enabled
		if mods[id].status.is_empty():
			mods[id].status = STATUS_LOADED if id in load_order else STATUS_DISABLED
	log_info("Active mods (%d/%d): %s" % [load_order.size(), mods.size(), ", ".join(load_order)])
	mods_initialized.emit()


func _ready() -> void:
	# The game's autoloads are added to the tree after us:
	# wait for the end of the frame so they are all ready.
	_on_game_ready.call_deferred()


func _on_game_ready() -> void:
	var game := get_game()
	if game == null:
		log_error("Autoload 'Game' not found: did the game change?")
		return
	_is_game_ready = true
	# Custom icons for mod items.
	extend_node_script(game.item_manager, _ITEM_MANAGER_EXT)
	for item: Resource in _pending_items:
		_add_item_now(item)
	_pending_items.clear()

	game.signals.world_ready.connect(_on_world_ready)
	add_console_command("mods", _cmd_mods, 0, 0, "Lists the installed mods.")

	# "Mod" tab in the settings menu (main menu and pause menu).
	for node: Node in get_tree().root.find_children("*", "Control", true, false):
		if node.scene_file_path == SETTINGS_MENU_SCENE:
			_inject_mods_tab(node)
	get_tree().node_added.connect(_on_node_added)

	for id: String in load_order:
		_call_mod(id, "_mod_ready", [self])
	game_ready.emit()
	log_info("Game ready, mods initialized.")


func _on_world_ready() -> void:
	var world: Node = get_game().world
	for id: String in load_order:
		_call_mod(id, "_world_ready", [world])
	world_loaded.emit(world)


func _on_node_added(node: Node) -> void:
	if node.scene_file_path == SETTINGS_MENU_SCENE:
		node.ready.connect(_inject_mods_tab.bind(node), CONNECT_ONE_SHOT)


func _inject_mods_tab(settings_menu: Node) -> void:
	if not is_instance_valid(settings_menu):
		return
	var tabs := settings_menu.get_node_or_null(^"TabContainer") as TabContainer
	if tabs == null:
		var found := settings_menu.find_children("*", "TabContainer", true, false)
		if found.is_empty():
			log_warn("Settings menu without TabContainer: 'Mod' tab not added")
			return
		tabs = found[0]
	if tabs.has_node(NodePath(MODS_TAB_NAME)):
		return
	var page: Control = load(_MODS_TAB_SCRIPT).new()
	page.setup(self, tabs.get_node_or_null(^"Video"))
	tabs.add_child(page)


# --------------------------------------------------------------------------
# Config (enabled/disabled mods)
# --------------------------------------------------------------------------

func _load_config() -> void:
	var path := game_dir.path_join(CONFIG_FILE)
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY:
		_disabled_ids = _to_str_array(data.get("disabled", []))
	else:
		log_warn("%s is not valid JSON, ignored" % CONFIG_FILE)


func _save_config() -> void:
	var disabled: Array[String] = []
	for id: String in mods:
		if not mods[id].enabled:
			disabled.append(id)
	# Remember disabled mods that are not installed right now, too.
	for id: String in _disabled_ids:
		if not mods.has(id) and id not in disabled:
			disabled.append(id)
	disabled.sort()
	_disabled_ids = disabled
	var f := FileAccess.open(game_dir.path_join(CONFIG_FILE), FileAccess.WRITE)
	if f == null:
		log_error("Could not write %s" % CONFIG_FILE)
		return
	f.store_string(JSON.stringify({"disabled": disabled}, "\t") + "\n")


# --------------------------------------------------------------------------
# Mod discovery and loading
# --------------------------------------------------------------------------

func _discover_mods() -> void:
	if not DirAccess.dir_exists_absolute(mods_dir):
		DirAccess.make_dir_recursive_absolute(mods_dir)
		log_info("Created empty folder: %s" % mods_dir)
		return

	var entries: Array[String] = []
	entries.append_array(DirAccess.get_directories_at(mods_dir))
	entries.append_array(DirAccess.get_files_at(mods_dir))
	entries.sort()

	for entry: String in entries:
		if entry.begins_with("."):
			continue
		var abs_path := mods_dir.path_join(entry)
		if DirAccess.dir_exists_absolute(abs_path):
			var manifest := abs_path.path_join(MANIFEST_FILE)
			if not FileAccess.file_exists(manifest):
				log_warn("%s: missing %s, skipped" % [entry, MANIFEST_FILE])
				continue
			_register_mod(FileAccess.get_file_as_string(manifest),
				"res://%s/%s" % [MODS_DIR_NAME, entry], "folder", "")
		elif entry.get_extension().to_lower() == "zip":
			_read_zip(abs_path)


## Reads the manifests inside a zip WITHOUT mounting it (it is mounted only
## if enabled). It must contain mods/<folder>/manifest.json.
func _read_zip(abs_path: String) -> void:
	var zr := ZIPReader.new()
	if zr.open(abs_path) != OK:
		log_error("Unreadable zip: %s" % abs_path.get_file())
		return
	var found := false
	for f: String in zr.get_files():
		var parts := f.split("/")
		if parts.size() == 3 and parts[0] == MODS_DIR_NAME and parts[2] == MANIFEST_FILE:
			found = true
			_register_mod(zr.read_file(f).get_string_from_utf8(),
				"res://" + f.get_base_dir(), abs_path.get_file(), abs_path)
	zr.close()
	if not found:
		log_error("%s: missing mods/<folder>/%s inside the zip" % [abs_path.get_file(), MANIFEST_FILE])


func _register_mod(manifest_text: String, res_dir: String, source: String, archive: String) -> void:
	var data: Variant = JSON.parse_string(manifest_text)
	if typeof(data) != TYPE_DICTIONARY:
		log_error("%s: invalid %s" % [res_dir, MANIFEST_FILE])
		return
	var id := str(data.get("id", ""))
	if not id.is_valid_ascii_identifier():
		log_error("%s: 'id' missing or invalid (letters, numbers and _ only)" % res_dir)
		return
	if mods.has(id):
		log_error("Duplicate mod '%s' (%s and %s)" % [id, mods[id].source, source])
		return

	var info := {
		"id": id,
		"name": str(data.get("name", id)),
		"version": str(data.get("version", "0.0.0")),
		"author": str(data.get("author", "")),
		"description": str(data.get("description", "")),
		"game_version": str(data.get("game_version", "")),
		"dependencies": _to_str_array(data.get("dependencies", [])),
		"load_after": _to_str_array(data.get("load_after", [])),
		"dir": res_dir,
		"source": source,
		"archive": archive,
		"enabled": id not in _disabled_ids,
		"status": "",
		"error": "",
	}
	mods[id] = info
	if not info.enabled:
		log_info("Found: %s v%s [%s] (disabled)" % [id, info.version, source])
		return
	if info.game_version and info.game_version != game_version:
		log_warn("%s was made for game v%s (you have v%s): it might not work" % [
			id, info.game_version, game_version])
	log_info("Found: %s v%s [%s]" % [id, info.version, source])


func _resolve_load_order() -> void:
	# Drop (cascading) enabled mods whose dependencies are missing or disabled.
	var changed := true
	while changed:
		changed = false
		for id: String in mods:
			var m: Dictionary = mods[id]
			if not m.enabled or m.error:
				continue
			for dep: String in m.dependencies:
				var reason := ""
				if not mods.has(dep):
					reason = "missing dependency: " + dep
				elif not mods[dep].enabled:
					reason = "required mod is disabled: " + dep
				elif mods[dep].error:
					reason = "required mod failed: " + dep
				if reason:
					_fail(id, reason)
					changed = true
					break

	var ids: Array = mods.keys()
	ids.sort()
	var visited := {}
	for id: String in ids:
		_visit(id, {}, visited)


func _visit(id: String, stack: Dictionary, visited: Dictionary) -> void:
	if visited.has(id) or not mods[id].enabled or mods[id].error:
		return
	if stack.has(id):
		_fail(id, "circular dependency")
		return
	stack[id] = true
	for dep: String in mods[id].dependencies + mods[id].load_after:
		if mods.has(dep):
			_visit(dep, stack, visited)
	stack.erase(id)
	visited[id] = true
	if not mods[id].error:
		load_order.append(id)


## Mounts the zips of the enabled mods on top of res://, in load order
## (a later mod overrides the files of an earlier one).
func _mount_archives() -> void:
	var mounted := {}
	for id: String in load_order.duplicate():
		var archive: String = mods[id].archive
		if archive.is_empty():
			continue
		if not mounted.has(archive):
			mounted[archive] = ProjectSettings.load_resource_pack(archive, true)
			if mounted[archive]:
				log_info("Mounted archive: %s" % archive.get_file())
		if not mounted[archive]:
			_fail(id, "could not mount " + archive.get_file())
			load_order.erase(id)


func _init_mods() -> void:
	for id: String in load_order.duplicate():
		var m: Dictionary = mods[id]
		var script_path: String = m.dir.path_join(MAIN_SCRIPT)
		if not FileAccess.file_exists(script_path):
			continue  # data/asset-only mod: that's fine
		var script := load(script_path) as GDScript
		if script == null or not script.can_instantiate():
			_fail(id, "error in %s (see the log)" % MAIN_SCRIPT)
			load_order.erase(id)
			continue
		var inst: Object = script.new()
		_instances[id] = inst
		if inst is Node:
			inst.name = id
			add_child(inst)
		_call_mod(id, "_mod_init", [self])


func _fail(id: String, reason: String) -> void:
	mods[id].error = reason
	mods[id].status = STATUS_ERROR
	log_error("%s was not loaded: %s" % [id, reason])


func _call_mod(id: String, method: String, args: Array) -> void:
	var inst: Object = _instances.get(id)
	if inst and inst.has_method(method):
		inst.callv(method, args)


# --------------------------------------------------------------------------
# Mod management API (used by the Settings > Mod tab)
# --------------------------------------------------------------------------

## Info of every installed mod, sorted by name.
func get_mod_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in mods:
		out.append(mods[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


func is_mod_enabled(id: String) -> bool:
	return mods.has(id) and mods[id].enabled


## Enables/disables a mod. Saved immediately, applied on the next launch.
func set_mod_enabled(id: String, enabled: bool) -> void:
	if not mods.has(id) or mods[id].enabled == enabled:
		return
	mods[id].enabled = enabled
	_save_config()
	log_info("%s %s (applied after restart)" % [id, "enabled" if enabled else "disabled"])
	mod_toggled.emit(id, enabled)


## True if some mod was enabled/disabled since the game started.
func has_pending_changes() -> bool:
	for id: String in mods:
		if mods[id].enabled != _enabled_at_start.get(id, mods[id].enabled):
			return true
	return false


## True when the game can be restarted safely (we are in the main menu).
func can_restart() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == MAIN_MENU_SCENE


## Closes the game the normal way (it saves its settings) and relaunches it.
func restart_game() -> void:
	log_info("Restarting the game...")
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)


## Text shown under "- Credits -" in the Mod tab ({version} = mod loader version).
func get_credits_text() -> String:
	var path := game_dir.path_join(CREDITS_FILE)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges().replace("{version}", LOADER_VERSION)


func open_mods_folder() -> void:
	# Same call the game uses to open world folders (works on Windows and Linux).
	OS.shell_show_in_file_manager(mods_dir, true)


# --------------------------------------------------------------------------
# API for mods
# --------------------------------------------------------------------------

## The game's "Game" autoload (null if not ready yet).
func get_game() -> Node:
	return get_node_or_null(^"/root/Game") if is_inside_tree() else null


func is_mod_loaded(id: String) -> bool:
	return id in load_order


## Replaces a game script with one that extends it.
## The child script must start with: extends "res://path/to/original.gd"
## and can override functions, calling super() to keep the base behavior.
## Call it in _mod_init, before the game uses the script. It applies to every
## node/object created AFTERWARDS (player, world, UI…).
## If the original script has a class_name, Godot prints
## "Compiler bug: unresolved assign": it is harmless (it falls back to a plain
## assignment), but for nodes that already exist extend_node_script() is cleaner.
func install_script_extension(child_script_path: String) -> bool:
	var child := load(child_script_path) as Script
	if child == null:
		log_error("Could not load extension: " + child_script_path)
		return false
	var parent := child.get_base_script()
	if parent == null or parent.resource_path.is_empty():
		log_error("%s must 'extends \"res://…\"' a game script" % child_script_path)
		return false
	var parent_path := parent.resource_path
	child.take_over_path(parent_path)
	_held.append(child)
	_extensions.append({"child": child_script_path, "parent": parent_path})
	log_info("Extension: %s -> %s" % [child_script_path, parent_path])
	return true


## Swaps the script of an ALREADY existing node (e.g. an autoload such as
## Game.item_manager) for one that extends it, keeping its variable values.
## Use it in _mod_ready. The script must extend the node's current script.
func extend_node_script(node: Object, child_script_path: String) -> bool:
	var child := load(child_script_path) as Script
	if node == null or child == null:
		log_error("extend_node_script: invalid node or script (%s)" % child_script_path)
		return false
	var old: Script = node.get_script()
	var state := {}
	if old:
		for p: Dictionary in old.get_script_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				state[p.name] = node.get(p.name)
	node.set_script(child)
	for k: String in state:
		node.set(k, state[k])
	_extensions.append({"child": child_script_path, "parent": old.resource_path if old else ""})
	log_info("Runtime extension: %s on %s" % [child_script_path, node])
	return true


## Replaces a game resource (texture, scene, .tres…) with another one.
## Call it in _mod_init. The type must be compatible with the original.
func replace_resource(game_path: String, new_resource: Resource) -> void:
	new_resource.take_over_path(game_path)
	_held.append(new_resource)
	log_info("Resource replaced: " + game_path)


## Loads an image (.png/.jpg/.webp) as a texture, also from a mod folder.
func load_texture(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		log_error("Could not load image: " + path)
		return null
	return ImageTexture.create_from_image(img)


## Creates a new empty ItemResource (configure it, then pass it to add_item).
func new_item(item_id: StringName) -> Resource:
	var item: Resource = load(_ITEM_RESOURCE_SCRIPT).new()
	item.item_id = item_id
	return item


## Registers (or replaces) an item. Optionally gives it an icon.
func add_item(item: Resource, icon: Texture2D = null) -> void:
	if icon:
		_item_icons[str(item.item_id)] = icon
	if _is_game_ready:
		_add_item_now(item)
	else:
		_pending_items.append(item)


func _add_item_now(item: Resource) -> void:
	get_game().item_manager._loaded_items[str(item.item_id)] = item
	log_info("Item registered: " + str(item.item_id))


## Custom icon of an item (used by the ItemManager extension).
func get_item_icon(item_id: String) -> Texture2D:
	return _item_icons.get(item_id)


func set_item_icon(item_id: String, icon: Texture2D) -> void:
	_item_icons[item_id] = icon


## Adds a recipe. inputs = {"item_id": amount, ...}
## list_path: RECIPES_CRAFTING (player crafting) or RECIPES_SMELTING (furnace).
func add_recipe(inputs: Dictionary, output_id: String, output_count: int = 1,
		list_path: String = RECIPES_CRAFTING) -> Resource:
	var list: Resource = load(list_path)
	if list == null:
		log_error("Recipe list not found: " + list_path)
		return null
	_held.append(list)
	var recipe: Resource = load(_CRAFTING_RECIPE_SCRIPT).new()
	for k: Variant in inputs:
		recipe.inputs[str(k)] = int(inputs[k])
	recipe.output_id = output_id
	recipe.output_count = output_count
	list.list.append(recipe)
	log_info("Recipe added: %s -> %dx %s" % [inputs, output_count, output_id])
	return recipe


## Removes every recipe that outputs output_id from a list.
func remove_recipes_for(output_id: String, list_path: String = RECIPES_CRAFTING) -> int:
	var list: Resource = load(list_path)
	_held.append(list)
	var before: int = list.list.size()
	list.list = list.list.filter(func(r: Resource) -> bool: return r.output_id != output_id)
	return before - list.list.size()


## Adds a command to the game's F1 console.
func add_console_command(name: String, callable: Callable, arguments: Variant = [],
		required: int = 0, description: String = "") -> void:
	var console := get_node_or_null(^"/root/Console")
	if console:
		console.add_command(name, callable, arguments, required, description)


# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------

func log_info(msg: String) -> void:
	_write("INFO", msg)


func log_warn(msg: String) -> void:
	_write("WARN", msg)
	push_warning("[ModLoader] " + msg)


func log_error(msg: String) -> void:
	_write("ERROR", msg)
	push_error("[ModLoader] " + msg)


func _write(level: String, msg: String) -> void:
	var line := "[ModLoader][%s] %s" % [level, msg]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


func _cmd_mods() -> void:
	var console := get_node_or_null(^"/root/Console")
	for m: Dictionary in get_mod_list():
		var line := "[%s] %s v%s — %s" % [m.status, m.name, m.version, m.description]
		if m.error:
			console.print_error(line + " (" + m.error + ")")
		else:
			console.print_line(line)


static func _to_str_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x: Variant in v:
			out.append(str(x))
	return out
