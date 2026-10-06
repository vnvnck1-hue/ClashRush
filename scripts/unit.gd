class_name Unit
extends Node3D
## Runtime unit: stats, targeting, free movement, attacks, energy/super, clash abilities.
## Gameplay code only raises events; motion & VFX live in UnitModel / Vfx / Hud / Sfx.

signal died(unit: Unit)

var kind := ""
var team := 0
var star := 1
var def := {}
var game: Node            # Main
var model: UnitModel
var ring: MeshInstance3D
var blob: MeshInstance3D
var ring_mat: StandardMaterial3D

var home := Vector2i.ZERO
var max_hp := 10.0
var hp := 10.0
var dmg := 1.0
var energy := 0.0
var alive := true
var hero := false
var revealed := true

var target: Unit
var cooldown := 0.0
var attacking := false
var retarget_t := 0.0
var knock := Vector3.ZERO
var speed_boost_t := 0.0
var clash_busy := false
var lifted := false
var _lift := 0.0
var _trail_t := 0.0
var _t := 0.0

const RADIUS := 0.34
const MODEL_SCALE := 1.45

func setup(p_kind: String, p_team: int, p_star: int, p_game: Node) -> Unit:
	kind = p_kind
	team = p_team
	star = p_star
	game = p_game
	def = Data.get_def(kind)
	hero = def.get("hero", false)
	# ground ring + blob shadow (not squashed with model)
	blob = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.9, 0.9)
	blob.mesh = pm
	blob.material_override = Mats.ground("blob", Color(0.23, 0.2, 0.44, 0.45), false)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.015
	add_child(blob)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.37
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	ring_mat = Mats.glow(color(), 1.15)
	ring.material_override = ring_mat
	ring.scale = Vector3(1, 0.25, 1)
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	model = UnitModel.new().build(kind, team)
	add_child(model)
	model.rotation.y = 0.0 if team == Data.TEAM_PLAYER else PI
	_apply_stats()
	return self

func color() -> Color:
	return Data.COL_PLAYER if team == Data.TEAM_PLAYER else Data.COL_ENEMY

func _apply_stats() -> void:
	var m := Data.star_mult(star)
	max_hp = def["hp"] * m
	hp = max_hp
	dmg = def["dmg"] * m
	var s: float = def["scale"] * MODEL_SCALE * (1.0 + 0.08 * (star - 1))
	model.scale = Vector3.ONE * s
	var rs := minf(s * 0.62, 1.05)
	ring.scale = Vector3(rs, 0.25, rs)
	blob.scale = Vector3.ONE * rs * 1.1

func upgrade() -> void:
	star = mini(star + 1, 3)
	_apply_stats()
	model.punch_scale(1.45, 0.6, 0.6)
	model.flash(Color(1, 0.9, 0.4), 1.6, 0.35)
	Vfx.upgrade_pillar(global_position)
	Sfx.play("chime", -4.0)

func reset_for_round() -> void:
	alive = true
	visible = true
	hp = max_hp
	energy = 0.0
	target = null
	attacking = false
	clash_busy = false
	cooldown = randf_range(0.1, 0.35)
	knock = Vector3.ZERO
	speed_boost_t = 0.0
	position = World.tile_pos(home.x, home.y)
	model.rotation = Vector3(0, 0.0 if team == Data.TEAM_PLAYER else PI, 0)
	model.position = Vector3.ZERO
	model.walk = 0.0
	ring.visible = true
	blob.visible = true

## Toy drop: fall in, squash on landing, dust ring.
func drop_in(height := 1.4, delay := 0.0) -> void:
	model.position.y = height
	model.scale.y = model.scale.x
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(model, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_land)

func _land() -> void:
	model.punch_scale(1.35, 0.62, 0.45)
	Vfx.dust_ring(global_position, 0.8)
	Sfx.play("pop", -5.0, 1.0 + randf() * 0.2)

func set_ghost(on: bool) -> void:
	model.set_ghost(on)
	ring.visible = not on

func set_lifted(on: bool) -> void:
	lifted = on

func _process(delta: float) -> void:
	_t += delta
	var goal := 1.0 if lifted else 0.0
	_lift = lerpf(_lift, goal, 1.0 - exp(-delta * 18.0))
	if _lift > 0.001 or lifted:
		model.position.y = _lift * 0.55
		model.rotation.z = sin(_t * 9.0) * 0.12 * _lift
		model.rotation.x = -0.25 * _lift

# ---------------------------------------------------------------- battle
func enemies() -> Array:
	return game.alive_units(1 - team)

func _pick_target() -> Unit:
	var best: Unit = null
	var far: bool = def.get("target", "") == "farthest"
	var best_d := -1.0 if far else INF
	for u in enemies():
		var d := _flat(u.global_position - global_position).length()
		if (far and d > best_d) or (not far and d < best_d):
			best_d = d
			best = u
	return best

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

