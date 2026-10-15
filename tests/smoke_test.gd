extends Node
## Headless smoke test. Run:
##   godot --headless --xr-mode off --path . res://tests/smoke_test.tscn -- --profile=smoke_test
## Uses its own profile, so it never touches a real player. Exit code 0 = all passed.
##
## Flat on purpose: one file, one pass, a few seconds. Sections in order: the
## game as it boots, on the real island (the first-time chain driven through,
## free play, a save with furniture in the house), hands and placement there,
## then a new game on a small island fixture that checks the chain in detail
## (measured rounds, the guide round a wall), the menu's picks and a save round
## trip, Start over and switching players, every module's own check from the
## Test Room (on its own profile), the menu, the sound table, and the island's map.

## Sections that ran all the way to their last line. A GDScript error aborts the
## function it happens in without raising, so without this a crashed section
## would simply print fewer lines and still say PASSED.
const SECTIONS := 10
## Where the test fingertip waits between pokes: out of reach of everything.
const MENU_AWAY := Vector3(0.0, -50.0, 0.0)

var _failures := 0
var _finished := 0


func _ready() -> void:
	if Profile.id != PROFILE:
		push_error("Run the smoke test with -- --profile=%s: it wipes the profile it runs on." % PROFILE)
		get_tree().quit(2)
		return
	_wipe(PROFILE)
	Events.profile_opened.emit(true)
	# Lines still queue and wait for each other in order, just without sitting
	# through them: set before the game boots, so the first lines are timed too.
	Narrator.read_pace = 0.0
	Narrator.min_seconds = 0.15
	add_child(load("res://main.tscn").instantiate())
	_listen()
	await _settle()
	await _island_playthrough()
	await _hands_and_placement()
	_new_game()
	await _open_world()
	await _replay()
	await _profiles()
	await _module_checks()
	await _menu()
	await _controls_and_debug()
	await _audio()
	await _island()
	_check(_finished == SECTIONS, "every section ran to its end (%d of %d)" % [_finished, SECTIONS])
	_wipe(PROFILE)
	_wipe(OTHER)
	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(_failures)


# ===== tasks & guide =====================================================

## The island in miniature: flat ground, the five places, both stations, the
## guide, a wall between the dock and the picnic table, and a pond.
const FIXTURE := "res://tests/fixtures/open_world.tscn"
const STONE := &"magic_stone"
const PROFILE := &"smoke_test"
## A second child on the same headset.
const OTHER := &"smoke_test_other"

var _goals: Array = [] # [text, place] for every goal_changed
var _judged: Array[StringName] = []
var _rounds: Array[Dictionary] = [] # every trial_ended, with "success" added
var _said: PackedStringArray = []


## The first-time chain, start to free play: welcome, the guide leading round a
## wall, five measured rounds at the picnic table across two sittings, five
## butterflies, and the first piece of furniture.
func _open_world() -> void:
	_check(Tasks.current() == &"", "a new game has no task before the island")
	await _go(FIXTURE)
	await _physics(4)
	var guide := Game.level.get_node(^"GuideCharacter") as GuideCharacter
	var picnic := Game.level.get_node(^"PicnicStation") as Station
	var meadow := Game.level.get_node(^"MeadowStation") as Station
	picnic.gap = 0.05 # no need to wait out the real pause between rounds
	meadow.gap = 0.05
	guide.walk_speed = 8.0

	# -- welcome: one task at a time, and the menu's view of it ---------------
	_check(Tasks.current() == &"welcome", "the welcome starts by itself on a new game")
	_check(Events.goal.place == &"dock" and _last_place() == &"dock",
		"goal_changed says what to do and that it happens at the dock")
	_check(Tasks.offers().is_empty(), "nothing is offered while a task is running")
	_check(not Tasks.accept(&"find_it") and not Tasks.start(&"find_it") and Tasks.current() == &"welcome",
		"only one task at a time")
	_check(not Tasks.abandon() and Tasks.current() == &"welcome", "the welcome cannot be abandoned")
	var about := Tasks.describe(&"find_it")
	_check(about.get("title") == "Find It" and about.get("visual_skills") == PackedStringArray(["Finding things in a mess"])
		and about.get("rewards") == {STONE: 2} and about.get("place") == &"picnic"
		and about.get("repeatable") == true and about.get("times_done") == 0 and about.get("can_abandon") == true,
		"describe gives title, visual skill names, rewards, place, repeatable, times done, can abandon")
	_check(Tasks.describe(&"welcome").get("can_abandon") == false, "describe says the welcome cannot be given up")
	_check(Tasks.describe(&"no_such_task").is_empty(), "describe of an unknown task is empty")
	for task in TaskDef.all():
		_check(task.rewards.keys().all(func(item: StringName) -> bool: return item == STONE),
			"%s pays Magic Stones only" % task.id)

	await _until(func() -> bool: return guide.is_offering() and guide.mode == GuideCharacter.Mode.THERE, 300)
	_check(guide.is_offering(), "the guide holds the glowing ball out")
	_check(_flat(guide.ball().global_position - _head()).length() < 1.4,
		"the ball is held out within reach of the child at the dock")
	var hand := Node3D.new()
	add_child(hand)
	guide.ball().grab(hand)
	_check(Events.goal.waiting_for == "opened:menu" and Events.goal.place == &"",
		"taking the ball moves the welcome on to the wrist menu")
	hand.free()
	Events.report(&"opened", &"menu") # what the wrist menu reports when its star is touched
	_check(Events.goal.place == &"picnic" and _last_place() == &"picnic", "then on to the picnic table")

	# -- the guide leads, round the wall, and waits for a child left behind --
	var crossed := false
	var waited := false
	for _frame in 900:
		await get_tree().physics_frame
		crossed = crossed or _in_wall(guide.global_position)
		if guide.mode == GuideCharacter.Mode.WAIT:
			if not waited:
				waited = true
				_check(_flat(guide.global_position - _head()).length() > 9.0,
					"the guide stops when the child falls 10 m behind")
				await _physics(20)
				_check(guide.mode == GuideCharacter.Mode.WAIT, "and keeps waiting, beckoning")
			_place_head(guide.global_position + Vector3(1.0, 0.0, 1.0)) # the child catches up
		if guide.mode == GuideCharacter.Mode.THERE:
			break
	_check(waited, "the guide waited for the child on the way")
	_check(guide.mode == GuideCharacter.Mode.THERE, "the guide got to the picnic table")
	_check(not crossed, "the guide walked round the wall, not through it")
	var by_table := _flat(guide.global_position - picnic.place.global_position).length()
	_check(by_table > 1.0 and by_table < 2.0, "it stops about 1.5 m from the place (%.2f m)" % by_table)
	var grid := GroundGrid.new(Game.level.get_world_3d())
	_check(not grid.can_stand(Vector3(8.0, 0.0, 4.0)) and grid.can_stand(Vector3(8.0, 0.0, 9.0)),
		"water in the 'water' group is not ground")
	var round_pond := grid.find_path(Vector3(8.0, 0.0, -0.5), Vector3(8.0, 0.0, 8.5))
	_check(not round_pond.is_empty() and not _path_crosses(round_pond, Rect2(6.0, 2.0, 4.0, 4.0)),
		"a path goes round the pond")
	var hopeless := grid.begin(Vector3(14.0, 0.0, 20.0), Vector3(20.0, 0.0, 20.0)) # inside a closed pen
	var calls := 0
	var worst := 0
	while not grid.advance(hopeless, guide.samples_per_frame) and calls < 1000:
		calls += 1
	var before_step := grid.samples
	grid.advance(grid.begin(Vector3(-20.0, 0.0, 20.0), Vector3(20.0, 0.0, 20.0)), guide.samples_per_frame)
	worst = grid.samples - before_step
	_check(hopeless.done and hopeless.path.is_empty() and calls > 5 and hopeless.closed.size() <= grid.max_nodes + 1,
		"a goal with no way to it gives up, spread over %d frames, not one" % calls)
	_check(worst <= guide.samples_per_frame + 16, "one frame of searching samples at most about its budget (%d)" % worst)

	# -- Find It: the station wakes, the child sits, the rounds run -----------
	_check(not picnic.is_wanted() and not picnic.beacon.visible, "a station is idle while no task wants it")
	_place_head(picnic.place.global_position)
	await _physics(3)
	_check(Tasks.is_done(&"welcome") and Inventory.count(STONE) == 1, "sitting down at the picnic ends the welcome: 1 stone")
	_check(Tasks.current() == &"find_it", "find_it follows the welcome the first time")
	_check(Narrator.current != null and Narrator.current.text == TaskDef.find(&"welcome").completed_text,
		"the reward line is being said; the next task's first instruction waits its turn")
	_check(picnic.is_wanted() and _last_place() == &"picnic", "find_it wants the picnic station")
	_check(not _walking(), "stick walking is off while sitting at a station")
	var trial := picnic.trial() as SearchTrial
	await _next_round(trial)
	_check(trial.is_running(), "rounds start with the child already sitting there")
	_check(picnic.sign_label.text.contains("Find It") and picnic.sign_label.text.contains("Trains: Finding things in a mess")
		and picnic.sign_label.text.contains("5 more to go"), "the sign shows the task, the visual skill and the rounds")

	# Round 1, a baseline probe: everything a researcher needs is in the line.
	_check(trial.condition.probe, "the run opens with an unscored baseline probe")
	_check(trial.condition.value(&"clutter") == 6.0 and trial.placed().size() == 6,
		"the pinned clutter axis sets how many objects are on the table")
	var ids := {}
	for node in trial.placed():
		ids[(node as Grabbable).id] = true
	_check(ids.size() == trial.placed().size(), "every object is distinct, so naming one is unambiguous")
	var graded: Contrast = null
	for child in trial.target().get_children():
		if child is Contrast:
			graded = child
	_check(graded != null and is_equal_approx(graded.background_luminance, Trial.luminance(trial.surface)),
		"objects are graded against the tablecloth they stand on")
	_check(graded != null and absf(graded.applied_luminance() - graded.intended_luminance()) < 0.01,
		"the object is graded to the Weber contrast the round logged")
	var before := Training.level(&"search")
	# Keep the feedback on screen while the gripping hand moves away.
	picnic.gap = 1.0
	var picked := trial.target() as Grabbable
	var rest := picked.global_position
	var picking_hand := Game.player.get_node(^"RightController/Hand") as Hand
	var controller := picking_hand.get_parent() as Node3D
	var hand_rest := controller.position
	var probe := await _pick(trial, picked)
	controller.position += Vector3(0.0, 0.15, 0.0)
	await get_tree().create_timer(0.75).timeout
	_check(picked.holder == null and picking_hand.held == null
		and picked.global_position.is_equal_approx(rest + Vector3.UP * trial.lift_height),
		"the correct pick lifts independently after the gripping hand moves")
	picking_hand.release()
	_check(picked.freeze, "letting go of grip later leaves the lifted feedback in place")
	controller.position = hand_rest
	picnic.gap = 0.05
	_check(probe.get("probe", false) and probe.get("trial") == &"search", "the probe round is logged as a probe")
	_check(probe.get("tries", -1) == 0 and probe.get("target") == probe.get("picked"), "a first-pick success logs no wrong tries")
	_check(probe.has("axis_overlap") and probe.has("axis_contrast") and probe.has("seconds") and probe.has("hint"),
		"the line carries every axis, the time and the help used")
	_check(Training.level(&"search") == before, "a probe never moves the difficulty it measures")
	_check(_judged.has(&"good"), "a right pick is judged good")

	# Round 2: a wrong pick, then the right one.
	await _next_round(trial)
	var wrong: Grabbable = null
	for node in trial.placed():
		if node != trial.target():
			wrong = node as Grabbable
			break
	var other := Node3D.new()
	wrong.grab(other)
	other.free()
	_check(trial.tries == 1 and trial.is_running(), "a wrong pick counts a try and the round goes on")
	_check(_judged.has(&"bad"), "a wrong pick is judged bad")
	var scored := await _pick(trial, trial.target())
	_check(scored.get("tries", -1) == 1, "the wrong try is logged with the round")

	# Round 3: ask for help, then stand up in the middle of it.
	await _next_round(trial)
	Events.report(&"asked", &"help")
	_check(trial.hint_level == 1, "asking for help raises the hint level")
	_place_head(picnic.place.global_position + Vector3(0.0, 0.0, 4.0))
	await _physics(3)
	_check(_walking() and picnic.beacon.visible, "standing up gives walking back and the beacon shows again")
	var clock := trial.seconds()
	await get_tree().create_timer(0.3).timeout
	_check(trial.is_held() and is_equal_approx(trial.seconds(), clock) and trial.hint_level == 1,
		"while nobody sits there the round's clock and hints wait")
	var hinted := await _pick(trial, trial.target())
	_check(hinted.get("hint", 0) == 1, "the hint level reached is logged with the round")
	_check(hinted.get("seconds", 99.0) < clock + 0.05, "the time away is not in the logged seconds")
	await get_tree().create_timer(0.4).timeout
	_check(not trial.is_running() and Events.goal.done == 3 and Events.goal.needed == 5,
		"standing up stops after the round in progress (3 of 5)")
	_check(Events.goal.text.contains("3/5") and picnic.sign_label.text.contains("2 more to go"),
		"the goal line and the station's sign count the same rounds")

	# Back to the bench: rounds 4 and 5, the first two that move the staircase.
	_place_head(picnic.place.global_position)
	await _next_round(trial)
	_check(trial.is_running() and not trial.condition.probe, "sitting down again carries on, probes done")
	var level_before := Training.level(&"search")
	await _pick(trial, trial.target())
	_check(Training.level(&"search") == level_before, "one success alone does not raise the difficulty")
	await _next_round(trial)
	await _pick(trial, trial.target())
	await _until(func() -> bool: return Tasks.current() != &"find_it", 120)
	_check(is_equal_approx(Training.level(&"search"), level_before + TrialDef.find(&"search").step),
		"two scored successes in a row raise the difficulty")
	_check(Tasks.times_done(&"find_it") == 1 and Inventory.count(STONE) == 3,
		"five rounds over two sittings finish Find It: 2 more stones")
	_check(not picnic.is_wanted() and not picnic.runner.is_running() and _walking(),
		"the station goes idle when its task is done")

	# -- Butterflies: nothing happens at the meadow until the child sits down --
	_check(Tasks.current() == &"butterflies" and _last_place() == &"meadow", "butterflies follow Find It the first time")
	var catcher := meadow.trial() as CatchTrial
	_check(meadow.is_wanted() and meadow.beacon.visible, "the meadow's beacon goes up")
	await _physics(10)
	_check(not meadow.runner.is_running() and not catcher.is_running(), "no rounds until the child's head is in the zone")
	_place_head(meadow.place.global_position)
	await _next_round(catcher)
	_check(catcher.current() != null, "a round puts one butterfly out")
	var wander: Wander = null
	if catcher.current():
		for child in catcher.current().get_children():
			if child is Wander:
				wander = child
	_check(wander != null and is_equal_approx(wander.speed, catcher.condition.value(&"speed")),
		"the speed axis is how fast it flies")
	var judged_before := _judged.size()
	var caught := await _catch(catcher)
	_check(caught.get("success") == true and caught.get("result") == "caught", "a caught butterfly is a success")
	_check(_judged.size() > judged_before and _judged[_judged.size() - 1] == &"good", "a catch is judged good")
	await _next_round(catcher)
	var fled := await _escape(catcher)
	_check(fled.get("success") == false and fled.get("result") == "escaped", "one that flies away is a fail")
	_check(_judged[_judged.size() - 1] == &"bad", "an escape is judged bad")
	await _next_round(catcher)
	_check(not catcher.condition.probe, "the meadow runs the catch trial's own two probes, not the search trial's three")
	await _catch(catcher)
	for _i in 2:
		await _next_round(catcher)
		await _catch(catcher)
	await _until(func() -> bool: return Tasks.current() != &"butterflies", 120)
	_check(Tasks.times_done(&"butterflies") == 1 and Inventory.count(STONE) == 5, "five butterflies: 2 more stones")

	# -- First furniture: buy, take out, put it in the house ------------------
	_check(Tasks.current() == &"first_furniture" and Events.goal.place == &"", "first_furniture follows")
	Events.report(&"bought", &"chair") # the shop
	Events.report(&"taken_out", &"chair") # the bag
	_check(Events.goal.place == &"home" and _last_place() == &"home", "the last step happens at home")
	await _physics(4)
	_check(guide.leading_to() == &"home", "the guide sets off for the house")
	Events.report(&"placed", &"chair")
	_check(Tasks.current() == &"" and Inventory.count(STONE) == 6, "furniture placed: the chain is done, 6 stones in all")
	_check(Events.goal.task == &"" and _goals[_goals.size() - 1] == ["", &""], "goal_changed goes empty when there is nothing to do")
	var last_line := TaskDef.find(&"first_furniture").completed_text
	await _until(func() -> bool: return _said.has(last_line), 120)
	_check(_said.has(last_line), "the last line tells the child about the wrist menu")
	await _physics(4)
	_check(guide.leading_to() == &"" and guide.mode == GuideCharacter.Mode.NEAR, "with no goal the guide stays near the child")

	var incomplete := 0
	for line in _rounds:
		var complete: bool = line.has("trial") and line.has("difficulty") and line.has("seconds") \
			and line.has("tries") and line.has("hint") and line.has("success") and line.has("visual_skill")
		complete = complete and line.keys().any(func(key: Variant) -> bool: return str(key).begins_with("axis_"))
		if not complete:
			incomplete += 1
			print("    incomplete round line: %s" % line)
	_check(_rounds.size() == 10 and incomplete == 0,
		"every round logs its visual skill, condition, result, time, tries and hint (%d lines)" % _rounds.size())
	_finished += 1


