class_name VisionProfile
extends Resource
## How the world looks: a spirit's "visual ability".
## Values multiply the current level's own look, so 1.0 everywhere = unchanged.

@export var display_name := ""
@export_range(0.5, 2.0) var brightness := 1.0
@export_range(0.5, 3.0) var contrast := 1.0
@export_range(0.0, 2.0) var saturation := 1.0
## 0 removes the level's fog, 1 keeps it.
@export_range(0.0, 1.0) var fog := 1.0
## Optional colour-grading LUT / gradient (Environment.adjustment_color_correction).
@export var color_correction: Texture
## Outline every node in the "vision_target" group.
@export var highlight_targets := false
@export var highlight_color := Color(1.0, 0.85, 0.1)


func changes_colors() -> bool:
	return brightness != 1.0 or contrast != 1.0 or saturation != 1.0 or color_correction != null
