class_name Sim
extends RefCounted
## Host-authoritative game simulation. Pure logic: no nodes, no rendering.
## Produces `events` (for VFX/sound) and `snapshot()` (for every peer's View).

const ENEMY_KINDS := ["goblin", "orc", "wolf", "shaman", "bat", "darkknight", "ogre"]

var map: MapDef
var rng := RandomNumberGenerator.new()
var time := 0.0
var gold := Data.START_GOLD
var lives := Data.START_LIVES
var phase := "prep"          # prep | running | won | lost
var wave := 0                # number of waves started
var wave_timer := Data.PREP_TIME
var spawn_queue: Array = []  # [time, lane, kind]
var next_id := 1
var events: Array = []
var danger := PackedFloat32Array([0, 0, 0, 0])
var stats := {"kills": 0, "leaks": 0, "built": 0}

var heroes: Array = []       # Array[Hero], index = slot
var enemies: Array = []
var soldiers: Array = []
var towers := {}             # spot_id -> Tower
var projectiles: Array = []
var zones: Array = []
var inputs: Array = []       # per slot input dictionaries

# ================================================================ entities
class Hero:
	var slot := 0
	var kind := ""
	var def := {}
	var pos := Vector2.ZERO
	var face := 0.0
	var hp := 100.0
	var level := 1
	var xp := 0.0
	var dead := false
	var respawn_t := 0.0
	var atk_cd := 0.0
	var q_cd := 0.0
	var e_cd := 0.0
	var sp_cd := 0.0
	var q_seq := 0
	var e_seq := 0
	var sp_seq := 0
	var dash_hit := {}        # enemies already hit by the current charge
	var dash_kind := ""
	var moving := false
	var guard_t := 0.0        # king shout damage reduction
	var empowered := 0        # queen empowered shots
	var whirl_t := 0.0
	var whirl_tick := 0.0
	var dash_t := 0.0
	var dash_vel := Vector2.ZERO
	var leap_t := 0.0
	var leap_from := Vector2.ZERO
	var leap_to := Vector2.ZERO
	var jump_y := 0.0
	var invuln_t := 0.0
	var hot_t := 0.0          # heal over time
	var name := ""
	func max_hp() -> float:
		return def["hp"] * Data.hero_stat_mult(level)
	func dmg() -> float:
		return def["dmg"] * Data.hero_stat_mult(level)

class Enemy:
	var id := 0
	var kind := ""
	var def := {}
	var lane := 0
	var dist := 0.0
	var offset := 0.0
	var pos := Vector2.ZERO
	var face := 0.0
	var hp := 10.0
	var max_hp := 10.0
	var fly := false
	var blocker = null        # Hero or Soldier
	var atk_cd := 0.0
	var slow_t := 0.0
	var slow_amt := 0.0
	var stun_t := 0.0
	var heal_cd := 3.0
	var moving := true
	var attacking := false
	var alive := true

class Soldier:
	var id := 0
	var tower = null
	var idx := 0
	var pos := Vector2.ZERO
	var face := 0.0
	var hp := 50.0
	var max_hp := 50.0
	var dead := false
	var respawn_t := 0.0
	var target = null
	var atk_cd := 0.0
	var moving := false

class Tower:
	var spot := 0
	var kind := ""
	var level := 1
	var pos := Vector2.ZERO
	var cd := 0.0
	var aim := 0.0
	var rally := Vector2.ZERO
	var soldiers: Array = []
	var lane := 0

# ================================================================ setup
func _init(p_map: MapDef, slots: Array, seed_v := 0) -> void:
	map = p_map
	rng.seed = seed_v if seed_v != 0 else randi()
	for i in 4:
		var s: Dictionary = slots[i]
		var h := Hero.new()
		h.slot = i
		h.kind = s["hero"]
		h.def = Data.HEROES[h.kind]
		h.name = s.get("name", "P%d" % (i + 1))
		h.pos = map.hero_spawn(i)
		h.face = atan2(-h.pos.x, -h.pos.y) + PI
		h.hp = h.max_hp()
		heroes.append(h)
		inputs.append(empty_input())

static func empty_input() -> Dictionary:
	return {"move": Vector2.ZERO, "aim": Vector2.ZERO, "attack": false, "q": 0, "e": 0, "sp": 0}

func _id() -> int:
	next_id += 1
	return next_id

func ev(a: Array) -> void:
	events.append(a)

# ================================================================ requests (validated)
func request_build(slot: int, spot_id: int, kind: String) -> bool:
	if phase == "won" or phase == "lost" or towers.has(spot_id) or not Data.TOWERS.has(kind):
		return false
	var cost: int = Data.TOWERS[kind]["cost"][0]
	if gold < cost:
		ev(["msg", slot, "골드가 부족합니다"])
		return false
	var spot: Dictionary = map.spots[spot_id]
	if not _hero_near(slot, spot["pos"], 3.2):
		return false
	gold -= cost
	var t := Tower.new()
	t.spot = spot_id
	t.kind = kind
	t.pos = spot["pos"]
	t.lane = spot["lane"]
	t.cd = 0.5
	if kind == "barracks":
		t.rally = _rally_for(t)
		for i in 3:
			var s := Soldier.new()
			s.id = _id()
			s.tower = t
			s.idx = i
			s.pos = t.pos
			_soldier_stats(s)
			s.hp = s.max_hp
			t.soldiers.append(s)
			soldiers.append(s)
	towers[spot_id] = t
	stats["built"] += 1
	ev(["build", spot_id, kind, 1, slot])
	return true