func _face(dir: Vector3, delta: float, rate := 12.0) -> void:
	if dir.length() < 0.001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-delta * rate))

func battle_tick(delta: float) -> void:
	if not alive:
		return
	# knockback always applies
	if knock.length() > 0.01:
		position += knock * delta
		knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-delta * 9.0))
	if clash_busy:
		return
	var atk_mult := 1.0
	if def.get("passive", "") == "rage":
		atk_mult += 0.6 * (1.0 - hp / max_hp)
	cooldown -= delta * atk_mult
	speed_boost_t -= delta
	retarget_t -= delta
	if target == null or not target.alive or retarget_t <= 0.0:
		target = _pick_target()
		retarget_t = 0.6
	if target == null:
		model.walk = lerpf(model.walk, 0.0, delta * 8.0)
		return
	var to := _flat(target.global_position - global_position)
	var dist := to.length()
	var rng: float = def["range"]
	if hero and energy >= 100.0 and not attacking:
		_super()
		return
	if dist > rng + 0.05:
		if not attacking:
			var spd: float = def["speed"] * (2.0 if speed_boost_t > 0.0 else 1.0)
			var v := to.normalized() * spd + _separation() * 3.2
			position += v * delta
			_face(to, delta)
			model.walk = lerpf(model.walk, 1.0, 1.0 - exp(-delta * 10.0))
			if speed_boost_t > 0.0:
				_trail_t -= delta
				if _trail_t <= 0.0:
					_trail_t = 0.06
					Vfx.speed_puffs(global_position, Color("e8d2a8"))
	else:
		model.walk = lerpf(model.walk, 0.0, 1.0 - exp(-delta * 12.0))
		_face(to, delta, 18.0)
		position += _separation() * delta * 2.0
		if cooldown <= 0.0 and not attacking:
			_attack()
	position.x = clampf(position.x, -2.45, 2.45)
	position.z = clampf(position.z, -3.95, 3.95)

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for u in game.alive_units(-1):
		if u == self:
			continue
		var d := _flat(global_position - u.global_position)
		var l := d.length()
		var minr := RADIUS * 2.0
		if l < minr and l > 0.0001:
			push += d / l * (minr - l) / minr
		elif l <= 0.0001:
			push += Vector3(randf() - 0.5, 0, randf() - 0.5)
	return push

func _attack() -> void:
	attacking = true
	var style: String = def["attack"]
	var interval: float = def["interval"]
	cooldown = interval
	var impact := model.play_attack(style)
	if style != "spin":
		Sfx.play("whoosh", -16.0, 1.3)
	await get_tree().create_timer(impact, false).timeout
	if not alive or not game.in_battle():
		attacking = false
		return
	match style:
		"melee":
			if target and target.alive:
				var mid := global_position.lerp(target.global_position, 0.6) + Vector3(0, 0.4, 0)
				var big := kind == "giant" or kind == "king"
				Vfx.hit_spark(mid, color().lightened(0.3), big)
				target.take_damage(dmg, self)
				if big:
					Vfx.cam.add_trauma(0.18)
				Sfx.play("thud", -4.0 if big else -7.0, 0.8 if big else 1.1)
		"arrow":
			var t := target
			var d := dmg
			var from := global_position + Vector3(0, 0.45, 0) + _fwd() * 0.25
			var on_arrow := func(_p: Vector3) -> void:
				if is_instance_valid(t) and t.alive:
					Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), Color("ffe08a"))
					t.take_damage(d, self)
					Sfx.play("thud", -10.0, 1.4)
			Vfx.projectile("arrow", from, t, on_arrow, 10.0)
		"fireball":
			var t2 := target
			var d2 := dmg
			var splash: float = def.get("splash", 1.0)
			var from2 := global_position + Vector3(0, 0.6, 0) + _fwd() * 0.3
			Sfx.play("whoosh", -9.0, 0.7)
			var on_fire := func(p: Vector3) -> void:
				var ground := Vector3(p.x, 0, p.z)
				Vfx.explosion(ground, Color("ff8a2a"), 0.8)
				Sfx.play("boom", -6.0, 1.3)
				for u in game.alive_units(1 - team):
					if _flat(u.global_position - ground).length() <= splash:
						u.take_damage(d2, self)
			Vfx.projectile("fireball", from2, t2, on_fire, 7.0)
		"spin":
			var splash2: float = def.get("splash", 1.1)
			Vfx.spin_slash(global_position, splash2, Color("ffb070"))
			Sfx.play("whoosh", -5.0, 0.9)
			for u in enemies():
				if _flat(u.global_position - global_position).length() <= splash2 + 0.2:
					Vfx.hit_spark(u.global_position + Vector3(0, 0.4, 0), Color("ffb070"))
					u.take_damage(dmg, self)
	if hero:
		gain_energy(20.0)
	await get_tree().create_timer(0.12, false).timeout
	attacking = false

