extends Node3D
## Game flow: INTRO -> DEPLOY -> CLASH -> BATTLE -> RESULT -> (next round | END).
## Owns match state, drag & drop input and the player's tray.

enum S { INTRO, DEPLOY, CLASH, BATTLE, RESULT, END }

const DEPLOY_TIME := 25.0
const BATTLE_TIME := 30.0
const WIN_FLAGS := 2
const MAX_ROUNDS := 5
const ELIXIR_PER_ROUND := 6
const ELIXIR_CAP := 10

var state := S.INTRO
var world: World
var cam: CameraRig
var hud: Hud
var sfx: Sfx
var units_root: Node3D

var units: Array[Unit] = []
var round_n := 0
var flags := [0, 0]
var elixir := [0, 0]
var rerolls := [0, 0]
var shop := [["", "", ""], ["", "", ""]]
var timer := 0.0
var tray_models: Array = [null, null, null]

# drag
var drag_slot := -1
var drag_unit: Unit = null
var drag_model: UnitModel = null
var hover_tile := Vector2i(-1, -1)

# automation (screenshots / smoke test)
var autoplay := false
var shots_dir := ""
var quit_after := 0.0
var _shot_n := 0
var _clock := 0.0
var cam_mode := ""
var selftest := false
var demo_mode := false
var demo_hold := false

