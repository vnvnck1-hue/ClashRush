class_name Bot
extends RefCounted
## AI hero controller. Produces the same input dictionary a human produces and issues build
## requests like a player would: guards its own lane, builds/upgrades its lane's spots,
## and runs to help a lane that is in danger when its own lane is calm.

const BUILD_PLAN := ["archer", "barracks", "mage", "archer", "artillery", "mage"]

var slot := 0
var sim: Sim
var q_seq := 0
var e_seq := 0
var sp_seq := 0
var help_lane := -1
var think_t := 0.0
var build_goal := -1          # spot id we are walking to
var reserve := 0              # gold to keep for humans
var stuck_t := 0.0

func _init(p_sim: Sim, p_slot: int, p_reserve := 0) -> void:
	sim = p_sim
	slot = p_slot
	reserve = p_reserve

func compute(dt: float) -> Dictionary:
	var inp := Sim.empty_input()
	inp["q"] = q_seq
	inp["e"] = e_seq
	var h: Sim.Hero = sim.heroes[slot]
	if h.dead or sim.phase == "won" or sim.phase == "lost":
		return inp
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.5
		_decide_lane()
	var lane := help_lane if help_lane >= 0 else slot
	var target := _front_enemy(lane, h)
	var ranged: bool = h.def["range"] > 3.0
	var goal: Vector2
	# build when the fight is still far away
	var rich: bool = sim.gold >= 260 + reserve and h.hp > h.max_hp() * 0.5
	if target and (target.pos.distance_to(h.pos) > 10.0 or rich) and help_lane < 0:
		var bg := _build_or_guard(h, lane, true)
		if bg != Vector2.INF:
			var mvb := bg - h.pos
			if mvb.length() > 0.4:
				inp["move"] = mvb.normalized()
			inp["aim"] = target.pos
			return inp
	if target:
		var to: Vector2 = target.pos - h.pos
		var want := 6.0 if ranged else 1.0
		if h.kind == "cleric":
			want = 6.5
		if to.length() > want:
			goal = target.pos - to.normalized() * want * 0.9
		else:
			goal = h.pos
			if ranged and to.length() < 2.5:
				goal = h.pos - to.normalized() * 2.0    # kite
		inp["aim"] = target.pos
		inp["attack"] = to.length() <= h.def["range"] + 0.5
		_use_skills(h, target, inp)
		build_goal = -1
	else:
		inp["aim"] = h.pos + Vector2(sin(h.face), cos(h.face)) * 3.0
		goal = _build_or_guard(h, lane)
	var mv := goal - h.pos
	if mv.length() > 0.4:
		inp["move"] = mv.normalized()
	inp["q"] = q_seq
	inp["e"] = e_seq
	inp["sp"] = sp_seq
	return inp

func _decide_lane() -> void:
	var own: float = sim.danger[slot]
	var worst := -1
	var wv := 0.0
	for k in 4:
		if k == slot:
			continue
		var owner: Sim.Hero = sim.heroes[k]
		var v: float = sim.danger[k] * (1.6 if owner.dead else 1.0)
		if v > wv:
			wv = v
			worst = k
	if help_lane >= 0:
		# go home when the crisis is over or our own lane heats up
		if sim.danger[help_lane] < 0.2 or own > 0.45:
			help_lane = -1
	elif worst >= 0 and wv > 0.55 and own < 0.2:
		help_lane = worst

func _front_enemy(lane: int, h: Sim.Hero) -> Sim.Enemy:
	var best: Sim.Enemy = null
	var best_score := -INF
	for e: Sim.Enemy in sim.enemies:
		if not e.alive:
			continue
		var d: float = e.pos.distance_to(h.pos)
		var in_lane: bool = e.lane == lane
		if not in_lane and d > 6.0:
			continue
		var prog: float = e.dist / sim.map.length(e.lane)
		var score := prog * 10.0 - d * 0.25
		if score > best_score:
			best_score = score
			best = e
	return best