## Everything said, judged, logged and asked for, from boot on.
func _listen() -> void:
	Events.goal_changed.connect(func(goal: Goal) -> void: _goals.append([goal.text, goal.place]))
	Events.feedback.connect(func(kind: StringName, _at: Vector3) -> void: _judged.append(kind))
	Events.trial_ended.connect(_on_round_logged)
	Narrator.line_started.connect(func(line: VoiceLine) -> void: _said.append(line.text))


## Forget the island playthrough, so the fixture starts from a new game.
func _new_game() -> void:
	# A save this version cannot read (one from before profiles) is not half-loaded:
	# every saveable starts fresh.
	var old := FileAccess.open(Profile.path(Profile.SAVE_FILE), FileAccess.WRITE)
	old.store_string(JSON.stringify({Tasks = {current = "find_it", step = "two"}, Inventory = {items = {magic_stone = 9}}}))
	old.close()
	Save.reload()
	_check(Tasks.current() == &"" and Tasks.times_done(&"welcome") == 0 and Inventory.count(STONE) == 0,
		"a save from another version loads as a fresh start, not half of one")
	_goals.clear()
	_judged.clear()
	_rounds.clear()
	_said.clear()


## The game as it boots: the real island, every place reachable on foot, both
## stations standing clear, and the whole first-time chain driven through the
## way the fixture section drives it (which checks each step in detail). Then
## free play, and a save round trip with a chair standing in the house.
func _island_playthrough() -> void:
	var island := Game.level as Level
	_check(island != null and island.level_id == &"island", "the game boots onto the island")
	if island == null:
		return
	await _physics(4)
	var dock := Place.find(get_tree(), &"dock")
	_check(dock != null and _flat(_head() - dock.global_position).length() < 1.0, "the child starts at the dock")
	_check(Tasks.current() == &"welcome" and Events.goal.place == &"dock", "the welcome starts, at the dock")
	var guide := island.get_node(^"GuideCharacter") as GuideCharacter
	var picnic := island.get_node(^"PicnicStation") as Station
	var meadow := island.get_node(^"MeadowStation") as Station
	picnic.gap = 0.05
	meadow.gap = 0.05
	guide.walk_speed = 8.0
	await _until(func() -> bool: return guide.is_offering() and guide.mode == GuideCharacter.Mode.THERE, 300)
	_check(guide.is_offering() and _flat(guide.ball().global_position - _head()).length() < 1.4,
		"the guide is on the dock holding the ball out, within reach")

	# Every place once, and a way on foot (the guide's own grid) there and back.
	var grid := GroundGrid.new(island.get_world_3d())
	for id: StringName in [&"dock", &"home", &"picnic", &"meadow", &"lighthouse"]:
		var count := 0
		for node in get_tree().get_nodes_in_group(Place.GROUP):
			count += 1 if (node as Place).id == id else 0
		var place := Place.find(get_tree(), id)
		_check(count == 1 and place != null, "one place called '%s' (%d)" % [id, count])
		if place == null or id == &"dock":
			continue
		_check(_walkable(grid, dock.global_position, place.global_position),
			"a way on foot from the dock to '%s' and back" % id)

	# Stations stand on flat floor, and nothing of the island is in their way.
	var space := island.get_world_3d().direct_space_state
	for station: Station in [picnic, meadow]:
		var own := _rids(station)
		var flat := true
		for corner in [Vector3(0, 0, 0), Vector3(1.5, 0, 1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, -1.5)]:
			var at: Vector3 = station.global_transform * corner
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN, 0xFFFFFFFF, own)
			var hit := space.intersect_ray(ray)
			flat = flat and not hit.is_empty() and hit.normal.y > 0.98 and absf(hit.position.y - station.global_position.y) < 0.1
		_check(flat, "%s stands on flat floor" % station.name)
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 1.8, 3.0)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.exclude = own
		query.transform = Transform3D(station.global_basis, station.global_position + Vector3.UP * 1.0)
		_check(space.intersect_shape(query).is_empty(), "nothing of the island stands in %s's way" % station.name)

	# The chain, start to free play.
	var hand := Node3D.new()
	add_child(hand)
	guide.ball().grab(hand)
	hand.free()
	Events.report(&"opened", &"menu")
	_check(Events.goal.place == &"picnic", "the ball, the wrist menu, then off to the picnic table")
	_place_head(picnic.place.global_position)
	await _physics(3)
	_check(Tasks.current() == &"find_it" and Inventory.count(STONE) == 1, "sitting down at the picnic: 1 stone, Find It")
	var trial := picnic.trial() as SearchTrial
	for _i in 5:
		await _next_round(trial)
		await _pick(trial, trial.target())
	await _until(func() -> bool: return Tasks.current() != &"find_it", 120)
	_check(Tasks.current() == &"butterflies" and Inventory.count(STONE) == 3, "five rounds of Find It: 3 stones, butterflies")
	_place_head(meadow.place.global_position)
	var catcher := meadow.trial() as CatchTrial
	for _i in 5:
		await _next_round(catcher)
		await _catch(catcher)
	await _until(func() -> bool: return Tasks.current() != &"butterflies", 120)
	_check(Tasks.current() == &"first_furniture" and Inventory.count(STONE) == 5, "five butterflies: 5 stones, first furniture")

	# Buy a chair, take it out of the bag in the house, let go: it stands on the floor.
	Events.report(&"bought", &"chair") # what the shop reports
	Inventory.add(&"chair", 1)
	var home := Place.find(get_tree(), &"home")
	_place_head(home.global_position)
	var right := Game.player.get_node(^"RightController/Hand") as Hand
	var rest: Vector3 = right.get_parent().position
	right.get_parent().position = Vector3(0.3, 0.8, -0.4)
	await _physics(2)
	var layout := island.get_node(^"DecorLayout") as DecorLayout
	Events.place_requested.emit(&"chair")
	var chair := layout.items()[layout.items().size() - 1] if not layout.items().is_empty() else null
	right.release()
	right.get_parent().position = rest
	await _physics(3)
	_check(Tasks.current() == &"" and Inventory.count(STONE) == 6, "the chair placed: the chain is done, 6 stones in all")
	_check(chair != null and absf(chair.global_position.y - home.global_position.y - 0.05) < 0.03,
		"the chair stands on the house's floorboards")
	var offers := Tasks.offers()
	_check(offers.size() == 2 and offers.has(&"find_it") and offers.has(&"butterflies"),
		"free play: the two repeatable tasks are offered (%s)" % ", ".join(PackedStringArray(offers)))

	# Save and load: tasks, stones and the chair, where it stood.
	var stood: Transform3D = chair.global_transform if chair else Transform3D()
	Save.write()
	Save.reload()
	await _physics(3)
	_check(Tasks.current() == &"" and Tasks.times_done(&"welcome") == 1 and Tasks.times_done(&"find_it") == 1
		and Tasks.times_done(&"butterflies") == 1 and Tasks.times_done(&"first_furniture") == 1,
		"finished tasks survive a save/load round trip")
	_check(Inventory.count(STONE) == 6, "stones survive it")
	var back_again := layout.items()
	_check(back_again.size() == 1 and back_again[0].global_transform.origin.is_equal_approx(stood.origin),
		"the chair is still in the house after it")
	_finished += 1


