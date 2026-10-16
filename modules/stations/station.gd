class_name Station
extends Node3D
## A fixed spot where measured training happens: a [Place], an activity zone,
## a [TrialRunner] with its [Trial], a sign and a beacon. Drop one into any
## level; nothing else has to know it is there.
##
## [b]Wanted[/b] while the goal ([member Events.goal]) names its trial. Then the
## beacon goes up, tall and soft, so it can be found from across the island, and
## the sign shows what the rounds are for (the task's title), the visual skill it trains
## and how many rounds are still to go — all read off the goal, which is the only
## count there is. The station keeps no copy of it.
##
## Rounds run while the child's head is in the zone: once nobody is talking, and
## a short gap after the last round, the next one starts. Movement stays free,
## and the station says once per step what the practice is for. Leaving the zone
## pauses the round's clock and hints; returning carries on. When the goal stops
## naming the trial (the last round is in, or a profile is reloaded) the station
## goes idle, and a round still out is dropped unscored.
##
## Every station reports "entered:<place id>" when a head comes in, idle or not,
## so a task step can send the child here without running anything — and again
## when the goal moves here with the child already here, or a step waiting for
## them to arrive would wait for ever.
##
## [b]Layers:[/b] stations sit on top of trials (modules/trials/) and talk to
## everything else only through [Events] and the Narrator. They never ask the
## Tasks module anything, so tasks → trials ← stations, one way.
##
## A concrete station is an inherited scene: it adds a [Trial] under Runner, its
## scenery as Visual, and whatever the trial needs (a Scatter on a table...).

## The [Place] id of this spot; also the fact reported on entering.
@export var place_id: StringName = &""
## The name on the sign when no task is using it.
@export var display_name := ""
## Trial id this station runs (a file name in res://content/trials/).
@export var trial_id: StringName = &"search"
## Seconds between rounds, so feedback has time to land.
@export var gap := 1.8

@onready var place := $Place as Place
@onready var runner := $Runner as TrialRunner
@onready var sign_label := $Sign as Label3D
@onready var beacon := $Beacon as Node3D
@onready var _zone := $Zone/Shape as CollisionShape3D

var _inside := false
var _time := 0.0
## When the next round may start ([member _time]): a gap after the last one.
var _next_at := 0.0
## The goal step whose "what this trains" line has been said.
var _introduced := ""
## The goal step that wanted this station, last seen; notices a change of step.
var _wanted_step := ""
## The goal's place last seen, to notice when it moves here.
var _goal_place: StringName = &""


func _ready() -> void:
	place.id = place_id
	place.display_name = display_name
	runner.trial_id = trial_id
	Events.goal_changed.connect(_on_goal_changed)
	if runner.trial:
		runner.trial.ended.connect(_on_round_ended)
		runner.trial.abandoned.connect(func() -> void: _next_at = _time + gap)
	_wanted_step = _wanted_key()
	_goal_place = Events.goal.place
	_refresh()


## The goal names this station's trial.
func is_wanted() -> bool:
	return Events.goal.trial == trial_id


## The child's head is in the zone.
func is_occupied() -> bool:
	return _inside


func trial() -> Trial:
	return runner.trial


func _physics_process(delta: float) -> void:
	_time += delta
	var inside := _head_inside()
	if inside != _inside:
		_inside = inside
		if inside:
			Events.report(&"entered", place_id)
			_enter_zone()
		else:
			_leave_zone()
		_refresh()
	_tick()
	if beacon.visible:
		var pulse := 1.0 + 0.12 * sin(_time * 2.2)
		beacon.scale = Vector3(pulse, 1.0, pulse)


## Starts what should run next, if anything should: the child is here, rounds
## are wanted, none is out, the gap is over and nobody is talking.
func _tick() -> void:
	if not _inside or not is_wanted() or runner.is_running() or _time < _next_at or not Narrator.is_quiet():
		return
	if _introduced != Events.goal.key():
		_introduced = Events.goal.key()
		var visual_skill := VisualSkillDef.find(_trial_def().visual_skill if _trial_def() else &"")
		if visual_skill:
			Narrator.say("%s! %s" % [visual_skill.display_name, visual_skill.description], null, &"station")
			return # the round waits for it to be heard
	runner.run(Events.goal.done)


func _enter_zone() -> void:
	if runner.trial:
		runner.trial.hold(false)


func _leave_zone() -> void:
	if runner.is_running():
		runner.trial.hold(true) # its clock and hints wait for the child to come back


func _on_round_ended(_success: bool) -> void:
	_next_at = _time + gap
	_refresh()


func _on_goal_changed(goal: Goal) -> void:
	var wanted := _wanted_key()
	if wanted != _wanted_step:
		if not wanted.is_empty() and goal.done == 0:
			_introduced = "" # a fresh run, including an unfinished task restarted after loading
		_wanted_step = wanted
		if wanted.is_empty():
			runner.cancel() # the goal moved on or was cleared: cancel any unfinished round
		elif _inside:
			_enter_zone()
	_refresh()
	if goal.place == _goal_place:
		return
	_goal_place = goal.place
	# The goal just moved here and the child is already here: whatever is
	# waiting for them to arrive would otherwise wait for an "entered" that never
	# comes. Deferred, so everyone else hears about the goal first.
	if goal.place == place_id and _inside:
		_enter_again.call_deferred()


func _enter_again() -> void:
	if _inside and Events.goal.place == place_id:
		Events.report(&"entered", place_id)


func _wanted_key() -> String:
	return Events.goal.key() if is_wanted() else ""


func _refresh() -> void:
	if sign_label == null:
		return
	var goal := Events.goal
	beacon.visible = is_wanted() and not _inside
	var def := _trial_def()
	var lines := PackedStringArray()
	if is_wanted():
		lines.append(goal.title)
	else:
		lines.append(display_name if not display_name.is_empty() else String(place_id).capitalize())
	if def:
		lines.append("Trains: %s" % VisualSkillDef.label(def.visual_skill))
	if is_wanted():
		var left := goal.rounds_left()
		lines.append("1 more to go" if left == 1 else "%d more to go" % left)
	sign_label.text = "\n".join(lines)
	sign_label.modulate = Color(1.0, 0.95, 0.6) if is_wanted() else Color(0.92, 0.92, 0.95)


func _trial_def() -> TrialDef:
	return TrialDef.find(trial_id)


func _head_inside() -> bool:
	var player := Game.player
	if not is_instance_valid(player) or _zone == null:
		return false
	var head := player.get_node_or_null(^"Camera") as Node3D
	var at := (head if head else player).global_position
	var local := _zone.to_local(at)
	var shape := _zone.shape as CylinderShape3D
	var radius := shape.radius if shape else 1.0
	var height := shape.height if shape else 2.4
	# A little give on the way out, so leaning back does not stop the round.
	var slack := 0.25 if _inside else 0.0
	return Vector2(local.x, local.z).length() <= radius + slack and absf(local.y) <= height * 0.5 + slack
