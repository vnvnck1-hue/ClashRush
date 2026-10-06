class_name Mats
extends RefCounted
## Material & procedural texture helpers. Soft-shaded toy look: low specular, rim light, no outlines.

static var _cache := {}
static var _tex := {}

## ---------------------------------------------------------------- Brawl-Stars-style toon
const OUTLINE_SHADER := preload("res://scripts/outline.gdshader")
static var _outlines := {}

## Ink outline material (cached). Color defaults to a darkened, more saturated version of the fill.
static func outline(col: Color, width := 2.2, vertex_color := false) -> ShaderMaterial:
	var key := "o%s%.2f%s" % [col.to_html(), width, vertex_color]
	if _outlines.has(key):
		return _outlines[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("outline_color", ink(col))
	m.set_shader_parameter("width_px", width)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	_outlines[key] = m
	return m

## Outline tint: dark, saturated, slightly purple-shifted version of the fill color.
static func ink(col: Color) -> Color:
	var c := col.darkened(0.6)
	c = c.lerp(Look.OUTLINE_NAVY, 0.6)
	return Color(c.r, c.g, c.b, 1.0)

## Two-tone cel shading: hard terminator, toon specular blob, thin bright rim.
## Soft cel: toon diffuse with a wide, soft terminator (reads as smooth stylized 3D),
## small soft highlight, gentle warm rim. softness ~0.4 = reference look.
static func toonify(m: StandardMaterial3D, outline_w := 1.6, softness := 0.42) -> StandardMaterial3D:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = softness
	m.metallic_specular = 0.22
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.4
	if outline_w > 0.0:
		m.next_pass = outline(m.albedo_color, outline_w, m.vertex_color_use_as_albedo)
	return m

## Shared, lit material for props (cached per color). outline_w = 0 for flat ground pieces.
## World props: soft wrap lighting, no specular. Outline only where asked (towers, castle).
static func prop(color: Color, _rough := 0.85, outline_w := 0.0) -> StandardMaterial3D:
	var key := "p%s%.2f" % [color.to_html(), outline_w]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	toonify(m, outline_w, 0.5)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.rim = 0.12
	_cache[key] = m
	return m

## Hand-painted environment material (arena map): colour and face tone come from vertex
## colours baked by Arena, multiplied by world-space brush-dab noise. No outline, no specular.
static func painted() -> StandardMaterial3D:
	if _cache.has("_painted"):
		return _cache["_painted"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = paint_noise()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.9, 0.9, 0.9)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["_painted"] = m
	return m

## Self-lit material for glowing statue eyes and runes.
static func emissive(color: Color, energy := 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

## Grayscale brush-dab noise (0.8..1.0), posterized so it reads as paint rather than grain.
static func paint_noise() -> Texture2D:
	if _tex.has("_paint"):
		return _tex["_paint"]
	var n := FastNoiseLite.new()
	n.seed = 11
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var src := n.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := floorf(src.get_pixel(x, y).r * 5.0) / 5.0
			var t := lerpf(0.82, 1.0, v)
			img.set_pixel(x, y, Color(t, t, t))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex["_paint"] = tex
	return tex

## Unique material for characters (needs per-instance flash). Thicker ink outline.
static func toy(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = Color(0, 0, 0)
	toonify(m, 1.9, 0.42)
	return m

static func glow(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## Unshaded transparent material for mesh-based VFX (alpha tweened by caller).
static func fx(color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Soft-lit puff material (clouds of smoke look volumetric-ish but cartoony).
static func puff(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.2
	m.metallic_specular = 0.0
	m.rim_enabled = true
	m.rim = 0.6
	m.emission_enabled = true
	m.emission = color * 0.35
	return m

## Billboard particle material using a procedural sprite.
static func particle(shape: String, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture(shape)
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Billboard quad material (non particle).
static func sprite(shape: String, color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = texture(shape)
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## Flat ground decal-like quad material.
static func ground(shape: String, color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = texture(shape)
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

static func texture(shape: String) -> Texture2D:
	if _tex.has(shape):
		return _tex[shape]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - c) / (size * 0.5)
			var d := p.length()
			var a := 0.0
			match shape:
				"soft":
					a = clampf(1.0 - d, 0.0, 1.0)
					a = a * a
				"circle":
					a = clampf((1.0 - d) * 18.0, 0.0, 1.0)
				"blob":
					a = clampf(1.0 - d, 0.0, 1.0)
					a = smoothstep(0.0, 0.7, a)
				"ring":
					a = clampf(1.0 - absf(d - 0.8) * 9.0, 0.0, 1.0)
				"ring_soft":
					a = clampf(1.0 - absf(d - 0.78) * 5.0, 0.0, 1.0)
					a *= clampf((1.0 - d) * 12.0, 0.0, 1.0)
				"star":
					var ang := atan2(p.y, p.x)
					var r := 0.42 + 0.5 * pow(absf(cos(ang * 2.0)), 6.0)
					a = clampf((r - d) * 14.0, 0.0, 1.0)
					a = maxf(a, clampf(1.0 - d * 2.6, 0.0, 1.0))
				"star5":
					var ang2 := atan2(p.y, p.x) + PI * 0.5
					var k := fmod(absf(ang2), TAU / 5.0) - TAU / 10.0
					var r2 := 0.95 * cos(TAU / 10.0) / cos(k) * (0.55 + 0.45 * absf(cos(k * 2.5)))
					a = clampf((r2 * 0.95 - d) * 14.0, 0.0, 1.0)
				"square":
					a = 1.0 if (absf(p.x) < 0.8 and absf(p.y) < 0.8) else 0.0
				"spikes":   # OCTOPO-style hit flash: 4 long + 4 short needle spikes, hot core
					var th := atan2(p.y, p.x)
					var c4 := cos(th * 4.0)
					var spike := pow(absf(c4), 60.0)
					var ln := 0.98 if c4 > 0.0 else 0.62
					a = clampf((ln * spike - d) * 9.0, 0.0, 1.0)
					a = maxf(a, clampf((0.32 - d) * 6.0, 0.0, 1.0))
				"plus":
					var w := 0.22
					var inb := (absf(p.x) < w and absf(p.y) < 0.8) or (absf(p.y) < w and absf(p.x) < 0.8)
					a = 1.0 if inb else 0.0
				"crack":    # radial ground cracks + soft center stain
					var th2 := atan2(p.y, p.x)
					var best := 1.0
					for k in 9:
						var ang := k * 0.7 + sin(k * 3.1) * 0.4
						var dth := absf(wrapf(th2 - ang - sin(d * 9.0 + k) * 0.12, -PI, PI))
						var width := 0.05 * (1.0 - d) + 0.004
						if d < 0.15 + 0.85 * fmod(k * 0.37 + 0.55, 1.0):
							best = minf(best, dth * d / width)
					a = clampf(1.0 - best, 0.0, 1.0)
					a = maxf(a, clampf(0.55 - d * 1.6, 0.0, 1.0) * 0.6)
				"rune":     # magic circle: double ring + tick marks + inner star
					var th3 := atan2(p.y, p.x)
					a = clampf(1.0 - absf(d - 0.9) * 28.0, 0.0, 1.0)
					a = maxf(a, clampf(1.0 - absf(d - 0.72) * 40.0, 0.0, 1.0))
					if d > 0.74 and d < 0.88 and absf(sin(th3 * 12.0)) > 0.92:
						a = 1.0
					var s5 := cos(th3 * 5.0)
					a = maxf(a, clampf(1.0 - absf(d - (0.28 + 0.3 * s5 * s5)) * 30.0, 0.0, 1.0) * (1.0 if d < 0.66 else 0.0))
				"flame":    # rounded fire (guide: no sharp/angular flames): round belly + soft round tip
					var b1 := (p - Vector2(0.0, 0.25)).length() - 0.58
					var b2 := (p - Vector2(0.08, -0.32)).length() - 0.36
					var b3 := (p - Vector2(0.14, -0.7)).length() - 0.16
					var k := 0.22
					var h12 := clampf(0.5 + 0.5 * (b2 - b1) / k, 0.0, 1.0)
					var dd := lerpf(b2, b1, h12) - k * h12 * (1.0 - h12)
					var h3 := clampf(0.5 + 0.5 * (b3 - dd) / k, 0.0, 1.0)
					dd = lerpf(b3, dd, h3) - k * h3 * (1.0 - h3)
					a = clampf(-dd * 14.0, 0.0, 1.0)
				"flame_old":
					var fy := (p.y + 1.0) * 0.5
					var half := 0.75 * sin(clampf(fy, 0.0, 1.0) * PI) * (0.35 + 0.65 * fy)
					a = clampf((half - absf(p.x)) * 10.0, 0.0, 1.0) * clampf((0.95 - fy) * 30.0 + 1.0, 0.0, 1.0)
					a *= clampf(fy * 4.0, 0.0, 1.0)
				"shard":
					a = 1.0 if (absf(p.x) * 2.2 + absf(p.y)) < 0.9 else 0.0
				"needle":   # queen: 3 long thin triangles (sharp, fast)
					var thn := atan2(p.y, p.x)
					var best_n := 0.0
					for k in 3:
						var ang := -PI * 0.5 + (k - 1) * 0.55
						var dd := absf(wrapf(thn - ang, -PI, PI))
						var w := 0.16 * (1.0 - d)
						if dd < w and d < (0.98 if k == 1 else 0.7):
							best_n = 1.0
					a = maxf(best_n, clampf((0.22 - d) * 8.0, 0.0, 1.0))
				"crescent": # valkyrie: crescent moon arc
					var c1 := clampf((0.92 - d) * 12.0, 0.0, 1.0)
					var d2 := (p - Vector2(0.28, -0.22)).length()
					a = c1 * clampf((d2 - 0.78) * 12.0, 0.0, 1.0)
				"wedge":    # king: blunt kite / wedge (heavy)
					a = 1.0 if (absf(p.x) * 1.25 + absf(p.y + 0.15) * 0.9) < 0.78 and p.y < 0.75 else 0.0
				"cross4":   # cleric: thin 4-point holy star
					var ax := absf(p.x)
					var ay := absf(p.y)
					a = 1.0 if (ax * 3.2 + ay < 0.95) or (ay * 3.2 + ax < 0.95) else 0.0
					a = maxf(a, clampf((0.2 - d) * 8.0, 0.0, 1.0))
				"orb":      # wizard: bumpy round puff
					var tho := atan2(p.y, p.x)
					var rr := 0.78 + 0.1 * sin(tho * 5.0)
					a = clampf((rr - d) * 14.0, 0.0, 1.0)
				"streak":   # horizontal speed streak, bright head fading tail
					a = clampf((1.0 - absf(p.y) * 6.0), 0.0, 1.0) * clampf((p.x + 1.0) * 0.5, 0.0, 1.0)
					a *= clampf((1.0 - p.x) * 8.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[shape] = t
	return t