## Whether someone on foot gets from [param from] to [param place], or to a spot
## within about 1.5 m of it as the guide does (a station's seat is between its
## bench and table), and back again.
func _walkable(grid: GroundGrid, from: Vector3, place: Vector3) -> bool:
	var spots: Array[Vector3] = [place]
	for i in 8:
		spots.append(place + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * 1.5)
	for spot in spots:
		if not grid.can_stand(spot):
			continue
		var there := grid.find_path(from, spot)
		var back := grid.find_path(spot, from)
		if not there.is_empty() and _flat(there[there.size() - 1] - spot).length() < 0.6 				and not back.is_empty() and _flat(back[back.size() - 1] - from).length() < 0.6:
			return true
	return false


func _rids(root: Node) -> Array[RID]:
	var found: Array[RID] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		found.append((node as CollisionObject3D).get_rid())
	if root is CollisionObject3D:
		found.append((root as CollisionObject3D).get_rid())
	return found


## After the chain: the menu picks, drops and repeats tasks, and progress
## survives a save.
func _replay() -> void:
	var picnic := Game.level.get_node(^"PicnicStation") as Station
	var meadow := Game.level.get_node(^"MeadowStation") as Station
	var offers := Tasks.offers()
	_check(offers.has(&"find_it") and offers.has(&"butterflies") and offers.size() == 2,
		"the repeatable training tasks are offered, nothing else (%s)" % ", ".join(PackedStringArray(offers)))

	_place_head(Vector3(0.0, 0.0, 8.0))
	await _physics(3)
	var accepted: Array[StringName] = []
	var listen := func(what: StringName, id: StringName, _data: Dictionary) -> void:
		if what == &"accepted":
			accepted.append(id)
	Events.reported.connect(listen)
	_check(Tasks.accept(&"butterflies") and Tasks.current() == &"butterflies" and accepted == [&"butterflies"],
		"accepting a task starts it and reports accepted:<id>")
	_check(meadow.is_wanted(), "an accepted task wakes its station")
	_place_head(meadow.place.global_position)
	var catcher := meadow.trial() as CatchTrial
	await _next_round(catcher)
	var butterfly := catcher.current()
	var lines := _rounds.size()
	var finished: Array[StringName] = []
	var on_finished := func(what: StringName, id: StringName, _data: Dictionary) -> void:
		if what == &"finished":
			finished.append(id)
	Events.reported.connect(on_finished)
	_check(Tasks.abandon() and Tasks.current() == &"" and not meadow.is_wanted(),
		"abandoning drops it and the station stands down")
	await get_tree().create_timer(0.3).timeout
	Events.reported.disconnect(on_finished)
	_check(not catcher.is_running() and not is_instance_valid(butterfly) and _rounds.size() == lines
		and finished.is_empty(),
		"the round in progress is dropped: not logged, not counted, nothing reported finished")
	_place_head(Vector3(0.0, 0.0, 8.0))
	await _physics(3)
	_check(_goals[_goals.size() - 1] == ["", &""], "abandoning empties the goal")
	_check(not Tasks.accept(&"welcome") and not Tasks.accept(&"first_furniture"),
		"a task that is not offered cannot be accepted")

	_check(Tasks.accept(&"find_it"), "a repeatable task can be accepted again")
	_place_head(picnic.place.global_position)
	var trial := picnic.trial() as SearchTrial
	Training.pin(&"clutter", 3.0)
	await _next_round(trial)
	_check(trial.placed().size() == 3, "a debug pin overrides the axis next round")
	Training.unpin_all()
	await _pick(trial, trial.target())
	await _physics(2)
	_check(Events.goal.done == 1 and Events.goal.needed == 5, "one round of the repeat done")

	Save.write()
	Tasks.load_state({}) # forget it all in memory...
	_place_head(Vector3(0.0, 0.0, 8.0))
	await _physics(3)
	_check(Tasks.current() == &"" and not picnic.is_wanted(), "(progress forgotten in memory)")
	Save.reload() # ...and get it back off disk
	await _physics(2)
	_check(Tasks.current() == &"find_it" and Events.goal.done == 1 and Events.goal.needed == 5,
		"the active task and its rounds survive a save/load round trip")
	_check(Tasks.times_done(&"find_it") == 1 and Tasks.times_done(&"welcome") == 1, "times done survive it too")
	_check(_last_place() == &"picnic" and picnic.is_wanted(), "after loading, the goal and the station's request come back")
	_check(Inventory.count(STONE) == 6, "stones survive it")

	_place_head(picnic.place.global_position)
	await _next_round(trial)
	_check(trial.condition.round_index == 1 and trial.condition.probe,
		"after loading, the run carries on at round 2, still one of the three baseline probes")
	await _pick(trial, trial.target())
	for _i in 3:
		await _next_round(trial)
		await _pick(trial, trial.target())
	_check(Tasks.current() == &"" and Tasks.times_done(&"find_it") == 2 and not picnic.is_wanted(),
		"the fifth round ends the step there and then: one count, nothing to report late")
	_check(Inventory.count(STONE) == 8, "the repeat pays again")
	_check(Tasks.offers().has(&"find_it"), "next does not chain a second time, and the task stays on offer")

	# A step that sends the child to where they already are.
	var real := Tasks.save_state()
	_place_head(picnic.place.global_position)
	await _physics(3)
	var forged := real.duplicate(true)
	forged.current = "welcome"
	forged.step = 2 # "Follow me to the picnic table!" waits for entered:picnic
	Tasks.load_state(forged)
	await _physics(3)
	_check(Tasks.times_done(&"welcome") == 2 and Tasks.current() == &"",
		"a step waiting for entered:<station> ends if the child is already sitting there")
	Tasks.load_state(real)

	var visual_skill := VisualSkillDef.find(&"search")
	var line := "%s! %s" % [visual_skill.display_name, visual_skill.description]
	await _until(func() -> bool: return _said.has(line), 600)
	_check(_said.count(line) == 2, "the station says what it trains once each time the task is run (%d)" % _said.count(line))
	var welcome_done := _said.find(TaskDef.find(&"welcome").completed_text)
	_check(welcome_done >= 0 and _said.find(TaskDef.find(&"find_it").steps[0].instruction) == welcome_done + 1
		and _said.find(line) == welcome_done + 2 and _said[welcome_done + 3].begins_with("Find the"),
		"after the reward: the next instruction, what the station trains, then the first round")
	Events.reported.disconnect(listen)
	_place_head(Vector3(0.0, 0.0, 8.0))
	_layers()
	_finished += 1


## Several children on one headset, and Start over. Each player's progress,
## settings and research log are their own; opening a profile replaces
## everything, so nothing of the last player or the last game is left behind.
func _profiles() -> void:
	_check(Tasks.times_done(&"find_it") == 2 and Inventory.count(STONE) > 0, "(a player with progress)")
	Settings.set_value(&"volume_master", 0.5)
	Training.pin(&"clutter", 3.0)
	var level_before := Training.level(&"search")
	_check(level_before != Training.START_LEVEL, "(and a staircase that has moved)")
	Narrator.say("A line from the old game.")
	Narrator.say("Another line from the old game.")
	var logs_before := _logs(PROFILE)

	# Start over: everything back to new, the research log kept.
	Profile.start_over()
	await _settle()
	await _settle()
	_check(Game.level.level_id == &"island" and Tasks.current() == &"welcome" and Tasks.times_done(&"find_it") == 0,
		"Start over begins this player's game again on the island")
	_check(Inventory.count(STONE) == 0, "with no stones")
	_check(Training.level(&"search") == Training.START_LEVEL and not Training.is_pinned(&"clutter"),
		"the staircase is back at its start and no debug pin is left")
	_check(is_equal_approx(Settings.value(&"volume_master"), 1.0), "the settings are back to their defaults")
	_check(not _said.slice(_said.find("A line from the old game.") + 1).has("Another line from the old game."),
		"a line still waiting from the old game is never said in the new one")
	_check(Events.goal.task == &"welcome" and Events.goal.place == &"dock", "the goal is the welcome's, at the dock")
	Narrator.say("New line.")
	_check(_logs(PROFILE).size() >= logs_before.size() and Array(logs_before).all(func(f: String) -> bool: return _logs(PROFILE).has(f)),
		"the research log is kept: Start over never deletes one")
	var newest := FileAccess.get_file_as_string(Profile.path("metrics/") + _logs(PROFILE)[-1])
	_check(newest.contains("\"type\":\"session\"") and newest.contains("\"wiped\":true"),
		"and the new session's log says this player started over")

	# A second child: their own game; switching back gives the first one back.
	Inventory.add(STONE, 3)
	Settings.set_value(&"turn_degrees", 45.0)
	Profile.switch(OTHER)
	await _settle()
	await _settle()
	_check(Profile.id == OTHER and Inventory.count(STONE) == 0 and Tasks.current() == &"welcome",
		"another player starts a game of their own")
	_check(Settings.value(&"turn_degrees") == 30.0, "with their own settings")
	Inventory.add(STONE, 5)
	Profile.switch(PROFILE)
	await _settle()
	await _settle()
	_check(Inventory.count(STONE) == 3 and Settings.value(&"turn_degrees") == 45.0,
		"switching back gives the first player their stones and settings")
	Profile.switch(OTHER)
	await _settle()
	await _settle()
	_check(Inventory.count(STONE) == 5, "and the second player theirs")
	Profile.switch(PROFILE)
	await _settle()
	await _settle()
	Settings.reset()
	_finished += 1


