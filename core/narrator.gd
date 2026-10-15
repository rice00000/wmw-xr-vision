extends Node
## Narrator (autoload "Narrator"): the one queue of everything the guide says.
##
## Every line — a task's instruction, a station's "what this trains", a round's
## "Find the cup", the reward — goes through [method say], and comes out one at a
## time, in order. The subtitle shows [member current] and the Audio module speaks
## [member current]; neither keeps a queue or a clock of its own, so what is read
## and what is heard are always the same line.
##
## [b]When a line is over:[/b] when it has been on screen long enough to read
## ([member read_pace]) [i]and[/i] the speaker has said it is done. Audio claims a
## line it speaks ([method speaking]) and hands it back when the recording or the
## text-to-speech utterance really ends ([method spoken]). With Audio off, no
## speech engine, or read-aloud switched off, the reading time alone decides.
##
## [b]Pause[/b] (the wrist menu, the headset's own menu): the line on show stops,
## subtitle and voice together, and starts again from its beginning when the
## world runs again — unless it went out of date meanwhile (see topics), when
## it is simply dropped. Lines said meanwhile wait their turn.
##
## [b]Topics:[/b] a line can speak for someone (&"task", &"station", &"trial"). A
## new line on a topic replaces one on that topic still waiting, and the line
## being said right now is not queued a second time, so pressing "what should I
## do?" five times says it once, and a task that has moved on never says its old
## instruction late. The line being said when its topic moves on finishes, but is
## never started again after a pause.
##
## Anyone who must not talk over the guide (a station about to start a round)
## waits with [code]await Narrator.wait_quiet()[/code] instead of guessing how long
## a line takes.

## A line started: show it, say it.
signal line_started(line: VoiceLine)
## A line is over, or was dropped ([method clear]).
signal line_ended(line: VoiceLine)
## Nothing is being said and nothing is waiting.
signal quiet
## The world paused or ran again; [member current] stops and restarts with it.
signal paused_changed(paused: bool)

## Seconds of reading time per character, and the least a line stays up. The
## smoke test turns these down so it does not sit through every line.
var read_pace := 0.06
var min_seconds := 2.0
## Longest a speaker may hold a line past its reading time, in case it never
## reports back.
var speaker_grace := 30.0

## The line being said, or null.
var current: VoiceLine

var _queue: Array[VoiceLine] = []
var _elapsed := 0.0
var _read_time := 0.0
var _speaking := false
var _paused := false
## [member current] is out of date: a newer line on its topic came, or its topic
## was dropped.
var _stale := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # it has to notice the pause from inside it
	Events.level_changing.connect(func(_path: String) -> void: clear())
	Events.profile_closing.connect(clear)


## Queues [param text] (with [param voice], a recording, when there is one).
func say(text: String, voice: AudioStream = null, topic: StringName = &"") -> void:
	if text.is_empty():
		return
	if not topic.is_empty():
		drop(topic)
		if current and current.topic == topic and current.text == text:
			return
		_stale = _stale or (current != null and current.topic == topic)
	_queue.append(VoiceLine.new(text, voice, topic))
	if current == null and not _paused:
		_next()


## Forgets the lines on [param topic] still waiting. The one being said finishes,
## and is not started again after a pause.
func drop(topic: StringName) -> void:
	_queue = _queue.filter(func(line: VoiceLine) -> bool: return line.topic != topic)
	_stale = _stale or (current != null and current.topic == topic)


## Stops the line being said and forgets every waiting one: a new level, another
## player, start over.
func clear() -> void:
	_queue.clear()
	if current:
		var line := current
		current = null
		line_ended.emit(line)
	quiet.emit()


func is_quiet() -> bool:
	return current == null and _queue.is_empty()


func is_paused() -> bool:
	return _paused


## Returns once nothing is being said and nothing is waiting.
func wait_quiet() -> void:
	while not is_quiet():
		await quiet


## The speaker is saying [param line] and will call [method spoken] when done.
func speaking(line: VoiceLine) -> void:
	if line == current:
		_speaking = true


## The speaker has finished [param line] (or could not say it).
func spoken(line: VoiceLine) -> void:
	if line == current:
		_speaking = false


func _process(delta: float) -> void:
	var paused := get_tree().paused
	if paused != _paused:
		_paused = paused
		_speaking = false
		paused_changed.emit(paused)
		if not paused:
			if current and not _stale:
				_start(current) # from the top: half a sentence before the pause is not worth keeping
			elif current:
				_finish()
			else:
				_next()
	if _paused or current == null:
		return
	_elapsed += delta
	if _elapsed >= _read_time and (not _speaking or _elapsed >= _read_time + speaker_grace):
		_finish()


func _finish() -> void:
	var line := current
	current = null
	line_ended.emit(line)
	_next()


func _next() -> void:
	if _queue.is_empty():
		quiet.emit()
		return
	current = _queue.pop_front()
	_start(current)


func _start(line: VoiceLine) -> void:
	_elapsed = 0.0
	_speaking = false
	_stale = false
	_read_time = maxf(min_seconds, line.text.length() * read_pace)
	line_started.emit(line)
