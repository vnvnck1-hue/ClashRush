class_name Fx
extends RefCounted
## Cartoon FX core, built from the Octopo "Cartoon FX Playbook" (사내 FX 가이드):
##  - COLOR SYSTEM: team primary + analogous hues + yellow accent, tiers Low/Medium/High/Ultra.
##    Ally = blue (green/purple analogous), Enemy = red (orange/magenta analogous). Hex values
##    were sampled directly from the guide's swatches.
##  - VALUE: every element renders with 3 hard tones (dark / main / light) via the master shader.
##  - SHAPE: rounded, inflated forms; size hierarchy (strong / medium / weak) with varied spacing.
##  - MOTION: one gravity for everything, ground bounce, motion that reflects the material.
##  - DISSIPATION: no alpha fades. White flash -> solid shape -> breaks into chunks that shrink.
##  - CLEANNESS: priority + active budget, off-screen culling, short lifetimes (no lingering).
## Palette arrays everywhere: [main, dark, light, accent].

const G := 14.0                 # single gravity for every falling element
const BUDGET := 110             # max simultaneously active FX nodes
const FRAME := 1.0 / 30.0
const SH_CUT := preload("res://scripts/fx_cartoon.gdshader")
const SH_ADD := preload("res://scripts/fx_cartoon_add.gdshader")

# ---------------------------------------------------------------- color system (sampled)
const ALLY := {
	"low": [Color("45b9fd"), Color("4669e1"), Color("bbfbfc"), Color("51f7fa")],
	"medium": [Color("45b9fd"), Color("4669e1"), Color("bbfbfc"), Color("3de4b4")],
	"high": [Color("45b9fd"), Color("6c2ddb"), Color("bbfbfc"), Color("f5f572")],
	"ultra": [Color("b475fe"), Color("6a00c3"), Color("f7edfe"), Color("f5f572")],
}
const ENEMY := {
	"low": [Color("eb5951"), Color("bc3328"), Color("fecbc8"), Color("fc8f8e")],
	"medium": [Color("eb5951"), Color("bc3328"), Color("fecbc8"), Color("f8b658")],
	"high": [Color("eb5951"), Color("d311b9"), Color("fecbc8"), Color("f5f572")],
	"ultra": [Color("ed479d"), Color("b82056"), Color("ffc6e7"), Color("f5f572")],
}
## state colour codes (heal / buff / control / economy) + neutral materials
const STATE := {
	"heal": [Color("5fe28f"), Color("1f9e6a"), Color("e2ffe9"), Color("f5f572")],
	"shield": [Color("51d8fa"), Color("2d6fd0"), Color("e6fbff"), Color("ffffff")],
	"stun": [Color("ffd84a"), Color("d08a10"), Color("fffbd8"), Color("ffffff")],
	"slow": [Color("8fe4ff"), Color("3f8fd8"), Color("eafbff"), Color("ffffff")],
	"gold": [Color("ffc93c"), Color("d9861a"), Color("fff4c0"), Color("ffffff")],
	"dust": [Color("e9d6ae"), Color("b8976a"), Color("fff7e6"), Color("ffffff")],
	"smoke": [Color("e8e6f2"), Color("aaa4c2"), Color("ffffff"), Color("ffffff")],
	"stone": [Color("a77a4c"), Color("6e4b2c"), Color("d2a878"), Color("ffffff")],
}

static func ally(tier: String) -> Array:
	return ALLY[tier]

static func enemy(tier: String) -> Array:
	return ENEMY[tier]

static func pal_of(c: Color) -> Array:
	var m := Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)
	return [m, m.darkened(0.35), m.lerp(Color.WHITE, 0.65), Color("f5f572")]

static func as_pal(p) -> Array:
	if p is Array and p.size() >= 3:
		return p if p.size() >= 4 else [p[0], p[1], p[2], Color("f5f572")]
	if p is Color:
		return pal_of(p)
	return ALLY["medium"]

# ---------------------------------------------------------------- resources
static var active := 0
static var _mats := {}
static var _noise: Texture2D
static var _sphere: SphereMesh
static var _quad: QuadMesh
static var _plane: PlaneMesh

static func noise() -> Texture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.frequency = 0.045
		fn.fractal_octaves = 2
		var img := fn.get_seamless_image(128, 128)
		_noise = ImageTexture.create_from_image(img)
	return _noise

