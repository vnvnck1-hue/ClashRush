class_name Octo
extends RefCounted
## Composite cartoon effects, rebuilt on the FX guide (Octopo Cartoon FX Playbook) via Fx.
##   Basic attack  = ATK (muzzle) -> PROJ -> HIT (<= 0.35 s, no lingering)
##   Skill         = ANTICIPATION -> EMIT (white flash, accent symbol, ring, size-hierarchy cluster)
##                   -> AFTERMATH (ballistic chunks with one gravity, short ground decal)
## Palettes: [main, dark, light, accent] from Fx (team colour system first, theme second).

const FRAME := 1.0 / 30.0

static func _pal(p) -> Array:
	return Fx.as_pal(p)

static func _hdr(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

# ================================================================ HIT
## 5 frames: f1 white flash, f2 accent star, f3 team ring, f4-5 clumps (1 strong, 2 medium, 2 weak).
static func impact(pos: Vector3, pal, size := 1.0, prio := 1) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, prio):
		return
	Fx.flash(pos, P, 0.9 * size, 3, prio)
	Fx.symbol(pos, "star", [P[3], P[0], Color.WHITE, P[3]], 0.75 * size, 0.16, randf_range(-0.5, 0.5), true, 1.4, prio)
	Fx.ring(pos, P, 0.2 * size, 1.3 * size, 0.2, "ring", prio)
	var sizes := [0.3, 0.2, 0.18, 0.12, 0.1]
	var base := randf() * TAU
	for i in sizes.size():
		var a := base + i * 2.399
		var d := Vector3(cos(a), randf_range(0.3, 0.8), sin(a))
		Fx.clump(pos + d * 0.1, P if i % 2 == 0 else [P[2], P[0], Color.WHITE, P[3]], sizes[i] * size, d * 0.45 * size, 0.28, FRAME * (1 + i / 2), 0, false)

# ================================================================ ATK (muzzle)
static func muzzle(pos: Vector3, dir: Vector3, pal, size := 1.0) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 1):
		return
	Fx.flash(pos, P, 0.6 * size, 3)
	Fx.symbol(pos, "star", [P[2], P[0], Color.WHITE, P[3]], 0.5 * size, 0.12, 0.3, true, 1.4)
	var d := dir.normalized()
	Fx.clump(pos + d * 0.25, P, 0.16 * size, d * 0.5, 0.22, 0.0, 0, false)

## a fading glowing line between two points (beams, speed lines)
static func streak(a: Vector3, b: Vector3, col: Color, width := 0.08, life := 0.2) -> void:
	var L := a.distance_to(b)
	if L < 0.01 or not Fx.ok(a, 0):
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, L)
	mi.mesh = bm
	var m := Mats.fx(col, true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx._add(mi, (a + b) * 0.5)
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.05, 0.05, 1.0), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

