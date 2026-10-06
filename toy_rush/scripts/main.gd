extends Node3D
## TOY RUSH flow: TITLE -> LOBBY -> GAME -> (result) -> LOBBY.
## Host runs Sim + Bots and broadcasts; every peer renders through View/Hud.

enum S { TITLE, LOBBY, GAME }

var state := S.TITLE
var net: Net
var lobby: Lobby
var sfx: Sfx
var cam: CameraRig
var showcase: Node3D
var show_models := {}

var map: MapDef
var sim: Sim
var view: View
var hud: Hud
var bots := {}
var my_slot := 0
var slots: Array = []
var q_seq := 0
var e_seq := 0
var sp_seq := 0
var tick := 0
var result_shown := false
var last_snap := {}
var client_bot_t := 0.0

# automation
var autoplay := false
var autostart := 0
var start_solo := false
var start_host := false
var join_ip := ""
var want_hero := ""
var my_name := ""
var shots_dir := ""
var shot_every := 0.0
var quit_after := 0.0
var seed_v := 0
var _clock := 0.0
var _shot_t := 0.0
var _shot_n := 0
var force_overview := false
var zoom_dist := 0.0
var skilltest := false
var uitest := false
var _st_t := 0.0
var _called_once := false
var focus_override := Vector3.INF     # dev: --focus=x,z pins the camera (map screenshots)

func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay": autoplay = true
		elif a == "--solo": start_solo = true
		elif a == "--host": start_host = true
		elif a.begins_with("--join="): join_ip = a.substr(7)
		elif a.begins_with("--hero="): want_hero = a.substr(7)
		elif a.begins_with("--name="): my_name = a.substr(7)
		elif a.begins_with("--autostart="): autostart = int(a.substr(12))
		elif a.begins_with("--shots="): shots_dir = a.substr(8)
		elif a.begins_with("--shot_every="): shot_every = float(a.substr(13))
		elif a.begins_with("--quit="): quit_after = float(a.substr(7))
		elif a.begins_with("--seed="): seed_v = int(a.substr(7))
		elif a == "--overview": force_overview = true
		elif a.begins_with("--focus="): var f := a.substr(8).split(","); focus_override = Vector3(float(f[0]), 0, float(f[1]))
		elif a.begins_with("--zoom="): zoom_dist = float(a.substr(7))
		elif a == "--uitest": uitest = true; start_solo = true
		elif a.begins_with("--speed="): Engine.time_scale = float(a.substr(8)); Engine.physics_ticks_per_second = 60
		elif a == "--skilltest": skilltest = true; start_solo = true
	sfx = Sfx.new()
	add_child(sfx)
	add_child(Portraits.new())
	net = Net.new()
	net.name = "Net"
	add_child(net)
	cam = CameraRig.new()
	add_child(cam)
	cam.current = true
	Vfx.root = self
	Vfx.cam = cam
	lobby = Lobby.new()
	add_child(lobby)
	lobby.solo_pressed.connect(_on_solo)
	lobby.host_pressed.connect(_on_host)
	lobby.join_pressed.connect(_on_join)
	lobby.hero_clicked.connect(func(h): net.pick_hero.rpc_id(1, h))
	lobby.hero_hovered.connect(_on_hero_hover)
	lobby.start_pressed.connect(_start_game)
	lobby.leave_pressed.connect(_leave)
	net.lobby_changed.connect(_on_lobby_changed)
	net.game_started.connect(_on_game_started)
	net.snap_received.connect(_on_snap)
	net.events_received.connect(_on_events)
	net.input_received.connect(_on_input)
	net.request_received.connect(_on_request)
	net.peer_left.connect(_on_peer_left)
	net.returned_to_lobby.connect(_on_back_to_lobby)
	net.connection_failed.connect(func(reason):
		_teardown_game()
		_build_showcase()
		state = S.TITLE
		lobby.show_title(reason))
	_build_showcase()
	if my_name == "":
		my_name = "용사%d" % (randi() % 900 + 100)
	lobby.name_edit.text = my_name
	if start_solo:
		_on_solo(my_name)
		_start_game()
	elif start_host:
		_on_host(my_name)
	elif join_ip != "":
		_on_join(my_name, join_ip)