func request_upgrade(slot: int, spot_id: int) -> bool:
	if not towers.has(spot_id):
		return false
	var t: Tower = towers[spot_id]
	if t.level >= 3:
		return false
	var cost: int = Data.TOWERS[t.kind]["cost"][t.level]
	if gold < cost:
		ev(["msg", slot, "골드가 부족합니다"])
		return false
	if not _hero_near(slot, t.pos, 3.2):
		return false
	gold -= cost
	t.level += 1
	for s: Soldier in t.soldiers:
		var ratio: float = s.hp / s.max_hp
		_soldier_stats(s)
		s.hp = s.max_hp * maxf(ratio, 0.5) if not s.dead else s.max_hp
	ev(["build", spot_id, t.kind, t.level, slot])
	return true

func request_sell(slot: int, spot_id: int) -> bool:
	if not towers.has(spot_id):
		return false
	var t: Tower = towers[spot_id]
	if not _hero_near(slot, t.pos, 3.2):
		return false
	var refund := int(round(Data.tower_total_cost(t.kind, t.level) * Data.SELL_RATIO))
	gold += refund
	for s: Soldier in t.soldiers:
		if s.target and s.target.blocker == s:
			s.target.blocker = null
		soldiers.erase(s)
	towers.erase(spot_id)
	ev(["sell", spot_id, refund, slot])
	return true

func request_call_wave(slot: int) -> bool:
	if phase == "won" or phase == "lost" or wave >= Data.WAVES.size() or wave_timer < 0.0:
		return false
	if not _hero_near(slot, Vector2.ZERO, MapDef.HORN_R + 1.0):
		return false
	var bonus := int(ceil(wave_timer)) if wave > 0 else 0
	gold += bonus
	var cd_bonus := minf(wave_timer, 10.0)
	for h: Hero in heroes:
		h.q_cd = maxf(h.q_cd - cd_bonus, 0.0)
		h.e_cd = maxf(h.e_cd - cd_bonus, 0.0)
		h.sp_cd = maxf(h.sp_cd - cd_bonus, 0.0)
	ev(["called", slot, bonus])
	_start_wave()
	return true

func _hero_near(slot: int, p: Vector2, r: float) -> bool:
	if slot < 0 or slot >= heroes.size():
		return true
	var h: Hero = heroes[slot]
	return not h.dead and h.pos.distance_to(p) <= r

func _rally_for(t: Tower) -> Vector2:
	var pr: Array = map.project(t.lane, t.pos)
	var road: Vector2 = pr[2]
	return road + (t.pos - road).normalized() * 0.4

func _soldier_stats(s: Soldier) -> void:
	var d: Dictionary = Data.TOWERS["barracks"]
	s.max_hp = d["soldier_hp"][s.tower.level - 1]

# ================================================================ waves
func _start_wave() -> void:
	if wave >= Data.WAVES.size():
		return
	var groups: Array = Data.WAVES[wave].duplicate(true)
	wave += 1
	phase = "running"
	wave_timer = -1.0
	for lane in 4:
		var gl := groups.duplicate(true)
		if wave >= 3:
			gl.append(Data.LANE_EXTRA[lane])
		for g in gl:
			var kind: String = g[0]
			var count: int = g[1]
			if kind == "ogre" and lane % 2 == 1:
				continue     # two bosses (N, S) keep the finale readable
			for i in count:
				spawn_queue.append([time + float(g[3]) + float(g[2]) * i + lane * 0.15, lane, kind])
	ev(["wave", wave])

func _update_waves(dt: float) -> void:
	if phase == "won" or phase == "lost":
		return
	if wave_timer >= 0.0:
		wave_timer -= dt
		if wave_timer <= 0.0:
			_start_wave()
	var i := 0
	while i < spawn_queue.size():
		var s: Array = spawn_queue[i]
		if time >= s[0]:
			_spawn_enemy(s[2], s[1])
			spawn_queue.remove_at(i)
		else:
			i += 1
	# next wave countdown starts when the current wave has fully spawned
	if wave_timer < 0.0 and spawn_queue.is_empty() and wave < Data.WAVES.size():
		wave_timer = Data.WAVE_GAP
	if wave >= Data.WAVES.size() and spawn_queue.is_empty() and enemies.is_empty():
		phase = "won"
		ev(["end", true])

func _spawn_enemy(kind: String, lane: int) -> void:
	var e := Enemy.new()
	e.id = _id()
	e.kind = kind
	e.def = Data.ENEMIES[kind]
	e.lane = lane
	e.max_hp = e.def["hp"] * (1.0 + 0.05 * (wave - 1))
	e.hp = e.max_hp
	e.fly = e.def.get("fly", false)
	e.offset = rng.randf_range(-0.7, 0.7) if not e.def.get("boss", false) else 0.0
	e.pos = map.spawn_pos(lane)
	enemies.append(e)
	if e.def.get("boss", false):
		ev(["boss", lane])

## debug/test helper: place a group of enemies along a lane
func debug_spawn(lane: int, kind: String, count: int, frac: float) -> void:
	for i in count:
		_spawn_enemy(kind, lane)
		var e: Enemy = enemies[enemies.size() - 1]
		e.dist = map.length(lane) * frac - i * 0.6
		e.pos = map.pos_at(lane, e.dist)

