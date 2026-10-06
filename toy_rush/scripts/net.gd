class_name Net
extends Node
## LAN co-op over ENet. The host owns the lobby and the simulation; clients send inputs and
## requests, and receive snapshots and events. Solo play uses Godot's offline peer, so the
## same RPC code path runs locally (no separate single-player branch).

signal lobby_changed(slots: Array)
signal game_started(slots: Array, seed_v: int, my_slot: int)
signal snap_received(s: Dictionary)
signal events_received(evs: Array)
signal input_received(peer: int, inp: Dictionary)
signal request_received(peer: int, type: String, a: int, b: String)
signal peer_left(peer: int)
signal returned_to_lobby
signal connection_failed(reason: String)

const PORT := 7777
var slots: Array = []
var my_name := "Player"
var my_hero := ""
var online := false
var in_game := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): connection_failed.emit("연결 실패"))
	multiplayer.server_disconnected.connect(func():
		_reset_peer()
		connection_failed.emit("호스트와 연결이 끊어졌습니다"))

func is_host() -> bool:
	return multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()

func my_slot() -> int:
	for i in slots.size():
		if slots[i]["peer"] == my_id():
			return i
	return 0

func _default_slots() -> Array:
	var out := []
	for i in 4:
		out.append({"peer": 0, "name": "봇 %d" % (i + 1), "hero": Data.HERO_ORDER[(i + 1) % 5] if i > 0 else Data.HERO_ORDER[0]})
	return out

func _free_hero(prefer: String) -> String:
	var used := []
	for s in slots:
		used.append(s["hero"])
	if prefer != "" and not used.has(prefer):
		return prefer
	for h in Data.HERO_ORDER:
		if not used.has(h):
			return h
	return Data.HERO_ORDER[0]

# ---------------------------------------------------------------- modes
func setup_solo(name: String, hero := "") -> void:
	_reset_peer()
	my_name = name
	slots = _default_slots()
	for sl in slots:
		sl["hero"] = ""
	slots[0] = {"peer": 1, "name": name, "hero": hero if Data.HEROES.has(hero) else Data.HERO_ORDER[0]}
	_rebalance_bots()
	lobby_changed.emit(slots)

func host(name: String, hero := "") -> int:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	my_name = name
	slots = _default_slots()
	for sl in slots:
		sl["hero"] = ""
	slots[0] = {"peer": 1, "name": name, "hero": hero if Data.HEROES.has(hero) else Data.HERO_ORDER[0]}
	_rebalance_bots()
	lobby_changed.emit(slots)
	return OK

func join(name: String, ip: String, hero := "") -> int:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	my_name = name
	my_hero = hero
	return OK

func leave() -> void:
	_reset_peer()
	slots = []

func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_game = false

## bots take the heroes nobody picked
func _rebalance_bots() -> void:
	for i in 4:
		if slots[i]["peer"] == 0:
			slots[i]["hero"] = ""
	for i in 4:
		if slots[i]["peer"] == 0:
			slots[i]["hero"] = _free_hero("")

# ---------------------------------------------------------------- server events
func _on_peer_connected(_id: int) -> void:
	pass

func _on_connected() -> void:
	hello.rpc_id(1, my_name, my_hero)

func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	for i in slots.size():
		if slots[i]["peer"] == id:
			slots[i] = {"peer": 0, "name": "봇 %d" % (i + 1), "hero": slots[i]["hero"]}
	peer_left.emit(id)
	if not in_game:
		_rebalance_bots()
	lobby_sync.rpc(slots)