# ================================================================ title / lobby
func _on_solo(name: String) -> void:
	net.setup_solo(name, want_hero)
	state = S.LOBBY
	lobby.show_lobby(true, "솔로: 빈 자리는 AI 봇이 맡습니다. 영웅을 고르고 시작하세요!")
	_on_lobby_changed(net.slots)

func _on_host(name: String) -> void:
	var err := net.host(name, want_hero)
	if err != OK:
		lobby.show_title("방을 만들 수 없습니다 (포트 %d 사용 중?)" % Net.PORT)
		return
	state = S.LOBBY
	var ips := []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10.") or ip.begins_with("172."):
			ips.append(ip)
	lobby.show_lobby(true, "LAN 방 생성됨 · 친구는 IP [%s] 로 참가 · 빈 자리는 봇" % (", ".join(ips) if not ips.is_empty() else "127.0.0.1"))
	_on_lobby_changed(net.slots)

func _on_join(name: String, ip: String) -> void:
	var err := net.join(name, ip, want_hero)
	if err != OK:
		lobby.show_title("접속 실패")
		return
	state = S.LOBBY
	lobby.show_lobby(false, "%s 에 접속 중..." % ip)

func _leave() -> void:
	net.leave()
	state = S.TITLE
	lobby.show_title("")

func _on_lobby_changed(s: Array) -> void:
	slots = s
	if state == S.LOBBY:
		lobby.refresh(s, net.my_id())
		if not net.is_host():
			lobby.info_l.text = "접속 완료! 영웅을 고르세요. 호스트가 시작합니다."
	_update_showcase()
	if autostart > 0 and net.is_host() and state == S.LOBBY:
		var humans := 0
		for x in s:
			if x["peer"] != 0:
				humans += 1
		if humans >= autostart:
			get_tree().create_timer(1.0).timeout.connect(func():
				if state == S.LOBBY:
					_start_game())

func _start_game() -> void:
	if net.is_host() and state == S.LOBBY:
		net.start_game(seed_v if seed_v != 0 else randi())