# ================================================================ main step
func step(dt: float) -> void:
	time += dt
	if phase == "won" or phase == "lost":
		return
	_update_waves(dt)
	for h: Hero in heroes:
		_update_hero(h, dt)
	for t: Tower in towers.values():
		_update_tower(t, dt)
	for s: Soldier in soldiers:
		_update_soldier(s, dt)
	for e: Enemy in enemies:
		_update_enemy(e, dt)
	_update_projectiles(dt)
	_update_zones(dt)
	enemies = enemies.filter(func(x): return x.alive)
	_separate_enemies()
	_update_danger()
	if lives <= 0 and phase != "lost":
		lives = 0
		phase = "lost"
		ev(["end", false])

# ================================================================ damage
func damage_enemy(e: Enemy, amount: float, dtype: String, src_hero = null, pierce := 0.0, show := true, tag := "") -> void:
	if not e.alive:
		return
	var a := amount
	if dtype == "phys":
		a *= 1.0 - e.def["armor"] * (1.0 - pierce)
	elif dtype == "magic":
		a *= 1.0 - e.def["mr"]
	e.hp -= a
	if show:
		ev(["hit", e.pos.x, e.pos.y, a, 1 if dtype == "magic" else 0, e.id, src_hero.slot if src_hero is Hero else -1, tag])
	if e.hp <= 0.0:
		e.alive = false
		var g: int = e.def["gold"]
		gold += g
		stats["kills"] += 1
		if e.blocker:
			e.blocker = null
		ev(["die", e.id, e.pos.x, e.pos.y, g, ENEMY_KINDS.find(e.kind)])
		if src_hero != null:
			_give_xp(src_hero, g * 3.0)
		# nearby heroes share a little xp
		for h: Hero in heroes:
			if h != src_hero and not h.dead and h.pos.distance_to(e.pos) < 7.0:
				_give_xp(h, g * 1.0)

func _give_xp(h: Hero, amt: float) -> void:
	var before := h.level
	h.xp += amt
	h.level = mini(Data.level_for_xp(h.xp), 5)
	if h.level > before:
		h.hp = minf(h.hp + h.max_hp() * 0.3, h.max_hp())
		ev(["lvl", h.slot, h.level])

func damage_hero(h: Hero, amount: float) -> void:
	if h.dead or h.invuln_t > 0.0:
		return
	var a: float = amount * (1.0 - h.def["armor"])
	if h.guard_t > 0.0:
		a *= 0.5
	h.hp -= a
	if h.hp <= 0.0:
		h.hp = 0.0
		h.dead = true
		h.respawn_t = Data.HERO_RESPAWN
		h.whirl_t = 0.0
		for e: Enemy in enemies:
			if e.blocker == h:
				e.blocker = null
		ev(["hero_die", h.slot, h.pos.x, h.pos.y])

func damage_soldier(s: Soldier, amount: float) -> void:
	if s.dead:
		return
	var armor: float = Data.TOWERS["barracks"]["armor"][s.tower.level - 1]
	s.hp -= amount * (1.0 - armor)
	if s.hp <= 0.0:
		s.dead = true
		s.respawn_t = Data.SOLDIER_RESPAWN
		if s.target and s.target.blocker == s:
			s.target.blocker = null
		s.target = null
		ev(["sdie", s.id, s.pos.x, s.pos.y])

# ================================================================ heroes
func _update_hero(h: Hero, dt: float) -> void:
	if h.dead:
		h.respawn_t -= dt
		if h.respawn_t <= 0.0:
			h.dead = false
			h.hp = h.max_hp()
			h.pos = map.hero_spawn(h.slot)
			h.invuln_t = 1.5
			ev(["respawn", h.slot, h.pos.x, h.pos.y])
		return
	var inp: Dictionary = inputs[h.slot]
	h.atk_cd -= dt
	h.q_cd = maxf(h.q_cd - dt, 0.0)
	h.e_cd = maxf(h.e_cd - dt, 0.0)
	h.sp_cd = maxf(h.sp_cd - dt, 0.0)
	h.guard_t -= dt
	h.invuln_t -= dt
	if h.hot_t > 0.0:
		h.hot_t -= dt
		h.hp = minf(h.hp + 14.0 * dt, h.max_hp())
	# regen out of combat
	h.hp = minf(h.hp + h.max_hp() * 0.01 * dt, h.max_hp())
	var aim: Vector2 = inp["aim"]
	var to_aim := aim - h.pos
	# special movement states
	if h.leap_t > 0.0:
		_update_leap(h, dt)
		return
	if h.dash_t > 0.0:
		h.dash_t -= dt
		_move_hero(h, h.dash_vel * dt)
		if h.dash_kind == "charge":
			for e: Enemy in _enemies_near(h.pos, 1.4, false):
				if not h.dash_hit.has(e.id):
					h.dash_hit[e.id] = true
					damage_enemy(e, 18.0 * Data.hero_stat_mult(h.level), "phys", h)
					e.stun_t = maxf(e.stun_t, 0.5)
					if not e.def.get("boss", false):
						e.pos += h.dash_vel.normalized() * 1.2
		if h.dash_t <= 0.0 and h.dash_kind != "":
			ev(["dash_end", h.slot, h.dash_kind, h.pos.x, h.pos.y])
			h.dash_kind = ""
		return
	var mv: Vector2 = inp["move"]
	if mv.length() > 1.0:
		mv = mv.normalized()
	var spd: float = h.def["speed"] * (0.75 if h.whirl_t > 0.0 else 1.0)
	_move_hero(h, mv * spd * dt)
	h.moving = mv.length() > 0.1
	if to_aim.length() > 0.2:
		h.face = atan2(to_aim.x, to_aim.y)
	elif h.moving:
		h.face = atan2(mv.x, mv.y)
	if h.whirl_t > 0.0:
		h.whirl_t -= dt
		h.whirl_tick -= dt
		if h.whirl_tick <= 0.0:
			h.whirl_tick = 0.25
			for e: Enemy in _enemies_near(h.pos, 2.2, true):
				damage_enemy(e, 8.0 * Data.hero_stat_mult(h.level), "phys", h)
		return
	# skills (sequence counters make presses loss-tolerant over the network)
	if inp["q"] != h.q_seq:
		h.q_seq = inp["q"]
		if h.q_cd <= 0.0:
			_skill_q(h, aim)
	if inp["e"] != h.e_seq:
		h.e_seq = inp["e"]
		if h.e_cd <= 0.0:
			_skill_e(h, aim, mv)
	if inp.get("sp", 0) != h.sp_seq:
		h.sp_seq = inp.get("sp", 0)
		if h.sp_cd <= 0.0:
			_skill_space(h, aim, mv)
			return
	if inp["attack"] and h.atk_cd <= 0.0:
		h.atk_cd = h.def["interval"]
		_hero_attack(h, aim)

