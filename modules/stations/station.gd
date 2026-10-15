class_name Station
extends Node3D
## A fixed spot where measured training happens: a [Place], a zone you sit down
## in, a [TrialRunner] with its [Trial], a sign and a beacon. Drop one into any
## level; nothing else has to know it is there.
##
## [b]Idle[/b] until someone wants its trial ([signal Events.trial_requested]).
## Then the beacon goes up, tall and soft, so it can be found from across the
## island, and the sign shows what the rounds are for (the request's title), the
## skill it trains and how many rounds are still to go.
## Rounds start only once the child's head is in the zone; stick walking goes off
## while they sit (teleport still works), and the station says once what the
## practice is for. Standing up stops after the round in progress; sitting down
## again carries on, and the rounds count across visits. When the budget is spent
## the runner reports "finished:<trial>", the task moves on and the station goes
## idle again. A request sent again with [code]rounds = -1[/code] withdraws it.
##
## With [member auto_start] it also runs endless free-play rounds whenever someone
## sits down and nobody is asking (the Test Room, F6 on a level).
##
## Every station reports "entered:<place id>" when a head comes in, idle or not,
## so a task step can send the child here without running anything — and again
## when the goal moves here ([signal Events.goal_changed]) with the child already
## sitting, or a step waiting for them to arrive would wait for ever.
##
## [b]Layers:[/b] stations sit on top of trials (modules/trials/) and talk to
## everything else only through [Events]. They never ask the Tasks module
## anything, so tasks → trials ← stations, one way.
##
## A concrete station is an inherited scene: it adds a [Trial] under Runner, its
## scenery as Visual, and whatever the trial needs (a Scatter on a table...).

## The [Place] id of this spot; also the fact reported on entering.
@export var place_id: StringName = &""
## The name on the sign when no task is using it.
@export var display_name := ""
## Trial id this station runs (a file name in res://content/trials/).
@export var trial_id: StringName = &"search"
## Run free-play rounds for anyone who sits down, task or no task.
@export var auto_start := false
## Switch stick walking off while rounds run here.
@export var seated := true
## Seconds between rounds.
@export var gap := 1.8

## About how long a line takes to be heard, in ms per character. The station
## waits for every line it has heard to be over before it speaks or starts the
## first round, so neither cuts a line off. The smoke test turns it down.
static var line_pace := 65

@onready var place := $Place as Place
@onready var runner := $Runner as TrialRunner
@onready var sign_label := $Sign as Label3D
@onready var beacon := $Beacon as Node3D
@onready var _zone := $Zone/Shape as CollisionShape3D

var _wanted := false
var _inside := false
var _told := false
var _walking_off := false
var _time := 0.0
## What the rounds are for, from the request ("Find It").
var _title := ""
## The goal's place last announced, to notice when it moves here.
var _goal_place: StringName = &""
## When the last line heard on the bus will be over (ticks, ms).
var _quiet_at := 0
## Bumped on every sit-down and stand-up, so a wait that outlived its sitting
## does nothing.
var _seat := 0


func _ready() -> void:
	place.id = place_id
	place.display_name = display_name
	runner.auto_start = false
	runner.configure(trial_id) # the runner was ready first, with its own default id
	runner.gap = gap
	Events.trial_requested.connect(_on_requested)
	Events.reported.connect(_on_reported)
	Events.goal_changed.connect(_on_goal_changed)
	Events.instruction.connect(_on_line)
	if runner.trial:
		runner.trial.ended.connect(func(_success: bool) -> void: _refresh())
	if auto_start:
		runner.budget(0)
	_refresh()


func _exit_tree() -> void:
	_set_walking(true)


## A task has asked for rounds here and they are not all done yet.
func is_wanted() -> bool:
	return _wanted


## The child's head is in the zone.
func is_occupied() -> bool:
	return _inside


func trial() -> Trial:
	return runner.trial


## Rounds would run here if someone sat down.
func is_active() -> bool:
	return _wanted or auto_start


func _physics_process(delta: float) -> void:
	_time += delta
	var inside := _head_inside()
	if inside != _inside:
		_inside = inside
		if inside:
			Events.report(&"entered", place_id)
			_sit()
		else:
			_stand()
		_refresh()
	if beacon.visible:
		var pulse := 1.0 + 0.12 * sin(_time * 2.2)
		beacon.scale = Vector3(pulse, 1.0, pulse)