func _ready() -> void:
	randomize()
	print("[ToyClash] start args=", OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a == "--demo":
			demo_mode = true
			seed(20260930)
		elif a.begins_with("--seed="):
			seed(int(a.substr(7)))
		elif a == "--selftest":
			selftest = true
		elif a.begins_with("--cam="):
			cam_mode = a.substr(6)
		elif a.begins_with("--quit="):
			quit_after = float(a.substr(7))
	sfx = Sfx.new()
	add_child(sfx)
	world = World.new()
	add_child(world)
	world.build()
	cam = CameraRig.new()
	add_child(cam)
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.setup(Vector3(0, 15.2, 10.6), Vector3(0, 0, 1.25), 27.0)
	if cam_mode == "close":
		cam.setup(Vector3(0.6, 4.2, 5.6), Vector3(0, 0.4, 1.9), 30.0)
	cam.current = true
	units_root = Node3D.new()
	add_child(units_root)
	Vfx.root = self
	Vfx.cam = cam
	hud = Hud.new()
	add_child(hud)
	hud.cam = cam
	hud.reroll_pressed.connect(_on_reroll)
	hud.fight_pressed.connect(start_battle)
	hud.restart_pressed.connect(_restart)
	start_match()
	if selftest:
		_run_selftest()
	if demo_mode:
		var d := Demo.new()
		d.game = self
		add_child(d)
		d.run()

func _run_selftest() -> void:
	await get_tree().create_timer(0.8).timeout
	elixir[0] = 10
	shop[0] = ["archer", "archer", "giant"]
	_refresh_tray(false)
	var drag := func(from: Vector3, to: Vector3) -> void:
		var a := cam.unproject_position(from)
		var b := cam.unproject_position(to)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		e.position = a
		_unhandled_input(e)
		var m := InputEventMouseMotion.new()
		m.position = b
		_unhandled_input(m)
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = false
		e2.position = b
		_unhandled_input(e2)
	drag.call(world.tray_slots[0], World.tile_pos(1, 2))
	print("SELFTEST place: units=", units.size(), " at(1,2)=", unit_at(Vector2i(1, 2)).kind if unit_at(Vector2i(1, 2)) else "none", " elixir=", elixir[0])
	await get_tree().create_timer(0.5).timeout
	drag.call(world.tray_slots[1], World.tile_pos(1, 2))
	var u := unit_at(Vector2i(1, 2))
	print("SELFTEST merge: star=", u.star if u else -1, " elixir=", elixir[0])
	drag.call(world.tray_slots[2], World.tile_pos(4, 6))
	print("SELFTEST enemy-side drop rejected: units=", units.size(), " tray2=", tray_models[2] != null)
	await get_tree().create_timer(0.5).timeout
	drag.call(World.tile_pos(1, 2) + Vector3(0, 0.3, 0), World.tile_pos(3, 0))
	print("SELFTEST move: at(3,0)=", unit_at(Vector2i(3, 0)).kind if unit_at(Vector2i(3, 0)) else "none")
	await get_tree().create_timer(0.6).timeout
	_shot_later(0.0, "selftest")
	await get_tree().create_timer(0.4).timeout
	start_battle()

# ---------------------------------------------------------------- match flow
func start_match() -> void:
	for u in units:
		hud.unregister_unit(u)
		u.queue_free()
	units.clear()
	round_n = 0
	flags = [0, 0]
	elixir = [0, 0]
	rerolls = [0, 0]
	hud.set_flags(0, 0)
	_spawn(Data.TEAM_PLAYER, "king", Vector2i(2, 1))
	_spawn(Data.TEAM_ENEMY, "queen", Vector2i(2, 6))
	next_round()

func _on_reroll() -> void:
	if state == S.DEPLOY:
		do_reroll(0)

func _restart() -> void:
	if hud.result_panel:
		hud.result_panel.queue_free()
		hud.result_panel = null
	start_match()

func next_round() -> void:
	round_n += 1
	for t in 2:
		elixir[t] = mini(elixir[t] + ELIXIR_PER_ROUND, ELIXIR_CAP)
		rerolls[t] += 1
		_roll_shop(t)
	# reset the board: every figure is set down again
	var i := 0
	for u in units:
		u.reset_for_round()
		if u.team == Data.TEAM_PLAYER:
			u.drop_in(1.2, 0.05 * i)
			i += 1
		else:
			u.revealed = true
			u.set_ghost(true)
	# enemy prepares in secret; new figures stay hidden until CLASH
	Ai.deploy(self, Data.TEAM_ENEMY)
	if autoplay:
		Ai.deploy(self, Data.TEAM_PLAYER)
	_refresh_tray()
	hud.set_round(round_n)
	hud.set_elixir(elixir[0])
	hud.set_rerolls(rerolls[0])
	hud.set_deploy_controls(true)
	hud.set_phase("Drag minis onto your side!" if round_n == 1 else "Enemy ghosts show last round. Counter them!")
	hud.banner("ROUND %d" % round_n, Color.WHITE, 0.5, 96, -120)
	world.deploy_glow = 1.0
	timer = DEPLOY_TIME
	state = S.DEPLOY
	_shot_later(1.2, "deploy")

func start_battle() -> void:
	if state != S.DEPLOY:
		return
	_cancel_drag()
	state = S.CLASH
	world.deploy_glow = 0.0
	world.clear_highlights()
	hud.set_deploy_controls(false)
	hud.set_phase("")
	for m in tray_models:
		if m:
			m.visible = false
	# reveal enemy
	var k := 0
	for u in units:
		if u.team != Data.TEAM_ENEMY:
			continue
		if not u.revealed or not u.visible:
			u.revealed = true
			u.visible = true
			u.set_ghost(false)
			u.drop_in(1.6, 0.04 * k)
			k += 1
		else:
			u.set_ghost(false)
			u.model.punch_scale(1.2, 0.8, 0.3)
	await get_tree().create_timer(0.25).timeout
	hud.banner("CLASH!!", Data.COL_GOLD, 0.45, 150)
	hud.flash(0.35, 0.25)
	Vfx.clash_flash(Vector3.ZERO)
	cam.add_trauma(0.35)
	cam.kick_fov(-2.5)
	Sfx.play("clash", -3.0)
	_shot_later(0.15, "clash")
	await get_tree().create_timer(0.75).timeout
	if state != S.CLASH:
		return
	for u in units:
		if u.alive:
			u.clash_ability()
	timer = BATTLE_TIME
	state = S.BATTLE
	_shot_later(1.6, "battle_a")
	_shot_later(3.4, "battle_b")

func end_round(winner: int) -> void:
	state = S.RESULT
	Engine.time_scale = 1.0
	print("[ToyClash] round ", round_n, " winner=", winner)
	if winner >= 0:
		flags[winner] += 1
	hud.set_flags(flags[0], flags[1])
	if winner == Data.TEAM_PLAYER:
		hud.banner("ROUND WON!", Color("8fe36a"), 0.9, 96)
		Sfx.play("chime", -4.0)
	elif winner == Data.TEAM_ENEMY:
		hud.banner("ROUND LOST", Color("ff7a90"), 0.9, 96)
		Sfx.play("sad", -6.0)
	else:
		hud.banner("DRAW", Color("dfe6ee"), 0.9, 96)
	# survivors celebrate with little hops
	for u in units:
		if u.alive and (winner < 0 or u.team == winner):
			_victory_hop(u)
	_shot_later(0.5, "round_end")
	await get_tree().create_timer(2.2).timeout
	if flags[0] >= WIN_FLAGS or flags[1] >= WIN_FLAGS or round_n >= MAX_ROUNDS:
		end_match()
	else:
		next_round()

func end_match() -> void:
	state = S.END
	var win: bool = flags[0] > flags[1]
	var draw: bool = flags[0] == flags[1]
	hud.show_result(win, draw)
	if win:
		Vfx.confetti(Vector3(0, 0.5, 2.0))
		Sfx.play("fanfare", -3.0)
	elif not draw:
		Sfx.play("sad", -4.0)
	_shot_later(0.9, "match_end")
	if autoplay:
		await get_tree().create_timer(3.0).timeout
		if autoplay and quit_after <= 0.0:
			_restart()

func _victory_hop(u: Unit) -> void:
	var tw := u.create_tween()
	for i in 2:
		tw.tween_property(u.model, "position:y", 0.45, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(u.model, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): u.model.punch_scale(1.25, 0.75, 0.3))
	tw.parallel().tween_property(u.model, "rotation:y", 0.0 if u.team == 0 else PI, 0.3)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.001)
	if quit_after > 0.0 and _clock > quit_after:
		get_tree().quit()
	match state:
		S.DEPLOY:
			if not demo_hold:
				timer -= delta
			hud.set_timer(timer, DEPLOY_TIME)
			if timer <= 5.0 and int(ceil(timer)) != int(ceil(timer + delta)):
				Sfx.play("tick", -8.0)
			if timer <= 0.0 or (autoplay and timer < DEPLOY_TIME - 2.0):
				start_battle()
		S.BATTLE:
			timer -= delta
			hud.set_timer(timer, BATTLE_TIME)
			for u in units:
				u.battle_tick(delta)
			var a0 := alive_units(0).size()
			var a1 := alive_units(1).size()
			if a0 == 0 or a1 == 0:
				end_round(-1 if a0 == a1 else (0 if a1 == 0 else 1))
			elif timer <= 0.0:
				var h0 := _hp_ratio(0)
				var h1 := _hp_ratio(1)
				end_round(-1 if absf(h0 - h1) < 0.01 else (0 if h0 > h1 else 1))
	hud.update_cost_badges(shop[0] if state == S.DEPLOY else [], world.tray_slots)
	# tray idle wobble
	for i in 3:
		var m: UnitModel = tray_models[i]
		if m and m != drag_model:
			m.rotation.y = PI + sin(_clock * 1.6 + i) * 0.25