@rpc("any_peer", "reliable")
func hello(name: String, hero: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_game:
		return
	for i in 4:
		if slots[i]["peer"] == 0:
			slots[i]["peer"] = id
			slots[i]["name"] = name
			slots[i]["hero"] = ""
			slots[i]["hero"] = _free_hero(hero)
			break
	_rebalance_bots()
	lobby_sync.rpc(slots)

@rpc("any_peer", "call_local", "reliable")
func pick_hero(hero: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	for s in slots:
		if s["hero"] == hero and s["peer"] != 0 and s["peer"] != id:
			return    # taken by another human
	for i in 4:
		if slots[i]["peer"] == id:
			slots[i]["hero"] = hero
	# a bot holding that hero swaps away
	_rebalance_bots()
	lobby_sync.rpc(slots)

@rpc("authority", "call_local", "reliable")
func lobby_sync(s: Array) -> void:
	slots = s
	lobby_changed.emit(slots)

func start_game(seed_v: int) -> void:
	if is_host():
		start.rpc(slots, seed_v)

@rpc("authority", "call_local", "reliable")
func start(s: Array, seed_v: int) -> void:
	slots = s
	in_game = true
	game_started.emit(slots, seed_v, my_slot())

@rpc("authority", "call_local", "reliable")
func back_to_lobby() -> void:
	in_game = false
	returned_to_lobby.emit()

# ---------------------------------------------------------------- in-game traffic
func send_input(inp: Dictionary) -> void:
	c_input.rpc_id(1, inp["move"], inp["aim"], inp["attack"], inp["q"], inp["e"], inp.get("sp", 0))

@rpc("any_peer", "unreliable_ordered")
func c_input(move: Vector2, aim: Vector2, attack: bool, q: int, e: int, sp: int) -> void:
	input_received.emit(multiplayer.get_remote_sender_id(), {"move": move, "aim": aim, "attack": attack, "q": q, "e": e, "sp": sp})

func send_request(type: String, a: int, b: String) -> void:
	c_request.rpc_id(1, type, a, b)

@rpc("any_peer", "reliable")
func c_request(type: String, a: int, b: String) -> void:
	request_received.emit(multiplayer.get_remote_sender_id(), type, a, b)

## Snapshots are quantized (int16) and DEFLATE-compressed to stay under the ENet MTU.
const E_SCALE := [1.0, 1.0, 50.0, 50.0, 1000.0, 1000.0, 1.0, 1.0]
const S_SCALE := [1.0, 50.0, 50.0, 1000.0, 1000.0, 1.0]

static func _quant(arr: PackedFloat32Array, scale: Array) -> PackedByteArray:
	var stride := scale.size()
	var out := PackedByteArray()
	out.resize(arr.size() * 2)
	for i in arr.size():
		var k := i % stride
		var v: float = arr[i] * float(scale[k])
		if k == 0:
			out.encode_u16(i * 2, int(v) & 0xFFFF)
		else:
			out.encode_s16(i * 2, clampi(int(round(v)), -32768, 32767))
	return out

static func _dequant(b: PackedByteArray, scale: Array) -> PackedFloat32Array:
	var stride := scale.size()
	var n := b.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var k := i % stride
		if k == 0:
			out[i] = float(b.decode_u16(i * 2))
		else:
			out[i] = float(b.decode_s16(i * 2)) / scale[k]
	return out

func broadcast_snapshot(s: Dictionary) -> void:
	if not online:
		return
	var d := s.duplicate()
	d["e"] = _quant(s["e"], E_SCALE)
	d["s"] = _quant(s["s"], S_SCALE)
	var raw := var_to_bytes(d)
	s_snap.rpc(raw.compress(FileAccess.COMPRESSION_DEFLATE), raw.size())

@rpc("authority", "unreliable_ordered")
func s_snap(data: PackedByteArray, raw_size: int) -> void:
	var d = bytes_to_var(data.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE))
	if typeof(d) != TYPE_DICTIONARY:
		return
	d["e"] = _dequant(d["e"], E_SCALE)
	d["s"] = _dequant(d["s"], S_SCALE)
	snap_received.emit(d)

func broadcast_events(evs: Array) -> void:
	if online and not evs.is_empty():
		s_events.rpc(evs)

@rpc("authority", "reliable")
func s_events(evs: Array) -> void:
	events_received.emit(evs)