func _move_hero(h: Hero, delta: Vector2) -> void:
	var p := h.pos + delta
	# castle body
	var cr := MapDef.CASTLE_R - 0.6
	if p.length() < cr:
		p = p.normalized() * cr
	for t: Tower in towers.values():
		var d: Vector2 = p - t.pos
		if d.length() < 1.05:
			p = t.pos + d.normalized() * 1.05
	p.x = clampf(p.x, -MapDef.BOUND + 1.0, MapDef.BOUND - 1.0)
	p.y = clampf(p.y, -MapDef.BOUND + 1.0, MapDef.BOUND - 1.0)
	h.pos = p

func _hero_attack(h: Hero, aim: Vector2) -> void:
	var dmg := h.dmg()
	var style: String = h.def["atk"]
	var fwd := Vector2(sin(h.face), cos(h.face))
	match style:
		"cleave":
			ev(["atk", "h", h.slot, "melee"])
			var hit := false
			for e: Enemy in _enemies_near(h.pos, h.def["range"], true):
				var d: Vector2 = (e.pos - h.pos)
				if d.length() < 0.6 or rad_to_deg(fwd.angle_to(d.normalized())) <= h.def["arc"] * 0.5:
					damage_enemy(e, dmg, "phys", h)
					hit = true
			if hit:
				ev(["shake", 0.08])
		"spin":
			ev(["atk", "h", h.slot, "spin"])
			for e: Enemy in _enemies_near(h.pos, h.def["range"], true):
				damage_enemy(e, dmg, "phys", h)
		"arrow", "holy":
			var t: Enemy = _aim_target(h.pos, aim, h.def["range"], true)
			var extra := 1.0
			if h.empowered > 0:
				h.empowered -= 1
				extra = 1.6
			ev(["atk", "h", h.slot, "arrow"])
			_fire(style, h.pos, t, aim, dmg * extra, h.def["dtype"], h, 0.0, 0.0, 16.0)
		"fireball":
			ev(["atk", "h", h.slot, "fireball"])
			var tgt := aim
			if tgt.distance_to(h.pos) > h.def["range"]:
				tgt = h.pos + (aim - h.pos).normalized() * h.def["range"]
			_fire("fireball", h.pos, null, tgt, dmg, "magic", h, h.def["splash"], 0.0, 12.0)

func _skill_q(h: Hero, aim: Vector2) -> void:
	var m := Data.hero_stat_mult(h.level)
	h.q_cd = h.def["q"]["cd"]
	match h.kind:
		"king":
			ev(["skill", h.slot, "slam", h.pos.x, h.pos.y])
			for e: Enemy in _enemies_near(h.pos, 3.0, true):
				damage_enemy(e, 40.0 * m, "phys", h)
				e.stun_t = 1.5
		"queen":
			ev(["skill", h.slot, "volley", h.pos.x, h.pos.y])
			var base := (aim - h.pos).angle()
			for i in 7:
				var a := base + deg_to_rad(-30.0 + i * 10.0)
				var to := h.pos + Vector2(cos(a), sin(a)) * 9.0
				var t: Enemy = _aim_target(h.pos, to, 9.0, true, 0.9)
				_fire("arrow", h.pos, t, to, h.dmg() * 1.2, "phys", h, 0.0, 0.0, 18.0)
		"wizard":
			var p := aim
			if p.distance_to(h.pos) > 11.0:
				p = h.pos + (aim - h.pos).normalized() * 11.0
			ev(["skill", h.slot, "meteor", p.x, p.y])
			zones.append({"kind": "meteor", "pos": p, "t": 0.85, "dmg": 90.0 * m, "src": h})
		"valkyrie":
			h.whirl_t = 2.5
			h.whirl_tick = 0.0
			ev(["skill", h.slot, "whirl", h.pos.x, h.pos.y])
		"cleric":
			ev(["skill", h.slot, "heal", h.pos.x, h.pos.y])
			for o: Hero in heroes:
				if not o.dead and o.pos.distance_to(h.pos) <= 5.0:
					o.hp = minf(o.hp + 40.0 * m, o.max_hp())
					o.hot_t = 3.0
					ev(["heal", o.pos.x, o.pos.y, 40.0 * m])
			for s: Soldier in soldiers:
				if not s.dead and s.pos.distance_to(h.pos) <= 5.0:
					s.hp = s.max_hp
					ev(["heal", s.pos.x, s.pos.y, 0.0])