# ================================================================ SLASH (solid cel crescent, burns from the tail)
static var _crescents := {}
static func _crescent(radius: float, arc: float, thick: float) -> ArrayMesh:
	var key := "%.2f|%.2f|%.2f" % [radius, arc, thick]
	if _crescents.has(key):
		return _crescents[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a0 := -arc * 0.5 + arc * t0
		var a1 := -arc * 0.5 + arc * t1
		var w0 := thick * pow(sin(t0 * PI), 0.8) * (0.4 + 0.6 * t0)   # rounded brush, thick head
		var w1 := thick * pow(sin(t1 * PI), 0.8) * (0.4 + 0.6 * t1)
		var po0 := Vector3(sin(a0), 0, -cos(a0)) * radius
		var po1 := Vector3(sin(a1), 0, -cos(a1)) * radius
		var pi0 := Vector3(sin(a0), 0, -cos(a0)) * (radius - w0)
		var pi1 := Vector3(sin(a1), 0, -cos(a1)) * (radius - w1)
		st.set_uv(Vector2(t0, 0.5)); st.add_vertex(po0)
		st.set_uv(Vector2(t0, 0.0)); st.add_vertex(pi0)
		st.set_uv(Vector2(t1, 0.5)); st.add_vertex(po1)
		st.set_uv(Vector2(t0, 0.0)); st.add_vertex(pi0)
		st.set_uv(Vector2(t1, 0.0)); st.add_vertex(pi1)
		st.set_uv(Vector2(t1, 0.5)); st.add_vertex(po1)
	var m := st.commit()
	_crescents[key] = m
	return m

static func slash(pos: Vector3, yaw: float, pal, radius := 1.6, arc_deg := 140.0, thick := 0.6, life := 0.18, prio := 1) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, prio):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _crescent(radius, deg_to_rad(arc_deg), thick)
	mi.material_override = Fx.mat("", 2, false)
	Fx._spawn(mi, pos)
	Fx.paint(mi, P)
	mi.rotation.y = yaw - deg_to_rad(arc_deg) * 0.35
	mi.scale = Vector3(0.75, 1, 0.75)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "rotation:y", yaw + deg_to_rad(arc_deg) * 0.15, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(1.08, 1, 1.08), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("dissolve", v), 0.0, 1.05, life * 0.6).set_delay(life * 0.45)
	tw.chain().tween_callback(mi.queue_free)

# ================================================================ ANTICIPATION / EMIT / AFTERMATH
## attract energy: rounded motes travel inward (ease-in) while the core grows
static func charge(pos: Vector3, pal, dur := 0.3, radius := 1.6) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 2):
		return
	for i in 6:
		var a := TAU * i / 6.0 + randf() * 0.4
		var start := pos + Vector3(cos(a) * radius, randf_range(-0.2, 0.6), sin(a) * radius)
		var mote := Fx.symbol(start, "circle" if i % 2 else "star", [P[2], P[0], Color.WHITE, P[3]], [0.3, 0.2, 0.16][i % 3], dur * 1.4, 0.0, true, 1.5, 2)
		if mote:
			mote.create_tween().tween_property(mote, "global_position", pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Fx.flash(pos, P, radius * 0.6, int(dur / FRAME), 2)

## emit: the strongest single beat. flash -> accent symbol -> double ring -> hierarchy cluster.
static func burst(pos: Vector3, pal, radius := 2.0, shake := 0.0) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 2):
		return
	var c := pos + Vector3(0, 0.4, 0)
	Fx.flash(c, P, radius * 1.5, 4, 2)
	Fx.symbol(c, "star", [P[3], P[0], Color.WHITE, P[3]], radius * 1.3, 0.22, randf_range(-0.6, 0.6), true, 1.5, 2)
	Fx.ring(pos, P, 0.4, radius * 2.4, 0.3, "ring", 2)
	Fx.ring(pos, [P[2], P[0], Color.WHITE, P[3]], 0.2, radius * 1.5, 0.22, "ring", 2)
	Fx.cluster(c, P, radius * 0.5, 1.0, 0.5, 2)
	Fx.cluster(c + Vector3(0, 0.2, 0), [P[2], P[0], Color.WHITE, P[3]], radius * 0.32, 1.3, 0.4, 1)
	if shake > 0.0 and Vfx.cam:
		Vfx.cam.add_trauma(shake)

## ground stamp (crack / rune / blob). short life, dissolves out.
static func decal(pos: Vector3, tex: String, col, radius: float, life := 0.9, spin := 0.0) -> Node3D:
	var P := Fx.pal_of(col) if col is Color else _pal(col)
	return Fx.decal(pos, tex, P, radius, minf(life, 1.4), spin, 2)

