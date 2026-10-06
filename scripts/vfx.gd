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

# ---------------------------------------------------------------- primitives
static func puff(pos: Vector3, color: Color, size: float, drift: Vector3, life := 0.5, delay := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	var m := Mats.puff(color)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.scale = Vector3.ONE * 0.01
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "global_position", pos + drift, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.45).set_delay(life * 0.55)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.4, life * 0.45).set_delay(life * 0.55)
	tw.chain().tween_callback(mi.queue_free)

static func ground_ring(pos: Vector3, color: Color, from_s: float, to_s: float, life := 0.35, shape := "ring", additive := true) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := Mats.ground(shape, color, additive)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos + Vector3(0, 0.03, 0))
	mi.scale = Vector3.ONE * from_s
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * to_s, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.6).set_delay(life * 0.4)
	tw.chain().tween_callback(mi.queue_free)

static func pop_sprite(pos: Vector3, shape: String, color: Color, size: float, life := 0.18, spin := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := Mats.sprite(shape, color, true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.5).set_delay(life * 0.5)
	if spin != 0.0:
		tw.tween_property(mi, "rotation:z", spin, life)
	tw.chain().tween_callback(mi.queue_free)

static func sparks(pos: Vector3, color: Color, amount := 8, speed := 3.0, life := 0.4, shape := "star", size := 0.14, gravity := -6.0, dir := Vector3.UP, spread := 80.0) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = Mats.particle(shape, true)
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
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(color.r, color.g, color.b, 0))
	g.add_point(0.25, color)
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(p, pos)
	p.emitting = true
	_free_later(p, life + 0.3)

# ---------------------------------------------------------------- composites
static func dust_ring(pos: Vector3, size := 1.0) -> void:
	var n := 9
	for i in n:
		var a := TAU * i / n + randf() * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		puff(pos + d * 0.15 * size + Vector3(0, 0.06, 0), DUST, randf_range(0.16, 0.24) * size, d * 0.55 * size + Vector3(0, 0.1, 0), 0.45)
	ground_ring(pos, Color(1, 1, 1, 0.7), 0.3 * size, 1.5 * size, 0.3, "ring_soft")

static func hit_spark(pos: Vector3, color: Color, big := false) -> void:
	var s := 0.75 if big else 0.5
	pop_sprite(pos, "star", Color(1.3, 1.3, 1.2, 0.9), s, 0.16, randf_range(-0.6, 0.6))
	pop_sprite(pos, "soft", Color(color.r, color.g, color.b, 0.45), s * 1.1, 0.18)
	sparks(pos, color, 10 if big else 6, 3.5, 0.35, "star", 0.14)
	puff(pos, WHITE, 0.14, Vector3(0, 0.2, 0), 0.3)

static func death_poof(pos: Vector3) -> void:
	for i in 9:
		var a := TAU * i / 9.0
		var d := Vector3(cos(a), randf_range(0.2, 0.9), sin(a))
		puff(pos + Vector3(0, 0.3, 0) + d * 0.1, Color(1, 1, 1), randf_range(0.22, 0.34), d * 0.45, 0.55, randf() * 0.05)
	sparks(pos + Vector3(0, 0.35, 0), Data.COL_GOLD, 6, 3.0, 0.6, "star5", 0.2, -5.0)
	pop_sprite(pos + Vector3(0, 0.35, 0), "soft", Color(1.0, 1.0, 1.0, 0.45), 0.9, 0.18)

static func explosion(pos: Vector3, color := Color("ff8a2a"), size := 1.0) -> void:
	pop_sprite(pos + Vector3(0, 0.25, 0), "soft", Color(1.6, 1.3, 0.8, 0.8), 1.3 * size, 0.16)
	pop_sprite(pos + Vector3(0, 0.25, 0), "star", Color(1.8, 1.2, 0.5), 1.2 * size, 0.2, 0.8)
	ground_ring(pos, Color(color.r * 1.5, color.g * 1.5, color.b, 1.0), 0.3, 2.2 * size, 0.35)
	ground_ring(pos, Color(0.25, 0.15, 0.1, 0.45), 1.3 * size, 1.4 * size, 1.4, "blob", false)  # scorch
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(cos(a), randf_range(0.3, 1.0), sin(a))
		puff(pos + Vector3(0, 0.2, 0), Color("fff0d0"), randf_range(0.25, 0.38) * size, d * 0.6 * size, 0.6)
	puff(pos + Vector3(0, 0.25, 0), Color("ffb13b"), 0.55 * size, Vector3(0, 0.35, 0), 0.35)
	sparks(pos + Vector3(0, 0.2, 0), color, 14, 5.0, 0.5, "star", 0.16, -8.0)
	if cam:
		cam.add_trauma(0.25)

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