func _hp_ratio(team: int) -> float:
	var s := 0.0
	var n := 0.0
	for u in units:
		if u.team == team:
			s += u.hp / u.max_hp if u.alive else 0.0
			n += 1.0
	return s / maxf(n, 1.0)

# ---------------------------------------------------------------- queries
func alive_units(team: int) -> Array:
	var out := []
	for u in units:
		if u.alive and u.revealed and u.visible and (team < 0 or u.team == team):
			out.append(u)
	return out

func in_battle() -> bool:
	return state == S.BATTLE or state == S.CLASH

func unit_at(t: Vector2i) -> Unit:
	for u in units:
		if u.home == t:
			return u
	return null

func mini_count(team: int) -> int:
	var n := 0
	for u in units:
		if u.team == team and not u.hero:
			n += 1
	return n

func find_upgradable(team: int, kind: String) -> Unit:
	var best: Unit = null
	for u in units:
		if u.team == team and u.kind == kind and u.star < 3:
			if best == null or u.star > best.star:
				best = u
	return best

# ---------------------------------------------------------------- economy
func _roll_shop(team: int) -> void:
	for i in 3:
		shop[team][i] = Data.DECK[randi() % Data.DECK.size()]

func do_reroll(team: int) -> void:
	if rerolls[team] <= 0:
		return
	rerolls[team] -= 1
	_roll_shop(team)
	if team == Data.TEAM_PLAYER:
		hud.set_rerolls(rerolls[0])
		_refresh_tray(true)
		Sfx.play("whoosh", -6.0, 1.2)