func _fwd() -> Vector3:
	return -model.global_transform.basis.z.normalized()

func gain_energy(v: float) -> void:
	if hero:
		energy = minf(energy + v, 100.0)

func take_damage(amount: float, from: Unit) -> void:
	if not alive:
		return
	hp -= amount
	gain_energy(8.0)
	model.flash()
	model.punch_scale(1.22, 0.78, 0.35)
	if from:
		var away := _flat(global_position - from.global_position).normalized()
		knock += away * 1.2
	game.hud.damage_number(global_position + Vector3(0, 0.9 * model.scale.y, 0), amount, team)
	if hp <= 0.0:
		_die()

func _die() -> void:
	alive = false
	hp = 0.0
	attacking = false
	ring.visible = false
	blob.visible = false
	Sfx.play("poof", -5.0)
	var tw := create_tween().set_parallel(true)
	var fall_dir := 1.0 if randf() < 0.5 else -1.0
	tw.tween_property(model, "rotation:z", 1.4 * fall_dir, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "position:y", 0.25, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_vanish)
	died.emit(self)

func _vanish() -> void:
	Vfx.death_poof(global_position)
	visible = false

# ---------------------------------------------------------------- abilities
func _super() -> void:
	energy = 0.0
	attacking = true
	match def.get("super", ""):
		"slam":
			game.hud.callout(global_position + Vector3(0, 1.4, 0), "GROUND SLAM!", Data.COL_GOLD)
			Sfx.play("whoosh", -4.0, 0.6)
			model.flash(Color(1, 0.85, 0.3), 1.0, 0.5)
			var tw := create_tween()
			tw.tween_property(model, "position:y", 1.1, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(model, "rotation:x", -0.5, 0.28)
			tw.tween_property(model, "position:y", 0.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(model, "rotation:x", 0.3, 0.09)
			await tw.finished
			if not alive or not game.in_battle():
				attacking = false
				return
			model.rotation.x = 0.0
			model.punch_scale(1.5, 0.5, 0.6)
			Vfx.slam(global_position, 1.7)
			Sfx.play("boom", -2.0, 0.8)
			for u in enemies():
				var d := _flat(u.global_position - global_position)
				if d.length() <= 1.7:
					u.take_damage(6.0 * Data.star_mult(star), self)
					u.knock += d.normalized() * 5.0
		"volley":
			game.hud.callout(global_position + Vector3(0, 1.4, 0), "TRIPLE SHOT!", Color("ff8ad8"))
			model.flash(Color(1, 0.5, 0.9), 1.0, 0.4)
			var targets := enemies()
			targets.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
			for i in mini(3, targets.size()):
				var t: Unit = targets[i]
				model.play_attack("arrow")
				await get_tree().create_timer(0.14, false).timeout
				if not alive or not game.in_battle():
					break
				Sfx.play("whoosh", -8.0, 1.5)
				var d2 := 3.0 * Data.star_mult(star)
				var on_v := func(_p: Vector3) -> void:
					if is_instance_valid(t) and t.alive:
						Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), Color("ff8ad8"), true)
						t.take_damage(d2, self)
				Vfx.projectile("arrow", global_position + Vector3(0, 0.5, 0), t, on_v, 12.0)
	await get_tree().create_timer(0.2, false).timeout
	attacking = false

## Called at CLASH!! moment.
func clash_ability() -> void:
	match def.get("clash", ""):
		"leap":
			var t := _pick_target()
			if t == null:
				return
			clash_busy = true
			var start := global_position
			var dir := _flat(t.global_position - start)
			var end := start + dir - dir.normalized() * 0.6
			end.x = clampf(end.x, -2.45, 2.45)
			end.z = clampf(end.z, -3.95, 3.95)
			_face(dir, 1.0, 100.0)
			model.punch_scale(1.3, 0.6, 0.2)
			Sfx.play("whoosh", -6.0, 1.6)
			game.hud.callout(global_position + Vector3(0, 1.1, 0), "LEAP!", Color("8fd14f"))
			var step := func(k: float) -> void:
				global_position = start.lerp(end, k) + Vector3(0, sin(k * PI) * 1.3, 0)
				if randf() < 0.5:
					Vfx.speed_puffs(global_position, Color("c8f0a0"))
			var tw := create_tween()
			tw.tween_method(step, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			await tw.finished
			global_position.y = 0.0
			model.punch_scale(1.35, 0.6, 0.4)
			Vfx.dust_ring(global_position, 0.7)
			cooldown = 0.0
			clash_busy = false
		"charge":
			speed_boost_t = 1.6
			model.punch_scale(0.8, 1.25, 0.4)
			game.hud.callout(global_position + Vector3(0, 1.4, 0), "CHARGE!", Color("ffb070"))
			Sfx.play("thud", -6.0, 0.6)