func _clamp_aim(h: Hero, aim: Vector2, r: float) -> Vector2:
	if aim.distance_to(h.pos) > r:
		return h.pos + (aim - h.pos).normalized() * r
	return aim

func _skill_e(h: Hero, aim: Vector2, _mv: Vector2) -> void:
	var m := Data.hero_stat_mult(h.level)
	h.e_cd = h.def["e"]["cd"]
	match h.kind:
		"king":
			h.guard_t = 4.0
			ev(["skill", h.slot, "shout", h.pos.x, h.pos.y])
			for e: Enemy in _enemies_near(h.pos, 4.5, false):
				e.blocker = h
		"queen":
			# piercing arrow: everything on a 12m line takes heavy damage
			var dir := (aim - h.pos).normalized() if aim.distance_to(h.pos) > 0.1 else Vector2(sin(h.face), cos(h.face))
			var end := h.pos + dir * 12.0
			ev(["skill", h.slot, "pierce", h.pos.x, h.pos.y, end.x, end.y])
			for e: Enemy in enemies:
				if not e.alive:
					continue
				var d: Vector2 = e.pos - h.pos
				var along := d.dot(dir)
				if along > -0.3 and along < 12.0 and absf(d.cross(dir)) < 1.0:
					damage_enemy(e, 45.0 * m, "phys", h)
		"wizard":
			ev(["skill", h.slot, "nova", h.pos.x, h.pos.y])
			for e: Enemy in _enemies_near(h.pos, 3.2):
				damage_enemy(e, 35.0 * m, "magic", h)
				e.slow_t = 2.5
				e.slow_amt = 0.5
				if not e.def.get("boss", false):
					e.pos += (e.pos - h.pos).normalized() * 0.8
		"valkyrie":
			var to := _clamp_aim(h, aim, 9.0)
			zones.append({"kind": "axe", "from": h.pos, "to": to, "t": 0.9, "dur": 0.9, "hit_out": {}, "hit_back": {}, "src": h, "m": m})
			ev(["skill", h.slot, "axe", h.pos.x, h.pos.y, to.x, to.y])
		"cleric":
			var p3 := _clamp_aim(h, aim, 10.0)
			zones.append({"kind": "sanct", "pos": p3, "t": 5.0, "tick": 0.0, "src": h, "m": m})
			ev(["skill", h.slot, "sanct", p3.x, p3.y])

## Space: movement skills
func _skill_space(h: Hero, aim: Vector2, mv: Vector2) -> void:
	var m := Data.hero_stat_mult(h.level)
	h.sp_cd = h.def["space"]["cd"]
	var dir := mv.normalized() if mv.length() > 0.1 else (aim - h.pos).normalized()
	if dir.length() < 0.1:
		dir = Vector2(sin(h.face), cos(h.face))
	match h.kind:
		"king":
			_release_blocks(h)
			h.dash_t = 0.32
			h.dash_vel = dir * 22.0
			h.dash_kind = "charge"
			h.dash_hit = {}
			h.face = atan2(dir.x, dir.y)
			ev(["skill", h.slot, "charge", h.pos.x, h.pos.y, h.pos.x + dir.x * 7.0, h.pos.y + dir.y * 7.0])
		"queen":
			var rd := mv.normalized() if mv.length() > 0.1 else -(aim - h.pos).normalized()
			h.dash_t = 0.28
			h.dash_vel = rd * 18.0
			h.dash_kind = "roll"
			h.invuln_t = 0.35
			h.empowered = 3
			_release_blocks(h)
			ev(["skill", h.slot, "roll", h.pos.x, h.pos.y, h.pos.x + rd.x * 5.0, h.pos.y + rd.y * 5.0])
		"wizard":
			var p := _clamp_aim(h, aim, 8.0)
			ev(["skill", h.slot, "blink", h.pos.x, h.pos.y, p.x, p.y])
			_release_blocks(h)
			h.pos = p
			_move_hero(h, Vector2.ZERO)
			for e: Enemy in _enemies_near(h.pos, 2.0, false):
				damage_enemy(e, 20.0 * m, "magic", h)
		"valkyrie":
			var p2 := _clamp_aim(h, aim, 8.0)
			h.leap_t = 0.5
			h.leap_from = h.pos
			h.leap_to = p2
			_release_blocks(h)
			ev(["skill", h.slot, "leap", h.pos.x, h.pos.y, p2.x, p2.y])
		"cleric":
			_release_blocks(h)
			h.dash_t = 0.3
			h.dash_vel = dir * 20.0
			h.dash_kind = "lightdash"
			h.invuln_t = 0.3
			h.hp = minf(h.hp + 25.0 * m, h.max_hp())
			ev(["skill", h.slot, "lightdash", h.pos.x, h.pos.y, h.pos.x + dir.x * 6.0, h.pos.y + dir.y * 6.0])