func _spawn(team: int, kind: String, tile: Vector2i, star := 1) -> Unit:
	var u := Unit.new()
	units_root.add_child(u)
	u.setup(kind, team, star, self)
	u.home = tile
	u.position = World.tile_pos(tile.x, tile.y)
	u.died.connect(_on_unit_died)
	units.append(u)
	hud.register_unit(u)
	return u

func _on_unit_died(u: Unit) -> void:
	cam.add_trauma(0.12)

func buy_place(team: int, slot: int, tile: Vector2i, hidden := false) -> Unit:
	var kind: String = shop[team][slot]
	elixir[team] -= Data.get_def(kind)["cost"]
	shop[team][slot] = ""
	var u := _spawn(team, kind, tile)
	if hidden:
		u.revealed = false
		u.visible = false
	return u

func buy_upgrade(team: int, slot: int, u: Unit, hidden := false) -> void:
	var kind: String = shop[team][slot]
	elixir[team] -= Data.get_def(kind)["cost"]
	shop[team][slot] = ""
	if hidden:
		u.star = mini(u.star + 1, 3)
		u._apply_stats()
	else:
		u.upgrade()

# ---------------------------------------------------------------- tray
func _refresh_tray(animate := true) -> void:
	for i in 3:
		if tray_models[i]:
			tray_models[i].queue_free()
			tray_models[i] = null
		var k: String = shop[0][i]
		if k == "":
			continue
		var m := UnitModel.new().build(k, Data.TEAM_PLAYER)
		add_child(m)
		m.position = world.tray_slots[i]
		m.rotation.y = PI
		var s: float = Data.get_def(k)["scale"] * 1.5
		if animate:
			m.scale = Vector3.ONE * 0.01
			var tw := m.create_tween()
			tw.tween_interval(0.06 * i)
			tw.tween_property(m, "scale", Vector3.ONE * s, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			m.scale = Vector3.ONE * s
		tray_models[i] = m

# ---------------------------------------------------------------- input (drag & drop)
func _ray_plane(screen: Vector2, y: float) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (y - o.y) / d.y
	return o + d * t

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif ev.keycode == KEY_SPACE and state == S.DEPLOY:
			start_battle()
		elif ev.keycode == KEY_R and state == S.DEPLOY:
			do_reroll(0)
	if state != S.DEPLOY:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_begin_drag(ev.position)
		else:
			_end_drag(ev.position)
	elif ev is InputEventMouseMotion and (drag_slot >= 0 or drag_unit):
		_move_drag(ev.position)

func _begin_drag(sp: Vector2) -> void:
	# tray first
	var pt := _ray_plane(sp, 0.4)
	for i in 3:
		if tray_models[i] and _flat_dist(pt, world.tray_slots[i]) < 0.7:
			drag_slot = i
			drag_model = tray_models[i]
			drag_model.punch_scale(1.2, 0.8, 0.3)
			Sfx.play("click", -4.0, 1.3)
			_move_drag(sp)
			return
	var pb := _ray_plane(sp, 0.3)
	var best: Unit = null
	var bd := 0.5
	for u in units:
		if u.team == Data.TEAM_PLAYER and u.visible:
			var d := _flat_dist(pb, u.global_position)
			if d < bd:
				bd = d
				best = u
	if best:
		drag_unit = best
		best.set_lifted(true)
		Sfx.play("click", -4.0, 1.3)

func _move_drag(sp: Vector2) -> void:
	var p := _ray_plane(sp, 0.0)
	if p == Vector3.INF:
		return
	world.clear_highlights()
	hover_tile = World.pos_to_tile(p)
	if drag_model:
		drag_model.global_position = p + Vector3(0, 0.6, 0.15)
		drag_model.rotation = Vector3(-0.2, 0.0, sin(_clock * 9.0) * 0.12)
	elif drag_unit:
		drag_unit.global_position = Vector3(p.x, 0, p.z)
	if World.in_board(hover_tile) and hover_tile.y < 4:
		world.set_tile_highlight(hover_tile, _tile_hint(hover_tile))

func _tile_hint(t: Vector2i) -> Color:
	var occ := unit_at(t)
	if drag_model:
		var k: String = shop[0][drag_slot]
		var cost: int = Data.get_def(k)["cost"]
		if cost > elixir[0]:
			return Color(1, 0.3, 0.35, 0.55)
		if occ and occ.kind == k and occ.star < 3:
			return Color(1.0, 0.85, 0.2, 0.7)
		if occ == null and mini_count(0) < 5:
			return Color(1, 1, 1, 0.55)
		return Color(1, 0.3, 0.35, 0.55)
	return Color(1, 1, 1, 0.55)

func _end_drag(sp: Vector2) -> void:
	world.clear_highlights()
	var p := _ray_plane(sp, 0.0)
	var t := World.pos_to_tile(p) if p != Vector3.INF else Vector2i(-1, -1)
	if drag_model:
		var slot := drag_slot
		var k: String = shop[0][slot]
		var cost: int = Data.get_def(k)["cost"]
		var ok := false
		var over_board := p != Vector3.INF and absf(p.x) < 3.0 and absf(p.z) < 4.2
		if over_board:
			if cost > elixir[0]:
				hud.toast("Not enough Elixir!")
				Sfx.play("thud", -6.0, 0.6)
			else:
				var occ := unit_at(t) if World.in_board(t) and t.y < 4 else null
				var target: Unit = null
				if occ and occ.kind == k and occ.star < 3:
					target = occ
				elif occ == null and World.in_board(t) and t.y < 4 and mini_count(0) < 5:
					var u := buy_place(0, slot, t)
					u.drop_in(1.0)
					ok = true
				elif occ == null or occ.kind != k:
					target = find_upgradable(0, k)   # auto-merge like the original
				if target and not ok:
					buy_upgrade(0, slot, target)
					ok = true
				if not ok and mini_count(0) >= 5:
					hud.toast("Board is full!")
		if ok:
			drag_model.queue_free()
			tray_models[slot] = null
			hud.set_elixir(elixir[0])
		else:
			var m := drag_model
			var tw := m.create_tween().set_parallel(true)
			tw.tween_property(m, "position", world.tray_slots[slot], 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(m, "rotation", Vector3(0, PI, 0), 0.3)
		drag_model = null
		drag_slot = -1
	elif drag_unit:
		var u := drag_unit
		u.set_lifted(false)
		if World.in_board(t) and t.y < 4:
			var occ := unit_at(t)
			if occ and occ != u:
				occ.home = u.home
				occ.position = World.tile_pos(occ.home.x, occ.home.y)
				occ.drop_in(0.4)
			u.home = t
		u.position = World.tile_pos(u.home.x, u.home.y)
		u.drop_in(0.35)
		drag_unit = null

func _cancel_drag() -> void:
	if drag_slot >= 0 or drag_unit:
		_end_drag(Vector2(-9999, -9999))

static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------------------------------------------------------------- screenshots
func _shot_later(delay: float, tag: String) -> void:
	if shots_dir == "":
		return
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_n += 1
	img.save_png("%s/r%d_%02d_%s.png" % [shots_dir, round_n, _shot_n, tag])
