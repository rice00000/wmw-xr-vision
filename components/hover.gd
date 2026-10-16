class_name Hover
extends RefCounted
## The one look every interactable thing has when a hand can use it: grabbables,
## touch buttons, creatures, the wrist menu. Call [method set_hovered] with true when a
## hand comes within reach and false when it leaves. Same colour, same width,
## everywhere, so "it lights up" always means "you can use this".
##
## The look is a thin shell around each mesh (drawn inside-out, a little wider
## than a [Highlight] outline), not the mesh's [code]material_overlay[/code].
## So it never takes anything away: a Highlight's green or red outline, or the
## Vision module's, stays exactly where it was underneath and is still there when
## the hand leaves. The shell is a one-instance MultiMeshInstance3D, an internal
## child of the mesh, so the MeshInstance3D lookups Highlight, Contrast and Vision
## make can never collect it. It also carries no information beyond "near your hand": in
## the search trial it lights whatever the hand is close to, target or not.
##
## Whether a node is hovered is kept as state ([method is_hovered]) even with the
## headless dummy renderer, where the shell itself is skipped, so tests can ask.

const COLOR := Color(1.0, 0.85, 0.2)
## Wider than Highlight.width, so both rims show at once.
const WIDTH := 0.024
const SHADER := preload("res://components/outline.gdshader")
const META := &"hovered"
const SHELL := &"HoverShell"

static var _material: ShaderMaterial


static func set_hovered(node: Node3D, on: bool) -> void:
	if node == null or not is_instance_valid(node) or is_hovered(node) == on:
		return
	if on:
		node.set_meta(META, true)
	else:
		node.remove_meta(META)
	if DisplayServer.get_name() == "headless":
		return
	if on:
		_add_shells(node)
	else:
		_remove_shells(node)


static func is_hovered(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and node.has_meta(META)


static func _add_shells(node: Node3D) -> void:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh.mesh
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, Transform3D.IDENTITY)
		var shell := MultiMeshInstance3D.new()
		shell.name = SHELL
		shell.multimesh = multimesh
		shell.material_override = _get_material()
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(shell, false, Node.INTERNAL_MODE_BACK)


static func _remove_shells(node: Node3D) -> void:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh: Node in meshes:
		for shell in mesh.get_children(true):
			if shell.name == SHELL:
				mesh.remove_child(shell)
				shell.queue_free()


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter(&"color", COLOR)
		_material.set_shader_parameter(&"width", WIDTH)
	return _material
