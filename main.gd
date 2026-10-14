extends Node3D
## Boot scene: creates the persistent player once, then swaps levels under $Level.

@export_file("*.tscn") var first_level := "res://levels/home/home.tscn"


func _ready() -> void:
	add_child(load(Game.PLAYER_SCENE).instantiate())
	Game.level_root = $Level
	Game.change_level(first_level)
