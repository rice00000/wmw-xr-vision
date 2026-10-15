extends ModuleCheck
## Vision: a spirit ability really re-grades the world, not just the sign.

@export var profile: VisionProfile


func _arm() -> void:
	var orb := preload("res://modules/vision/vision_orb.tscn").instantiate() as VisionOrb
	orb.profile = profile
	orb.id = &"selftest_spirit"
	orb.touched.connect(_on_orb)
	add_prop(orb, Vector3(0.0, 0.3, 0.0))
	update("world: as the room made it")


func _on_orb(_hand: Node3D) -> void:
	# The orb already toggled the profile; read what actually reached the screen.
	var env := get_viewport().find_world_3d().environment
	if env == null:
		fail_now("this room has no Environment to grade")
		return
	var on: bool = mod().profile != null
	var graded := env.adjustment_enabled and not is_equal_approx(env.adjustment_contrast, 1.0)
	var trace := "contrast %.2f, spirit %s" % [env.adjustment_contrast, "on" if on else "off"]
	if on and graded:
		pass_now(trace)
	elif not on:
		update("%s  (touch it again to switch back on)" % trace)
	else:
		fail_now("%s  (nothing reached the screen)" % trace)


func auto() -> void:
	if mod().profile != null:
		mod().apply(null)
	for child in _props.get_children():
		if child is VisionOrb:
			(child as VisionOrb).touch(null)