static func mat(shape: String, mode: int, billboard: bool, additive := false) -> ShaderMaterial:
	var key := "%s|%d|%s|%s" % [shape, mode, billboard, additive]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SH_ADD if additive else SH_CUT
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("use_shape", shape != "")
	if shape != "":
		m.set_shader_parameter("shape_tex", Mats.texture(shape))
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("hard_edge", not additive)
	_mats[key] = m
	return m

static func sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
	return _sphere

static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad

static func plane() -> PlaneMesh:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(1, 1)
	return _plane

static func paint(gi: GeometryInstance3D, P: Array, glow := 1.0) -> void:
	gi.set_instance_shader_parameter("col_main", P[0])
	gi.set_instance_shader_parameter("col_dark", P[1])
	gi.set_instance_shader_parameter("col_light", P[2])
	gi.set_instance_shader_parameter("glow", glow)
	gi.set_instance_shader_parameter("seed", randf() * 10.0)

# ---------------------------------------------------------------- budget
## prio 0 = ambient (dust, trails), 1 = basic attacks, 2 = skills, 3 = always
static func ok(pos: Vector3, prio := 1) -> bool:
	if prio < 3 and not Vfx.visible_at(pos):
		return false
	if prio == 0 and active > BUDGET * 0.6:
		return false
	if prio == 1 and active > BUDGET:
		return false
	return true

static func _spawn(n: GeometryInstance3D, pos: Vector3) -> void:
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx._add(n, pos)
	active += 1
	n.tree_exiting.connect(func(): active -= 1)

# ---------------------------------------------------------------- primitives
## Cel smoke clump (3-tone lit sphere). Pops with overshoot, drifts, then BREAKS into 2-3
## smaller clumps that shrink away (no alpha fade).
static func clump(pos: Vector3, pal, size: float, drift := Vector3.ZERO, life := 0.45, delay := 0.0, prio := 0, split := true) -> void:
	if not ok(pos, prio):
		return
	var P := as_pal(pal)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere()
	mi.material_override = mat("", 1, false)
	_spawn(mi, pos)
	paint(mi, P)
	mi.scale = Vector3.ONE * 0.01
	var end := pos + drift
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.18, life * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "global_position", end, life * 0.75).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.15)
	if split and size > 0.16:
		tw.tween_callback(func():
			var n := 2 + (randi() % 2)
			var base := randf() * TAU
			for i in n:
				var a := base + TAU * i / n + randf_range(-0.4, 0.4)
				var d := Vector3(cos(a), randf_range(-0.1, 0.5), sin(a))
				var s := size * randf_range(0.32, 0.55)     # size hierarchy on break
				clump(mi.global_position + d * size * 0.35, P, s, d * size * 0.5, life * 0.55, 0.0, 0, false))
		tw.tween_property(mi, "scale", Vector3.ZERO, life * 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		tw.tween_property(mi, "scale", Vector3.ZERO, life * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

## Camera-facing symbol (star, circle, plus...). Pops in, holds briefly, shrinks out.
static func symbol(pos: Vector3, shape: String, pal, size: float, life := 0.2, spin := 0.0, additive := true, glow := 1.6, prio := 1) -> MeshInstance3D:
	if not ok(pos, prio):
		return null
	var P := as_pal(pal)
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = mat(shape, 0, true, additive)
	_spawn(mi, pos)
	paint(mi, P, glow)
	var a0 := randf() * TAU
	mi.set_instance_shader_parameter("spin", a0)
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.15, life * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.2)
	tw.tween_property(mi, "scale", Vector3.ZERO, life * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if spin != 0.0:
		tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("spin", v), a0, a0 + spin, life)
	tw.tween_callback(mi.queue_free)
	return mi

## Ground shockwave ring: expands with expo-out, then BURNS away (dissolve with bright edge).
static func ring(pos: Vector3, pal, r0: float, r1: float, life := 0.3, shape := "ring", prio := 1) -> void:
	if not ok(pos, prio):
		return
	var P := as_pal(pal)
	var mi := MeshInstance3D.new()
	mi.mesh = plane()
	mi.material_override = mat(shape, 4, false)
	_spawn(mi, Vector3(pos.x, 0.05, pos.z))
	paint(mi, P)
	mi.scale = Vector3.ONE * r0
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * r1, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("dissolve", v), 0.0, 1.0, life * 0.55).set_delay(life * 0.45)
	tw.chain().tween_callback(mi.queue_free)