func _sit() -> void:
	if runner.trial:
		runner.trial.hold(false)
	if not is_active():
		return
	if seated:
		_set_walking(false)
	_seat += 1
	_after_lines(_speak.bind(_seat))


## Once nobody is talking: say what this trains (once per request), then, once
## that has been heard, start the rounds.
func _speak(seat: int) -> void:
	if seat != _seat or not _inside or not is_active():
		return
	if _wanted and not _told:
		_told = true
		var skill := SkillDef.find(_trial_def().skill if _trial_def() else &"")
		if skill:
			Events.say("%s! %s" % [skill.display_name, skill.description])
	_after_lines(_run.bind(seat))


func _run(seat: int) -> void:
	if seat == _seat and _inside and is_active():
		runner.start()


## Calls [param then] once every line heard so far is over. Looks again when the
## wait is up, because more may have been said meanwhile (the next instruction
## queued behind a reward line).
func _after_lines(then: Callable) -> void:
	var wait := (_quiet_at - Time.get_ticks_msec()) / 1000.0
	if wait <= 0.0:
		then.call()
		return
	get_tree().create_timer(wait + 0.25, false).timeout.connect(_after_lines.bind(then))


func _on_line(text: String, _voice: AudioStream) -> void:
	if text.is_empty():
		return
	var length := clampi(text.length() * line_pace, 30 * line_pace, 110 * line_pace)
	_quiet_at = maxi(_quiet_at, Time.get_ticks_msec() + length)


func _stand() -> void:
	_seat += 1
	runner.stop()
	if runner.trial and runner.trial.is_running():
		runner.trial.hold(true) # its clock and hints wait for the child to come back
	_set_walking(true)


func _on_goal_changed(_text: String, place: StringName) -> void:
	_refresh()
	if place == _goal_place:
		return
	_goal_place = place
	# The goal just moved here and the child is already sitting here: whatever is
	# waiting for them to arrive would otherwise wait for an "entered" that never
	# comes. Deferred, so the announcement finishes first.
	if place == place_id and _inside:
		_enter_again.call_deferred()


func _enter_again() -> void:
	if _inside and _goal_place == place_id:
		Events.report(&"entered", place_id)


func _on_requested(requested: StringName, count: int, title: String) -> void:
	if requested != trial_id:
		return
	if count < 0:
		_wanted = false
		_told = false
		_title = ""
		if auto_start:
			runner.budget(0)
		else:
			runner.cancel() # the task was dropped: the round in progress is nobody's
			_set_walking(true)
		_refresh()
		return
	_wanted = true
	_title = title
	runner.budget(count)
	if _inside:
		_sit()
	_refresh()


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what != &"finished" or id != trial_id:
		return
	_wanted = false
	_told = false
	_title = ""
	if auto_start:
		runner.budget(0)
		if _inside:
			runner.start()
	else:
		runner.stop()
		_set_walking(true)
	_refresh()


func _refresh() -> void:
	if sign_label == null:
		return
	beacon.visible = _wanted and not _inside
	var def := _trial_def()
	var lines := PackedStringArray()
	if _wanted and not _title.is_empty():
		lines.append(_title)
	elif _wanted and def:
		lines.append(def.title)
	else:
		lines.append(display_name if not display_name.is_empty() else String(place_id).capitalize())
	if def:
		lines.append("Trains: %s" % SkillDef.label(def.skill))
	if _wanted and runner.rounds_left() >= 0:
		var left := runner.rounds_left()
		lines.append("1 more to go" if left == 1 else "%d more to go" % left)
	elif auto_start:
		lines.append("Free play")
	sign_label.text = "\n".join(lines)
	sign_label.modulate = Color(1.0, 0.95, 0.6) if _wanted else Color(0.92, 0.92, 0.95)


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


## Duck-typed like [method Level._set_walking]: a rig without a Locomotion node
## simply has nothing to switch.
func _set_walking(on: bool) -> void:
	if on == not _walking_off:
		return
	_walking_off = not on
	if not is_instance_valid(Game.player):
		return
	var walking := Game.player.get_node_or_null(^"Locomotion")
	if walking and &"enabled" in walking:
		walking.enabled = on
