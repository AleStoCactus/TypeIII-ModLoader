extends Node
## Example mod: adds a new item with an icon and a recipe to craft it.
## Avoid writing game types (Game, ItemResource…) statically here:
## use the loader's functions, so other mods can still extend them.

var dir: String = get_script().resource_path.get_base_dir()


func _mod_init(loader: Node) -> void:
	# Script extensions would go here (before the game loads), e.g.:
	# loader.install_script_extension(dir.path_join("extensions/player_3d_ext.gd"))
	pass


func _mod_ready(loader: Node) -> void:
	var gem: Resource = loader.new_item(&"mod_gem")
	gem.item_name_override = &"Mod Gem"
	gem.description = "An item added by a mod!"
	gem.rarity = 2  # 0 common, 1 rare, 2 epic, 3 legendary, 4 mythic
	gem.max_stack_size = 50
	loader.add_item(gem, loader.load_texture(dir.path_join("icon.png")))

	loader.add_recipe({"pebble": 3}, "mod_gem", 1)


func _world_ready(world: Node) -> void:
	ModLoader.log_info("[example_gem] world loaded: %s" % world.name)