## This profile's research logs, oldest first.
func _logs(profile: StringName) -> PackedStringArray:
	var files := DirAccess.get_files_at("user://profiles/%s/metrics/" % profile)
	files.sort()
	return files


## Deletes [param profile]'s progress and settings; its logs stay.
func _wipe(profile: StringName) -> void:
	for file in [Profile.SAVE_FILE, Profile.SETTINGS_FILE]:
		DirAccess.remove_absolute("user://profiles/%s/%s" % [profile, file])


## tasks → trials ← stations, checked rather than hoped for: no code in a layer
## names a layer it must not depend on. Comments may.
func _layers() -> void:
	var rules := {
		"res://modules/trials/": "\\b(Tasks|TaskDef|TaskStep|Station)\\b",
		"res://modules/stations/": "\\b(Tasks|TaskDef|TaskStep)\\b",
		"res://modules/tasks/": "\\b(Station|TrialRunner|Trial|SearchTrial|CatchTrial|Training)\\b",
	}
	var comment := RegEx.create_from_string("(^\\s*#.*$)|(\\s#[# ].*$)")
	for root: String in rules:
		var forbidden := RegEx.create_from_string(rules[root])
		var found := PackedStringArray()
		for path in _scripts(root):
			var number := 0
			for line in FileAccess.get_file_as_string(path).split("\n"):
				number += 1
				var code := comment.sub(line, "")
				var hit := forbidden.search(code)
				if hit:
					found.append("%s:%d %s" % [path.get_file(), number, hit.get_string()])
		_check(found.is_empty(), "%s names no layer it must not depend on%s"
			% [root, "" if found.is_empty() else ": " + ", ".join(found)])


func _on_round_logged(_visual_skill: StringName, success: bool, data: Dictionary) -> void:
	var line := data.duplicate()
	line.success = success
	_rounds.append(line)


func _catch(trial: CatchTrial) -> Dictionary:
	var before := _rounds.size()
	var butterfly := trial.current() as Catchable
	if butterfly == null:
		return {}
	butterfly.touch(null)
	await get_tree().process_frame
	return _rounds[before] if _rounds.size() > before else {}


func _escape(trial: CatchTrial) -> Dictionary:
	var before := _rounds.size()
	var butterfly := trial.current() as Catchable
	if butterfly == null:
		return {}
	butterfly.escape()
	await get_tree().process_frame
	return _rounds[before] if _rounds.size() > before else {}


func _last_place() -> StringName:
	return _goals[_goals.size() - 1][1] if not _goals.is_empty() else &"none"


func _head() -> Vector3:
	return (Game.player.get_node(^"Camera") as Node3D).global_position


func _place_head(at: Vector3) -> void:
	Game.place_player(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.z)))


func _walking() -> bool:
	return Game.player.get_node(^"Locomotion").enabled


func _in_wall(at: Vector3) -> bool:
	var wall := Game.level.get_node(^"Wall") as Node3D
	var local := at - wall.global_position
	return absf(local.x) < 5.0 and absf(local.z) < 0.3


