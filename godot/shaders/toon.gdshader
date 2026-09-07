// Soft cel shading + world-space triplanar texturing (no UVs needed on the Blender models).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_mix = 0.0;
uniform float tex_scale = 0.5;
uniform vec4 tex_tint : source_color = vec4(1.0);
uniform float tex_colour = 0.35;  // 0 = texture only modulates brightness of albedo, 1 = texture's own colours
uniform vec2 scroll = vec2(0.0);
uniform float wave = 0.0;
uniform float saturation = 1.25;  // console-game punch

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wave > 0.0) {
		VERTEX.y += sin(wp.x * 1.3 + TIME * 1.4) * cos(wp.z * 1.1 + TIME * 1.1) * wave;
	}
	wpos = wp;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 off = scroll * TIME;
	vec3 cx = texture(tex, p.zy * tex_scale + off).rgb;
	vec3 cy = texture(tex, p.xz * tex_scale + off).rgb;
	vec3 cz = texture(tex, p.xy * tex_scale + off).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

void fragment() {
	vec3 base = albedo.rgb;
	if (tex_mix > 0.0) {
		vec3 t = triplanar(wpos, wnrm);
		float lum = dot(t, vec3(0.3, 0.59, 0.11));
		vec3 detail = albedo.rgb * (0.55 + 0.6 * lum);          // keeps the muted palette
		vec3 coloured = mix(detail, t * tex_tint.rgb, tex_colour);  // lets some of the painted hue through
		base = mix(base, coloured, tex_mix);
	}
	float grey = dot(base, vec3(0.3, 0.59, 0.11));
	ALBEDO = clamp(mix(vec3(grey), base, saturation), 0.0, 1.0);
	EMISSION = emission_col.rgb * emission_strength;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// two hard bands + a thin highlight band, like hand-painted console sprites
	float band = smoothstep(0.02, 0.10, ndl) * ATTENUATION;
	float hi = smoothstep(0.62, 0.68, ndl) * ATTENUATION * 0.12;
	float lit = 0.58 + 0.42 * band + hi;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit / PI;
}
