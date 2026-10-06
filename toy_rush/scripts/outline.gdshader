shader_type spatial;
// Brawl-Stars-style ink outline: inverted hull pushed out in screen space so the line keeps a
// constant pixel width at any distance. Used as next_pass on toon materials.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

global uniform float outline_scale;
uniform vec4 outline_color : source_color = vec4(0.11, 0.07, 0.17, 1.0);
uniform float width_px = 2.2;
uniform bool use_vertex_color = false;
uniform float vertex_color_dark = 0.32;

varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 nv = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(nv, 0.0)).xy;
	float l = length(dir);
	if (l > 0.0001) {
		dir /= l;
	}
	float px = width_px * outline_scale * (VIEWPORT_SIZE.y / 720.0);
	clip.xy += dir * px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 c = outline_color.rgb;
	if (use_vertex_color) {
		c = v_col * vertex_color_dark;
	}
	ALBEDO = c;
}