func _path_crosses(path: PackedVector3Array, area: Rect2) -> bool:
	for i in range(1, path.size()):
		for t in 20:
			var at := path[i - 1].lerp(path[i], t / 19.0)
			if area.has_point(Vector2(at.x, at.z)):
				return true
	return false


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _physics(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _until(done: Callable, frames: int) -> void:
	for _frame in frames:
		if done.call():
			return
		await get_tree().physics_frame

# ===== end tasks & guide =================================================


## How the child touches the world and feels every judgement, and how furniture
## goes from the bag to the floor and back. Runs on the island, which has the
## world's DecorLayout; the hover props float high above it, clear of everything.
func _hands_and_placement() -> void:
	var player := Game.player as Player
	var level := Game.level as Node3D

	# Hover: what a hand could use right now lights up, and nothing else.
	var spot := Vector3(0.0, 10.0, 0.0)
	var ball := (load("res://content/trials/objects/ball.tscn") as PackedScene).instantiate() as Grabbable
	level.add_child(ball)
	ball.global_position = spot
	var button := (load("res://components/touch_button.tscn") as PackedScene).instantiate() as TouchButton
	button.id = &"hover_probe"
	level.add_child(button)
	button.global_position = spot + Vector3(1.0, 0.0, 0.0)
	var controller := XRController3D.new()
	var hand := Hand.new()
	var hand_shape := CollisionShape3D.new()
	hand_shape.shape = SphereShape3D.new()
	(hand_shape.shape as SphereShape3D).radius = 0.07
	hand.add_child(hand_shape)
	controller.add_child(hand)
	level.add_child(controller)
	controller.global_position = spot + Vector3(0.0, 2.0, 0.0)
	await _physics_frames()
	_check(not Hover.is_hovered(ball) and not Hover.is_hovered(button), "nothing is lit with no hand near")
	controller.global_position = ball.global_position + Vector3(0.0, 0.055, 0.0)
	await _physics_frames()
	_check(Hover.is_hovered(ball), "a grabbable lights up when a hand can grab it")
	controller.global_position = button.global_position + Vector3(0.0, 0.0, 0.2) # in reach, not touching
	await _physics_frames()
	_check(not Hover.is_hovered(ball), "the grabbable goes dark when the hand leaves")
	_check(Hover.is_hovered(button), "a touchable lights up just before it is touched")
	controller.global_position = spot + Vector3(0.0, 2.0, 0.0)
	await _physics_frames()
	_check(not Hover.is_hovered(button), "the touchable goes dark when the hand leaves")

	# Hover layers over a Highlight or Vision outline and never takes it away:
	# whatever overlay was there is still there, both ways round.
	var mesh := ball.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var outline := ShaderMaterial.new() # stands in for Highlight's / Vision's overlay
	mesh.material_overlay = outline
	Hover.set_hovered(ball, true)
	Hover.set_hovered(ball, false)
	_check(mesh.material_overlay == outline, "an outline that was there before hover is there after it")
	Hover.set_hovered(ball, true)
	mesh.material_overlay = null # the Highlight clears while the hand is still near
	Hover.set_hovered(ball, false)
	_check(mesh.material_overlay == null, "hover never brings back an outline that was cleared under it")
	# The shell itself (skipped headless otherwise) is never a MeshInstance3D that
	# Highlight, Contrast or Vision could pick up and keep after it is freed.
	var mesh_count := ball.find_children("*", "MeshInstance3D", true, false).size()
	Hover._add_shells(ball)
	var shells := 0
	for child in mesh.get_children(true):
		shells += 1 if child.name == Hover.SHELL else 0
	_check(shells == 1 and ball.find_children("*", "MeshInstance3D", true, false).size() == mesh_count,
		"the hover shell is drawn but no mesh lookup can collect it")
	Hover._remove_shells(ball)

	# The fingertip pokes, 6 cm ahead of the hand along the controller.
	_check(hand.poke_point().is_equal_approx(hand.global_position + Vector3(0.0, 0.0, -hand.poke_reach)),
		"the hand's poke point is just in front of it")

	# The menu pauses the world mid-carry: the hand moves on, the object waits,
	# and letting go meanwhile drops it once the world runs again, never throws it.
	var carried := Grabbable.new()
	carried.id = &"ball"
	level.add_child(carried)
	controller.process_mode = Node.PROCESS_MODE_ALWAYS # as the player rig does
	controller.global_position = spot + Vector3(0.0, 2.0, 0.0)
	carried.global_position = controller.global_position
	hand.hold(carried)
	await _physics_frames()
	get_tree().paused = true
	hand._on_button_released("grip_click")
	controller.global_position += Vector3(5.0, 0.0, 0.0)
	await _physics_frames()
	_check(hand.held == carried, "letting go while paused waits for the world to run again")
	get_tree().paused = false
	await _physics_frames()
	_check(hand.held == null and carried.linear_velocity.length() < 1.0,
		"then it drops, instead of flying off with the hand's paused movement (%.1f m/s)" % carried.linear_velocity.length())
	carried.queue_free()
	controller.queue_free()
	ball.queue_free()
	button.queue_free()
	await get_tree().process_frame

	# Feedback: the nearest hand vibrates (scaled by the setting) and a shape
	# mark appears where it happened.
	var right := player.get_node(^"RightController/Hand") as Hand
	var left := player.get_node(^"LeftController/Hand") as Hand
	var right_rest: Vector3 = right.get_parent().position
	var left_rest: Vector3 = left.get_parent().position
	right.get_parent().position = Vector3(0.3, 1.0, -0.3)
	left.get_parent().position = Vector3(-0.3, 1.0, -0.3)
	Settings.set_value(&"haptics", 0.5)
	right.last_pulse = 0.0
	left.last_pulse = 0.0
	var feedback := player.get_node(^"Feedback")
	Events.judge(&"good", right.global_position)
	_check(is_equal_approx(right.last_pulse, 0.25) and left.last_pulse == 0.0,
		"good: the nearest hand ticks at the strength the haptics setting allows")
	_check(feedback.last_mark != null and feedback.last_mark.get_meta(&"shape") == &"tick", "good: a tick mark")
	Events.judge(&"bad", left.global_position)
	_check(is_equal_approx(left.last_pulse, 0.15), "bad: a softer buzz on the hand nearest to it")
	_check(feedback.last_mark.get_meta(&"shape") == &"cross", "bad: a cross mark")
	Events.judge(&"reward", right.global_position)
	_check(feedback.last_mark.get_meta(&"shape") == &"star", "reward: a star mark")
	Settings.set_value(&"haptics", 0.0)
	right.last_pulse = 0.0
	Events.judge(&"good", right.global_position)
	_check(right.last_pulse == 0.0, "haptics at 0 means no vibration at all")
	Settings.reset()

	# Comfort: nothing moves the child while the menu has the world paused, and
	# the move mode and turn size apply live.
	var walk := player.get_node(^"Locomotion")
	var teleport := player.get_node(^"Teleport")
	var home := player.global_transform
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 20.0, 0.0)) # open air
	var start := player.global_transform
	get_tree().paused = true
	walk.step(Vector2(0.0, 1.0), Vector2(1.0, 0.0), 0.5)
	var teleported: bool = teleport.teleport_to(start.origin + Vector3(2.0, 0.0, 0.0))
	get_tree().paused = false
	_check(player.global_transform.is_equal_approx(start) and not teleported,
		"paused: the sticks neither walk nor turn, and teleport does nothing")
	Settings.set_value(&"move_mode", &"teleport")
	walk.step(Vector2(0.0, 1.0), Vector2.ZERO, 0.5)
	_check(player.global_position.is_equal_approx(start.origin), "teleport mode: the stick does not walk")
	_check(teleport.teleport_to(start.origin + Vector3(2.0, 0.0, 0.0)), "teleport mode still teleports")
	player.global_transform = start
	Settings.set_value(&"move_mode", &"walk")
	walk.step(Vector2(0.0, 1.0), Vector2.ZERO, 0.5)
	_check(not player.global_position.is_equal_approx(start.origin), "walk mode: the stick walks")
	walk.enabled = false # a seated station
	player.global_transform = start
	walk.step(Vector2(0.0, 1.0), Vector2.ZERO, 0.5)
	_check(player.global_position.is_equal_approx(start.origin), "seated: the stick does not walk, whatever the setting")
	walk.enabled = true
	Settings.set_value(&"turn_degrees", 45.0)
	walk.step(Vector2.ZERO, Vector2.ZERO, 0.1)
	walk.step(Vector2.ZERO, Vector2(1.0, 0.0), 0.1)
	_check(is_equal_approx(rad_to_deg(absf(player.global_rotation.y)), 45.0), "snap turn follows the turn setting")
	walk.step(Vector2.ZERO, Vector2.ZERO, 0.1)
	Settings.reset()
	player.global_transform = home

	# Placement: bag -> hand -> floor -> bag, all through the contract.
	var layout := level.get_node(^"DecorLayout") as DecorLayout
	var facts: PackedStringArray = []
	var listen := func(what: StringName, id: StringName, _data: Dictionary) -> void: facts.append("%s:%s" % [what, id])
	Events.reported.connect(listen)
	var owned_before := layout.items().size()
	Events.place_requested.emit(&"lamp")
	_check(layout.items().size() == owned_before and not facts.has("taken_out:lamp"),
		"asking for furniture you do not own does nothing")
	Inventory.add(&"lamp", 2)
	Events.place_requested.emit(&"lamp")
	var lamp := layout.items()[layout.items().size() - 1] as Grabbable
	_check(Inventory.count(&"lamp") == 1, "taking one out leaves one in the bag")
	_check(layout.items().size() == owned_before + 1 and lamp.id == &"lamp", "the lamp is in the world's layout")
	_check(facts.has("taken_out:lamp"), "taking out is reported")
	_check(lamp.holder == right, "it lands in the free hand, the right one first")
	right.release()
	_check(facts.has("placed:lamp") and lamp.holder == null, "letting go places it")

	# Put away: pick it up, the other hand touches the button over it.
	right.hold(lamp)
	var put_away := layout.get_node(^"PutAwayButton") as PutAwayButton
	_check(put_away.visible and put_away.global_position.y > lamp.global_position.y,
		"a put-away button floats over the held item")
	_check(not put_away.touch(right), "the hand holding it cannot press its button by accident")
	_check(put_away.touch(left), "the other hand can")
	_check(Inventory.count(&"lamp") == 2 and facts.has("put_away:lamp"), "putting it away is +1 in the bag, reported")
	_check(right.held == null and facts.count("placed:lamp") == 1, "put away lets go of it without placing it")
	await get_tree().create_timer(0.4).timeout
	_check(not is_instance_valid(lamp) and layout.items().size() == owned_before, "the put-away item is gone")

	# Two pieces held: letting one go leaves the button on the other.
	Inventory.add(&"lamp", 1)
	Events.place_requested.emit(&"lamp")
	var first := layout.items()[layout.items().size() - 1] as Grabbable
	Events.place_requested.emit(&"lamp")
	var second := layout.items()[layout.items().size() - 1] as Grabbable
	_check(first.holder == right and second.holder == left and put_away.item == second,
		"a second item goes to the other hand and the button moves to it")
	left.release()
	_check(put_away.visible and put_away.item == first, "letting one go leaves the button on the one still held")
	right.release()
	_check(not put_away.visible, "the button goes once nothing is held")
	var floor_y := first.global_position.y

	# Both hands full: it waits in front of the child instead.
	var dummy_a := Grabbable.new()
	var dummy_b := Grabbable.new()
	dummy_a.id = &"ball" # anything with a sound row
	dummy_b.id = &"ball"
	level.add_child(dummy_a)
	level.add_child(dummy_b)
	right.hold(dummy_a)
	left.hold(dummy_b)
	Events.place_requested.emit(&"lamp")
	var waiting := layout.items()[layout.items().size() - 1]
	var eye := player.camera.global_position
	var flat := Vector2(waiting.global_position.x - eye.x, waiting.global_position.z - eye.z).length()
	_check(waiting.get(&"holder") == null and absf(flat - layout.front_distance) < 0.05,
		"with both hands full the item waits 0.4 m in front")
	right.held = null
	left.held = null
	dummy_a.queue_free()
	dummy_b.queue_free()
	Events.reported.disconnect(listen)

	# The layout is remembered: id and transform of every item. One is in a hand
	# when the game saves (focus lost): it comes back standing on the floor.
	right.hold(first)
	right.get_parent().position = Vector3(0.3, 1.6, -0.3)
	await _physics_frames(1)
	var saved := layout.save_state()
	Save.write()
	Save.reload()
	var loaded := layout.save_state()
	var same: bool = saved.items.size() == loaded.items.size() and saved.items.size() == owned_before + 3
	var held_index := -1
	for i in mini(saved.items.size(), loaded.items.size()):
		same = same and saved.items[i][0] == loaded.items[i][0] \
			and (saved.items[i][1] as Transform3D).is_equal_approx(loaded.items[i][1])
		if saved.items[i][2]:
			held_index = i
	_check(same, "the layout survives a save/load round trip, ids and transforms")
	await _physics_frames(2)
	_check(held_index >= 0 and absf(layout.items()[held_index].global_position.y - floor_y) < 0.02,
		"an item saved while held comes back settled on the floor, not in mid-air")
	right.get_parent().position = right_rest
	left.get_parent().position = left_rest

	# Content: every shop item is furniture made the swappable way.
	var furniture := [&"chair", &"table", &"bed", &"lamp", &"plant", &"rug", &"bookshelf",
		&"picture_frame", &"toy_chest", &"cushion"]
	var bad := PackedStringArray()
	for item_id: StringName in furniture:
		var def := ItemDef.find(item_id)
		var price: int = def.cost.get(&"magic_stone", 0) if def else 0
		if def == null or not def.in_shop or def.scene == null or def.cost.size() != 1 or price < 1 or price > 4:
			bad.append("%s (def)" % item_id)
			continue
		var node := def.scene.instantiate()
		var visual := node.get_node_or_null(^"Visual")
		if not (node is Grabbable) or not (node.get_node_or_null(^"Placeable") is Placeable) \
				or visual == null or not visual.scene_file_path.begins_with("res://content/items/visuals/") \
				or _has_script(visual):
			bad.append("%s (scene)" % item_id)
		node.free()
	_check(bad.is_empty(), "every furniture item: shop, 1-4 stones, logic scene, script-free visual%s"
		% ("" if bad.is_empty() else ": %s" % ", ".join(bad)))
	_check(ItemDef.find(&"coin") == null, "there are no coins: Magic Stones are the only currency")
	_check(ResourceLoader.exists("res://content/items/visuals/magic_stone.tscn"), "the Magic Stone has a look")

	# Trial objects: same split, and grading still reaches the meshes inside Visual.
	bad.clear()
	for file in ResourceLoader.list_directory("res://content/trials/objects/"):
		if not file.ends_with(".tscn"):
			continue
		var node := (load("res://content/trials/objects/" + file) as PackedScene).instantiate()
		level.add_child(node)
		var visual := node.get_node_or_null(^"Visual")
		var contrast: Contrast = null
		var highlight: Highlight = null
		for child in node.get_children():
			if child is Contrast:
				contrast = child
			elif child is Highlight:
				highlight = child
		if visual == null or _has_script(visual) or contrast == null or highlight == null \
				or contrast._meshes.is_empty() or highlight._meshes.is_empty():
			bad.append(file)
		node.free()
	_check(bad.is_empty(), "trial objects: a script-free Visual that Contrast and Highlight both reach%s"
		% ("" if bad.is_empty() else ": %s" % ", ".join(bad)))
	for kind in [&"mark_good", &"mark_bad", &"mark_reward", &"put_away_icon"]:
		var visual := (load("res://content/effects/%s.tscn" % kind) as PackedScene).instantiate()
		if _has_script(visual):
			bad.append(kind)
		visual.free()
	_check(bad.is_empty(), "feedback marks are looks only, with no scripts")
	_finished += 1


func _has_script(node: Node) -> bool:
	if node.get_script() != null:
		return true
	for child in node.get_children():
		if _has_script(child):
			return true
	return false


func _physics_frames(count := 3) -> void:
	for _i in count:
		await get_tree().physics_frame




