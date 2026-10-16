extends Node
## Audio module (autoload "Audio"): everything the game can be heard doing.
##
## [b]Nothing outside this file touches an audio node[/b], and nothing outside
## this file names a sound. Gameplay code reports what happened — it already
## does, on [Events] — and this module looks the answer up in one table:
## [code]content/audio/sounds.tsv[/code]. Adding or changing a sound is editing
## a spreadsheet; there is no per-button, per-creature or per-door audio code
## anywhere, and there is nowhere to put any.
##
## [b]Keys[/b] are made from the bus, so the table's left column is a list of
## things that happen in the game:
## [codeblock]
## Events.report(&"pressed", &"hello")     ->  pressed.hello  ->  pressed
## Events.report(&"caught", &"butterfly")  ->  caught.butterfly
## Events.reward_granted(&"magic_stone")   ->  reward.magic_stone
## Events.task_completed(&"find_it")       ->  task.completed.find_it
## Events.trial_ended(&"search", true)     ->  trial.ended.search.hit
## Events.level_changed(island)            ->  ambience.island     (a loop)
## [/codeblock]
## Keys fall back along the dots, so one [code]pressed[/code] row gives every
## button in the game a sound and a later row overrides one of them. See
## [SoundTable].
##
## [b]Two seams stay[/b] for sound the table cannot name: a Narrator line can
## carry the guide's recording, and [method Events.play_at] plays a stream a task
## is holding.
##
## [b]Before any audio is recorded[/b], a clip cell can say [code]tone:660[/code]
## and get a generated beep. That is how the whole system is demonstrable and
## testable today, and swapping in a real clip later is editing one cell.
##
## [b]The guide's voice[/b] is the Narrator's current line and nothing else:
## this module speaks [member Narrator.current] when it starts (its recording, or
## baked speech while the [code]read_aloud[/code] setting is on), tells the
## Narrator when it has really finished, and stops when the world pauses. It
## keeps no queue, so it cannot get ahead of or behind the subtitle.
## [br][signal Events.read_aloud] (a menu button being pointed at; a new one cuts
## off the one before) is spoken too, but never over the guide: while the world
## runs and a line is being said, it is skipped. Many of the children this is for
## read poorly, so nothing on screen should exist only as text. [member speech]
## records each request, so a test can see it arrive with no audio device present.
##
## [b]Volumes[/b] follow [Settings] live: [code]volume_master[/code] on the
## Master bus, [code]volume_voice[/code] on the Voice bus and on speech.
##
## Runs while the tree is paused (the wrist menu pauses it), or the menu's
## clicks and read-aloud would be silent.
##
## Switch this autoload off and the game is silent and otherwise unchanged.

const TABLE_PATH := "res://content/audio/sounds.tsv"
## Non-positional players, for interface sounds and the guide.
const FLAT_VOICES := 6
## Positional players. The design leans on sound to say *where* to look, so
## there are more of these than of the flat ones.
const SPATIAL_VOICES := 8
## How far the Sfx bus drops while the guide is speaking. The guide's line is
## the one thing a child must not miss, so this is a rule of the project rather
## than a per-sound setting nobody would fill in.
const DUCK_DB := -9.0
const AMBIENCE_FADE := 0.8
## How often the table is re-read while running from the editor.
const RELOAD_SECONDS := 1.0
const TONE_RATE := 22050

## Recorded lines and sounds started since launch. A test can say "the sound
## reached the seam" from these with no audio device.
var spoken := 0
var cued := 0

var table: SoundTable
## Keys the game sent that no row answers. Printed once each while running from
## the editor, and failed by the smoke test, so the table can never quietly fall
## behind the game.
var unmapped: Dictionary[String, bool] = {}
## "<key> -> <clip>" for everything played, newest last. Lets a test name the
## sound a fact produced; capped so a long session cannot grow without bound.
var played: PackedStringArray = []
## Every baked-speech request since launch, newest last, as "say: <text>"
## (the Narrator's line) or "read: <text>" (read aloud).
## Recorded whether or not an audio device is present, so the headless suite can
## assert that a line reached the seam. Capped like [member played].
var speech: PackedStringArray = []

