# Type III — Mod Loader

Mod loader for Type III 0.0.7 (Godot 4.6). It does not modify the game's executable.

## Installation

Pick one:

- **Windows**: put `install-modloader.bat` in the game folder (next to the game's
  `.exe`) and double-click it.
- **Linux**: put `install-modloader.sh` in the game folder and run it
  (double-click → "Run", or `./install-modloader.sh` in a terminal).
- **Manual**: extract `TypeIII-ModLoader-<version>.zip` directly into the game
  folder, so `override.cfg` ends up next to the game executable.

The installers are single files that contain everything and work from any folder.
They:
- never delete your mods or your mod settings;
- keep example mods you already have;
- keep any existing `override.cfg` (they add to it and save a `.bak` copy).

Running them again updates the mod loader.

**Uninstall**: run `install-modloader.bat uninstall` (Windows, from a terminal)
or `./install-modloader.sh --uninstall` (Linux). This removes `override.cfg`,
`modloader/`, this README and `modding/extract_scripts.py`. Your `mods/` folder
is kept. Add `-y` to skip the confirmation questions.

## How it works

Godot reads `override.cfg` next to the executable. Its `[autoload_prepend]` section
loads `modloader/mod_loader.gd` **before** the game's autoloads (`Game`, `Console`,
`GlobalHealth`). The loader scans the `mods/` folder, mounts zips on top of `res://`,
and runs the mods' scripts at the right moments.

```
TypeIII_linux_0.0.7        ← the game (unmodified)
override.cfg               ← hooks in the mod loader (delete it = vanilla game)
modloader/
  mod_loader.gd            ← the loader (autoload "ModLoader")
  extensions/              ← internal extensions (custom item icons)
  ui/mods_tab.gd           ← the "Mod" tab in Settings
  credits.txt              ← credits shown at the bottom of the Mod tab ({version} = loader version)
  mod_config.json          ← which mods are disabled (written by the Mod tab)
  modloader.log            ← log of the last launch
mods/                      ← PUT MODS HERE
  example_gem/             ← example mod (item + icon + recipe)
  dev_console/             ← re-enables the F1 console in single player
  example_translation/     ← template to translate the game (off until a language is set)
modding/
  extract_scripts.py       ← extracts the game's scripts as a reference
  game_scripts/            ← decompiled game scripts (read-only)
```

## Installing / enabling / disabling mods

- **Folder mod**: copy the folder into `mods/` (it must contain `manifest.json`).
- **Zip mod**: copy the `.zip` into `mods/`.
- **Enable / disable**: in the game go to **Settings → Mod** and switch each mod
  **On** / **Off**. The choice is saved right away (in `modloader/mod_config.json`)
  and applied on the next launch: press **Restart now** (main menu only).
  - Hover a mod to see its description, author, requirements and status.
  - A grey name means the mod is off; a red name means it is on but failed to load
    (for example a required mod is missing or disabled).
  - **Open mods folder** opens the `mods/` folder in the file manager.
  - The tab is also in the pause menu's settings, but there you have to go back
    to the main menu to restart.
- A disabled zip is not even mounted, so its files do not touch the game.
- **Back to the vanilla game**: delete or rename `override.cfg`.
- In game: press **F1** (with the console mod enabled) and type `mods` to list the mods and their status.

`modloader/mod_config.json` can also be edited by hand:
```json
{
	"disabled": ["example_gem"]
}
```

## Making a mod

```
mods/my_mod/
  manifest.json
  mod_main.gd      (optional: a mod can be made of files/data only)
  ...assets (png, .gd, .tres)
```

`manifest.json`:
```json
{
  "id": "my_mod",
  "name": "My mod",
  "version": "1.0.0",
  "author": "Me",
  "description": "What it does",
  "game_version": "0.0.7",
  "dependencies": ["other_mod"],
  "load_after": ["optional_mod"]
}
```
- `id`: letters, numbers and `_` only. Must be unique.
- `dependencies`: if one is missing or disabled, the mod is not loaded.
- `load_after`: load order only, not required.

`mod_main.gd`: every function is optional.
```gdscript
extends Node

func _mod_init(loader: Node) -> void:
	# BEFORE the game loads: script extensions, resource replacement
	pass

func _mod_ready(loader: Node) -> void:
	# Game ready (main menu): items, recipes, console commands
	pass

func _world_ready(world: Node) -> void:
	# A world has been loaded
	pass
```