static func debris(pos: Vector3, count: int, color: Color) -> void:
	for i in count:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * randf_range(0.06, 0.12)
		mi.mesh = b
		mi.material_override = Mats.prop(color.lightened(randf() * 0.2))
		_add(mi, pos + Vector3(0, 0.1, 0))
		var a := randf() * TAU
		var v := Vector3(cos(a) * randf_range(1.0, 2.5), randf_range(2.5, 4.5), sin(a) * randf_range(1.0, 2.5))
		var t := randf_range(0.5, 0.75)
		var fly := func(k: float) -> void:
			var tt := k * t
			mi.global_position = pos + Vector3(v.x * tt, maxf(0.05, 0.1 + v.y * tt - 6.0 * tt * tt), v.z * tt)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_method(fly, 0.0, 1.0, t)
		tw.tween_property(mi, "rotation", Vector3(randf() * 8, randf() * 8, randf() * 8), t)
		tw.chain().tween_property(mi, "scale", Vector3.ZERO, 0.25)
		tw.chain().tween_callback(mi.queue_free)

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

# ---------------------------------------------------------------- projectiles
static func projectile(kind: String, from: Vector3, target: Node3D, on_hit: Callable, speed := 9.0) -> void:
	var pr := Projectile.new()
	pr.kind = kind
	pr.target = target
	pr.on_hit = on_hit
	pr.speed = speed
	pr.start = from
	_add(pr, from)
	pr.setup()

class Projectile extends Node3D:
	var kind := "arrow"
	var target: Node3D
	var on_hit: Callable
	var speed := 9.0
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var t := 0.0
	var dur := 0.4
	var arc := 0.6
	var _trail_acc := 0.0
	var body: Node3D

	func setup() -> void:
		end = _aim()
		var dist := start.distance_to(end)
		dur = clampf(dist / speed, 0.18, 0.8)
		body = Node3D.new()
		add_child(body)
		if kind == "fireball":
			arc = 0.9 + dist * 0.12
			var core := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.1
			s.height = 0.2
			core.mesh = s
			core.material_override = Mats.glow(Color(1.0, 0.95, 0.8), 2.5)
			body.add_child(core)
			var shell := MeshInstance3D.new()
			var s2 := SphereMesh.new()
			s2.radius = 0.17
			s2.height = 0.34
			shell.mesh = s2
			shell.material_override = Mats.fx(Color(2.0, 0.9, 0.2, 0.7), true)
			body.add_child(shell)
		else:
			arc = 0.35 + dist * 0.08
			var shaft := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.018
			c.bottom_radius = 0.018
			c.height = 0.42
			shaft.mesh = c
			shaft.material_override = Mats.prop(Color("8a5a2b"))
			shaft.rotation.x = PI * 0.5
			body.add_child(shaft)
			var tip := MeshInstance3D.new()
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.0
			c2.bottom_radius = 0.045
			c2.height = 0.1
			tip.mesh = c2
			tip.material_override = Mats.prop(Color("dfe6ee"))
			tip.rotation.x = -PI * 0.5
			tip.position.z = -0.24
			body.add_child(tip)
			var fl := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.01, 0.1)
			fl.mesh = b
			fl.material_override = Mats.prop(Color("ff6fae"))
			fl.position.z = 0.18
			body.add_child(fl)

	func _aim() -> Vector3:
		if is_instance_valid(target):
			return target.global_position + Vector3(0, 0.35, 0)
		return end

	func _process(delta: float) -> void:
		t += delta / dur
		if is_instance_valid(target):
			end = _aim()
		var k := minf(t, 1.0)
		var p := start.lerp(end, k) + Vector3(0, sin(k * PI) * arc, 0)
		var prev := global_position
		global_position = p
		if (p - prev).length() > 0.0001:
			body.look_at(p + (p - prev), Vector3.UP)
		_trail_acc += delta
		var step := 0.025 if kind == "fireball" else 0.04
		while _trail_acc > step:
			_trail_acc -= step
			if kind == "fireball":
				Vfx.puff(p, Color(1, 0.97, 0.92), randf_range(0.14, 0.2), Vector3(0, 0.12, 0), 0.55)
			else:
				Vfx.puff(p, Color(1, 1, 1), 0.06, Vector3.ZERO, 0.22)
		if t >= 1.0:
			if on_hit.is_valid():
				on_hit.call(end)
			queue_free()
