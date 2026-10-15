class_name SoundDef
extends RefCounted
## One row of the sound table, parsed: what to play for a key and how.
##
## Built by [SoundTable] from two cells — the clips and an options string like
## [code]vol=-6 pitch=0.9-1.1 space=3d cd=0.2[/code]. Everything has a default
## that is right for a short interface sound, so the ordinary row is a key and a
## clip and nothing else.

enum Pick {
	RANDOM, ## a different one most times; the default
	CYCLE, ## strictly in turn, so a repeated press never repeats a clip
}

## Buses the module makes for itself (see Audio._build_buses). Named here
## because the table's "bus=" option is checked against them.
const BUSES: PackedStringArray = ["Voice", "Sfx", "Ambience"]

## The key this row answers to, e.g. "pressed.hello".
var key := ""
## Clips to choose from: a res:// path, or "tone:<hz>" / "tone:<hz>/<ms>" for a
## generated placeholder beep. More than one = variations.
var sources: PackedStringArray = []
var pick := Pick.RANDOM
var volume_db := 0.0
## Playback speed, drawn fresh each time between the two. Equal = no variation.
var pitch_low := 1.0
var pitch_high := 1.0
var bus: StringName = &"Sfx"
## Play at the position the fact happened, when one was reported. VR leans on
## sound to say *where* to look, so this is worth a column.
var positional := false
## Seconds before this key may sound again. Stops a child who is mashing a
## button from stacking twenty copies of the same clip.
var cooldown := 0.0
## Keep going until something stops it (level ambience).
var loop := false

var _next := 0


## One of [member sources], by [member pick].
func choose() -> String:
	if sources.is_empty():
		return ""
	if sources.size() == 1:
		return sources[0]
	if pick == Pick.CYCLE:
		_next = (_next + 1) % sources.size()
		return sources[_next]
	return sources[randi() % sources.size()]


func pitch() -> float:
	return pitch_low if is_equal_approx(pitch_low, pitch_high) else randf_range(pitch_low, pitch_high)


## Fills the row from an options string. Returns the problems found, so a typo
## is a loud table error at load instead of a setting that silently does nothing.
func parse_options(options: String) -> PackedStringArray:
	var problems := PackedStringArray()
	for token in options.split(" ", false):
		var name := token.get_slice("=", 0).strip_edges().to_lower()
		var value := token.substr(token.find("=") + 1).strip_edges() if token.contains("=") else ""
		match name:
			"vol", "volume":
				volume_db = _number(value, problems, token)
			"pitch":
				_parse_pitch(value, problems, token)
			"bus":
				var wanted := value.capitalize()
				if BUSES.has(wanted):
					bus = StringName(wanted)
				else:
					problems.append("unknown bus '%s' (one of %s)" % [value, ", ".join(BUSES).to_lower()])
			"space":
				if value == "3d":
					positional = true
				elif value != "2d":
					problems.append("space must be 2d or 3d, not '%s'" % value)
			"cd", "cooldown":
				cooldown = maxf(_number(value, problems, token), 0.0)
			"pick":
				if value == "cycle":
					pick = Pick.CYCLE
				elif value != "random":
					problems.append("pick must be random or cycle, not '%s'" % value)
			"loop":
				loop = true
			_:
				problems.append("unknown option '%s'" % name)
	return problems


func _parse_pitch(value: String, problems: PackedStringArray, token: String) -> void:
	var parts := value.split("-", false)
	pitch_low = _number(parts[0], problems, token) if parts.size() > 0 else 1.0
	pitch_high = _number(parts[1], problems, token) if parts.size() > 1 else pitch_low
	if pitch_low <= 0.0 or pitch_high < pitch_low:
		problems.append("pitch '%s' must be a positive number, or low-high" % value)
		pitch_low = 1.0
		pitch_high = 1.0


func _number(value: String, problems: PackedStringArray, token: String) -> float:
	if not value.is_valid_float():
		problems.append("'%s' needs a number" % token)
		return 0.0
	return value.to_float()
