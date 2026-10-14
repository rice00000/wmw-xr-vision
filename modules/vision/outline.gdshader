// Inverted-hull outline, used as material_overlay on vision targets.
// Cheap and works on the Mobile renderer / Quest.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.1, 1.0);
uniform float width = 0.015;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