## Ground decal (crack, rune, scorch). Short life, dissolves out (no lingering).
static func decal(pos: Vector3, shape: String, pal, radius: float, life := 0.9, spin := 0.0, prio := 1) -> MeshInstance3D:
	if not ok(pos, prio):
		return null
	var P := as_pal(pal)
	var mi := MeshInstance3D.new()
	mi.mesh = plane()
	mi.material_override = mat(shape, 4, false)
	_spawn(mi, Vector3(pos.x, 0.045, pos.z))
	paint(mi, P)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * radius * 1.4
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if spin != 0.0:
		tw.tween_property(mi, "rotation:y", mi.rotation.y + spin * life, life)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("dissolve", v), 0.0, 1.0, life * 0.4).set_delay(life * 0.6)
	tw.chain().tween_callback(mi.queue_free)
	return mi

## Additive hot core (the "white flash" frame). 2-4 frames only.
static func flash(pos: Vector3, pal, size: float, frames := 4, prio := 1) -> void:
	if not ok(pos, prio):
		return
	var P := as_pal(pal)
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = mat("soft", 0, true, true)
	_spawn(mi, pos)
	paint(mi, [P[2], P[0], Color.WHITE, P[3]], 2.2)
	mi.scale = Vector3.ONE * size
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.15, FRAME * frames).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

## Ballistic chunks with the single gravity and a ground bounce (stone / jelly / drops).
## material: "stone" = heavy, small bounce; "jelly" = squash on landing, bigger bounce; "spark" = light.
static func chunks(pos: Vector3, pal, n: int, speed := 4.0, size := 0.16, material := "stone", prio := 1) -> void:
	if not ok(pos, prio):
		return
	var P := as_pal(pal)
	var bounce := {"stone": 0.28, "jelly": 0.5, "spark": 0.18}.get(material, 0.3) as float
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = sphere()
		mi.material_override = mat("", 1, false)
		var p0 := pos + Vector3(0, 0.15, 0)
		_spawn(mi, p0)
		paint(mi, P)
		var s := size * ([1.0, 0.7, 0.5][i % 3] as float) * randf_range(0.85, 1.15)   # hierarchy
		mi.scale = Vector3.ONE * s
		var a := randf() * TAU
		var hs := speed * randf_range(0.35, 0.8)
		var v := Vector3(cos(a) * hs, speed * randf_range(0.7, 1.15), sin(a) * hs)
		var t1 := (v.y + sqrt(v.y * v.y + 2.0 * G * p0.y)) / G          # first landing
		var v2 := v.y * bounce
		var t2 := 2.0 * v2 / G                                           # bounce arc
		var total := t1 + t2
		var land := p0 + Vector3(v.x, 0, v.z) * t1
		land.y = s * 0.5
		var step := func(t: float) -> void:
			if t <= t1:
				mi.global_position = p0 + Vector3(v.x * t, v.y * t - 0.5 * G * t * t, v.z * t)
			else:
				var u := t - t1
				var hv := Vector3(v.x, 0, v.z) * 0.4
				mi.global_position = land + Vector3(hv.x * u, maxf(0.0, v2 * u - 0.5 * G * u * u), hv.z * u)
		var tw := mi.create_tween()
		tw.tween_method(step, 0.0, total, total)
		if material == "jelly":
			tw.parallel().tween_callback(func(): mi.scale = Vector3(s * 1.4, s * 0.55, s * 1.4)).set_delay(t1)
			tw.parallel().tween_property(mi, "scale", Vector3.ONE * s, 0.2).set_delay(t1 + 0.02).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)

## Cluster of clumps laid out with size hierarchy + varied spacing (guide: strong/medium/weak).
static func cluster(pos: Vector3, pal, radius: float, drift := 0.5, life := 0.5, prio := 1) -> void:
	var sizes := [1.0, 0.68, 0.6, 0.42, 0.36, 0.26]
	var base := randf() * TAU
	for i in sizes.size():
		var a := base + i * 2.399 + randf_range(-0.3, 0.3)          # golden angle -> uneven spacing
		var r := radius * (0.0 if i == 0 else randf_range(0.35, 0.95))
		var d := Vector3(cos(a), randf_range(0.15, 0.55), sin(a))
		clump(pos + Vector3(cos(a) * r, 0.0, sin(a) * r) * 0.6, pal, radius * 0.9 * sizes[i], d * drift * radius, life * randf_range(0.85, 1.1), FRAME * (i / 2), prio if i < 3 else 0, i < 3)