func _update_leap(h: Hero, dt: float) -> void:
	h.leap_t -= dt
	var k := clampf(1.0 - h.leap_t / 0.5, 0.0, 1.0)
	h.pos = h.leap_from.lerp(h.leap_to, k)
	h.jump_y = sin(k * PI) * 2.2
	if h.leap_t <= 0.0:
		h.jump_y = 0.0
		_move_hero(h, Vector2.ZERO)
		var m := Data.hero_stat_mult(h.level)
		ev(["boom", "leap", h.pos.x, h.pos.y, 2.5])
		for e: Enemy in _enemies_near(h.pos, 2.5, true):
			damage_enemy(e, 35.0 * m, "phys", h)
			if not e.def.get("boss", false):
				e.stun_t = maxf(e.stun_t, 0.6)

func _release_blocks(h: Hero) -> void:
	for e: Enemy in enemies:
		if e.blocker == h:
			e.blocker = null

# ================================================================ helpers
func _enemies_near(p: Vector2, r: float, include_air := true) -> Array:
	var out := []
	for e: Enemy in enemies:
		if e.alive and (include_air or not e.fly) and e.pos.distance_to(p) <= r:
			out.append(e)
	return out

## enemy nearest to the line from `from` toward `aim`, inside range
func _aim_target(from: Vector2, aim: Vector2, rng_r: float, air: bool, width := 1.6) -> Enemy:
	var dir := (aim - from)
	if dir.length() < 0.01:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	var best: Enemy = null
	var best_score := INF
	for e: Enemy in enemies:
		if not e.alive or (e.fly and not air):
			continue
		var d: Vector2 = e.pos - from
		var along := d.dot(dir)
		if along < -0.5 or d.length() > rng_r:
			continue
		var perp := absf(d.cross(dir))
		var allowed := width + along * 0.18
		if perp > allowed:
			continue
		var score := perp * 2.0 + along * 0.15 + e.pos.distance_to(aim) * 0.3
		if score < best_score:
			best_score = score
			best = e
	return best

## Launch a projectile. If target is null it flies to the point.
func _fire(kind: String, from: Vector2, target, to: Vector2, dmg: float, dtype: String, src, splash: float, pierce: float, speed: float) -> void:
	var end: Vector2 = target.pos if target else to
	var dur := clampf(from.distance_to(end) / speed, 0.12, 1.4)
	if kind == "shell":
		dur = 0.9
	projectiles.append({"kind": kind, "target": target, "to": end, "t": dur, "dmg": dmg, "dtype": dtype,
		"src": src, "splash": splash, "pierce": pierce})
	var fy := 1.0
	if src is Tower:
		fy = 2.4 if kind != "shell" else 1.6
	ev(["proj", kind, from.x, fy, from.y, target.id if target else -1, end.x, end.y, dur])

func _update_projectiles(dt: float) -> void:
	var keep := []
	for p in projectiles:
		p["t"] -= dt
		var tgt = p["target"]
		if tgt and tgt.alive:
			p["to"] = tgt.pos
		if p["t"] > 0.0:
			keep.append(p)
			continue
		var src_hero = p["src"] if p["src"] is Hero else null
		var tag: String = (p["src"] as Tower).kind if p["src"] is Tower else ""
		if p["splash"] > 0.0:
			var at: Vector2 = p["to"]
			ev(["boom", p["kind"], at.x, at.y, p["splash"]])
			var air: bool = p["kind"] != "shell"
			for e: Enemy in enemies:
				if e.alive and (air or not e.fly) and e.pos.distance_to(at) <= p["splash"]:
					damage_enemy(e, p["dmg"], p["dtype"], src_hero, p["pierce"], true, tag)
		elif tgt and tgt.alive:
			damage_enemy(tgt, p["dmg"], p["dtype"], src_hero, p["pierce"], true, tag)
	projectiles = keep

func _update_zones(dt: float) -> void:
	var keep := []
	for z in zones:
		z["t"] -= dt
		match z["kind"]:
			"meteor":
				if z["t"] <= 0.0:
					var p: Vector2 = z["pos"]
					ev(["boom", "meteor", p.x, p.y, 3.5])
					for e: Enemy in _enemies_near(p, 3.5):
						damage_enemy(e, z["dmg"], "magic", z["src"])
						if not e.def.get("boss", false):
							e.stun_t = maxf(e.stun_t, 0.5)
					continue
			"axe":
				var k: float = 1.0 - z["t"] / z["dur"]
				var out := k < 0.5
				var src: Hero = z["src"]
				var back_to: Vector2 = src.pos if not src.dead else z["from"]
				var ap: Vector2 = z["from"].lerp(z["to"], k * 2.0) if out else z["to"].lerp(back_to, (k - 0.5) * 2.0)
				var hits: Dictionary = z["hit_out"] if out else z["hit_back"]
				for e: Enemy in _enemies_near(ap, 1.3):
					if not hits.has(e.id):
						hits[e.id] = true
						damage_enemy(e, 26.0 * z["m"], "phys", src)
				if z["t"] <= 0.0:
					continue
			"sanct":
				z["tick"] -= dt
				var p2: Vector2 = z["pos"]
				for e: Enemy in _enemies_near(p2, 3.5):
					e.slow_t = 0.3
					e.slow_amt = 0.5
				if z["tick"] <= 0.0:
					z["tick"] = 0.5
					for e: Enemy in _enemies_near(p2, 3.5):
						damage_enemy(e, 3.0 * z["m"], "magic", z["src"], 0.0, false)
				if z["t"] <= 0.0:
					continue
		keep.append(z)
	zones = keep

