class_name MenuIcons
extends RefCounted
## Small pictures built from primitive meshes, one per thing the menu names.
##
## Every button carries a shape as well as a word, because many of the children
## this is for read poorly, and a colour alone says nothing to some of them. A
## house is Home, a gem is a Magic Stone, a cross is Close — the same shape every
## time it appears. Built in code from boxes, prisms, spheres and rings, so the
## menu needs no art files to be usable; replace [method make] with scenes when
## there is art.

const INK := Color(0.06, 0.06, 0.1)
const STONE := Color(0.62, 0.42, 1.0)
const STAR := Color(1.0, 0.86, 0.25)

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


## A picture about [param size] metres across, facing +Z. Unknown kinds give an
## empty node, so a missing icon never stops a button from being built.
static func make(kind: StringName, size := 0.03, color := INK) -> Node3D:
	var icon := Node3D.new()
	icon.name = "Icon"
	var s := size
	match kind:
		&"home":
			_box(icon, Vector3(0.7, 0.45, 0.2) * s, Vector3(0, -0.2, 0) * s, color)
			_prism(icon, Vector3(0.95, 0.45, 0.2) * s, Vector3(0, 0.25, 0) * s, 0.0, color)
		&"tasks":
			for i in 3:
				_box(icon, Vector3(0.8, 0.14, 0.15) * s, Vector3(0.1, 0.32 - i * 0.32, 0) * s, color)
				_box(icon, Vector3(0.14, 0.14, 0.15) * s, Vector3(-0.42, 0.32 - i * 0.32, 0) * s, color)
		&"shop":
			_gem(icon, 0.38 * s, Vector3(0, 0.15, 0) * s, STONE)
			_box(icon, Vector3(0.9, 0.14, 0.15) * s, Vector3(0, -0.38, 0) * s, color)
		&"stone", &"buy":
			_gem(icon, 0.45 * s, Vector3.ZERO, STONE)
		&"bag", &"take_out":
			_box(icon, Vector3(0.8, 0.6, 0.25) * s, Vector3(0, -0.15, 0) * s, color)
			_ring(icon, 0.22 * s, Vector3(0, 0.2, 0) * s, color)
			if kind == &"take_out":
				_prism(icon, Vector3(0.4, 0.3, 0.2) * s, Vector3(0.3, 0.45, 0.05) * s, 0.0, STONE)
		&"settings":
			_ring(icon, 0.32 * s, Vector3.ZERO, color)
			for i in 4:
				var tooth := _box(icon, Vector3(0.18, 0.95, 0.15) * s, Vector3.ZERO, color)
				tooth.rotation.z = i * PI / 4.0
		&"close", &"no", &"give_up":
			for angle in [PI / 4.0, -PI / 4.0]:
				var bar := _box(icon, Vector3(0.18, 0.95, 0.15) * s, Vector3.ZERO, color)
				bar.rotation.z = angle
		&"accept", &"yes":
			var short := _box(icon, Vector3(0.18, 0.45, 0.15) * s, Vector3(-0.22, -0.08, 0) * s, color)
			short.rotation.z = PI / 4.0
			var long := _box(icon, Vector3(0.18, 0.85, 0.15) * s, Vector3(0.12, 0.05, 0) * s, color)
			long.rotation.z = -PI / 5.0
		&"where":
			_prism(icon, Vector3(0.7, 0.45, 0.2) * s, Vector3(0, 0.25, 0) * s, 0.0, color)
			_box(icon, Vector3(0.25, 0.5, 0.15) * s, Vector3(0, -0.2, 0) * s, color)
		&"prev":
			_prism(icon, Vector3(0.7, 0.6, 0.2) * s, Vector3.ZERO, PI / 2.0, color)
		&"next":
			_prism(icon, Vector3(0.7, 0.6, 0.2) * s, Vector3.ZERO, -PI / 2.0, color)
		&"minus":
			_box(icon, Vector3(0.8, 0.2, 0.15) * s, Vector3.ZERO, color)
		&"plus":
			_box(icon, Vector3(0.8, 0.2, 0.15) * s, Vector3.ZERO, color)
			_box(icon, Vector3(0.2, 0.8, 0.15) * s, Vector3.ZERO, color)
		&"on":
			_disc(icon, 0.4 * s, color)
		&"off":
			_ring(icon, 0.3 * s, Vector3.ZERO, color)
		&"walk":
			_box(icon, Vector3(0.22, 0.5, 0.15) * s, Vector3(-0.18, -0.15, 0) * s, color)
			_box(icon, Vector3(0.22, 0.5, 0.15) * s, Vector3(0.18, 0.15, 0) * s, color)
		&"teleport":
			var pad := _ring(icon, 0.35 * s, Vector3(0, -0.2, 0) * s, color)
			pad.rotation.x = PI / 2.5
			_gem(icon, 0.22 * s, Vector3(0, 0.25, 0) * s, color)
		&"start_over":
			_ring(icon, 0.33 * s, Vector3.ZERO, color)
			_prism(icon, Vector3(0.35, 0.3, 0.2) * s, Vector3(0.33, 0.1, 0.05) * s, PI, color)
		&"star":
			for i in 5:
				var angle := i * TAU / 5.0
				var point := MeshInstance3D.new()
				var mesh := PrismMesh.new()
				mesh.size = Vector3(0.36, 0.42, 0.18) * s
				point.mesh = mesh
				point.position = Vector3(-sin(angle), cos(angle), 0.0) * 0.3 * s
				point.rotation.z = angle
				point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				point.material_override = material(color, true)
				icon.add_child(point)
			var middle := CylinderMesh.new()
			middle.top_radius = 0.2 * s
			middle.bottom_radius = 0.2 * s
			middle.height = 0.18 * s
			middle.radial_segments = 5
			var heart := _add(icon, middle, Vector3.ZERO, color, true)
			heart.rotation.x = PI / 2.0
	return icon


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, at, color, glow)


static func _prism(parent: Node3D, size: Vector3, at: Vector3, roll: float, color: Color) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	var node := _add(parent, mesh, at, color, false)
	node.rotation.z = roll
	return node


## A Magic Stone: an eight-faced gem, the same shape wherever stones are counted.
static func _gem(parent: Node3D, radius: float, at: Vector3, color: Color, glow := true) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.6
	mesh.radial_segments = 4
	mesh.rings = 2
	return _add(parent, mesh, at, color, glow)


static func _ring(parent: Node3D, radius: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.7
	mesh.outer_radius = radius
	mesh.rings = 16
	mesh.ring_segments = 6
	var node := _add(parent, mesh, at, color, false)
	node.rotation.x = PI / 2.0
	return node


static func _disc(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = radius * 0.4
	mesh.radial_segments = 16
	var node := _add(parent, mesh, Vector3.ZERO, color, false)
	node.rotation.x = PI / 2.0
	return node


static func _add(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = material(color, glow)
	parent.add_child(node)
	return node


## One shared unshaded material per colour, so the whole menu is a handful of
## materials however many buttons it shows.
static func material(color: Color, glow := false) -> StandardMaterial3D:
	var key := Color(color.r, color.g, color.b, 0.5 if glow else 1.0)
	if not _materials.has(key):
		var made := StandardMaterial3D.new()
		made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		made.albedo_color = color
		if glow:
			made.emission_enabled = true
			made.emission = color
			made.emission_energy_multiplier = 1.5
		_materials[key] = made
	return _materials[key]
