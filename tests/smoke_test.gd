extends Node
## Headless smoke test of the first-playable loop. Run:
##   godot --headless --path . res://tests/smoke_test.tscn -- --slot=smoke_test
## Uses its own save slot, so it never touches real progress. Exit code 0 = all passed.

var _failures := 0


func _ready() -> void:
	Save.use_slot("smoke_test")
	Save.wipe()
	add_child(load("res://main.tscn").instantiate())
	await _settle()
	_check(Game.level.level_id == &"home", "boots into home")
	_check(Quests.is_active(&"tutorial"), "tutorial starts on entering home")

	Events.report(&"grabbed", &"ball")
	Events.report(&"pressed", &"hello")
	await _go("res://levels/training/training.tscn")
	_check(Quests.is_done(&"tutorial"), "tutorial done after reaching training")
	_check(Inventory.count(&"coin") == 2, "tutorial reward: 2 coins")
	_check(Quests.is_active(&"training"), "training quest starts")

	for _i in 3:
		Events.trial_ended.emit(&"motion", true, {})
		Events.report(&"caught", &"butterfly")
	_check(Quests.is_done(&"training"), "training done after 3 catches")
	_check(Training.level(&"motion") > Training.START_LEVEL, "difficulty went up after successes")

	await _go("res://levels/backyard/backyard.tscn")
	_check(Quests.is_active(&"find_blue"), "find_blue starts in backyard")
	Vision.apply(load("res://content/vision/clear_sight.tres"))
	_check(get_viewport().find_world_3d().environment.fog_density == 0.0, "clear sight removes fog")
	Vision.apply(null)
	Events.report(&"caught", &"butterfly_blue")
	_check(Inventory.count(&"magic_stone") == 1, "find_blue reward: magic stone")
	_check(Quests.is_active(&"decorate"), "decorate chained after find_blue")

	await _go("res://levels/home/home.tscn")
	var layout := Game.level.get_node(^"HomeLayout") as HomeLayout
	var board := Game.level.get_node(^"DecorBoard") as DecorBoard
	board._on_button_touched(null, &"chair")
	_check(Inventory.count(&"magic_stone") == 0, "chair costs the magic stone")
	var chair := layout.get_child(0) as Grabbable
	_check(chair != null, "chair spawned into the layout")
	var hand := Node3D.new()
	chair.grab(hand)
	chair.release(hand, Vector3.ZERO)
	hand.free()
	_check(Quests.is_done(&"decorate"), "placing furniture finishes decorate")

	Save.write()
	Save.use_slot("smoke_test") # re-read from disk
	_check(Inventory.count(&"coin") == 10, "coins survive a save/load round trip")
	_check(Quests.is_done(&"find_blue"), "quest progress survives a save/load round trip")
	_check(layout.get_child_count() == 1, "furniture layout survives a save/load round trip")

	Save.wipe()
	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(_failures)


func _go(path: String) -> void:
	Game.change_level(path)
	await _settle()


func _settle() -> void:
	await get_tree().create_timer(Game.FADE_TIME + 0.3).timeout


func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1
