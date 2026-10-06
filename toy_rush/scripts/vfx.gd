class_name Vfx
extends RefCounted
## VFX factory. Grammar (from reference research): white core + saturated rim,
## chunky cartoon puffs, star sparks, ring shockwaves, peak on the emit frame.

static var root: Node3D
static var cam: CameraRig

const WHITE := Color(1, 1, 1)
const DUST := Color("f4ead6")

static func _add(n: Node3D, pos: Vector3) -> Node3D:
	root.add_child(n)
	n.global_position = pos
	return n

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

# ---------------------------------------------------------------- primitives (routed through Fx: guide rules)
## Legacy entry points kept so every caller automatically follows the FX guide.
static func puff(pos: Vector3, color: Color, size: float, drift: Vector3, life := 0.5, delay := 0.0) -> void:
	Fx.clump(pos, Fx.pal_of(color), size, drift, life, delay, 0, size > 0.2)

static func ground_ring(pos: Vector3, color: Color, from_s: float, to_s: float, life := 0.35, shape := "ring", _additive := true) -> void:
	if shape == "blob":
		Fx.decal(pos, "blob", Fx.pal_of(color), to_s * 0.5, life)
	else:
		Fx.ring(pos, Fx.pal_of(color), from_s, to_s, life, "ring" if shape == "ring_soft" else shape)

static func pop_sprite(pos: Vector3, shape: String, color: Color, size: float, life := 0.18, spin := 0.0) -> void:
	Fx.symbol(pos, "circle" if shape == "soft" else shape, Fx.pal_of(color), size * 0.8, life, spin)

## Controlled particle count (guide: cleanness). Falling sparks use the single gravity Fx.G.
static func sparks(pos: Vector3, color: Color, amount := 8, speed := 3.0, life := 0.4, shape := "star", size := 0.14, gravity := -6.0, dir := Vector3.UP, spread := 80.0) -> void:
	if not Fx.ok(pos, 0):
		return
	amount = mini(amount, 8)
	if Fx.active > Fx.BUDGET * 0.5:
		amount = maxi(2, amount / 3)
	if gravity < 0.0:
		gravity = -Fx.G
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = Mats.particle("circle" if shape == "soft" else shape, true)
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var c := Color(minf(color.r, 1.0), minf(color.g, 1.0), minf(color.b, 1.0))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, c)
	g.add_point(0.3, c.lerp(Color.WHITE, 0.3))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(p, pos)
	p.emitting = true
	_free_later(p, life + 0.3)

# ---------------------------------------------------------------- composites
static func dust_ring(pos: Vector3, size := 1.0) -> void:
	var n := 6
	var base := randf() * TAU
	for i in n:
		var a := base + TAU * i / n + randf_range(-0.25, 0.25)
		var d := Vector3(cos(a), 0, sin(a))
		var s: float = [0.3, 0.2, 0.26, 0.16, 0.22, 0.14][i] * size
		Fx.clump(pos + d * 0.2 * size + Vector3(0, 0.08, 0), Fx.STATE["dust"], s, d * 0.6 * size + Vector3(0, 0.08, 0), 0.4, 0.0, 0, false)
	Fx.ring(pos, Fx.STATE["dust"], 0.3 * size, 1.5 * size, 0.24, "ring", 0)

static func hit_spark(pos: Vector3, color: Color, big := false) -> void:
	Octo.impact(pos, Fx.pal_of(color), 1.3 if big else 0.9)

static func death_poof(pos: Vector3) -> void:
	Fx.flash(pos + Vector3(0, 0.35, 0), Fx.STATE["smoke"], 1.0, 3)
	Fx.cluster(pos + Vector3(0, 0.3, 0), Fx.STATE["smoke"], 0.55, 0.9, 0.5)

static func explosion(pos: Vector3, color := Color("ff8a2a"), size := 1.0) -> void:
	Octo.burst(pos, Fx.pal_of(color), size)

static func debris(pos: Vector3, count: int, _color: Color) -> void:
	Fx.chunks(pos, Fx.STATE["stone"], mini(count, 8), 4.5, 0.18, "stone")

