extends Node
## The game disables the F1 console in release builds. This mod re-enables it,
## but only when the world runs on your own PC (single player):
## on other people's servers it stays off.
##
## Note: in Type III, single player starts a local headless server
## (same executable, so it loads the mods too) and the client connects to it.
## In that case Game.mp.local_server_pid holds the local server's PID.

const MODE_CLIENT := 1  # Game.GameMode.MODE_CLIENT


func _mod_ready(_loader: Node) -> void:
	get_node(^"/root/Console").enable()


func _world_ready(_world: Node) -> void:
	var game: Node = ModLoader.get_game()
	var remote_server: bool = game.mode == MODE_CLIENT and game.mp.local_server_pid == -1
	var console := get_node(^"/root/Console")
	if remote_server:
		console.disable()
	else:
		console.enable()
