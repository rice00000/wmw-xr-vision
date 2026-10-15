class_name SoundTable
extends RefCounted
## The sound table: one tab-separated file mapping what happened to what to play.
##
## Keys are dotted and fall back, so one row covers a whole family and a later
## row overrides one member of it:
## [codeblock]
## pressed              tone:520/70    every button in the game
## pressed.hello        tone:700/90    except this one
## pressed.dbg_up       -              and this one makes no sound at all
## [/codeblock]
## Looking up [code]pressed.dbg_up[/code] stops at the dash (silent); looking up
## [code]pressed.anything_else[/code] falls back to [code]pressed[/code]. A row
## with an empty clip cell is a placeholder for whoever is filling the table in:
## it means "still inherit", not "silent".
##
## Tab-separated rather than a .tres per sound, unlike the rest of content/,
## because this is fifty one-line rows that an artist edits in a spreadsheet,
## not a handful of substantial objects. Lines starting with # are notes.
##
## Everything that can be wrong with a row is collected in [member errors] at
## load: an unknown option, a clip file that is not there, a duplicate key. The
## module prints them and the test suite fails on them, so the table can never
## quietly say something untrue.

## A key answered with this plays nothing, and stops the fallback walk.
const SILENT := "-"
## Generated placeholder beep, "tone:<hz>" or "tone:<hz>/<milliseconds>". Lets
## the whole system be wired up and demonstrated before a clip is recorded.
## Notes joined by "+" play one after another, and a 0 Hz note is a rest, so a
## placeholder can have a rhythm: "tone:660/90+880/90+1175/200" is a quick
## rising three-note "yes", "tone:330/220+0/60+262/360" a slow falling "oh-oh".
## Feedback is never told apart by pitch alone.
const TONE := "tone:"

var rows: Dictionary[String, SoundDef] = {}
var errors: PackedStringArray = []

var _silenced: Dictionary[String, bool] = {}
var _cache: Dictionary[String, Variant] = {}


static func from_file(path: String) -> SoundTable:
	var table := SoundTable.new()
	if not FileAccess.file_exists(path):
		table.errors.append("%s: no such file" % path)
		return table
	table.parse(FileAccess.get_file_as_string(path), path.get_file())
	return table


func parse(text: String, source := "sounds.tsv") -> void:
	rows.clear()
	_cache.clear()
	var key_column := -1
	var sound_column := -1
	var options_column := -1
	var lines := text.split("\n")
	for index in lines.size():
		var line := lines[index].trim_suffix("\r").trim_prefix("﻿")
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#"):
			continue
		var cells := line.split("\t")
		for i in cells.size():
			cells[i] = cells[i].strip_edges()
		if key_column < 0:
			key_column = _column(cells, "key")
			sound_column = _column(cells, "sound")
			options_column = _column(cells, "options")
			if key_column < 0 or sound_column < 0:
				errors.append("%s:%d header needs 'key' and 'sound' columns" % [source, index + 1])
				return
			continue
		_add(_cell(cells, key_column), _cell(cells, sound_column),
			_cell(cells, options_column), "%s:%d" % [source, index + 1])


## The row that answers [param key], walking up the dotted fallback.
## Null means no row anywhere along the chain (an unmapped key, which the module
## reports once); a row whose clip cell is "-" answers with null too, but
## deliberately — use [method is_silenced] to tell the two apart.
func lookup(key: String) -> SoundDef:
	var found: Variant = _resolve(key)
	return found as SoundDef if found is SoundDef else null


## True when a row along the chain said "-": this key is meant to be quiet.
func is_silenced(key: String) -> bool:
	return _resolve(key) == SILENT


func _resolve(key: String) -> Variant:
	if _cache.has(key):
		return _cache[key]
	var answer: Variant = null
	var current := key
	while true:
		if rows.has(current):
			answer = rows[current]
			break
		if _silenced.has(current):
			answer = SILENT
			break
		var dot := current.rfind(".")
		if dot < 0:
			break
		current = current.left(dot)
	_cache[key] = answer
	return answer


func _add(key: String, sound: String, options: String, where: String) -> void:
	if key.is_empty():
		return
	if key.contains(" ") or key.begins_with(".") or key.ends_with("."):
		errors.append("%s: '%s' is not a usable key" % [where, key])
		return
	if rows.has(key) or _silenced.has(key):
		errors.append("%s: '%s' appears twice" % [where, key])
		return
	if sound == SILENT:
		_silenced[key] = true
		return
	if sound.is_empty():
		return # a placeholder row: still falls back, and says so to whoever fills it in
	var def := SoundDef.new()
	def.key = key
	for problem in def.parse_options(options):
		errors.append("%s [%s]: %s" % [where, key, problem])
	for raw in sound.split("|", false):
		var clip := raw.strip_edges()
		if clip.begins_with(TONE):
			if tone_notes(clip).is_empty():
				errors.append("%s [%s]: '%s' should be tone:<hz>, tone:<hz>/<ms>, or notes joined by +" % [where, key, clip])
				continue
		elif not ResourceLoader.exists(clip):
			errors.append("%s [%s]: no clip at %s" % [where, key, clip])
			continue
		def.sources.append(clip)
	if def.sources.is_empty():
		return
	rows[key] = def


## The notes of a "tone:" source as (hz, milliseconds), in order; 0 Hz is a
## rest. Empty when the source is malformed or has nothing audible in it.
static func tone_notes(source: String) -> Array[Vector2]:
	var notes: Array[Vector2] = []
	var audible := false
	for part in source.trim_prefix(TONE).split("+"):
		var hz_text := part.get_slice("/", 0).strip_edges()
		var ms_text := part.get_slice("/", 1).strip_edges() if part.contains("/") else "120"
		if not hz_text.is_valid_float() or not ms_text.is_valid_float():
			return []
		var hz := hz_text.to_float()
		var ms := ms_text.to_float()
		if hz < 0.0 or ms <= 0.0:
			return []
		audible = audible or hz > 0.0
		notes.append(Vector2(hz, ms))
	if not audible:
		notes.clear()
	return notes


static func _column(header: PackedStringArray, name: String) -> int:
	for i in header.size():
		if header[i].to_lower() == name:
			return i
	return -1


static func _cell(cells: PackedStringArray, column: int) -> String:
	return cells[column] if column >= 0 and column < cells.size() else ""