# ================================================================ towers
func _tower_target(t: Tower, rng_r: float, air: bool) -> Enemy:
	var best: Enemy = null
	var best_prog := -1.0
	for e: Enemy in enemies:
		if not e.alive or (e.fly and not air):
			continue
		if e.pos.distance_to(t.pos) > rng_r:
			continue
		var prog: float = e.dist / map.length(e.lane)
		if prog > best_prog:
			best_prog = prog
			best = e
	return best

func _update_tower(t: Tower, dt: float) -> void:
	if t.kind == "barracks":
		return
	t.cd -= dt
	if t.cd > 0.0:
		return
	var d: Dictionary = Data.TOWERS[t.kind]
	var li := t.level - 1
	var target := _tower_target(t, d["range"][li], d.get("air", false))
	if target == null:
		return
	t.cd = d["interval"][li]
	t.aim = atan2(target.pos.x - t.pos.x, target.pos.y - t.pos.y)
	ev(["atk", "t", t.spot, t.kind])
	match t.kind:
		"archer":
			_fire("tower_arrow", t.pos, target, target.pos, d["dmg"][li], "phys", t, 0.0, 0.0, 14.0)
		"mage":
			_fire("magic", t.pos, target, target.pos, d["dmg"][li], "magic", t, 0.0, 0.0, 11.0)
		"artillery":
			var lead: Vector2 = map.pos_at(target.lane, target.dist + target.def["speed"] * 0.9 * _speed_mult(target))
			if target.blocker or target.stun_t > 0.0:
				lead = target.pos
			_fire("shell", t.pos, null, lead, d["dmg"][li], "phys", t, d["splash"][li], d["pierce"], 1.0)

# ================================================================ soldiers
func _update_soldier(s: Soldier, dt: float) -> void:
	var t: Tower = s.tower
	if s.dead:
		s.respawn_t -= dt
		if s.respawn_t <= 0.0:
			s.dead = false
			s.hp = s.max_hp
			s.pos = t.pos
		return
	var d: Dictionary = Data.TOWERS["barracks"]
	var li := t.level - 1
	var rally := t.rally + Vector2(cos(s.idx * TAU / 3.0), sin(s.idx * TAU / 3.0)) * 0.7
	s.atk_cd -= dt
	if s.target and (not s.target.alive or s.target.pos.distance_to(t.rally) > d["range"][li] + 1.0):
		if s.target.blocker == s:
			s.target.blocker = null
		s.target = null
	if s.target == null:
		var best: Enemy = null
		var bd := INF
		for e: Enemy in enemies:
			if not e.alive or e.fly:
				continue
			if e.pos.distance_to(t.rally) > d["range"][li]:
				continue
			var score: float = e.pos.distance_to(s.pos) + (3.0 if e.blocker != null else 0.0)
			if score < bd:
				bd = score
				best = e
		s.target = best
	var goal := rally
	if s.target:
		goal = s.target.pos
	var to := goal - s.pos
	var reach := 0.85 if s.target else 0.08
	if to.length() > reach:
		s.pos += to.normalized() * minf(3.2 * dt, to.length() - reach * 0.5)
		s.moving = true
		s.face = atan2(to.x, to.y)
	else:
		s.moving = false
		if s.target:
			s.face = atan2(to.x, to.y)
			if s.target.blocker == null:
				s.target.blocker = s
			if s.atk_cd <= 0.0:
				s.atk_cd = d["interval"][li]
				ev(["atk", "s", s.id, "melee"])
				damage_enemy(s.target, d["dmg"][li], "phys", null, 0.0, true, "soldier")

# ================================================================ enemies
func _speed_mult(e: Enemy) -> float:
	return 1.0 - (e.slow_amt if e.slow_t > 0.0 else 0.0)

