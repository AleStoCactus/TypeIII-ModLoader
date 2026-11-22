extends "res://UI/HUD/tooltip.gd"
## Translation mod: shows the translated item name in the item tooltip.
## The name is translated only on screen, it is never saved into the worlds.


func set_item(item_id: StringName) -> void:
	super(item_id)
	if item_id == &"" or pinned:
		return
	var item: Resource = Game.item_manager.item_id_to_resource(item_id)
	if item == null:
		return
	var name_en: String = item.item_name
	var name_it: String = TranslationServer.translate(name_en, &"item name")
	if name_it != name_en and item_name_label.text.ends_with(name_en):
		item_name_label.text = item_name_label.text.left(-name_en.length()) + name_it