## The sound table: the thing that has to be true is that it is the only place
## a sound is named, and that it never quietly says something untrue.
func _audio() -> void:
	var table := Audio.table
	_check(table.errors.is_empty(),
		"the sound table loads with nothing wrong with it%s"
		% ("" if table.errors.is_empty() else ": %s" % table.errors[0]))
	_check(table.rows.size() > 10, "the table has rows (%d)" % table.rows.size())

	# Dotted fallback: one row gives every button in the game a sound.
	var any_button := table.lookup("pressed.a_button_nobody_has_named")
	_check(any_button != null and any_button.key == "pressed",
		"an unnamed button falls back to the general 'pressed' row")
	var named := table.lookup("pressed.hello")
	_check(named != null and named.key == "pressed.hello", "a named button overrides the fallback")
	_check(table.is_silenced("asked.help") and table.lookup("asked.help") == null,
		"a row of '-' silences a whole family and stops the fallback")
	_check(table.lookup("nothing.like.this") == null and not table.is_silenced("nothing.like.this"),
		"a key with no row anywhere is unmapped, which is not the same as silent")

	# Options are parsed, and a typo in one is a loud error rather than a
	# setting that silently does nothing.
	var options := SoundDef.new()
	var problems := options.parse_options("vol=-6 pitch=0.9-1.1 bus=ambience space=3d cd=0.25 pick=cycle loop")
	_check(problems.is_empty(), "a well-formed options string parses clean")
	_check(options.volume_db == -6.0 and options.bus == &"Ambience" and options.positional
		and options.cooldown == 0.25 and options.loop and options.pick == SoundDef.Pick.CYCLE,
		"every option reaches the sound")
	_check(options.pitch() >= 0.9 and options.pitch() <= 1.1, "pitch varies inside its range")
	_check(SoundDef.new().parse_options("volum=-6").size() == 1, "a misspelt option is an error")
	_check(SoundDef.new().parse_options("bus=reverb").size() == 1, "an unknown bus is an error")

	# A fact on the bus is heard without anything being wired to it.
	var before: int = Audio.cued
	Events.report(&"caught", &"butterfly", {position = Vector3(1.0, 1.5, -2.0)})
	_check(Audio.cued > before, "a fact reported on the bus plays a sound")
	# The newest few, not just the last: the live island may sound something in the
	# same frame, and the log is capped, so its size alone says nothing.
	_check(Array(Audio.played.slice(-5)).any(func(key: String) -> bool: return key.begins_with("caught.butterfly")),
		"the key the sound was found under is the fact that happened")

	# The two seams still work, because tasks hold clips of their own.
	await Narrator.wait_quiet()
	before = Audio.spoken
	Narrator.say("A line with a clip.", Audio.tone(440.0, 60.0))
	_check(Audio.spoken == before + 1, "a Narrator line with a recording reaches the guide's voice")
	await Narrator.wait_quiet()
	Narrator.say("A line nobody has recorded yet.")
	_check(Audio.speech[Audio.speech.size() - 1] == "say: A line nobody has recorded yet.",
		"a line with no recording goes to text-to-speech")
	Events.read_aloud.emit("Shop page")
	_check(Audio.speech[Audio.speech.size() - 1] == "say: A line nobody has recorded yet.",
		"reading a button aloud never talks over the guide")
	before = Audio.cued
	Events.play_at(Audio.tone(880.0, 60.0), Vector3.ZERO)
	_check(Audio.cued > before, "Events.play_at still plays a stream the caller is holding")

	# The claim the whole design rests on, checked rather than asserted in a
	# comment: one file owns the audio nodes, and a button has no idea it makes
	# a sound. Break this and sounds start being wired in code again.
	var owners := PackedStringArray()
	for path in _scripts("res://"):
		if path.begins_with("res://modules/audio/") or path.begins_with("res://tests/"):
			continue
		if FileAccess.get_file_as_string(path).contains("AudioStreamPlayer"):
			owners.append(path)
	_check(owners.is_empty(), "only the audio module owns an audio node%s"
		% ("" if owners.is_empty() else ": %s" % ", ".join(owners)))
	var button_source := FileAccess.get_file_as_string("res://components/touch_button.gd")
	_check(not button_source.contains("AudioStream") and not button_source.contains("Audio."),
		"touch_button.gd calls nothing in the audio module, yet every button is heard")

	# Every fact the contract names is answered, whether or not this run happened
	# to report it, so a new kind of moment cannot ship silent by accident.
	for key in ["opened.menu", "closed.menu", "accepted.any_task", "bought.any_item",
			"taken_out.any_item", "placed.any_item", "put_away.any_item", "entered.any_place",
			"feedback.good", "feedback.bad", "feedback.reward"]:
		_check(table.lookup(key) != null or table.is_silenced(key), "the table answers %s" % key)
	# Good and bad have to be told apart by more than pitch: by rhythm or length.
	var good := table.lookup("feedback.good")
	var bad := table.lookup("feedback.bad")
	if good and bad and good.sources[0].begins_with(SoundTable.TONE) and bad.sources[0].begins_with(SoundTable.TONE):
		var good_notes := SoundTable.tone_notes(good.sources[0])
		var bad_notes := SoundTable.tone_notes(bad.sources[0])
		var good_ms := 0.0
		var bad_ms := 0.0
		var good_beats := 0
		var bad_beats := 0
		for note in good_notes:
			good_ms += note.y
			good_beats += 1 if note.x > 0.0 else 0
		for note in bad_notes:
			bad_ms += note.y
			bad_beats += 1 if note.x > 0.0 else 0
		_check(good_beats != bad_beats and absf(good_ms - bad_ms) > 100.0,
			"good and bad feedback differ in rhythm and length, not only pitch (%d vs %d notes, %d vs %d ms)"
			% [good_beats, bad_beats, good_ms, bad_ms])
	_check(Audio.melody(SoundTable.tone_notes("tone:440/100+0/50+660/100")).data.size()
		== (int(Audio.TONE_RATE * 0.1) * 2 + int(Audio.TONE_RATE * 0.05)) * 2,
		"a note sequence with a rest is as long as its notes")

	# The table has to keep up with the game. Anything the game said that no row
	# answers is listed here by name, so it is fixed rather than forgotten.
	_check(Audio.unmapped.is_empty(),
		"every fact the whole playthrough reported has a row or is silenced%s"
		% ("" if Audio.unmapped.is_empty() else ": %s" % ", ".join(PackedStringArray(Audio.unmapped.keys()))))
	_finished += 1


## Every module's own station in the Test Room, run with nobody in the headset.
## These are the same check objects the room shows, so a green suite and a green
## board can never disagree — and a module that breaks is named, not just
## counted.
func _module_checks() -> void:
	var stones := Inventory.count(STONE)
	var done := Tasks.times_done(&"welcome")
	await _go(Profile.TESTBED)
	await _settle() # the profile is swapped on the way: one more fade
	_check(Profile.is_test_room() and Game.level.level_id == &"testbed",
		"asking for the Test Room opens it on its own profile")
	_check(Inventory.count(STONE) == 0 and Tasks.times_done(&"welcome") == 0,
		"the Test Room starts empty, whoever was playing")
	var board := Game.level.get_node(^"Board") as CheckBoard
	var stations := board.stations()
	_check(stations.size() == 13, "the Test Room has a station for every module (%d)" % stations.size())
	for station: ModuleCheck in stations:
		_check(not station.checks.is_empty() and not station.action.is_empty()
			and not station.pass_when.is_empty(),
			"%s: the sign says what it checks, what to do and what a pass is" % station.title)
	await board.run_all()
	await get_tree().create_timer(2.0).timeout # stations with a deadline of their own
	for station: ModuleCheck in stations:
		_check(station.verdict == ModuleCheck.Verdict.PASS,
			"%s: %s [%s]" % [station.title, station.pass_when, station.note])
	Profile.switch(PROFILE)
	await _settle()
	await _settle()
	_check(Profile.id == PROFILE and Inventory.count(STONE) == stones and Tasks.times_done(&"welcome") == done,
		"leaving the Test Room gives the player back untouched by the hand tests (%d stones)" % Inventory.count(STONE))
	_finished += 1


