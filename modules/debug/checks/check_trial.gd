extends ModuleCheck
## Tasks, measured half: a round of a real [SearchTrial] builds itself, scores
## the pick and writes a complete log line.
##
## A whole trial in miniature on one pedestal: the same Scatter, SearchTrial and
## TrialRunner the picnic station uses, running res://content/trials/selftest.tres
## (its own visual skill, so hand-testing never moves a child's staircase).

const TRIAL := &"selftest"

## Grabbable objects with an id, a Highlight and a Contrast, as in the real room.
@export var objects: Array[PackedScene] = []

var _runner: TrialRunner
var _trial: SearchTrial
## True only between pressing the button and that round ending. Other stations
## emit trial_ended too, and a station must judge its own round and no other.
var _mine := false


func _arm() -> void:
	add_button(&"go", "Start\na round")
	var scatter := Scatter.new()
	scatter.name = "Objects"
	scatter.radius = 0.22
	scatter.spacing = 0.13
	scatter.unique = true
	add_prop(scatter, Vector3(0.0, 0.02, 0.0))

	_trial = SearchTrial.new()
	_trial.name = "Trial"
	_trial.scatter = scatter
	_trial.objects = objects

	_runner = TrialRunner.new()
	_runner.name = "%sRunner" % name
	_runner.trial = _trial
	_runner.trial_id = TRIAL
	_runner.add_child(_trial)
	_props.add_child(_runner)
	Events.trial_ended.connect(_on_round_ended)
	update("no round yet")


func _teardown() -> void:
	if Events.trial_ended.is_connected(_on_round_ended):
		Events.trial_ended.disconnect(_on_round_ended)


func _on_press(id: StringName) -> void:
	if id != &"go" or _runner == null or _runner.is_running():
		return
	_mine = true
	_runner.run(0)
	update("pick the one the guide names")


func _on_round_ended(_visual_skill: StringName, success: bool, data: Dictionary) -> void:
	if not _mine or StringName(str(data.get("trial", ""))) != TRIAL:
		return
	_mine = false
	var logged: bool = data.has("axis_clutter") and data.has("seconds") and data.has("hint")
	var trace := "picked %s, wanted %s, %.1fs" % [
		data.get("picked", "-"), data.get("target", "-"), data.get("seconds", 0.0)
	]
	if success and logged:
		pass_now("%s, logged" % trace)
	else:
		fail_now("%s%s" % [trace, "" if logged else ", log line incomplete"])


func auto() -> void:
	_on_press(&"go")
	for _frame in 600:
		if _trial.is_running():
			break
		await get_tree().process_frame
	var target := _trial.target()
	if target == null:
		fail_now("no round started")
		return
	var hand := Node3D.new()
	(target as Grabbable).grab(hand)
	await get_tree().process_frame
	hand.free()