static func slam(pos: Vector3, radius: float) -> void:
	pop_sprite(pos + Vector3(0, 0.2, 0), "soft", Color(2.0, 1.9, 1.5), 2.2, 0.16)
	ground_ring(pos, Color(1.6, 1.4, 0.8, 1.0), 0.4, radius * 2.4, 0.4)
	ground_ring(pos, Color(1.0, 1.0, 1.0, 0.8), 0.2, radius * 1.7, 0.3, "ring_soft")
	ground_ring(pos, Color(0.3, 0.2, 0.12, 0.5), radius * 1.6, radius * 1.7, 1.2, "blob", false)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		puff(pos + d * 0.3, DUST, randf_range(0.26, 0.4), d * radius * 0.9 + Vector3(0, 0.15, 0), 0.6)
	debris(pos, 10, Color("9a6a3a"))
	sparks(pos + Vector3(0, 0.2, 0), Data.COL_GOLD, 16, 6.0, 0.55, "star", 0.18, -10.0)
	if cam:
		cam.add_trauma(0.6)
		cam.hitstop(0.09)

static func upgrade_pillar(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.42
	c.bottom_radius = 0.42
	c.height = 3.0
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	var m := Mats.fx(Color(1.6, 1.3, 0.4, 0.55), true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos + Vector3(0, 1.5, 0))
	mi.scale = Vector3(0.1, 1, 0.1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(0.05, 1.3, 0.05), 0.35).set_delay(0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_delay(0.35)
	tw.chain().tween_callback(mi.queue_free)
	sparks(pos + Vector3(0, 0.2, 0), Data.COL_GOLD, 16, 3.0, 0.9, "star5", 0.18, 2.5, Vector3.UP, 30.0)
	ground_ring(pos, Color(1.6, 1.3, 0.4, 1.0), 0.4, 2.0, 0.4)

static func spin_slash(pos: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := Mats.ground("ring_soft", Color(1.4, 1.4, 1.4, 0.9), true)
	mi.material_override = m
	_add(mi, pos + Vector3(0, 0.3, 0))
	mi.scale = Vector3.ONE * radius * 1.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.3, 0.25).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", -TAU, 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18).set_delay(0.08)
	tw.chain().tween_callback(mi.queue_free)
	sparks(pos + Vector3(0, 0.3, 0), color, 10, 4.0, 0.3, "soft", 0.12, 0.0, Vector3.UP, 180.0)

static func speed_puffs(pos: Vector3, color: Color) -> void:
	puff(pos + Vector3(randf_range(-0.1, 0.1), 0.08, randf_range(-0.1, 0.1)), color, randf_range(0.1, 0.16), Vector3(0, 0.15, 0), 0.35)

static func clash_flash(center: Vector3) -> void:
	ground_ring(center, Color(1.2, 1.2, 1.0, 0.6), 0.5, 9.0, 0.45, "ring_soft")
	sparks(center + Vector3(0, 0.2, 0), Color(1, 1, 0.6), 30, 7.0, 0.6, "star", 0.2, -4.0, Vector3.UP, 90.0)

static func confetti(pos: Vector3) -> void:
	var cols := [Color("ff5f7e"), Color("ffd23f"), Color("3fa9f5"), Color("8fd14f"), Color("c56cf0")]
	for c in cols:
		var p := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.16, 0.1)
		var m := Mats.particle("square", false)
		q.material = m
		p.mesh = q
		p.amount = 24
		p.lifetime = 2.4
		p.one_shot = true
		p.explosiveness = 0.9
		p.direction = Vector3.UP
		p.spread = 50.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -4, 0)
		p.damping_min = 2.0
		p.damping_max = 3.0
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.2
		p.color = c * 1.3
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(2.4, 0.1, 3.5)
		_add(p, pos)
		p.emitting = true
		_free_later(p, 3.0)

# ---------------------------------------------------------------- toy rush extras
static var focus := Vector3.ZERO      # camera focus for culling
const CULL := 34.0

static func visible_at(p: Vector3) -> bool:
	return Vector2(p.x - focus.x, p.z - focus.z).length() < CULL

