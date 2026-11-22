extends "res://Scenes/Autoload/item_manager.gd"
## Internal mod loader extension: lets mod items have their own icon
## instead of a slot in the game's spritesheet.


func item_id_texture(id: String) -> AtlasTexture:
	var icon: Texture2D = ModLoader.get_item_icon(id)
	if icon == null:
		return super(id)
	var tex := AtlasTexture.new()
	tex.atlas = icon
	tex.region = Rect2(Vector2.ZERO, icon.get_size())
	return tex
