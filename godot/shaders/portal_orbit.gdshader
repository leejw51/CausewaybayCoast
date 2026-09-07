shader_type particles;
render_mode disable_force, disable_velocity;

uniform float particle_scale = 0.035;
uniform float orbit_radius = 0.83;
uniform float angular_speed = 2.4;
uniform float energy = 1.0;
uniform bool interior = false;

float random1(float x) { return fract(sin(x * 12.9898 + 78.233) * 43758.5453); }

void start() {
	CUSTOM = vec4(random1(float(NUMBER)) * 6.283185, 0.0, random1(float(NUMBER) + 19.0), random1(float(NUMBER) + 47.0));
}

void process() {
	CUSTOM.y += DELTA;
	float age = CUSTOM.y / LIFETIME;
	float angle = CUSTOM.x + CUSTOM.y * angular_speed * (0.8 + CUSTOM.z * 0.4);
	float radius = orbit_radius + (CUSTOM.z - 0.5) * 0.09;
	if (interior) { radius = orbit_radius * sqrt(CUSTOM.z) * (1.0 - age * 0.35); }
	float envelope = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.75, 1.0, age));
	float scale = particle_scale * (0.7 + CUSTOM.w * 0.6);
	TRANSFORM[0] = vec4(cos(angle) * scale, sin(angle) * scale, 0.0, 0.0);
	TRANSFORM[1] = vec4(-sin(angle) * scale, cos(angle) * scale, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, scale, 0.0);
	TRANSFORM[3] = vec4(cos(angle) * radius, sin(angle) * radius, sin(angle * 3.0 + CUSTOM.w * 6.0) * 0.035, 1.0);
	COLOR = vec4(mix(vec3(0.28, 0.9, 1.0), vec3(0.72, 0.3, 1.0), CUSTOM.w) * energy, envelope);
}