# ================================================================ showcase (lobby 3D)
func _build_showcase() -> void:
	if showcase:
		return
	showcase = Node3D.new()
	add_child(showcase)
	var we := WorldEnvironment.new()
	we.environment = Look.environment()
	showcase.add_child(we)
	showcase.add_child(Look.sun())
	_sc_mesh(_cylm(14.0, 14.5, 1.0), Color("7fd14a"), Vector3(0, -0.5, 0))
	_sc_mesh(_cylm(5.0, 5.0, 0.06), Color("f3dfa6"), Vector3(0, 0.03, 2.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 26:
		var a := rng.randf_range(PI * 1.05, PI * 1.95)
		var r := rng.randf_range(9.0, 13.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var g := Color("57b53a").lerp(Color("82d04a"), rng.randf())
		_sc_mesh(_cylm(0.15, 0.2, 1.0), Color("8a5a34"), p + Vector3(0, 0.5, 0))
		var s := SphereMesh.new()
		s.radius = 0.9
		s.height = 1.6
		_sc_mesh(s, g, p + Vector3(0, 1.5, 0))
	show_models.clear()
	for j in 5:
		var hk: String = Data.HERO_ORDER[j]
		var x := -6.0 + j * 3.0
		var z := -absf(x) * 0.18
		var ped := Node3D.new()
		showcase.add_child(ped)
		ped.position = Vector3(x, 0, z)
		_sc_mesh(_cylm(1.05, 1.15, 0.5), Color("d8d0c0"), Vector3(0, 0.25, 0), ped)
		_sc_mesh(_cylm(1.12, 1.12, 0.1), Color("b5aa95"), Vector3(0, 0.52, 0), ped)
		var m := UnitModel.new().build(Data.HEROES[hk]["model"], Color("8a8fa0"))
		m.scale = Vector3.ONE * 2.3
		m.position.y = 0.57
		m.rotation.y = PI
		ped.add_child(m)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.12
		tm.outer_radius = 1.3
		ring.mesh = tm
		ring.material_override = Mats.glow(Color.WHITE, 1.3)
		ring.scale = Vector3(1, 0.3, 1)
		ring.position.y = 0.58
		ring.visible = false
		ped.add_child(ring)
		show_models[hk] = {"ped": ped, "model": m, "ring": ring}
	cam.set_process(false)
	RenderingServer.global_shader_parameter_set("outline_scale", 1.25)
	cam.position = Vector3(0, 4.6, 11.5)
	cam.look_at(Vector3(0, 1.6, -0.5), Vector3.UP)
	cam.fov = 42.0

func _cylm(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 32
	return c

func _sc_mesh(mesh: Mesh, col: Color, pos: Vector3, parent: Node3D = null) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = Mats.prop(col)
	m.position = pos
	(parent if parent else showcase).add_child(m)

func _update_showcase() -> void:
	if showcase == null or slots.is_empty():
		return
	for hk in show_models:
		var sm: Dictionary = show_models[hk]
		var owner := -1
		for i in 4:
			if slots[i]["hero"] == hk:
				owner = i
		var ring: MeshInstance3D = sm["ring"]
		ring.visible = owner >= 0
		if owner >= 0:
			ring.material_override = Mats.glow(Data.PLAYER_COLORS[owner], 1.3)
			if slots[owner]["peer"] == net.my_id():
				var m: UnitModel = sm["model"]
				m.punch_scale(1.3, 0.7, 0.5)
				m.play_attack("melee")
				Sfx.play("pop", -6.0, 1.2)

func _on_hero_hover(hk: String) -> void:
	if show_models.has(hk):
		(show_models[hk]["model"] as UnitModel).punch_scale(0.85, 1.2, 0.4)

# ================================================================ game start / end
func _on_game_started(s: Array, sd: int, mine: int) -> void:
	slots = s
	my_slot = mine
	if showcase:
		showcase.queue_free()
		showcase = null
	lobby.visible = false
	_teardown_game()
	map = MapDef.new()
	hud = Hud.new()
	add_child(hud)
	view = View.new()
	add_child(view)
	view.setup(map, slots, my_slot, hud, cam)
	hud.setup(map, slots, my_slot, cam)
	hud.menu_action.connect(func(action, spot, kind): _request(action, spot, kind))
	hud.result_closed.connect(func(): net.back_to_lobby.rpc())
	cam.set_process(true)
	cam.snap_to(view.hero_pos(my_slot))
	if zoom_dist > 0.0:
		cam.dist_goal = zoom_dist
		cam.dist = zoom_dist
	result_shown = false
	tick = 0
	bots.clear()
	if net.is_host():
		sim = Sim.new(map, slots, sd)
		var humans := 0
		for x in slots:
			if x["peer"] != 0:
				humans += 1
		for i in 4:
			if slots[i]["peer"] == 0 or (autoplay and i == my_slot):
				var real_humans := humans - (1 if autoplay else 0)
				bots[i] = Bot.new(sim, i, 40 if real_humans > 0 else 0)
	state = S.GAME
	if uitest:
		_run_uitest()
	hud.banner("준비!", Color.WHITE, 0.6, 90)
	hud.toast("%s 라인을 지키세요! 부지에서 [F]로 타워 건설" % Data.LANE_NAMES[my_slot], Data.PLAYER_COLORS[my_slot].lightened(0.3))

func _teardown_game() -> void:
	if view:
		view.queue_free()
		view = null
	if hud:
		hud.queue_free()
		hud = null
	sim = null
	bots.clear()
	for c in get_children():
		if c is Vfx.Shot:
			c.queue_free()

func _on_back_to_lobby() -> void:
	_teardown_game()
	_build_showcase()
	state = S.LOBBY
	lobby.show_lobby(net.is_host(), "다시 한 판!")
	lobby.refresh(slots, net.my_id())
	_update_showcase()

func _on_peer_left(peer: int) -> void:
	if state != S.GAME or sim == null:
		return
	for i in 4:
		if slots[i]["peer"] == peer:
			slots[i]["peer"] = 0
			bots[i] = Bot.new(sim, i, 40)
			hud.toast("%s 님이 나갔습니다. 봇이 대신 지킵니다" % slots[i]["name"], Color("ffb0c0"))

# ================================================================ requests & inputs
func _slot_of(peer: int) -> int:
	for i in 4:
		if slots[i]["peer"] == peer:
			return i
	return -1

func _request(type: String, a: int, b: String) -> void:
	if net.is_host():
		_apply_request(my_slot, type, a, b)
	else:
		net.send_request(type, a, b)

func _apply_request(slot: int, type: String, a: int, b: String) -> void:
	if sim == null or slot < 0:
		return
	var ok := false
	match type:
		"build": ok = sim.request_build(slot, a, b)
		"upgrade": ok = sim.request_upgrade(slot, a)
		"sell": ok = sim.request_sell(slot, a)
		"call": ok = sim.request_call_wave(slot)
	if slot != my_slot:
		print("NET request from slot %d: %s %d %s -> %s" % [slot, type, a, b, ok])

func _on_request(peer: int, type: String, a: int, b: String) -> void:
	_apply_request(_slot_of(peer), type, a, b)

func _on_input(peer: int, inp: Dictionary) -> void:
	var s := _slot_of(peer)
	if sim and s >= 0 and not bots.has(s):
		sim.inputs[s] = inp

func _on_snap(s: Dictionary) -> void:
	if state != S.GAME or view == null:
		return
	last_snap = s
	view.apply_snapshot(s)
	hud.update_state(s)
	_check_end(s)

func _on_events(evs: Array) -> void:
	if state == S.GAME and view:
		view.handle_events(evs)

func _check_end(s: Dictionary) -> void:
	var ph: String = s.get("ph", "")
	if (ph == "won" or ph == "lost") and not result_shown:
		result_shown = true
		get_tree().create_timer(1.2).timeout.connect(func():
			if hud:
				hud.show_result(ph == "won", s, net.is_host())
				if ph == "won":
					Vfx.confetti(view.hero_pos(my_slot) + Vector3(0, 1, 0))
					Sfx.play("fanfare", -3.0)
				else:
					Sfx.play("sad", -3.0))

# ================================================================ per frame
func _physics_process(delta: float) -> void:
	if state != S.GAME:
		return
	tick += 1
	var inp := _gather_input()
	if skilltest and sim:
		inp = _skilltest_input(delta)
	if net.is_host() and sim:
		if not bots.has(my_slot):
			sim.inputs[my_slot] = inp
		for i in bots:
			sim.inputs[i] = (bots[i] as Bot).compute(delta)
		sim.step(delta)
		var evs := sim.events
		sim.events = []
		var s := sim.snapshot()
		last_snap = s
		view.apply_snapshot(s)
		view.handle_events(evs)
		hud.update_state(s)
		net.broadcast_events(evs)
		if tick % 3 == 0:
			net.broadcast_snapshot(s)
		_check_end(s)
	elif tick % 2 == 0:
		if autoplay:
			inp = _client_bot(delta * 2.0)
		net.send_input(inp)

func _process(delta: float) -> void:
	_clock += delta
	if quit_after > 0.0 and _clock > quit_after:
		get_tree().quit()
	if shots_dir != "" and shot_every > 0.0:
		_shot_t += delta
		if _shot_t >= shot_every:
			_shot_t = 0.0
			_shot()
	if showcase:
		for hk in show_models:
			var m: UnitModel = show_models[hk]["model"]
			m.rotation.y = PI + sin(_clock * 0.8 + hk.length()) * 0.25
	if state != S.GAME or view == null:
		return
	var hp := view.hero_pos(my_slot)
	cam.target = hp if focus_override == Vector3.INF else focus_override
	cam.overview = Input.is_key_pressed(KEY_TAB) or force_overview
	var aim := _mouse_ground()
	view.set_aim_marker(aim, not hud.menu_open() and not cam.overview)
	# interaction prompt / menu housekeeping
	var hp2 := Vector2(hp.x, hp.z)
	var dead := _my_dead()
	if hud.menu_open():
		var sp: Vector2 = map.spots[hud.menu_spot]["pos"]
		if hp2.distance_to(sp) > 4.0 or dead:
			hud.close_menu()
		else:
			var r := hud.selected_range()
			view.show_range(sp, r, r > 0.0)
			hud.set_prompt("[1~4] 또는 클릭: 선택 후 한 번 더 눌러 확정 · [F/Esc] 닫기")
	else:
		view.show_range(Vector2.ZERO, 0.0, false)
		hud.set_prompt("" if dead else _prompt_text(hp2))

func _my_dead() -> bool:
	var hs: Array = last_snap.get("h", [])
	return hs.size() > my_slot and hs[my_slot][6] == 1

func _nearest_spot(p: Vector2) -> int:
	var best := -1
	var bd := 2.8
	for sp in map.spots:
		var d: float = p.distance_to(sp["pos"])
		if d < bd:
			bd = d
			best = sp["id"]
	return best

func _tower_at(spot: int) -> Array:
	for t in last_snap.get("t", []):
		if t[0] == spot:
			return t
	return []

func _prompt_text(p: Vector2) -> String:
	var sp := _nearest_spot(p)
	if sp >= 0:
		var t := _tower_at(sp)
		if t.is_empty():
			return "[F] 타워 건설"
		return "[F] %s Lv%d 업그레이드 / 판매" % [Data.TOWERS[Data.TOWER_ORDER[t[1]]]["name"], t[2]]
	if p.length() < MapDef.HORN_R + 1.0 and last_snap.get("wt", -1.0) >= 0.0:
		var bonus := int(ceil(last_snap["wt"])) if last_snap.get("w", 0) > 0 else 0
		return "[F] 나팔 불기: 다음 웨이브 호출%s" % ((" (+%dG)" % bonus) if bonus > 0 else "")
	return ""

func _interact() -> void:
	if _my_dead():
		return
	if hud.menu_open():
		hud.close_menu()
		return
	var hp := view.hero_pos(my_slot)
	var p := Vector2(hp.x, hp.z)
	var sp := _nearest_spot(p)
	if sp >= 0:
		hud.open_menu(sp, _tower_at(sp))
		return
	if p.length() < MapDef.HORN_R + 1.0:
		_request("call", 0, "")

func _mouse_ground() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return Vector3.ZERO
	var t := -o.y / d.y
	return o + d * t

func _gather_input() -> Dictionary:
	var inp := Sim.empty_input()
	if view == null:
		return inp
	var mv := Vector2.ZERO
	var f := cam.forward_2d()
	var r := cam.right_2d()
	if Input.is_key_pressed(KEY_W): mv += f
	if Input.is_key_pressed(KEY_S): mv -= f
	if Input.is_key_pressed(KEY_D): mv += r
	if Input.is_key_pressed(KEY_A): mv -= r
	inp["move"] = mv.normalized() if mv.length() > 0.0 else Vector2.ZERO
	var aim := _mouse_ground()
	inp["aim"] = Vector2(aim.x, aim.z)
	inp["attack"] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not hud.menu_open() and not cam.overview
	inp["q"] = q_seq
	inp["e"] = e_seq
	inp["sp"] = sp_seq
	return inp

func _unhandled_input(ev: InputEvent) -> void:
	if state != S.GAME or hud == null:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_Q: q_seq += 1
			KEY_E: e_seq += 1
			KEY_SPACE: sp_seq += 1
			KEY_F: _interact()
			KEY_ESCAPE: hud.close_menu()
			KEY_1, KEY_2, KEY_3, KEY_4:
				if hud.menu_open():
					hud.menu_press(ev.keycode - KEY_1)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom(-2.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom(2.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT and hud.menu_open():
			hud.close_menu()

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var e2 := InputEventKey.new()
	e2.keycode = code
	e2.pressed = false
	Input.parse_input_event(e2)

func _run_uitest() -> void:
	var tw := func(t: float) -> void:
		await get_tree().create_timer(t).timeout
	var spot: Dictionary = {}
	for sp in map.spots:
		if sp["lane"] == my_slot:
			spot = sp
			break
	await tw.call(1.0)
	sim.heroes[my_slot].pos = spot["pos"] + Vector2(1.2, 0.8)
	await tw.call(0.5)
	_key(KEY_F)
	await tw.call(0.4)
	print("UITEST menu_open=", hud.menu_open(), " items=", hud.menu_items.size())
	_shot()
	_key(KEY_2)
	await tw.call(0.4)
	_shot()
	_key(KEY_2)
	await tw.call(0.6)
	print("UITEST built=", sim.towers.has(spot["id"]), " kind=", sim.towers[spot["id"]].kind if sim.towers.has(spot["id"]) else "-", " gold=", sim.gold)
	_shot()
	await tw.call(0.6)
	_key(KEY_F)
	await tw.call(0.3)
	_key(KEY_1)
	await tw.call(0.3)
	_shot()
	_key(KEY_1)
	await tw.call(0.8)
	print("UITEST upgraded level=", sim.towers[spot["id"]].level, " gold=", sim.gold)
	_shot()
	sim.heroes[my_slot].pos = Vector2(0, MapDef.CASTLE_R + 1.2)
	await tw.call(0.6)
	var before := sim.gold
	_key(KEY_F)
	await tw.call(0.5)
	print("UITEST call wave: wave=", sim.wave, " bonus=", sim.gold - before)
	_shot()
	await tw.call(2.5)
	_shot()

## scripted showcase of attack + Q + E on a spawned enemy group
func _skilltest_input(delta: float) -> Dictionary:
	_st_t += delta
	var inp := Sim.empty_input()
	var h: Sim.Hero = sim.heroes[my_slot]
	var lane := my_slot
	var center := map.pos_at(lane, map.length(lane) * 0.5)
	if _st_t < 0.1:
		sim.wave_timer = 999.0
		h.pos = map.pos_at(lane, map.length(lane) * 0.62)
		sim.debug_spawn(lane, "goblin", 7, 0.5)
		sim.debug_spawn(lane, "orc", 3, 0.47)
	var target := center
	if not sim.enemies.is_empty():
		target = sim.enemies[0].pos
	inp["aim"] = target
	var melee: bool = h.def["range"] < 3.0
	var to := target - h.pos
	if melee and to.length() > 1.2:
		inp["move"] = to.normalized()
	elif not melee and to.length() > 6.0:
		inp["move"] = to.normalized()
	inp["attack"] = _st_t > 0.8
	if _st_t > 2.2:
		q_seq = 1
	if _st_t > 4.2:
		e_seq = 1
	if _st_t > 6.2:
		sp_seq = 1
		inp["aim"] = target + (target - h.pos).normalized() * 2.0
	inp["q"] = q_seq
	inp["e"] = e_seq
	inp["sp"] = sp_seq
	if _st_t > 6.5 and sim.enemies.size() < 3:
		sim.debug_spawn(lane, "goblin", 5, 0.5)
	return inp

## simple snapshot-driven autopilot for client test runs
func _client_bot(_dt: float) -> Dictionary:
	var inp := Sim.empty_input()
	inp["q"] = q_seq
	inp["e"] = e_seq
	var hs: Array = last_snap.get("h", [])
	if hs.size() <= my_slot:
		return inp
	var me := Vector2(hs[my_slot][1], hs[my_slot][2])
	var es: PackedFloat32Array = last_snap.get("e", PackedFloat32Array())
	var best := Vector2.INF
	var bd := 12.0
	var i := 0
	while i + 7 < es.size():
		var p := Vector2(es[i + 2], es[i + 3])
		if p.distance_to(me) < bd and map.lane_of_point(p) == my_slot:
			bd = p.distance_to(me)
			best = p
		i += 8
	var goal := map.guard_pos(my_slot)
	if not _called_once and int(last_snap.get("w", 0)) == 0 and me.length() < MapDef.HORN_R + 1.0:
		_called_once = true
		_request("call", 0, "")
	if best == Vector2.INF and int(last_snap.get("g", 0)) >= 70:
		for sp in map.spots:
			if sp["lane"] == my_slot and _tower_at(sp["id"]).is_empty():
				goal = sp["pos"]
				if me.distance_to(goal) < 2.0:
					_request("build", sp["id"], "archer")
				break
	if best != Vector2.INF:
		inp["aim"] = best
		inp["attack"] = true
		goal = best + (me - best).normalized() * 5.0
		client_bot_t += _dt
		if client_bot_t > 4.0:
			client_bot_t = 0.0
			q_seq += 1
			inp["q"] = q_seq
	if goal.distance_to(me) > 0.6:
		inp["move"] = (goal - me).normalized()
	return inp

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_n += 1
	var role := "host" if net.is_host() else "client"
	img.save_png("%s/%s_%03d.png" % [shots_dir, role, _shot_n])