var _guide := AudioStreamPlayer.new()
var _reader := AudioStreamPlayer.new()
## The Narrator line being spoken, and whether its voice was generated.
var _line: VoiceLine
var _generated_line := false
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _started_ms: Dictionary[int, int] = {} # player id -> when it started
var _cooldowns: Dictionary[String, int] = {} # row key -> when it may sound again
var _tones: Dictionary[String, AudioStreamWAV] = {}
var _ambience: AudioStreamPlayer
var _ambience_key := ""
var _table_time := 0
var _since_reload := 0.0
var _verbose := false
var _ducked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the wrist menu pauses the tree and still has to be heard
	_verbose = OS.has_feature("editor") and DisplayServer.get_name() != "headless"
	_build_buses()
	_apply_volumes()
	Settings.changed.connect(_on_setting_changed)
	_guide.bus = &"Voice"
	add_child(_guide)
	_guide.finished.connect(_on_line_done)
	_reader.bus = &"Voice"
	add_child(_reader)
	for _i in FLAT_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat.append(player)
	for _i in SPATIAL_VOICES:
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		_spatial.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	add_child(_ambience)
	reload()
	Narrator.line_started.connect(_on_line_started)
	Narrator.line_ended.connect(_on_line_ended)
	Narrator.paused_changed.connect(func(paused: bool) -> void:
		_hush()
		if not paused:
			_reader.stop())
	Events.profile_closing.connect(_reader.stop)
	Events.read_aloud.connect(_on_read_aloud)
	Events.feedback.connect(_on_feedback)
	Events.cue.connect(_on_stream_cue)
	Events.reported.connect(_on_reported)
	Events.reward_granted.connect(_on_reward)
	Events.task_started.connect(func(id: StringName) -> void: cue("task.started.%s" % id))
	Events.task_completed.connect(func(id: StringName) -> void: cue("task.completed.%s" % id))
	Events.trial_started.connect(_on_trial_started)
	Events.trial_ended.connect(_on_trial_ended)
	Events.level_changed.connect(_on_level_changed)


## Re-reads the table. Problems are printed, kept in [member SoundTable.errors]
## and asserted by the test suite, so a typo is never a sound that silently
## does nothing.
func reload() -> void:
	table = SoundTable.from_file(TABLE_PATH)
	_table_time = FileAccess.get_modified_time(TABLE_PATH)
	unmapped.clear()
	for problem in table.errors:
		push_warning("[Audio] %s" % problem)


## Play whatever the table says this key means. [param position] is where the
## fact happened, used only by rows marked [code]space=3d[/code].
func cue(key: String, position: Variant = null) -> void:
	var def := table.lookup(key)
	if def == null:
		if not table.is_silenced(key) and not unmapped.has(key):
			unmapped[key] = true
			if _verbose:
				print("AUDIO_UNMAPPED: %s" % key)
		return
	var now := Time.get_ticks_msec()
	# Keyed by the row, not the key asked for: a child rattling through several
	# buttons shares one cooldown, which is the point of having one.
	if def.cooldown > 0.0 and now < _cooldowns.get(def.key, 0):
		return
	_cooldowns[def.key] = now + roundi(def.cooldown * 1000.0)
	var source := def.choose()
	var stream := _stream(source)
	if stream == null:
		return
	if def.loop:
		_play_ambience(key, stream, def)
		return
	_play(stream, def, position if position is Vector3 else null)
	_note(key, source)


## True while anything is sounding.
func is_playing() -> bool:
	if _guide.playing or _reader.playing or _ambience.playing:
		return true
	for player in _flat:
		if player.playing:
			return true
	for player in _spatial:
		if player.playing:
			return true
	return false


