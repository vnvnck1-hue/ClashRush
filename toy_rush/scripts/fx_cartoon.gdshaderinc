// Cartoon FX master shader (one shader for every effect, like Octopo's MasterShader_Cartoon).
// Modules:
//  - SHAPE   : alpha mask texture (procedural shapes) or full mesh
//  - BANDS   : 3-color gradient map (dark / main / light), hard bands, no soft gradients
//  - VOLUME  : 3-tone cel shading for mesh volumes (smoke clumps) from a screen upper-left light
//  - SCROLL  : UV scroll for cylinders/strips (shockwaves, beams)
//  - DISSOLVE: noise erosion with a bright burning edge instead of alpha fades
// Per-instance values use `instance uniform` so every effect can share one material.

uniform sampler2D shape_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;               // 0 sprite (radial bands), 1 volume (cel lighting), 2 strip/scroll, 3 flame
uniform bool billboard = true;
uniform bool use_shape = true;
uniform vec2 scroll_speed = vec2(0.0, 0.0);
uniform float noise_scale = 1.0;
uniform float band_hi = 0.62;       // above -> light
uniform float band_lo = 0.22;       // below -> dark
uniform float edge_width = 0.07;
uniform vec3 light_view = vec3(-0.55, 0.7, 0.45);
uniform bool hard_edge = true;     // cel cut-out; false only for additive glows

instance uniform float dissolve = 0.0;
instance uniform float spin = 0.0;
instance uniform float glow = 1.0;
instance uniform float seed = 0.0;
instance uniform vec4 col_dark : source_color = vec4(0.8, 0.35, 0.05, 1.0);
instance uniform vec4 col_main : source_color = vec4(1.0, 0.82, 0.25, 1.0);
instance uniform vec4 col_light : source_color = vec4(1.0, 0.98, 0.88, 1.0);

varying vec3 v_normal_view;

void vertex() {
	if (billboard) {
		float c = cos(spin);
		float s = sin(spin);
		VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	v_normal_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	float mask = 1.0;
	if (use_shape) {
		mask = texture(shape_tex, uv).a;
	}
	vec2 nuv = uv * noise_scale + vec2(seed * 0.37, seed * 0.71) + scroll_speed * TIME;
	float n = texture(noise_tex, nuv).r;

	// tone value t in 0..1 -> 3 hard bands
	float t;
	if (mode == 1) {
		float l = dot(normalize(v_normal_view), normalize(light_view));
		t = l * 0.5 + 0.5;
		t += (n - 0.5) * 0.18;            // slightly broken, hand-drawn band edge
	} else if (mode == 2) {
		t = 1.0 - abs(uv.y - 0.5) * 2.0;  // strip: hot center line
		t = t * 0.8 + n * 0.3;
	} else if (mode == 3) {
		// flame: hot core low and centered (3-band fire from the guide)
		t = (1.0 - abs(uv.x - 0.5) * 2.0) * 0.55 + (uv.y) * 0.45 - 0.12;
		t += (n - 0.5) * 0.2;
	} else if (mode == 4) {
		t = 0.42 + (n - 0.5) * 0.12;      // flat: main color (rings, decals), light only on burn edge
	} else {
		float d = length(uv - vec2(0.5)) * 2.0;
		t = 1.0 - d;                      // sprite: hot center, darker rim
		t = t * 0.9 + mask * 0.25;
	}
	vec3 col = t > band_hi ? col_light.rgb : (t > band_lo ? col_main.rgb : col_dark.rgb);

	// dissolve erosion (eats from the noise, biased toward the outer rim of the shape)
	float erosion = n * 0.75 + mask * 0.25;
	if (mode == 2) {
		erosion = n * 0.45 + uv.x * 0.55;   // strips/slashes burn away from the tail
	}
	if (mode == 1) {
		erosion = n * 0.8 + (1.0 - (1.0 - dot(normalize(v_normal_view), vec3(0.0, 0.0, 1.0)))) * 0.2;
	}
	float vis = step(dissolve, erosion);
	float edge = step(dissolve, erosion) - step(dissolve + edge_width, erosion);
	if (dissolve > 0.001) {
		col = mix(col, col_light.rgb, edge);
	}
	float a = (hard_edge ? step(0.35, mask) : mask) * vis;
	ALBEDO = col * glow;
	ALPHA = a * col_main.a;
#ifdef CUTOUT
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