## Touch the wrist star, then use tracked aim poses and trigger input while
## paused. Every page still stands with its optional module switched off.
func _menu() -> void:
	var menu := Game.module(&"Menu")
	if menu == null:
		_check(false, "the Menu module is switched on")
		_finished += 1
		return
	var audio := Game.module(&"Audio")
	var fingertip := GDScript.new()
	fingertip.source_code = "extends Node3D\nfunc poke_point() -> Vector3:\n\treturn global_position\n"
	fingertip.reload()
	var finger := Node3D.new()
	finger.set_script(fingertip)
	finger.add_to_group(&"hand")
	add_child(finger)
	finger.global_position = MENU_AWAY
	var controller := Game.player.get_node(^"RightController") as XRController3D
	var previous_tracker := controller.tracker
	var tracker := XRControllerTracker.new()
	tracker.name = &"/smoke/menu/right"
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"default", Transform3D(Basis.IDENTITY, MENU_AWAY), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input(&"trigger_click", false)
	controller.tracker = tracker.name
	var facts := PackedStringArray()
	var toggles: Array[bool] = []
	var judged: Array[StringName] = []
	var requested: Array[StringName] = []
	var on_fact := func(what: StringName, id: StringName, _data: Dictionary) -> void:
		facts.append("%s:%s" % [what, id])
	var on_toggle := func(open: bool) -> void: toggles.append(open)
	var on_judge := func(kind: StringName, _at: Vector3) -> void: judged.append(kind)
	var on_place := func(item_id: StringName) -> void: requested.append(item_id)
	Events.reported.connect(on_fact)
	Events.menu_toggled.connect(on_toggle)
	Events.feedback.connect(on_judge)
	Events.place_requested.connect(on_place)
	# Headless, both controllers sit at the rig's origin, a hand's width from the
	# star. Park the rig's own hands out of reach so only the test finger counts.
	var parked := {}
	for hand in get_tree().get_nodes_in_group(&"hand"):
		if hand != finger and hand is Node3D:
			parked[hand] = hand.position
			hand.global_position = MENU_AWAY + Vector3(parked.size(), 0.0, 0.0)
	await _frames(3)

	await Narrator.wait_quiet() # nothing of the game's own left to say: the lines below are the test's
	# The wrist: always there, and fed by the bus rather than by polling.
	_check(menu.star() != null and menu.star().is_inside_tree(), "the star is on the left wrist")
	_check(menu.readout_text().contains("Magic Stones"), "the wrist counts Magic Stones next to the star")
	var real_goal := Events.goal
	var fake := Goal.new()
	fake.task = &"fake"
	fake.text = "Find the red flower"
	Events.set_goal(fake)
	_check(menu.readout_text().contains("Find the red flower"), "the wrist shows a new goal the moment it is sent")
	Events.set_goal(real_goal)

	# Touching the star with the other hand opens the menu and stops the world.
	finger.global_position = menu.star().global_position
	await _frames(3)
	_check(menu.is_open and get_tree().paused, "touching the star opens the menu and pauses the world")
	_check(toggles.size() == 1 and toggles[0], "menu_toggled(true) goes out once")
	_check(facts.has("opened:menu"), "opening reports opened:menu")
	_check(not menu.star().is_visible_in_tree(), "the wrist hides while the panel is open")
	finger.global_position = MENU_AWAY
	await _frames(3)
	finger.global_position = menu.star().global_position
	await _frames(3)
	_check(menu.is_open and toggles.size() == 1, "reaching back across the wrist does not close the panel")
	finger.global_position = MENU_AWAY
	await _frames(3)

	# Lines said while the menu is open wait: nothing is shown or heard, in order.
	var subtitle := Label3D.new()
	subtitle.set_script(load("res://player/subtitle.gd"))
	add_child(subtitle)
	Settings.set_value(&"subtitles", true)
	Narrator.say("First line.")
	Narrator.say("Next line.")
	await get_tree().create_timer(0.4).timeout
	_check(Narrator.current == null and not subtitle.visible,
		"lines said while the menu is open are neither shown nor heard until it closes")
	await _click_menu(tracker, &"menu_close")
	_check(not menu.is_open and subtitle.visible and subtitle.text == "First line."
		and Narrator.current.text == "First line.",
		"closing the menu starts the first line: on screen and in the voice together")
	_check(menu.star().is_visible_in_tree(), "closing restores the wrist entry")
	await _until(func() -> bool: return Narrator.current != null and Narrator.current.text == "Next line.", 300)
	_check(subtitle.text == "Next line.", "then the next line, in order, still the same on screen as in the voice")
	menu.open()
	await _frames(2) # Narrator observes the tree pause in its process step
	_check(not subtitle.visible and Narrator.current.text == "Next line.",
		"opening the menu stops the line on show; it waits to start again")
	Settings.set_value(&"subtitles", false)
	menu.close()
	_check(not subtitle.visible, "subtitles switched off in the menu stay off after closing")
	Settings.set_value(&"subtitles", true)
	await Narrator.wait_quiet()
	subtitle.free()
	menu.open()

	# Trigger edges survive rebuilding the page under the held trigger.
	_aim_menu(tracker, menu.find_button(&"menu_tab_tasks").global_position)
	await _frames(3)
	tracker.set_input(&"trigger_click", true)
	await _frames(40)
	_check(facts.count("pressed:menu_tab_tasks") == 1, "holding the trigger across a page rebuild clicks exactly once")
	_check(menu.page == &"tasks", "the ray click opens its page while paused")
	_aim_menu(tracker, menu.find_button(&"menu_tab_bag").global_position)
	await _frames(3)
	_check(not facts.has("pressed:menu_tab_bag"), "dragging a held trigger onto another button does not click")
	tracker.set_input(&"trigger_click", false)
	await _frames(3)

	# A ray from behind the panel cannot select it.
	var bag_tab: RayButton = menu.find_button(&"menu_tab_bag")
	var back := bag_tab.global_position - bag_tab.global_basis.z * 0.4
	_aim_menu(tracker, bag_tab.global_position, back)
	await _frames(3)
	tracker.set_input(&"trigger_click", true)
	await _frames(3)
	_check(not facts.has("pressed:menu_tab_bag"), "a ray behind the panel cannot click through it")
	tracker.set_input(&"trigger_click", false)

	# Pointing reads aloud without pressing, using aim rather than the parked grip.
	if audio:
		_aim_menu(tracker, menu.find_button(&"menu_tab_shop").global_position)
		await get_tree().create_timer(RayButton.DWELL + 0.25).timeout
		_check(not audio.speech.is_empty() and audio.speech[audio.speech.size() - 1] == "read: Shop page",
			"pointing at a button reads its label aloud")
		_check(not facts.has("pressed:menu_tab_shop"), "aiming without the trigger never clicks")

	# Tracking loss hides the ray; regaining it with a held trigger is not a click.
	tracker.invalidate_pose(&"aim")
	tracker.set_input(&"trigger_click", true)
	await _frames(3)
	_check(not Game.player.get_node(^"RightControllerMenuPointer").visible, "lost aim tracking hides the ray")
	_aim_menu(tracker, menu.find_button(&"menu_tab_shop").global_position)
	await _frames(3)
	_check(not facts.has("pressed:menu_tab_shop"), "restoring tracking with the trigger held does not click")
	tracker.set_input(&"trigger_click", false)
	await _frames(3)

	# Both hands can select; simultaneous triggers over one button click once.
	var left_controller := Game.player.get_node(^"LeftController") as XRController3D
	var previous_left_tracker := left_controller.tracker
	var left_tracker := XRControllerTracker.new()
	left_tracker.name = &"/smoke/menu/left"
	left_tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(left_tracker)
	left_controller.tracker = left_tracker.name
	left_tracker.set_input(&"trigger_click", false)
	var home: Vector3 = menu.find_button(&"menu_tab_home").global_position
	_aim_menu(left_tracker, home)
	_aim_menu(tracker, home)
	await _frames(3)
	var home_clicks := facts.count("pressed:menu_tab_home")
	left_tracker.set_input(&"trigger_click", true)
	tracker.set_input(&"trigger_click", true)
	await _frames(3)
	_check(facts.count("pressed:menu_tab_home") == home_clicks + 1,
		"two triggers on the same button in one frame produce one click")
	left_tracker.set_input(&"trigger_click", false)
	tracker.set_input(&"trigger_click", false)
	await _frames(3)
	await _click_menu(left_tracker, &"menu_tab_bag")
	_check(menu.page == &"bag", "the left controller can click the menu too")
	left_controller.tracker = previous_left_tracker
	XRServer.remove_tracker(left_tracker)

	# Updating tracked poses after closing cannot make the ray reappear.
	menu.close()
	_aim_menu(tracker, home)
	await _frames(3)
	_check(not Game.player.get_node(^"RightControllerMenuPointer").visible, "tracking updates leave the ray hidden while the menu is closed")
	tracker.set_input(&"trigger_click", true)
	menu.open()
	_aim_menu(tracker, menu.find_button(&"menu_tab_bag").global_position)
	await _frames(3)
	_check(menu.page == &"home", "opening with the trigger held waits for a release")
	tracker.set_input(&"trigger_click", false)
	await _frames(3)

	# The shop: enough stones buys, too few is a gentle no and costs nothing.
	var chair := ItemDef.find(&"chair")
	var price: int = chair.cost.get(&"magic_stone", 0)
	menu.shop_override.assign([chair])
	Inventory.spend({&"magic_stone": Inventory.count(&"magic_stone")})
	Inventory.add(&"magic_stone", price)
	var chairs := Inventory.count(&"chair")
	menu.show_page(&"shop")
	await _click_menu(tracker, &"menu_buy_chair")
	_check(Inventory.count(&"magic_stone") == 0 and Inventory.count(&"chair") == chairs + 1,
		"buying spends the stones and puts the chair in the bag")
	_check(facts.has("bought:chair") and judged.has(&"reward"), "a purchase reports bought:chair and is a reward")
	if price > 0:
		await _click_menu(tracker, &"menu_buy_chair")
		_check(Inventory.count(&"chair") == chairs + 1 and Inventory.count(&"magic_stone") == 0,
			"with too few stones nothing is bought and nothing is spent")
		_check(not judged.is_empty() and judged[judged.size() - 1] == &"bad", "too few stones is judged bad")
		_check(menu.page_text().contains("more"), "and the child is told how many more they need")
	menu.shop_override.clear()

	# The bag, where nothing in the world can take the thing: said, and kept.
	var listeners := Events.place_requested.get_connections()
	for connection in listeners:
		Events.place_requested.disconnect(connection.callable)
	menu.show_page(&"bag")
	await _click_menu(tracker, &"menu_take_out_chair")
	_check(menu.is_open and Inventory.count(&"chair") == chairs + 1 and menu.page_text().contains("nowhere"),
		"with nowhere to put it, Take out says so and the chair stays in the bag")
	for connection in listeners:
		Events.place_requested.connect(connection.callable, connection.flags)

	# The bag: taking something out asks the world for it and gets out of the way.
	await _click_menu(tracker, &"menu_take_out_chair")
	_check(requested.has(&"chair"), "Take out asks the world to place a chair")
	_check(not menu.is_open and not get_tree().paused, "taking something out closes the menu and the world goes on")

	# Settings: a press reaches Settings, and Settings reaches the disk.
	menu.open()
	menu.show_page(&"settings")
	var volume: float = Settings.value(&"volume_master")
	await _click_menu(tracker, &"menu_set_volume_master_down")
	_check(is_equal_approx(Settings.value(&"volume_master"), volume - 0.1),
		"a setting changed on the page reaches Settings")
	Settings.reload()
	_check(is_equal_approx(Settings.value(&"volume_master"), volume - 0.1),
		"and survives re-reading the settings file")

	# The gap has no target: one trigger cannot select both neighbouring buttons.
	var less: RayButton = menu.find_button(&"menu_set_volume_voice_down")
	var more: RayButton = menu.find_button(&"menu_set_volume_voice_up")
	var between := (less.global_position + more.global_position) * 0.5
	_aim_menu(tracker, between)
	await _frames(3)
	tracker.set_input(&"trigger_click", true)
	await _frames(3)
	tracker.set_input(&"trigger_click", false)
	await _frames(3)
	_check(not facts.has("pressed:menu_set_volume_voice_down") and not facts.has("pressed:menu_set_volume_voice_up"),
		"clicking the gap between buttons selects neither")

	# Volume never goes to silent from the menu: the clicks and voice are how a
	# child who cannot read finds their way back.
	for _i in 12:
		menu.press(&"menu_set_volume_master_down")
		await _frames(1)
	_check(Settings.value(&"volume_master") >= 0.099, "the menu never turns the volume all the way off")

	# The panel follows a headset re-centre while open.
	var camera := Game.player.get_node(^"Camera") as Node3D
	var panel_was: Vector3 = menu.find_button(&"menu_tab_home").global_position
	var camera_was := camera.transform
	camera.rotate_y(PI * 0.5)
	await menu.recentre()
	_check(menu.find_button(&"menu_tab_home").global_position.distance_to(panel_was) > 0.2,
		"re-centring the headset brings the open panel back in front")
	camera.transform = camera_was
	await menu.recentre()

	# Pause belongs to whoever holds it: closing the menu does not end the
	# headset's own pause.
	Game.hold_pause(&"headset", true)
	menu.close()
	_check(get_tree().paused, "closing the menu leaves a pause someone else holds")
	Game.hold_pause(&"headset", false)
	_check(not get_tree().paused, "and the world runs once nobody holds it")
	menu.open()
	menu.show_page(&"settings")
	await _click_menu(tracker, &"menu_next")
	await _click_menu(tracker, &"menu_next")
	await _click_menu(tracker, &"menu_start_over")
	_check(menu.find_button(&"menu_start_over_yes") != null and menu.is_open,
		"Start over asks before it wipes anything")
	await _click_menu(tracker, &"menu_start_over_no")
	_check(menu.find_button(&"menu_start_over") != null, "and No takes the question back")
	Settings.reset()
	menu.close()

	# Every page stands with the module it needs switched off, and says so.
	var needs := {&"Tasks": [&"home", &"tasks"], &"Inventory": [&"home", &"shop", &"bag"], &"Save": [&"settings"]}
	for module_name: StringName in needs:
		var key := "autoload/%s" % module_name
		var saved: Variant = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, null)
		menu.open()
		var broken := PackedStringArray()
		for page: StringName in [&"home", &"tasks", &"shop", &"bag", &"settings"]:
			menu.show_page(page)
			if page == &"settings":
				for _i in 2:
					menu.press(&"menu_next")
					await _frames(1)
			await _frames(1)
			var text: String = menu.page_text()
			var says_off: bool = text.contains("switched off")
			if menu.buttons().size() < 5 or (needs[module_name].has(page) and not says_off):
				broken.append(String(page))
		menu.close()
		ProjectSettings.set_setting(key, saved)
		_check(broken.is_empty(), "with %s off, every page stands and the ones that need it say so%s"
			% [module_name, "" if broken.is_empty() else " (not: %s)" % ", ".join(broken)])
	_check(Game.module(&"Tasks") != null and Game.module(&"Save") != null, "and every module is back on after")

	Events.reported.disconnect(on_fact)
	Events.menu_toggled.disconnect(on_toggle)
	Events.feedback.disconnect(on_judge)
	Events.place_requested.disconnect(on_place)
	controller.tracker = previous_tracker
	XRServer.remove_tracker(tracker)
	finger.queue_free()
	for hand: Node3D in parked:
		if is_instance_valid(hand):
			hand.position = parked[hand]
	_check(not get_tree().paused, "the menu leaves the world running")
	_finished += 1


## Synthetic tracker input takes the same pose/trigger path as a controller.
func _click_menu(tracker: XRControllerTracker, id: StringName) -> void:
	var menu := Game.module(&"Menu")
	var button: RayButton = menu.find_button(id)
	if button == null:
		_check(false, "the menu shows a %s button (page %s)" % [id, menu.page])
		return
	tracker.set_input(&"trigger_click", false)
	_aim_menu(tracker, button.global_position)
	await _frames(3)
	tracker.set_input(&"trigger_click", true)
	await _frames(3)
	tracker.set_input(&"trigger_click", false)
	await _frames(3)