## A short beep built in code: 16-bit mono, faded out so it does not click.
## This is what makes the table usable before a single clip is recorded.
static func tone(hz := 660.0, milliseconds := 120.0) -> AudioStreamWAV:
	return melody([Vector2(hz, milliseconds)])


## Beeps one after another, each (hz, milliseconds); 0 Hz is a rest. Rhythm is
## what lets two placeholder sounds differ by more than pitch.
static func melody(notes: Array[Vector2]) -> AudioStreamWAV:
	var data := PackedByteArray()
	for note in notes:
		var frames := maxi(int(TONE_RATE * note.y / 1000.0), 1)
		var start := data.size()
		data.resize(start + frames * 2) # new bytes are zero: a rest is just this
		if note.x <= 0.0:
			continue
		for i in frames:
			var fade := 1.0 - float(i) / frames
			data.encode_s16(start + i * 2, roundi(sin(TAU * note.x * i / TONE_RATE) * 12000.0 * fade))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TONE_RATE
	wav.stereo = false
	wav.data = data
	return wav


# -- the bus ----------------------------------------------------------------

func _on_reported(what: StringName, id: StringName, data: Dictionary) -> void:
	cue("%s.%s" % [what, id] if not id.is_empty() else String(what), data.get("position"))


func _on_reward(item_id: StringName, _amount: int) -> void:
	cue("reward.%s" % item_id)


func _on_trial_started(trial: StringName, _condition: Dictionary) -> void:
	cue("trial.started.%s" % trial)


func _on_trial_ended(visual_skill: StringName, success: bool, _data: Dictionary) -> void:
	cue("trial.ended.%s.%s" % [visual_skill, "hit" if success else "miss"])


## One looping bed per level, named ambience.<level id>. The loop a level starts
## is stopped when the next level comes up, so no row has to say "stop".
func _on_level_changed(level: Node) -> void:
	var id: Variant = level.get(&"level_id") if level else null
	cue("ambience.%s" % id if id != null else "ambience")


## "feedback.good", "feedback.bad", "feedback.reward": one row each, played
## where the judged thing is.
func _on_feedback(kind: StringName, position: Vector3) -> void:
	cue("feedback.%s" % kind, position)


func _on_line_started(line: VoiceLine) -> void:
	_hush()
	_reader.stop()
	_generated_line = line.voice == null
	var voice := line.voice if line.voice else _speech_stream("say", line.text)
	if voice == null:
		return
	spoken += 1
	_line = line
	_guide.stream = voice
	_guide.play()
	_duck(true)
	Narrator.speaking(line)


## Dropped before its end (a new level, another player): stop saying it.
func _on_line_ended(line: VoiceLine) -> void:
	if line == _line:
		_hush()


## A recorded or baked line has finished playing.
func _on_line_done() -> void:
	if _line:
		var line := _line
		_line = null
		Narrator.spoken(line)


## Stops the guide's line without reporting it done: the Narrator decides what
## happens to it (it restarts after a pause).
func _hush() -> void:
	if _line == null:
		return
	_line = null
	if _guide.playing:
		_guide.stop()


## A stream a task is holding, played where it happened. Kept because a task can
## own a clip the table never named — a recorded object name, say.
func _on_stream_cue(sound: AudioStream, position: Vector3) -> void:
	if sound == null:
		return
	var def := SoundDef.new()
	def.positional = true
	_play(sound, def, position)
	_note("play_at", "(stream)")


## A menu label being pointed at, or anything else that wants reading out
## without a subtitle. Cuts off whatever was being read, so pointing along a
## row of buttons reads the one the finger is on now, not a backlog. Never cuts
## off the guide: skipped while a line is being said and the world runs.
func _on_read_aloud(text: String) -> void:
	if text.is_empty() or (Narrator.current != null and not Narrator.is_paused()):
		return
	var voice := _speech_stream("read", text)
	if voice:
		_reader.stream = voice
		_reader.play()