func _update_enemy(e: Enemy, dt: float) -> void:
	if not e.alive:
		return
	e.slow_t -= dt
	e.atk_cd -= dt
	if e.stun_t > 0.0:
		e.stun_t -= dt
		e.moving = false
		return
	# shaman heal
	if e.def.get("heal", false):
		e.heal_cd -= dt
		if e.heal_cd <= 0.0:
			e.heal_cd = 4.0
			var healed := false
			for o: Enemy in enemies:
				if o.alive and o != e and o.pos.distance_to(e.pos) < 3.2 and o.hp < o.max_hp:
					o.hp = minf(o.hp + 25.0, o.max_hp)
					healed = true
			if healed:
				ev(["eheal", e.pos.x, e.pos.y])
	# engagement with heroes (ground only)
	if not e.fly and e.blocker == null:
		for h: Hero in heroes:
			if h.dead or h.leap_t > 0.0 or h.dash_t > 0.0:
				continue
			if h.pos.distance_to(e.pos) < 1.3 and _engaged_count(h) < 3:
				e.blocker = h
				break
	var b = e.blocker
	if b != null:
		var valid := false
		if b is Hero:
			valid = not b.dead
		elif b is Soldier:
			valid = not b.dead and soldiers.has(b)
		if not valid:
			e.blocker = null
			b = null
	e.attacking = false
	if b != null:
		var to: Vector2 = b.pos - e.pos
		if to.length() <= 1.25:
			e.moving = false
			e.attacking = true
			e.face = atan2(to.x, to.y)
			if e.atk_cd <= 0.0 and e.def["dmg"] > 0.0:
				e.atk_cd = e.def["interval"]
				ev(["atk", "e", e.id, "melee"])
				if e.def.get("boss", false):
					ev(["boom", "ogre", e.pos.x + to.normalized().x, e.pos.y + to.normalized().y, 2.2])
					for h: Hero in heroes:
						if not h.dead and h.pos.distance_to(e.pos) < 2.6:
							damage_hero(h, e.def["dmg"])
					for s: Soldier in soldiers:
						if not s.dead and s.pos.distance_to(e.pos) < 2.6:
							damage_soldier(s, e.def["dmg"])
				elif b is Hero:
					damage_hero(b, e.def["dmg"])
				else:
					damage_soldier(b, e.def["dmg"])
			return
		elif to.length() > 3.0:
			e.blocker = null
		else:
			# step toward the blocker (they meet halfway)
			e.pos += to.normalized() * e.def["speed"] * 0.6 * dt
			e.moving = true
			e.face = atan2(to.x, to.y)
			return
	# walk the path
	var spd: float = e.def["speed"] * _speed_mult(e)
	e.dist += spd * dt
	var L := map.length(e.lane)
	if e.dist >= L:
		e.alive = false
		lives -= int(e.def["lives"])
		stats["leaks"] += 1
		stats["leak_lane%d" % e.lane] = stats.get("leak_lane%d" % e.lane, 0) + int(e.def["lives"])
		ev(["leak", e.lane, int(e.def["lives"]), e.pos.x, e.pos.y])
		return
	var p := map.pos_at(e.lane, e.dist)
	var tdir := map.dir_at(e.lane, e.dist)
	var n := Vector2(-tdir.y, tdir.x)
	var target := p + n * e.offset
	var mv := target - e.pos
	if mv.length() > 0.001:
		e.face = atan2(mv.x, mv.y)
	e.pos = e.pos.lerp(target, minf(1.0, dt * 8.0)) if mv.length() < 2.0 else target
	e.moving = true

## keep ground enemies from stacking on one spot (especially around blockers)
func _separate_enemies() -> void:
	var n := enemies.size()
	for i in n:
		var a: Enemy = enemies[i]
		if a.fly:
			continue
		for j in range(i + 1, n):
			var b: Enemy = enemies[j]
			if b.fly:
				continue
			var d := a.pos - b.pos
			var l := d.length()
			var minr := 0.55 * (2.0 if a.def.get("boss", false) or b.def.get("boss", false) else 1.0)
			if l < minr:
				var push := (d / l if l > 0.001 else Vector2(rng.randf() - 0.5, rng.randf() - 0.5).normalized()) * (minr - l) * 0.5
				a.pos += push
				b.pos -= push

func _engaged_count(h: Hero) -> int:
	var n := 0
	for e: Enemy in enemies:
		if e.blocker == h:
			n += 1
	return n

# ================================================================ danger
func _update_danger() -> void:
	var acc := PackedFloat32Array([0, 0, 0, 0])
	for e: Enemy in enemies:
		var prog: float = e.dist / map.length(e.lane)
		var weight: float = (e.hp / 60.0) * (0.25 + prog * prog * 2.0)
		if e.blocker != null:
			weight *= 0.5
		acc[e.lane] += weight
	for k in 4:
		var v := clampf(acc[k] / 6.0, 0.0, 1.0)
		danger[k] = lerpf(danger[k], v, 0.1)

# ================================================================ snapshot
func snapshot() -> Dictionary:
	var hs := []
	for h: Hero in heroes:
		var mh := h.max_hp()
		var lvl_lo: float = Data.XP_LEVELS[h.level - 1]
		var lvl_hi: float = Data.XP_LEVELS[h.level] if h.level < 5 else lvl_lo + 1.0
		var xpf := clampf((h.xp - lvl_lo) / (lvl_hi - lvl_lo), 0.0, 1.0) if h.level < 5 else 1.0
		hs.append([h.slot, h.pos.x, h.pos.y, h.face, h.hp, mh, 1 if h.dead else 0, h.respawn_t, h.level, xpf,
			h.q_cd / h.def["q"]["cd"], h.e_cd / h.def["e"]["cd"], 1 if h.moving else 0,
			1 if h.whirl_t > 0.0 else 0, h.jump_y, 1 if h.guard_t > 0.0 else 0, h.sp_cd / h.def["space"]["cd"]])
	var es := PackedFloat32Array()
	for e: Enemy in enemies:
		var flags := (1 if e.moving else 0) | (2 if e.attacking else 0) | (4 if e.slow_t > 0.0 else 0) | (8 if e.stun_t > 0.0 else 0)
		es.append_array([e.id, ENEMY_KINDS.find(e.kind), e.pos.x, e.pos.y, e.face, e.hp / e.max_hp, flags, 1.0 if e.fly else 0.0])
	var ss := PackedFloat32Array()
	for s: Soldier in soldiers:
		if s.dead:
			continue
		ss.append_array([s.id, s.pos.x, s.pos.y, s.face, s.hp / s.max_hp, 1.0 if s.moving else 0.0])
	var ts := []
	for t: Tower in towers.values():
		ts.append([t.spot, Data.TOWER_ORDER.find(t.kind), t.level, t.aim])
	return {"h": hs, "e": es, "s": ss, "t": ts, "g": gold, "l": lives, "w": wave, "wn": Data.WAVES.size(),
		"wt": wave_timer, "ph": phase, "tm": time, "d": danger, "st": stats}