func _aim_menu(tracker: XRControllerTracker, target: Vector3, origin := Vector3.INF) -> void:
	if origin == Vector3.INF:
		var camera := Game.player.get_node(^"Camera") as Node3D
		origin = camera.global_position + camera.global_basis * Vector3(0.25, -0.35, -0.2)
	var world := Transform3D(Basis.looking_at(target - origin), origin)
	tracker.set_pose(&"aim", Game.player.global_transform.affine_inverse() * world,
		Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


## Exercise controller signals, both chord orders and native UI clicks.
func _controls_and_debug() -> void:
	var menu := Game.module(&"Menu")
	var debug := Game.module(&"Debug")
	menu.close()
	debug.close()
	var controllers := [Game.player.get_node(^"LeftController"), Game.player.get_node(^"RightController")]
	var previous := [controllers[0].tracker, controllers[1].tracker]
	var trackers: Array[XRControllerTracker] = []
	for i in 2:
		var tracker := XRControllerTracker.new()
		tracker.name = StringName("/smoke/controls/%d" % i)
		tracker.type = XRServer.TRACKER_CONTROLLER
		XRServer.add_tracker(tracker)
		tracker.set_pose(&"default", Transform3D(Basis.IDENTITY, MENU_AWAY), Vector3.ZERO, Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		for action in [&"menu_button", &"by_button", &"trigger_click"]:
			tracker.set_input(action, false)
		controllers[i].tracker = tracker.name
		trackers.append(tracker)
	var left := trackers[0]
	var right := trackers[1]
	var facts := PackedStringArray()
	var on_fact := func(what: StringName, id: StringName, _data: Dictionary) -> void:
		facts.append("%s:%s" % [what, id])
	Events.reported.connect(on_fact)
	await _frames(3)

	left.set_input(&"menu_button", true)
	await _frames(3)
	_check(not menu.is_open and not debug.is_open, "Menu down opens neither panel")
	left.set_input(&"menu_button", false)
	await _frames(3)
	_check(menu.is_open and not debug.is_open, "Menu release opens the ordinary menu")
	left.set_input(&"menu_button", true)
	await _frames(3)
	_check(menu.is_open, "holding Menu leaves the current panel alone")
	left.set_input(&"menu_button", false)
	await _frames(3)
	_check(not menu.is_open, "another Menu release closes the ordinary menu")

	for press_y_first in [false, true]:
		for release_y_first in [false, true]:
			menu.open() # a chord also replaces an already open ordinary menu
			facts.clear()
			var first := &"by_button" if press_y_first else &"menu_button"
			var second := &"menu_button" if press_y_first else &"by_button"
			left.set_input(first, true)
			await _frames(3)
			_check(not debug.is_open and not facts.has("asked:help"), "the first chord key waits for its partner or release")
			left.set_input(second, true)
			await _frames(6)
			_check(debug.is_open and not menu.is_open and facts.count("asked:debug") == 1,
				"overlapping Menu/Y opens Debug once (Y first: %s)" % press_y_first)
			_check(get_tree().paused and not menu.star().is_visible_in_tree(), "Debug pauses play and hides the wrist")
			left.set_input(&"by_button" if release_y_first else &"menu_button", false)
			await _frames(3)
			left.set_input(&"menu_button" if release_y_first else &"by_button", false)
			await _frames(3)
			_check(debug.is_open and not menu.is_open and not facts.has("asked:menu") and not facts.has("asked:help"),
				"either chord release order suppresses ordinary menu and help")
			debug.close()

	facts.clear()
	left.set_input(&"by_button", true)
	await _frames(3)
	_check(not facts.has("asked:help"), "left Y waits until release for help")
	left.set_input(&"by_button", false)
	await _frames(3)
	_check(facts.count("asked:help") == 1, "left Y alone asks for help once on release")
	right.set_input(&"by_button", true)
	await _frames(3)
	_check(facts.count("asked:help") == 2, "right B still asks for help on press")
	right.set_input(&"by_button", false)
	await _frames(3)

	# A second Y press in the same held Menu gesture cannot retrigger Debug.
	left.set_input(&"menu_button", true)
	left.set_input(&"by_button", true)
	await _frames(3)
	left.set_input(&"by_button", false)
	await _frames(3)
	left.set_input(&"by_button", true)
	await _frames(3)
	_check(debug.is_open, "a consumed chord cannot toggle twice until both keys are up")
	left.set_input(&"menu_button", false)
	left.set_input(&"by_button", false)
	await _frames(3)

	var panel := Game.player.get_node(^"DebugPanel") as ViewportUI
	_check(panel.content is PanelContainer and panel.find_children("*", "TouchButton", true, false).is_empty(),
		"Debug is a Control UI with no old touch buttons")
	await _click_control(left, panel, &"dbg_saves")
	_check(panel.content.find_child("Saves", true, false).visible, "left ray clicks the native Saves tab while paused")
	await _click_control(right, panel, &"dbg_training")
	_check(panel.content.find_child("Training", true, false).visible, "right ray clicks the native Training tab")
	Training.unpin_all()
	Events.trial_started.emit(&"search", Training.condition(&"search").to_log())
	await _frames(4)
	var before: float = Training.condition(&"search").value(&"overlap")
	await _click_control(right, panel, &"dbg_overlap_up")
	await _click_control(right, panel, &"dbg_overlap_up")
	_check(Training.is_pinned(&"overlap") and is_equal_approx(Training.condition(&"search").value(&"overlap"), before + 0.1),
		"two UI nudges accumulate against the next round's pinned value")
	await _click_control(left, panel, &"dbg_auto")
	_check(not Training.is_pinned(&"overlap"), "the UI clears difficulty pins")
	Game.hold_pause(&"headset", true)
	await _click_control(right, panel, &"dbg_close")
	_check(not debug.is_open and get_tree().paused, "closing Debug leaves the headset's pause in place")
	Game.hold_pause(&"headset", false)
	_check(not get_tree().paused and menu.star().is_visible_in_tree(), "closing the last panel restores play and the wrist")

	# The same chord closes Debug, and its Menu release cannot reopen anything.
	for _i in 2:
		left.set_input(&"menu_button", true)
		left.set_input(&"by_button", true)
		await _frames(3)
		left.set_input(&"by_button", false)
		left.set_input(&"menu_button", false)
		await _frames(3)
	_check(not debug.is_open and not menu.is_open and not get_tree().paused, "the closing chord leaves both panels closed")
	Events.reported.disconnect(on_fact)
	for i in 2:
		controllers[i].tracker = previous[i]
		XRServer.remove_tracker(trackers[i])
	_finished += 1


func _click_control(tracker: XRControllerTracker, panel: ViewportUI, id: StringName) -> void:
	var button := panel.content.find_child(String(id), true, false) as Button
	tracker.set_input(&"trigger_click", false)
	_aim_menu(tracker, panel.button_position(button))
	await _frames(4)
	tracker.set_input(&"trigger_click", true)
	await _frames(4)
	tracker.set_input(&"trigger_click", false)
	await _frames(4)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


## Every .gd file in the project, so a rule about the whole codebase can be
## checked instead of hoped for.
func _scripts(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for name in dir.get_directories():
		if not name.begins_with("."):
			found.append_array(_scripts(root.path_join(name)))
	for name in dir.get_files():
		if name.ends_with(".gd"):
			found.append(root.path_join(name))
	return found


## Grabs [param node] and returns the round's log line.
func _pick(trial: SearchTrial, node: Node3D) -> Dictionary:
	if node == null:
		_check(false, "a round was running with a target to pick")
		return {}
	var logged := {}
	Events.trial_ended.connect(
		func(_visual_skill: StringName, _ok: bool, data: Dictionary) -> void: logged.merge(data),
		CONNECT_ONE_SHOT)
	var hand := Game.player.get_node(^"RightController/Hand") as Hand
	_check(hand.hold(node as Grabbable), "the hand takes the selected object")
	_check(hand.held == null and (node as Grabbable).holder == null,
		"correct-grab callbacks release both sides of the hold immediately")
	await get_tree().process_frame
	return logged


## Waits for [param trial]'s next round: up to 10 s, as it waits its turn behind
## the guide's lines.
func _next_round(trial: Trial) -> void:
	var until := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until:
		if trial.is_running():
			return
		await get_tree().process_frame


func _go(path: String) -> void:
	Game.change_level(path)
	await _settle()


func _settle() -> void:
	await get_tree().create_timer(Game.FADE_TIME + 0.3).timeout


func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1


## The island, from its colliders: what every other piece assumes about the map
## (the places exist and stand on floor, the house can be walked into, the
## stations have room, nobody walks off the edge), plus the rule that its look
## is swappable art: no CSG, and no script in any visual scene.
func _island() -> void:
	await _go("res://levels/island/island.tscn")
	var island := Game.level as Level
	_check(island != null and island.level_id == &"island", "the island level is called island")
	if island == null:
		return
	var spawn := island.get_node_or_null(^"Spawn") as Marker3D
	_check(spawn != null, "the island has a Spawn")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := island.get_world_3d().direct_space_state

	var places := {}
	for node in get_tree().get_nodes_in_group(Place.GROUP):
		if island.is_ancestor_of(node):
			places[(node as Place).id] = node
	var spots: Array[Node3D] = [spawn]
	for id: StringName in [&"dock", &"home", &"picnic", &"meadow", &"lighthouse"]:
		var place := places.get(id) as Place
		_check(place != null and not place.display_name.is_empty(), "place '%s' exists and has a name to say" % id)
		if place:
			spots.append(place)
	for spot in spots:
		if spot == null:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			spot.global_position + Vector3.UP * 2.0, spot.global_position + Vector3.DOWN))
		_check(not hit.is_empty() and hit.normal.y > 0.7, "%s stands on a floor you can teleport to" % spot.name)

	# Walking in is a straight line from the doorstep, at knee and at eye height.
	var doorway := island.get_node_or_null(^"House/Doorway") as Node3D
	var home := places.get(&"home") as Node3D
	if doorway and home:
		for height: float in [0.4, 1.2]:
			var lift := Vector3.UP * height
			var blocked := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				doorway.global_position + lift, home.global_position + lift))
			_check(blocked.is_empty(), "nothing blocks the way from the doorway into the house at %.1f m" % height)
	else:
		_check(false, "the house has a Doorway marker")

	# The stations bring their own furniture: nothing else may stand there.
	var room := {&"picnic": [BoxShape3D.new(), Vector3(4, 1.8, 4)], &"meadow": [CylinderShape3D.new(), Vector3(4, 1.8, 0)]}
	for id: StringName in room:
		var place := places.get(id) as Node3D
		if place == null:
			continue
		var shape: Shape3D = room[id][0]
		var size: Vector3 = room[id][1]
		if shape is BoxShape3D:
			(shape as BoxShape3D).size = size
		else:
			(shape as CylinderShape3D).radius = size.x
			(shape as CylinderShape3D).height = size.y
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.exclude = _rids(place.get_parent()) # the station's own table and benches
		query.transform = Transform3D(Basis(), place.global_position + Vector3.UP * (size.y / 2.0 + 0.1))
		_check(space.intersect_shape(query).is_empty(), "the %s spot is clear round its station" % id)

	# The shore is closed: walls taller than anything else, so a level ray at
	# 3.5 m only ever meets them, in every direction from everywhere you stand.
	var gaps := 0
	for spot in spots:
		if spot == null:
			continue
		for i in 72:
			var from := spot.global_position + Vector3.UP * 3.5
			var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 72.0)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 80.0)).is_empty():
				gaps += 1
	_check(gaps == 0, "the shoreline has no gap to walk through (%d open directions)" % gaps)

	# Swappable art: no CSG on the island, no scripts in its look scenes.
	var csg := 0
	var stack: Array[Node] = [island]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CSGShape3D:
			csg += 1
		stack.append_array(node.get_children())
	_check(csg == 0, "the island has no CSG nodes (%d)" % csg)
	var scripted := PackedStringArray()
	for dir_path in ["res://content/buildings", "res://content/landmarks", "res://content/nature"]:
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".tscn"):
				continue
			var visual := (load(dir_path.path_join(file)) as PackedScene).instantiate()
			var nodes: Array[Node] = [visual]
			while not nodes.is_empty():
				var node: Node = nodes.pop_back()
				if node.get_script() != null or node is CSGShape3D:
					scripted.append(file)
					break
				nodes.append_array(node.get_children())
			visual.free()
	_check(scripted.is_empty(), "no visual scene has a script or CSG in it%s"
		% ("" if scripted.is_empty() else ": %s" % ", ".join(scripted)))
	_finished += 1