# -- speech -----------------------------------------------------------------

## Resolves text to existing audio files. No synthesis occurs during gameplay.
func _speech_stream(kind: String, text: String) -> AudioStream:
	if not Settings.value(&"read_aloud"):
		return null
	if speech.size() >= 200:
		speech = speech.slice(100)
	speech.append("%s: %s" % [kind, text])
	return BakedSpeech.stream(text)


# -- playing ----------------------------------------------------------------

func _play(stream: AudioStream, def: SoundDef, position: Variant) -> void:
	cued += 1
	if def.positional and position is Vector3:
		var player := _free_spatial()
		player.bus = def.bus
		player.volume_db = def.volume_db
		player.pitch_scale = def.pitch()
		player.global_position = position
		player.stream = stream
		player.play()
		_started_ms[player.get_instance_id()] = Time.get_ticks_msec()
		return
	var flat := _free_flat()
	flat.bus = def.bus
	flat.volume_db = def.volume_db
	flat.pitch_scale = def.pitch()
	flat.stream = stream
	flat.play()
	_started_ms[flat.get_instance_id()] = Time.get_ticks_msec()


func _play_ambience(key: String, stream: AudioStream, def: SoundDef) -> void:
	if _ambience_key == key:
		return
	_ambience_key = key
	cued += 1
	_ambience.stream = stream
	_ambience.volume_db = def.volume_db
	_ambience.play()
	_note(key, "(loop)")


## Everything else steps back while a recorded or baked voice plays.
func _duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	var sfx := AudioServer.get_bus_index("Sfx")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, DUCK_DB if on else 0.0)


func _free_flat() -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = _flat[0]
	for player in _flat:
		if not player.playing:
			return player
		if _started_ms.get(player.get_instance_id(), 0) < _started_ms.get(oldest.get_instance_id(), 0):
			oldest = player
	return oldest


func _free_spatial() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = _spatial[0]
	for player in _spatial:
		if not player.playing:
			return player
		if _started_ms.get(player.get_instance_id(), 0) < _started_ms.get(oldest.get_instance_id(), 0):
			oldest = player
	return oldest


## A clip path or a "tone:" spec, loaded once and kept.
func _stream(source: String) -> AudioStream:
	if source.is_empty():
		return null
	if source.begins_with(SoundTable.TONE):
		if not _tones.has(source):
			_tones[source] = melody(SoundTable.tone_notes(source))
		return _tones[source]
	return load(source) as AudioStream


func _note(key: String, source: String) -> void:
	if played.size() >= 200:
		played = played.slice(100)
	played.append("%s -> %s" % [key, source])


# -- housekeeping -----------------------------------------------------------

## Three buses, made here rather than in a bus layout file, so the module stays
## zero-config and works the same headless.
func _build_buses() -> void:
	for name in SoundDef.BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, &"Master")


func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"volume_master", &"volume_voice":
			_apply_volumes()
		&"read_aloud":
			if not value:
				_reader.stop()
			if not value and _line and _generated_line:
				var line := _line
				_hush()
				Narrator.spoken(line) # nothing left to wait for: reading time alone


func _apply_volumes() -> void:
	_set_bus_volume(&"Master", Settings.value(&"volume_master"))
	_set_bus_volume(&"Voice", Settings.value(&"volume_voice"))


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


## Saving the table takes effect within a second while running from the editor,
## so a sound can be tuned without restarting the game.
func _process(delta: float) -> void:
	_duck(_guide.playing or _reader.playing)
	if not _verbose:
		return
	_since_reload += delta
	if _since_reload < RELOAD_SECONDS:
		return
	_since_reload = 0.0
	if FileAccess.get_modified_time(TABLE_PATH) != _table_time:
		reload()
		print("AUDIO_TABLE_RELOADED: %d rows, %d problems" % [table.rows.size(), table.errors.size()])
