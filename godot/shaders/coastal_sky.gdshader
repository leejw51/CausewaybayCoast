shader_type sky;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 horizon = vec3(0.65, 0.82, 0.85);
	vec3 zenith = vec3(0.22, 0.49, 0.72);
	vec3 base = mix(horizon, zenith, pow(elevation, 0.55));
	vec2 p = EYEDIR.xz / (elevation + 0.2) * 2.5 + vec2(TIME * 0.005, 0.0);
	float clouds = noise21(p) * 0.65 + noise21(p * 2.1) * 0.25 + noise21(p * 4.2) * 0.1;
	float mask = smoothstep(0.56, 0.77, clouds) * smoothstep(0.02, 0.20, EYEDIR.y);
	base = mix(base, vec3(0.94, 0.94, 0.89), mask * 0.85);
	float sun = pow(max(dot(EYEDIR, normalize(vec3(-0.55, 0.45, -0.6))), 0.0), 320.0);
	COLOR = base + vec3(1.0, 0.85, 0.62) * sun * 0.35;
}