> Important rule: in mod scripts **do not use game types statically** at file
> level (`var x: ItemResource`, `Game.something`). Godot would load those scripts
> immediately, before other mods can extend them. Use `loader.get_game()` and
> untyped variables (`var x: Resource`).

## ModLoader API

Available through `loader` or the global name `ModLoader`.

| Function | What it does |
|---|---|
| `get_game()` | the game's `Game` autoload (item_manager, world, signals, mp, …) |
| `new_item(id)` | creates a new item (ItemResource) to configure |
| `add_item(item, icon)` | registers/replaces an item, with an optional icon |
| `set_item_icon(id, texture)` | changes an item's icon (vanilla items too) |
| `load_texture(path)` | loads a mod .png as a texture |
| `add_recipe({"id": amount}, output, amount, list)` | adds a recipe (`RECIPES_CRAFTING` or `RECIPES_SMELTING`) |
| `remove_recipes_for(output, list)` | removes the recipes for an item |
| `add_console_command(name, callable, args, required, descr)` | new command in the F1 console |
| `install_script_extension(path)` | replaces a game script with one that extends it (in `_mod_init`) |
| `extend_node_script(node, path)` | extends the script of a node that already exists (in `_mod_ready`) |
| `replace_resource(game_path, resource)` | replaces a game resource (in `_mod_init`) |
| `is_mod_loaded(id)` | checks whether another mod is active |
| `log_info / log_warn / log_error` | writes to the log `modloader/modloader.log` |
| signals `mods_initialized`, `game_ready`, `world_loaded(world)` | |

### Extending a game script

`mods/my_mod/player_ext.gd`:
```gdscript
extends "res://Scenes/Entity/player_3d.gd"

func give_item(item_id: String, count: int = 1) -> ItemResource:
	print("The player receives ", count, "x ", item_id)
	return super(item_id, count)   # keeps the original behavior
```
In `_mod_init`: `loader.install_script_extension("res://mods/my_mod/player_ext.gd")`

Function and variable names can be found in `modding/game_scripts/`.
If the original script has a `class_name`, Godot prints a harmless error:
`Compiler bug: unresolved assign` (it falls back to a plain assignment).

## Zip mods: adding or replacing game files

A zip is mounted **on top of** `res://`. Files with the same path as the game's
files replace them. Layout:

```
my_mod.zip
  mods/my_mod/manifest.json      ← required
  mods/my_mod/mod_main.gd        ← optional
  Items/mod_sword.tres           ← new item, the game finds it on its own
  Scenes/Autoload/ServerModules/my_module.gd   ← new server module
```

Example of a data-only item (`Items/mod_sword.tres`):
```
[gd_resource type="Resource" script_class="ItemResource" format=3]

[ext_resource type="Script" path="res://Items/item_resource.gd" id="1_s"]

[resource]
script = ExtResource("1_s")
item_id = &"mod_sword"
item_name_override = &"Mod Sword"
description = "Added with a single file"
rarity = 3
```

The list of every `res://` path in the game is in `modding/game_scripts/_res_file_list.txt`.

## Translating the game

`mods/example_translation/` contains every text of the game with an empty
translation (`translation.po`). Copy the folder, set `id`, `name` and `language`
in its `manifest.json`, and translate the `.po` file (Poedit works well).
Full instructions: `mods/example_translation/README.md`.

## What is easy and what is not

**Easy:**
- new items
- crafting and smelting recipes
- icons
- console commands
- changing the behavior of player, world, UI and inventories with script extensions
- server modules (`ServerModules/` folder, loaded automatically)
- values in `.tres` resources

**Harder:**
- **New blocks in the voxel world.** `WorldObjectDB` builds the voxel engine's
  library from a texture atlas. It can be done by extending `wobj_db.gd`, but it
  takes more work.
- **Replacing original textures or models.** In the game they are imported
  (`.ctex`, `.scn`). A replacement file has to be prepared with the **Godot 4.6**
  editor (same version as the game). For item icons, `set_item_icon` is enough.

## Multiplayer

In single player the game starts a **local headless server** with the same
executable, so mods are active in both the server and the client.
In multiplayer, **the server and all players need the same mods** if those mods
add content (items, recipes), otherwise unknown items cause errors.

## Game updates

When you update Type III, keep `override.cfg`, `modloader/` and `mods/`.
Then run `python3 modding/extract_scripts.py` again to see what changed.
Mods that extend scripts might need to be updated.