## Persistent ground circle (sanctuary, meteor warning, whirlwind). Returns the node.
static func zone_ring(pos: Vector3, radius: float, color: Color, life: float, pulse := true) -> Node3D:
	var root_n := Node3D.new()
	_add(root_n, pos + Vector3(0, 0.04, 0))
	var fill := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(2, 2)
	fill.mesh = q
	var fm := Mats.ground("blob", Color(color.r, color.g, color.b, 0.28), true)
	fill.material_override = fm
	fill.scale = Vector3.ONE * radius
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_n.add_child(fill)
	var ring := MeshInstance3D.new()
	ring.mesh = q
	var rm := Mats.ground("ring", Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 0.9), true)
	ring.material_override = rm
	ring.scale = Vector3.ONE * radius * 0.62
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_n.add_child(ring)
	root_n.scale = Vector3.ONE * 0.2
	var tw := root_n.create_tween()
	tw.tween_property(root_n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if pulse:
		var tp := ring.create_tween().set_loops(int(life / 0.6) + 1)
		tp.tween_property(ring, "scale", Vector3.ONE * radius * 0.66, 0.3)
		tp.tween_property(ring, "scale", Vector3.ONE * radius * 0.6, 0.3)
	tw.tween_interval(maxf(life - 0.5, 0.0))
	tw.tween_property(fm, "albedo_color:a", 0.0, 0.25)
	tw.parallel().tween_property(rm, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(root_n.queue_free)
	return root_n

static func meteor(pos: Vector3, delay: float) -> void:
	zone_ring(pos, 3.5, Color(1.0, 0.4, 0.15), delay + 0.1, true)
	var rock := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.4
	rock.mesh = s
	rock.material_override = Mats.glow(Color(1.0, 0.55, 0.2), 1.8)
	_add(rock, pos + Vector3(-4, 14, -4))
	var tw := rock.create_tween()
	tw.tween_property(rock, "global_position", pos + Vector3(0, 0.3, 0), delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(rock.queue_free)
	var trail := func(k: float) -> void:
		if randf() < 0.6:
			puff(pos + Vector3(-4, 14, -4).lerp(Vector3(0, 0.3, 0), k * k), Color(1, 0.8, 0.5), randf_range(0.4, 0.7), Vector3(0, 0.3, 0), 0.6)
	var tw2 := rock.create_tween()
	tw2.tween_method(trail, 0.0, 1.0, delay)

static func heal_sparkle(pos: Vector3) -> void:
	sparks(pos + Vector3(0, 0.3, 0), Color(0.5, 1.6, 0.6), 10, 2.0, 0.9, "star5", 0.16, 2.0, Vector3.UP, 25.0)
	ground_ring(pos, Color(0.4, 1.4, 0.5, 0.9), 0.3, 1.8, 0.4)

static func coin_burst(pos: Vector3, n := 4) -> void:
	sparks(pos + Vector3(0, 0.5, 0), Color(1.6, 1.3, 0.3), n, 3.0, 0.6, "circle", 0.14, -9.0, Vector3.UP, 35.0)

static func level_up(pos: Vector3) -> void:
	upgrade_pillar(pos)

static func blink(from: Vector3, to: Vector3) -> void:
	for p in [from, to]:
		for i in 6:
			var a := TAU * i / 6.0
			puff(p + Vector3(0, 0.5, 0), Color(0.75, 0.55, 1.0), randf_range(0.25, 0.35), Vector3(cos(a), 0.4, sin(a)) * 0.6, 0.45)
		sparks(p + Vector3(0, 0.6, 0), Color(0.8, 0.5, 1.6), 12, 4.0, 0.4, "star", 0.15, 0.0, Vector3.UP, 180.0)

## Visual projectile with fixed duration (sim decides timing). Target node optional.
static func shot(kind: String, from: Vector3, target: Node3D, to: Vector3, dur: float) -> void:
	var pr := Shot.new()
	pr.kind = kind
	pr.target = target
	pr.end = to
	pr.dur = maxf(dur, 0.05)
	pr.start = from
	_add(pr, from)
	pr.setup()

class Shot extends Node3D:
	var kind := "arrow"
	var target: Node3D
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var t := 0.0
	var dur := 0.4
	var arc := 0.6
	var _acc := 0.0
	var body: Node3D

	func setup() -> void:
		body = Node3D.new()
		add_child(body)
		var dist := start.distance_to(end)
		match kind:
			"fireball":
				arc = 0.6 + dist * 0.06
				_orb(0.11, Color(1.0, 0.98, 0.85), 2.5)
				_shell(0.19, Color(1.2, 0.75, 2.0, 0.7))
				_tongues()
			"magic":
				arc = 0.3
				_orb(0.1, Color(1.0, 0.9, 1.0), 2.5)
				_shell(0.2, Color(1.4, 0.5, 2.0, 0.7))
				_orbiters(Color(1.6, 0.9, 2.2), 2)
			"holy":
				arc = 0.25
				_orb(0.09, Color(1.0, 1.0, 0.9), 2.5)
				_shell(0.18, Color(1.8, 1.6, 0.6, 0.7))
				_orbiters(Color(2.0, 1.9, 1.0), 3)
			"shell":
				arc = 2.6 + dist * 0.1
				var b := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 0.18
				s.height = 0.36
				b.mesh = s
				b.material_override = Mats.prop(Color("3a3a48"), 0.4)
				body.add_child(b)
			_:
				arc = 0.25 + dist * 0.05
				_arrow()

	var spinner: Node3D

	## sparkles orbiting the projectile core (OCTOPO "sequence" read on magic shots)
	func _orbiters(c: Color, n: int) -> void:
		spinner = Node3D.new()
		body.add_child(spinner)
		for i in n:
			var s := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.18, 0.18)
			s.mesh = q
			s.material_override = Mats.sprite("star", c, true)
			var a := TAU * i / n
			s.position = Vector3(cos(a), sin(a), 0) * 0.28
			spinner.add_child(s)

	## flame tongues trailing behind a fireball
	func _tongues() -> void:
		for i in 3:
			var f := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.32, 0.6)
			f.mesh = q
			f.material_override = Mats.sprite("flame", [Color(1.2, 0.7, 2.0), Color(1.6, 1.4, 0.6), Color(1.0, 0.8, 2.0)][i], true)
			f.position = Vector3((i - 1) * 0.1, 0.05, 0.22 + i * 0.05)
			f.rotation.x = -PI * 0.5
			body.add_child(f)

	func _orb(r: float, c: Color, e: float) -> void:
		var core := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		core.mesh = s
		core.material_override = Mats.glow(c, e)
		body.add_child(core)

	func _shell(r: float, c: Color) -> void:
		var sh := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		sh.mesh = s
		sh.material_override = Mats.fx(c, true)
		body.add_child(sh)

	func _arrow() -> void:
		var shaft := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.022
		c.bottom_radius = 0.022
		c.height = 0.5
		shaft.mesh = c
		shaft.material_override = Mats.prop(Color("8a5a2b"))
		shaft.rotation.x = PI * 0.5
		body.add_child(shaft)
		var tip := MeshInstance3D.new()
		var c2 := CylinderMesh.new()
		c2.top_radius = 0.0
		c2.bottom_radius = 0.05
		c2.height = 0.12
		tip.mesh = c2
		tip.material_override = Mats.prop(Color("dfe6ee"))
		tip.rotation.x = -PI * 0.5
		tip.position.z = -0.28
		body.add_child(tip)
		var fl := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.14, 0.01, 0.12)
		fl.mesh = b
		fl.material_override = Mats.prop(Color("ff6fae"))
		fl.position.z = 0.22
		body.add_child(fl)

	func _process(delta: float) -> void:
		t += delta / dur
		if is_instance_valid(target):
			end = target.global_position + Vector3(0, 0.6, 0)
		var k := minf(t, 1.0)
		var p := start.lerp(end, k) + Vector3(0, sin(k * PI) * arc, 0)
		var prev := global_position
		global_position = p
		if (p - prev).length() > 0.0001:
			body.look_at(p + (p - prev), Vector3.UP)
			if kind in ["arrow", "tower_arrow"]:
				Octo.streak(prev, p, Color(1.8, 1.7, 1.5, 0.8), 0.04, 0.12)
		if spinner:
			spinner.rotation.z += delta * 14.0
		if kind == "shell":
			body.rotation.x += delta * 9.0
		_acc += delta
		var step := 0.07 if kind in ["fireball", "magic", "holy", "shell"] else 0.12
		while _acc > step:
			_acc -= step
			match kind:
				"fireball":
					Fx.clump(p, Fx.ALLY["ultra"], randf_range(0.16, 0.24), Vector3(0, 0.1, 0), 0.35, 0.0, 0, false)
				"magic":
					Fx.clump(p, Fx.ALLY["ultra"], 0.13, Vector3.ZERO, 0.3, 0.0, 0, false)
				"holy":
					Fx.clump(p, Fx.ALLY["low"], 0.12, Vector3.ZERO, 0.3, 0.0, 0, false)
				"shell":
					Fx.clump(p, Fx.STATE["smoke"], 0.16, Vector3.ZERO, 0.35, 0.0, 0, false)
				_:
					pass
		if t >= 1.0:
			queue_free()
