extends SceneTree
## Render the same synthetic poses as headless tests, without an OpenXR runtime.


func _initialize() -> void:
	var quiet := GDScript.new()
	quiet.source_code = "extends \"res://core/game.gd\"\nfunc _ready() -> void:\n\tpass\n"
	quiet.reload()
	root.get_node(^"Game").set_script(quiet)
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tools/playtest/session.tscn").instantiate())
