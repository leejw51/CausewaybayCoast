shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float energy = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float angle = atan(p.y, p.x);
	float edge = 1.0 - smoothstep(0.88, 1.0, r);
	float vortex = sin(angle * 5.0 - r * 13.0 + TIME * 2.4);
	vec2 tangent = vec2(-p.y, p.x);
	vec2 distortion = (tangent * vortex + p * sin(r * 22.0 - TIME * 3.0)) * 0.005 * edge * energy;
	vec2 uv = clamp(SCREEN_UV + distortion, vec2(0.002), vec2(0.998));
	vec3 behind;
	behind.r = textureLod(scene_color, clamp(uv + distortion * 0.18, vec2(0.002), vec2(0.998)), 0.0).r;
	behind.g = textureLod(scene_color, uv, 0.0).g;
	behind.b = textureLod(scene_color, clamp(uv - distortion * 0.18, vec2(0.002), vec2(0.998)), 0.0).b;
	float wisps = pow(max(vortex, 0.0), 18.0) * smoothstep(0.05, 0.35, r) * edge;
	vec3 tint = mix(vec3(0.12, 0.48, 0.65), vec3(0.38, 0.16, 0.65), r);
	ALBEDO = mix(behind, tint, 0.08 * edge) + tint * wisps * 0.2 * energy;
	ALPHA = edge * 0.88;
}
