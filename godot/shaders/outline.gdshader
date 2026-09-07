// Inverted-hull outline pass, used as next_pass on every toon material.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform float width = 0.028;
uniform vec4 color : source_color = vec4(0.16, 0.10, 0.16, 1.0);

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