func _use_skills(h: Sim.Hero, target: Sim.Enemy, inp: Dictionary) -> void:
	var near_me := sim._enemies_near(h.pos, 3.0, false).size()
	var near_t := sim._enemies_near(target.pos, 3.0).size()
	var dist: float = h.pos.distance_to(target.pos)
	match h.kind:
		"king":
			if h.q_cd <= 0.0 and near_me >= 2:
				q_seq += 1
			if h.e_cd <= 0.0 and near_me >= 3:
				e_seq += 1
			if h.sp_cd <= 0.0 and dist > 3.0 and dist < 7.0 and near_t >= 2:
				inp["move"] = (target.pos - h.pos).normalized()
				sp_seq += 1
		"queen":
			if h.q_cd <= 0.0 and near_t >= 2 and dist < 8.0:
				q_seq += 1
			if h.e_cd <= 0.0 and dist < 10.0:
				e_seq += 1
			if h.sp_cd <= 0.0 and dist < 2.0:
				sp_seq += 1
				inp["move"] = (h.pos - target.pos).normalized()
		"wizard":
			if h.q_cd <= 0.0 and near_t >= 3:
				q_seq += 1
			if h.e_cd <= 0.0 and near_me >= 3:
				e_seq += 1
			if h.sp_cd <= 0.0 and dist < 1.8 and h.hp < h.max_hp() * 0.6:
				inp["aim"] = h.pos + (h.pos - target.pos).normalized() * 6.0
				sp_seq += 1
		"valkyrie":
			if h.q_cd <= 0.0 and near_me >= 3:
				q_seq += 1
			if h.e_cd <= 0.0 and dist > 2.5 and dist < 9.0:
				e_seq += 1
			if h.sp_cd <= 0.0 and near_t >= 3 and dist > 3.0 and dist < 8.0:
				sp_seq += 1
		"cleric":
			if h.q_cd <= 0.0:
				for o: Sim.Hero in sim.heroes:
					if not o.dead and o.pos.distance_to(h.pos) < 5.0 and o.hp < o.max_hp() * 0.65:
						q_seq += 1
						break
			if h.e_cd <= 0.0 and near_t >= 3:
				e_seq += 1
			if h.sp_cd <= 0.0 and dist < 1.6:
				sp_seq += 1
				inp["move"] = (h.pos - target.pos).normalized()

func _build_or_guard(h: Sim.Hero, lane: int, only_build := false) -> Vector2:
	var guard := sim.map.guard_pos(lane)
	if help_lane >= 0:
		return guard
	# find next build action on own lane
	var lane_spots: Array = []
	for sp in sim.map.spots:
		if sp["lane"] == slot:
			lane_spots.append(sp)
	var want_spot := -1
	var want_cost := 0
	var upgrade := false
	for i in lane_spots.size():
		var sp: Dictionary = lane_spots[i]
		if not sim.towers.has(sp["id"]):
			want_spot = sp["id"]
			want_cost = Data.TOWERS[BUILD_PLAN[i]]["cost"][0]
			break
	if want_spot < 0:
		# all built: upgrade the cheapest tower
		var best_cost := 99999
		for sp in lane_spots:
			var t: Sim.Tower = sim.towers.get(sp["id"])
			if t and t.level < 3:
				var c: int = Data.TOWERS[t.kind]["cost"][t.level]
				if c < best_cost:
					best_cost = c
					want_spot = sp["id"]
		want_cost = best_cost
		upgrade = true
	if want_spot >= 0 and sim.gold >= want_cost + reserve:
		var spos: Vector2 = sim.map.spots[want_spot]["pos"]
		if h.pos.distance_to(spos) < 2.4:
			if upgrade:
				sim.request_upgrade(slot, want_spot)
			else:
				var idx := 0
				for i in lane_spots.size():
					if lane_spots[i]["id"] == want_spot:
						idx = i
				sim.request_build(slot, want_spot, BUILD_PLAN[idx])
			return h.pos
		return spos
	return Vector2.INF if only_build else guard
