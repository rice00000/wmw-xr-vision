extends ModuleCheck
## Audio, the seam: a spoken line and a sound at a place both come out.
##
## Read off the Audio module's own counters, so it is the same answer in the
## headset and on a headless machine with no audio device; the note then says
## whether it is actually sounding. The beep is generated rather than loaded,
## which is the point of having the seam before anything is recorded.

var _beep: AudioStream


func _arm() -> void:
	_beep = mod().tone(660.0, 300.0) # through the module, so unticking it leaves this station loadable
	add_button(&"say", "Say +\nbeep")
	update("nothing played yet")


func _on_press(id: StringName) -> void:
	if id != &"say":
		return
	update("waiting for the guide to finish talking")
	await Narrator.wait_quiet() # a line is said in its turn, never over another
	var spoken_before: int = mod().spoken
	var cued_before: int = mod().cued
	Narrator.say("Audio test: a beep should come from your right.", _beep)
	Events.play_at(_beep, global_position + Vector3(0.6, 1.2, 0.0))
	var said: bool = mod().spoken == spoken_before + 1
	var heard: bool = mod().cued > cued_before
	var trace := "clips %d, sounds %d, %s" % [
		mod().spoken, mod().cued, "sounding" if mod().is_playing() else "silent (no audio device?)"
	]
	if said and heard:
		pass_now(trace)
	else:
		fail_now(trace)


func auto() -> void:
	await _on_press(&"say")
