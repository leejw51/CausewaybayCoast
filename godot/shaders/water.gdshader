shader_type spatial;
render_mode cull_back;
uniform vec4 water_color : source_color = vec4(0.46, 0.72, 0.73, 1.0);
uniform sampler2D caustics : source_color, filter_linear_mipmap, repeat_enable;
uniform bool is_pond = false;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = world.xz * (is_pond ? 0.18 : 0.055);
	vec3 a = texture(caustics, uv + vec2(TIME * 0.012, -TIME * 0.008)).rgb;
	vec3 b = texture(caustics, uv * 1.37 + vec2(-TIME * 0.009, TIME * 0.006)).rgb;
	float caustic = dot((a + b) * 0.5, vec3(0.3, 0.5, 0.2));
	vec2 slope = vec2(cos(world.x * 1.8 + world.z * 0.7 + TIME * 1.3), sin(world.z * 2.2 - world.x * 0.4 - TIME));
	float foam = 0.0;
	vec3 base = water_color.rgb;
	if (is_pond) {
		vec2 center = world.xz - vec2(5.0, 4.0);
		float radius = length(center);
		float ring = sin(radius * 10.0 - TIME * 2.2);
		slope += normalize(center + vec2(0.001)) * ring * 0.65;
		base += (caustic - 0.5) * 0.12 + pow(max(ring, 0.0), 12.0) * 0.045;
	} else {
		float angle = atan(-world.z, world.x);
		float edge = 13.2 * (1.0 + 0.018 * sin(5.0 * angle) + 0.014 * cos(3.0 * angle + 0.4));
		float distance_to_beach = length(world.xz) - edge;
		float shallow = 1.0 - smoothstep(0.0, 11.0, distance_to_beach);
		base = mix(vec3(0.12, 0.38, 0.49), water_color.rgb, shallow);
		base += (caustic - 0.5) * 0.18;
		float surge = 0.65 + sin(TIME * 0.85 + angle * 2.0) * 0.45;
		foam = (1.0 - smoothstep(0.08, 0.30, abs(distance_to_beach - surge))) * smoothstep(-0.1, 0.1, distance_to_beach);
		foam *= 0.6 + 0.4 * sin(angle * 38.0 + TIME);
	}
	ALBEDO = mix(base, vec3(0.85, 0.94, 0.90), foam * 0.8);
	vec3 world_normal = normalize(vec3(slope.x * 0.065, 1.0, slope.y * 0.065));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ROUGHNESS = is_pond ? 0.25 : 0.32;
	SPECULAR = 0.35;
}