## rounded crystals popping out of the ground in a ring (pop, hold, shrink)
static func shards(pos: Vector3, pal, n := 8, radius := 1.2, life := 0.7) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 2):
		return
	for i in mini(n, 8):
		var a := TAU * i / n + randf() * 0.3
		var mi := MeshInstance3D.new()
		var pm := CapsuleMesh.new()
		pm.radius = 0.12
		pm.height = 0.7
		mi.mesh = pm
		mi.material_override = Fx.mat("", 1, false)
		var p := pos + Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.7, 1.0)
		Fx._spawn(mi, p)
		Fx.paint(mi, P)
		mi.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
		mi.scale = Vector3(1, 0.01, 1)
		var s: float = [1.3, 0.9, 0.7][i % 3]
		var tw := mi.create_tween()
		tw.tween_interval(FRAME * (i % 3))
		tw.tween_property(mi, "scale", Vector3(s, s * 1.2, s), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(life * 0.4)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)

## rounded flame tongues around a ring (3-band fire via shader mode 3)
static func flame_ring(pos: Vector3, radius: float, pal, life := 0.6) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 2):
		return
	Fx.ring(pos, P, radius * 0.4, radius * 2.3, 0.35, "ring", 2)
	var n := mini(int(radius * 7.0), 22)
	for i in n:
		var a := TAU * i / n
		var fp := pos + Vector3(cos(a), 0.0, sin(a)) * radius * randf_range(0.85, 1.05)
		var fl := MeshInstance3D.new()
		fl.mesh = Fx.quad()
		fl.material_override = Fx.mat("flame", 3, true)
		Fx._spawn(fl, fp + Vector3(0, 0.6, 0))
		Fx.paint(fl, [P[0], P[1], Color(1, 1, 0.92), P[3]])
		var h: float = [1.25, 0.9, 1.05][i % 3]          # height hierarchy (rounded, not spiky)
		fl.scale = Vector3(1.0, 0.1, 1)
		var tw := fl.create_tween()
		tw.tween_interval(randf() * 0.08)
		tw.tween_property(fl, "scale", Vector3(1.05, h, 1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(fl, "position:y", fl.position.y + 0.35, life * 0.5)
		tw.tween_property(fl, "scale", Vector3.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(fl.queue_free)

## heal: green plus symbols rise (motion direction = state: heal goes UP)
static func plus_rise(pos: Vector3, _col: Color, n := 6, radius := 0.8) -> void:
	if not Fx.ok(pos, 1):
		return
	var P := Fx.STATE["heal"]
	for i in mini(n, 6):
		var p := pos + Vector3(randf_range(-radius, radius), randf_range(0.3, 0.9), randf_range(-radius, radius))
		var q := Fx.symbol(p, "plus", P, [0.42, 0.3, 0.24][i % 3], 0.65, 0.0, false, 1.0, 1)
		if q:
			q.create_tween().tween_property(q, "position:y", p.y + 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## jagged lightning between two points (magic towers / arcane hits)
static func lightning(a: Vector3, b: Vector3, pal, segments := 6, life := 0.12) -> void:
	var P := _pal(pal)
	if not Fx.ok(a, 1):
		return
	var prev := a
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var p := a.lerp(b, t)
		if i < segments:
			p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.15, 0.15), randf_range(-0.3, 0.3))
		streak(prev, p, _hdr(P[2], 1.8), 0.07, life)
		streak(prev, p, _hdr(P[0], 1.3), 0.15, life * 0.8)
		prev = p

## dash: a few speed lines + dust clumps with size hierarchy kicked up behind
static func dash_trail(a: Vector3, b: Vector3, pal) -> void:
	var P := _pal(pal)
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	for i in 3:
		var o := side * randf_range(-0.4, 0.4) + Vector3(0, randf_range(0.3, 0.9), 0)
		streak(a + o, b + o - dir * 0.6, _hdr(P[2], 1.4), 0.05, 0.18)
	var steps := mini(int(a.distance_to(b) / 1.0), 7)
	for i in steps:
		var p := a.lerp(b, float(i) / maxf(steps, 1))
		Fx.clump(p + Vector3(0, 0.1, 0), Fx.STATE["dust"], [0.34, 0.24, 0.18][i % 3], Vector3(0, 0.2, 0) - dir * 0.3, 0.4, i * 0.03, 1, false)

## stunned: 3 rounded stars orbit (yellow = control state code)
static func stun_stars(parent: Node3D, height: float, life := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = Vector3(0, height, 0)
	for i in 3:
		var s := MeshInstance3D.new()
		s.mesh = Fx.quad()
		s.material_override = Fx.mat("star5", 0, true)
		Fx.paint(s, Fx.STATE["stun"])
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(s)
		var a := TAU * i / 3.0
		s.position = Vector3(cos(a), 0, sin(a)) * 0.35
		s.scale = Vector3.ONE * [0.3, 0.24, 0.2][i]
	var tw := root.create_tween()
	tw.tween_property(root, "rotation:y", TAU * 2.0, life)
	tw.tween_callback(root.queue_free)

## death (smoke-ring rule from the guide): white flash -> solid clumps -> break into pieces -> shrink
static func death(pos: Vector3, pal) -> void:
	var P := _pal(pal)
	if not Fx.ok(pos, 1):
		return
	var c := pos + Vector3(0, 0.4, 0)
	Fx.flash(c, Fx.STATE["smoke"], 1.1, 3)
	var n := 6
	var base := randf() * TAU
	for i in n:
		var a := base + TAU * i / n + randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.25, sin(a))
		var s: float = [0.42, 0.3, 0.36, 0.24, 0.32, 0.2][i]
		Fx.clump(c + d * 0.15, Fx.STATE["smoke"], s, d * 0.55, 0.42, FRAME, 1, true)
	Fx.symbol(c, "star", [P[3], P[0], Color.WHITE, P[3]], 0.7, 0.14, 0.4, true, 1.3)

## level up / tower upgrade: anticipation -> pillar -> rune stamp -> rising stars
static func level_up(pos: Vector3, pal) -> void:
	var P := _pal(pal)
	charge(pos + Vector3(0, 0.6, 0), P, 0.2, 1.3)
	Vfx.upgrade_pillar(pos)
	decal(pos, "rune", P, 1.4, 0.9, 1.5)
	Vfx.sparks(pos + Vector3(0, 0.3, 0), P[3], 8, 3.5, 0.8, "star5", 0.2, 3.0, Vector3.UP, 25.0)

## spinning thrown axe that flies out and comes back to its owner
static func axe(from: Vector3, to: Vector3, owner: Node3D, dur: float, pal) -> void:
	var P := _pal(pal)
	var root := Node3D.new()
	Vfx._add(root, from)
	var body := Node3D.new()
	root.add_child(body)
	var handle := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.04
	c.bottom_radius = 0.04
	c.height = 0.9
	handle.mesh = c
	handle.material_override = Mats.prop(Color("8a5a34"), 0.8, 1.6)
	handle.rotation.z = PI * 0.5
	body.add_child(handle)
	for s in [-1.0, 1.0]:
		var blade := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.32
		bc.bottom_radius = 0.32
		bc.height = 0.06
		blade.mesh = bc
		blade.material_override = Mats.prop(Color("e8eef6"), 0.8, 1.6)
		blade.position = Vector3(0.38 * s, 0, 0)
		blade.scale = Vector3(0.7, 1, 1)
		body.add_child(blade)
	var t := [0.0]
	var step := func(k: float) -> void:
		var back: Vector3 = owner.global_position + Vector3(0, 0.8, 0) if is_instance_valid(owner) else from
		var p := from.lerp(to, k * 2.0) if k < 0.5 else to.lerp(back, (k - 0.5) * 2.0)
		p.y = 0.9 + sin(k * TAU) * 0.15
		root.global_position = p
		body.rotation.y += 0.55
		t[0] += 1.0
		if int(t[0]) % 4 == 0:
			slash(p - Vector3(0, 0.3, 0), body.rotation.y, P, 0.75, 260.0, 0.22, 0.12, 2)
	var tw := root.create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	tw.tween_callback(root.queue_free)
