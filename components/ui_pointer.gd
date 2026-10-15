class_name UIPointer
extends XRNode3D
## A UI ray using a controller's aim pose and one edge per trigger press.
## Its panel owns visibility and ray targets.

const LENGTH := 2.0

var controller: XRController3D

var _down := true # opening with a held trigger requires a release first
var _beam: MeshInstance3D
var _tip: MeshInstance3D


func _ready() -> void:
	show_when_tracked = false # The panel owns visibility, including while tracking keeps updating
	visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.7, 0.9, 1.0)
	_beam = MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.top_radius = 0.0015
	line.bottom_radius = 0.0015
	line.height = 1.0
	line.radial_segments = 6
	_beam.mesh = line
	_beam.rotation.x = PI / 2.0
	_beam.material_override = material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_tip = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	dot.radial_segments = 12
	dot.rings = 6
	_tip.mesh = dot
	_tip.material_override = material
	_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tip)


## Consume the trigger edge even on a miss. Holding and moving onto a button
## never clicks; lost tracking also requires releasing before another click.
func sample(open: bool) -> bool:
	if tracker != controller.tracker:
		tracker = controller.tracker
		pose = &"aim" # assigning a tracker resets XRNode3D's pose to default
	var aim := get_pose()
	visible = open and aim != null and aim.has_tracking_data
	var down := controller.is_button_pressed(&"trigger_click")
	var pressed := visible and down and not _down
	_down = down or not visible
	return pressed


func draw_ray(distance: float, hit: bool) -> void:
	_beam.scale.y = distance
	_beam.position.z = -distance * 0.5
	_tip.visible = hit
	_tip.position.z = -distance + 0.012
