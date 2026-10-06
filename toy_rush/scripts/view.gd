class_name View
extends Node3D
## Renders the game from snapshots + events (identical on host and clients).
## Builds the toy-kingdom diorama, keeps entity nodes in sync, turns events into VFX/sound.

const GRASS := Color("7fd14a")
const ROAD := Color("d8b86c")
const ROAD_EDGE := Color("bf9852")
const DIRT := Color("b77b45")

var map: MapDef
var hud: Node
var cam: CameraRig
var local_slot := 0
var slots: Array = []
var rng := RandomNumberGenerator.new()

var hero_nodes: Array = []          # per slot {root, model, ring, kind}
var enemy_nodes := {}               # id -> {root, model, kind, fly}
var soldier_nodes := {}             # id -> {root, model}
var tower_nodes := {}               # spot -> {model, kind, level}
var spot_nodes := {}                # spot -> Node3D
var snap := {}
var aim_marker: MeshInstance3D
var range_ring: MeshInstance3D
var _t := 0.0
var outline_w := 0.0          # ink outline width for props built by helpers

# ================================================================ build
func setup(p_map: MapDef, p_slots: Array, p_local: int, p_hud: Node, p_cam: CameraRig) -> void:
	map = p_map
	slots = p_slots
	local_slot = p_local
	hud = p_hud
	cam = p_cam
	rng.seed = 99
	if "--classic-map" in OS.get_cmdline_user_args():
		_env()
		_ground()
		_roads()
		_castle()
		_spawns()
		_spots()
		_props()
	else:
		var arena := Arena.new()
		add_child(arena)
		arena.build(map, cam)
		spot_nodes = arena.spot_nodes
	for i in 4:
		var kind: String = slots[i]["hero"]
		var root := Node3D.new()
		add_child(root)
		var m := UnitModel.new().build(Data.HEROES[kind]["model"], Data.PLAYER_COLORS[i])
		m.scale = Vector3.ONE * 1.8
		root.add_child(m)
		var ring := _ring(Data.PLAYER_COLORS[i], 0.55)
		root.add_child(ring)
		root.add_child(_blob(0.75))
		root.position = _v3(map.hero_spawn(i))
		hero_nodes.append({"root": root, "model": m, "ring": ring, "kind": kind, "dead": false})
	aim_marker = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	aim_marker.mesh = pm
	aim_marker.material_override = Mats.ground("ring", Color(1.3, 1.3, 1.3, 0.85), true)
	aim_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aim_marker.scale = Vector3.ONE * 0.9
	add_child(aim_marker)
	range_ring = MeshInstance3D.new()
	range_ring.mesh = pm
	range_ring.material_override = Mats.ground("ring_soft", Color(0.6, 1.4, 0.5, 0.7), true)
	range_ring.visible = false
	add_child(range_ring)

static func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)

func _env() -> void:
	var we := WorldEnvironment.new()
	we.environment = Look.environment()
	add_child(we)
	add_child(Look.sun())

func _mesh(mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = Mats.prop(col, 0.85, outline_w)
	m.position = pos
	m.rotation = rot
	m.scale = scl
	(parent if parent else self).add_child(m)
	return m

func _box(size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, col, pos, rot, Vector3.ONE, parent)

func _cyl(rt: float, rb: float, h: float, col: Color, pos: Vector3, parent: Node3D = null, seg := 20) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	return _mesh(c, col, pos, Vector3.ZERO, Vector3.ONE, parent)

func _sphere(r: float, col: Color, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _mesh(s, col, pos, Vector3.ZERO, scl, parent)

func _ring(col: Color, r: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + 0.1
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = Mats.glow(col, 1.2)
	ring.scale = Vector3(1, 0.25, 1)
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

func _blob(size: float) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size * 2.0, size * 2.0)
	b.mesh = pm
	b.material_override = Mats.ground("blob", Color(0.23, 0.2, 0.44, 0.45), false)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.position.y = 0.03
	return b

func _ground() -> void:
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(130, 1.0, 130)
	g.mesh = bm
	var gm := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	nt.noise = fn
	var ramp := Gradient.new()
	ramp.set_color(0, Color("70cc42"))
	ramp.set_color(1, Color("9be25a"))
	ramp.add_point(0.5, Color("86d84d"))
	nt.color_ramp = ramp
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(6, 6, 6)
	gm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	gm.roughness = 1.0
	gm.metallic_specular = 0.0
	g.material_override = gm
	g.position = Vector3(0, -0.5, 0)
	add_child(g)
	# raised boxy terrain blocks around the outside
	for i in 34:
		var a := TAU * i / 34.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(44.0, 50.0)
		var p := Vector2(cos(a), sin(a)) * r
		var sz := Vector3(rng.randf_range(6, 11), rng.randf_range(1.0, 3.5), rng.randf_range(6, 11))
		_box(sz, DIRT, _v3(p, sz.y * 0.5 - 0.1), Vector3(0, -a, 0))
		_box(Vector3(sz.x + 0.3, 0.3, sz.z + 0.3), GRASS.darkened(0.05), _v3(p, sz.y), Vector3(0, -a, 0))

func _roads() -> void:
	outline_w = 0.0
	for k in 4:
		var pts: PackedVector2Array = map.lanes[k]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var mid := (a + b) * 0.5
			var L := a.distance_to(b)
			var ang := atan2(b.x - a.x, b.y - a.y)
			_box(Vector3(MapDef.ROAD_W + 0.5, 0.06, L), ROAD_EDGE, _v3(mid, 0.02), Vector3(0, ang, 0))
			_box(Vector3(MapDef.ROAD_W, 0.08, L), ROAD, _v3(mid, 0.03), Vector3(0, ang, 0))
		for p in pts:
			_cyl(MapDef.ROAD_W * 0.5 + 0.25, MapDef.ROAD_W * 0.5 + 0.25, 0.06, ROAD_EDGE, _v3(p, 0.02))
			_cyl(MapDef.ROAD_W * 0.5, MapDef.ROAD_W * 0.5, 0.08, ROAD, _v3(p, 0.035))
		# pebbles on the road
		for i in 14:
			var d := rng.randf_range(2.0, map.length(k) - 4.0)
			var pp := map.pos_at(k, d) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
			_sphere(rng.randf_range(0.06, 0.12), ROAD_EDGE, _v3(pp, 0.08), Vector3(1, 0.5, 1))
	# plaza around castle
	_cyl(MapDef.HORN_R + 0.6, MapDef.HORN_R + 0.6, 0.06, ROAD_EDGE, Vector3(0, 0.02, 0), null, 40)
	_cyl(MapDef.HORN_R + 0.3, MapDef.HORN_R + 0.3, 0.08, Color("e1d6bd"), Vector3(0, 0.035, 0), null, 40)
	outline_w = 0.0

func _castle() -> void:
	outline_w = 1.3
	var stone := Color("d8d0c0")
	var stone_d := Color("b5aa95")
	var roof := Color("4a7fd1")
	var r := MapDef.CASTLE_R - 1.0
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		_cyl(0.85, 0.95, 3.2, stone, p + Vector3(0, 1.6, 0))
		_cyl(1.0, 1.0, 0.3, stone_d, p + Vector3(0, 3.25, 0))
		_cyl(0.0, 1.05, 1.5, roof, p + Vector3(0, 4.15, 0), null, 12)
		_cyl(0.03, 0.03, 0.8, Color("6b4a2f"), p + Vector3(0, 5.2, 0))
		_box(Vector3(0.6, 0.35, 0.03), Data.PLAYER_COLORS[i], p + Vector3(0.3, 5.45, 0))
	# walls between towers (gates face the lanes)
	for i in 4:
		var a := TAU * i / 4.0
		var p := Vector3(cos(a) * r * 0.72, 0, sin(a) * r * 0.72)
		var wall := Node3D.new()
		add_child(wall)
		wall.position = p
		wall.rotation.y = -a + PI * 0.5
		_box(Vector3(4.2, 1.9, 0.6), stone, Vector3(0, 0.95, 0), Vector3.ZERO, wall)
		for j in 6:
			_box(Vector3(0.45, 0.4, 0.62), stone_d, Vector3(-1.9 + j * 0.76, 2.05, 0), Vector3.ZERO, wall)
		_box(Vector3(1.3, 1.4, 0.64), Color("6b4a2f"), Vector3(0, 0.7, 0), Vector3.ZERO, wall)
	# keep
	_box(Vector3(2.6, 3.8, 2.6), stone, Vector3(0, 1.9, 0))
	var prism := PrismMesh.new()
	prism.size = Vector3(3.0, 1.6, 3.0)
	_mesh(prism, roof, Vector3(0, 4.6, 0))
	_cyl(0.04, 0.04, 1.4, Color("6b4a2f"), Vector3(0, 6.0, 0))
	_box(Vector3(1.0, 0.6, 0.04), Color("ffd23f"), Vector3(0.5, 6.4, 0))
	# war horn (call wave)
	var horn := Node3D.new()
	add_child(horn)
	horn.position = Vector3(0, 0, MapDef.CASTLE_R + 0.2)
	_cyl(0.3, 0.38, 0.6, Color("8a5a34"), Vector3(0, 0.3, 0), horn)
	var hm := _cyl(0.06, 0.32, 1.2, Color("ffd23f"), Vector3(0.2, 0.95, 0), horn)
	hm.rotation.z = 1.2
	outline_w = 0.0

func _spawns() -> void:
	var rock := Color("8f8db5")
	for k in 4:
		var p := map.spawn_pos(k)
		var dir := (map.pos_at(k, 2.0) - p).normalized()
		var root := Node3D.new()
		add_child(root)
		root.position = _v3(p - dir * 1.0)
		root.rotation.y = atan2(dir.x, dir.y)
		# rocky hill (overlapping rounded boulders)
		var boulders := [[0.0, -2.2, 3.2, 2.4], [-2.8, -1.6, 2.2, 1.8], [2.8, -1.6, 2.3, 1.9], [-1.6, -3.6, 2.4, 2.6],
			[1.8, -3.8, 2.5, 2.8], [0.0, -4.6, 2.6, 3.4], [-4.3, -0.6, 1.4, 1.1], [4.3, -0.7, 1.5, 1.2]]
		for b in boulders:
			var c := rock.lerp(Color("a6a4c6"), rng.randf() * 0.6)
			_mesh(Look.rock_mesh(), c, Vector3(b[0], b[3] * 0.45, b[1]), Vector3(0, rng.randf() * TAU, 0), Vector3(b[2], b[3] * 0.75, b[2]), root)
		# grass cap + little trees on top
		_sphere(2.6, GRASS, Vector3(0, 3.0, -3.6), Vector3(1.2, 0.35, 1.0), root)
		for j in 3:
			var tp := Vector3(-1.4 + j * 1.4, 3.1, -3.8 + rng.randf_range(-0.4, 0.4))
			_cyl(0.1, 0.13, 0.6, Color("8a5a34"), tp + Vector3(0, 0.3, 0), root)
			_sphere(0.55, Color("57b53a").lerp(Color("82d04a"), rng.randf()), tp + Vector3(0, 0.95, 0), Vector3(1, 0.85, 1), root)
		# cave mouth: dark half-disc facing the road
		var mouth := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.7
		cm.bottom_radius = 1.7
		cm.height = 0.2
		mouth.mesh = cm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color("1d1530")
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mouth.material_override = mm
		mouth.rotation.x = PI * 0.5
		mouth.position = Vector3(0, 0.2, -0.05)
		mouth.scale = Vector3(1.0, 1.0, 1.25)
		root.add_child(mouth)
		_box(Vector3(4.0, 0.3, 1.2), Color("2a2238"), Vector3(0, 0.05, 0.3), Vector3.ZERO, root)
		# glowing eyes in the dark (spooky but cute)
		for sx in [-0.45, 0.45]:
			var e := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.12
			es.height = 0.18
			e.mesh = es
			e.material_override = Mats.glow(Color(1.0, 0.85, 0.3), 2.4)
			e.position = Vector3(sx, 1.1, 0.05)
			root.add_child(e)
		# lane owner banners
		for sx2 in [-1.0, 1.0]:
			_cyl(0.07, 0.07, 2.6, Color("6b4a2f"), Vector3(sx2 * 2.6, 1.3, 1.4), root)
			_box(Vector3(0.8, 1.1, 0.05), Data.PLAYER_COLORS[k], Vector3(sx2 * 2.6 + 0.42, 2.0, 1.4), Vector3.ZERO, root)
			_sphere(0.12, Color("ffd23f"), Vector3(sx2 * 2.6, 2.65, 1.4), Vector3.ONE, root)

func _spots() -> void:
	for sp in map.spots:
		var n := Node3D.new()
		add_child(n)
		n.position = _v3(sp["pos"])
		outline_w = 0.0
		_cyl(MapDef.SPOT_R + 0.15, MapDef.SPOT_R + 0.2, 0.08, ROAD_EDGE.darkened(0.1), Vector3(0, 0.03, 0), n)
		_cyl(MapDef.SPOT_R, MapDef.SPOT_R, 0.1, Color("d9b97a"), Vector3(0, 0.05, 0), n)
		outline_w = 0.0
		_cyl(0.04, 0.04, 0.8, Color("6b4a2f"), Vector3(0.5, 0.45, -0.4), n)
		_box(Vector3(0.45, 0.32, 0.04), Color("fff8e6"), Vector3(0.5, 0.82, -0.4), Vector3(0, 0.3, 0), n)
		_box(Vector3(0.18, 0.12, 0.05), Data.PLAYER_COLORS[sp["lane"]], Vector3(0.5, 0.82, -0.38), Vector3(0, 0.3, 0), n)
		spot_nodes[sp["id"]] = n

func _clear_of_layout(p: Vector2, margin: float) -> bool:
	if p.length() < MapDef.HORN_R + 2.0:
		return false
	if absf(p.x) > 43.0 or absf(p.y) > 43.0:
		return false
	if map.dist_to_any_road(p) < MapDef.ROAD_W * 0.5 + margin:
		return false
	for sp in map.spots:
		if p.distance_to(sp["pos"]) < 1.9 + margin * 0.5:
			return false
	for k in 4:
		if p.distance_to(map.spawn_pos(k)) < 6.5:
			return false
	return true

## MultiMesh helper: one draw call per prop part, per-instance color
func _multi(mesh: Mesh, xforms: Array, colors: Array, shadows := true, ink := 0.0) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	Mats.toonify(m, ink, 0.5)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.rim = 0.15
	mi.material_override = m
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _props() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 7
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.75
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 8
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 8
	var canopy_x := []
	var canopy_c := []
	var trunk_x := []
	var trunk_c := []
	var rock_x := []
	var rock_c := []
	var small_x := []
	var small_c := []
	var tuft_x := []
	var tuft_c := []
	var add_tree := func(p: Vector2, s: float) -> void:
		trunk_x.append(Transform3D(Basis.from_scale(Vector3(0.17, 0.95, 0.17) * s), _v3(p, 0.47 * s)))
		trunk_c.append(Color("8a5a34"))
		var g := Color("3a952c").lerp(Color("55b236"), rng.randf())
		canopy_x.append(Transform3D(Basis.from_scale(Vector3(0.8, 0.68, 0.8) * s), _v3(p, 1.3 * s)))
		canopy_c.append(g)
		canopy_x.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.52 * s), _v3(p, 1.85 * s) + Vector3(0.3, 0, -0.12) * s))
		canopy_c.append(g.lightened(0.12))
		canopy_x.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.46 * s), _v3(p, 1.55 * s) + Vector3(-0.42, 0, 0.2) * s))
		canopy_c.append(g.darkened(0.06))
	# 1) dense forest belts far from the roads (Kingdom Rush style framing)
	var tries := 0
	var placed := 0
	while placed < 420 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-43, 43), rng.randf_range(-43, 43))
		var dr := map.dist_to_any_road(p)
		if dr < 6.0 or not _clear_of_layout(p, 2.0):
			continue
		add_tree.call(p, rng.randf_range(0.9, 1.5))
		placed += 1
	# 2) groves, bushes, rocks and flowers near the roads
	tries = 0
	placed = 0
	while placed < 360 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-42, 42), rng.randf_range(-42, 42))
		if not _clear_of_layout(p, 1.2):
			continue
		var r := rng.randf()
		if r < 0.18:
			add_tree.call(p, rng.randf_range(0.8, 1.2))
		elif r < 0.45:
			var g := Color("45a332").lerp(Color("62bd3d"), rng.randf())
			var s := rng.randf_range(0.8, 1.3)
			small_x.append(Transform3D(Basis.from_scale(Vector3(0.45, 0.36, 0.45) * s), _v3(p, 0.25 * s)))
			small_c.append(g)
			small_x.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.3 * s), _v3(p, 0.2 * s) + Vector3(0.32, 0, 0.06) * s))
			small_c.append(g.lightened(0.1))
		elif r < 0.6:
			var s2 := rng.randf_range(0.5, 1.4)
			rock_x.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(0.55, 0.32, 0.45) * s2), _v3(p, 0.12 * s2)))
			rock_c.append(Color("8f8db5").lerp(Color("a6a4c6"), rng.randf()))
		elif r < 0.82:
			var fc: Color = [Color("ffffff"), Color("ff8fb8"), Color("ffe066"), Color("b8a4ff")][rng.randi() % 4]
			for i in 5:
				var a := TAU * i / 5.0
				small_x.append(Transform3D(Basis.from_scale(Vector3(0.07, 0.03, 0.07)), _v3(p + Vector2(cos(a), sin(a)) * 0.09, 0.05)))
				small_c.append(fc)
			small_x.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.05), _v3(p, 0.07)))
			small_c.append(Color("ffd23f"))
		else:
			for i in 3:
				var o := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
				tuft_x.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).scaled(Vector3(0.05, 0.28, 0.05)), _v3(p + o, 0.12)))
				tuft_c.append(Color("4ea83a").lerp(Color("6cc24a"), rng.randf()))
		placed += 1
	_multi(sphere, canopy_x, canopy_c)
	_multi(trunk, trunk_x, trunk_c)
	_multi(Look.rock_mesh(), rock_x, rock_c)
	_multi(sphere, small_x, small_c, false)
	_multi(cone, tuft_x, tuft_c, false, 0.0)
	# fences along the last bend before the castle
	for k in 4:
		var L := map.length(k)
		var d := L * 0.08
		while d < L * 0.95:
			var pp := map.pos_at(k, d)
			var t := map.dir_at(k, d)
			var n := Vector2(-t.y, t.x)
			for sd in [-1.0, 1.0]:
				var fp: Vector2 = pp + n * sd * (MapDef.ROAD_W * 0.5 + 0.55)
				if map.dist_to_any_road(fp) > MapDef.ROAD_W * 0.5 + 0.3 and _spot_clear(fp):
					_cyl(0.06, 0.07, 0.55, Color("c8894a"), _v3(fp, 0.27))
			d += 2.2

func _spot_clear(p: Vector2) -> bool:
	for sp in map.spots:
		if p.distance_to(sp["pos"]) < 1.8:
			return false
	return p.length() > MapDef.HORN_R + 1.0

# ================================================================ snapshot sync
func apply_snapshot(s: Dictionary) -> void:
	snap = s
	# towers
	var seen_t := {}
	for t in s.get("t", []):
		var spot: int = t[0]
		var kind: String = Data.TOWER_ORDER[t[1]]
		var level: int = t[2]
		seen_t[spot] = true
		var tn = tower_nodes.get(spot)
		if tn == null or tn["level"] != level or tn["kind"] != kind:
			_place_tower(spot, kind, level, tn == null)
		tower_nodes[spot]["aim"] = t[3]
	for spot in tower_nodes.keys():
		if not seen_t.has(spot):
			var tm: TowerModel = tower_nodes[spot]["model"]
			var tw := tm.create_tween()
			tw.tween_property(tm, "scale", Vector3(1.3, 0.1, 1.3), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(tm.queue_free)
			tower_nodes.erase(spot)
			spot_nodes[spot].visible = true
	# enemies
	var es: PackedFloat32Array = s.get("e", PackedFloat32Array())
	var seen := {}
	var i := 0
	while i + 7 < es.size():
		var id := int(es[i])
		seen[id] = true
		var en = enemy_nodes.get(id)
		if en == null:
			en = _make_enemy(id, Sim.ENEMY_KINDS[int(es[i + 1])], Vector2(es[i + 2], es[i + 3]))
		en["goal"] = Vector2(es[i + 2], es[i + 3])
		en["face"] = es[i + 4]
		en["hp"] = es[i + 5]
		en["flags"] = int(es[i + 6])
		i += 8
	for id in enemy_nodes.keys():
		if not seen.has(id):
			_remove_enemy(id)
	# soldiers
	var ss: PackedFloat32Array = s.get("s", PackedFloat32Array())
	var seen_s := {}
	i = 0
	while i + 5 < ss.size():
		var sid := int(ss[i])
		seen_s[sid] = true
		var sn = soldier_nodes.get(sid)
		if sn == null:
			sn = _make_soldier(sid, Vector2(ss[i + 1], ss[i + 2]))
		sn["goal"] = Vector2(ss[i + 1], ss[i + 2])
		sn["face"] = ss[i + 3]
		sn["hp"] = ss[i + 4]
		sn["moving"] = ss[i + 5] > 0.5
		i += 6
	for sid in soldier_nodes.keys():
		if not seen_s.has(sid):
			var node: Node3D = soldier_nodes[sid]["root"]
			node.queue_free()
			soldier_nodes.erase(sid)
	# heroes
	for h in s.get("h", []):
		var hn: Dictionary = hero_nodes[h[0]]
		hn["goal"] = Vector2(h[1], h[2])
		hn["face"] = h[3]
		hn["hp"] = h[4] / maxf(h[5], 1.0)
		var dead: bool = h[6] == 1
		if dead != hn["dead"]:
			hn["dead"] = dead
			hn["root"].visible = not dead
			if not dead:
				hn["root"].position = _v3(Vector2(h[1], h[2]))
		hn["moving"] = h[12] == 1
		hn["whirl"] = h[13] == 1
		hn["jump"] = h[14]
		hn["guard"] = h[15] == 1

func _place_tower(spot: int, kind: String, level: int, fresh: bool) -> void:
	var old = tower_nodes.get(spot)
	if old:
		old["model"].queue_free()
	var tm := TowerModel.new().build(kind, level)
	var sp: Dictionary = map.spots[spot]
	add_child(tm)
	tm.position = _v3(sp["pos"])
	tm.rotation.y = PI * 0.25 + PI   # face the camera a bit
	var target_scale := tm.scale
	tm.position.y = 2.5
	tm.scale = target_scale * Vector3(0.8, 1.2, 0.8)
	var tw := tm.create_tween()
	tw.tween_property(tm, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(tm, "scale", target_scale * Vector3(1.25, 0.7, 1.25), 0.06)
	tw.tween_property(tm, "scale", target_scale, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	spot_nodes[spot].visible = false
	tower_nodes[spot] = {"model": tm, "kind": kind, "level": level, "aim": 0.0}

func _make_enemy(id: int, kind: String, p: Vector2) -> Dictionary:
	var d: Dictionary = Data.ENEMIES[kind]
	var root := Node3D.new()
	add_child(root)
	root.position = _v3(p)
	var m := UnitModel.new().build(kind, Data.COL_ENEMY)
	m.scale = Vector3.ONE * 1.55 * d["scale"]
	root.add_child(m)
	var fly: bool = d.get("fly", false)
	if fly:
		m.position.y = 1.6
	root.add_child(_blob(0.5 * d["scale"]))
	var en := {"root": root, "model": m, "kind": kind, "fly": fly, "goal": p, "face": 0.0, "hp": 1.0, "flags": 0}
	enemy_nodes[id] = en
	# pop in from the cave
	m.scale *= 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 1.55 * d["scale"], 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return en

func _remove_enemy(id: int) -> void:
	var en: Dictionary = enemy_nodes[id]
	enemy_nodes.erase(id)
	var root: Node3D = en["root"]
	var m: UnitModel = en["model"]
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(m, "rotation:z", 1.4, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "scale", m.scale * 0.6, 0.2)
	tw.chain().tween_callback(root.queue_free)

func _make_soldier(id: int, p: Vector2) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.position = _v3(p)
	var m := UnitModel.new().build("footman", Color("3fa9f5"))
	m.scale = Vector3.ONE * 1.35
	root.add_child(m)
	root.add_child(_blob(0.45))
	var sn := {"root": root, "model": m, "goal": p, "face": 0.0, "hp": 1.0, "moving": false}
	soldier_nodes[id] = sn
	m.scale *= 0.2
	m.create_tween().tween_property(m, "scale", Vector3.ONE * 1.35, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return sn

# ================================================================ per frame
func _process(delta: float) -> void:
	_t += delta
	for id in dmg_acc.keys():
		if dmg_acc[id]["t"] <= _t:
			_flush_damage(id)
	var k := 1.0 - exp(-delta * 14.0)
	for i in hero_nodes.size():
		var hn: Dictionary = hero_nodes[i]
		if not hn.has("goal"):
			continue
		var root: Node3D = hn["root"]
		var g: Vector2 = hn["goal"]
		root.position = root.position.lerp(_v3(g), k)
		var m: UnitModel = hn["model"]
		m.position.y = hn.get("jump", 0.0)
		if hn.get("whirl", false):
			m.rotation.y += delta * 22.0
		else:
			m.rotation.y = lerp_angle(m.rotation.y, hn["face"] + PI, 1.0 - exp(-delta * 18.0))
		m.walk = lerpf(m.walk, 1.0 if hn.get("moving", false) else 0.0, 1.0 - exp(-delta * 10.0))
		if not hn["dead"]:
			hud.bar("h%d" % i, root.position + Vector3(0, 2.3 + m.position.y, 0), hn["hp"], Data.PLAYER_COLORS[i], 76, slots[i]["name"])
	for id in enemy_nodes:
		var en: Dictionary = enemy_nodes[id]
		var root: Node3D = en["root"]
		root.position = root.position.lerp(_v3(en["goal"]), k)
		var m: UnitModel = en["model"]
		m.rotation.y = lerp_angle(m.rotation.y, en["face"] + PI, 1.0 - exp(-delta * 12.0))
		var fl: int = en["flags"]
		m.walk = lerpf(m.walk, 1.0 if fl & 1 else 0.0, 1.0 - exp(-delta * 10.0))
		var stunned := (fl & 8) != 0
		m.rotation.z = sin(_t * 12.0) * 0.15 if stunned else lerpf(m.rotation.z, 0.0, 0.2)
		if stunned and _t > en.get("stun_fx", 0.0):
			en["stun_fx"] = _t + 0.95
			Octo.stun_stars(root, 1.6 * Data.ENEMIES[en["kind"]]["scale"] + (1.6 if en["fly"] else 0.0), 1.0)
		var big: bool = Data.ENEMIES[en["kind"]].get("boss", false)
		var hy: float = (1.6 if en["fly"] else 0.0) + 1.5 * Data.ENEMIES[en["kind"]]["scale"]
		hud.bar("e%d" % id, root.position + Vector3(0, hy, 0), en["hp"], Data.COL_ENEMY, 120 if big else 44, "")
	for id in soldier_nodes:
		var sn: Dictionary = soldier_nodes[id]
		var root: Node3D = sn["root"]
		root.position = root.position.lerp(_v3(sn["goal"]), k)
		var m: UnitModel = sn["model"]
		m.rotation.y = lerp_angle(m.rotation.y, sn["face"] + PI, 1.0 - exp(-delta * 12.0))
		m.walk = lerpf(m.walk, 1.0 if sn["moving"] else 0.0, 1.0 - exp(-delta * 10.0))
		if sn["hp"] < 0.999:
			hud.bar("s%d" % id, root.position + Vector3(0, 1.4, 0), sn["hp"], Color("7fc8ff"), 36, "")
	for spot in tower_nodes:
		var tn: Dictionary = tower_nodes[spot]
		(tn["model"] as TowerModel).aim_at(tn["aim"] - PI * 0.25 - PI, delta)

func hero_pos(slot: int) -> Vector3:
	return (hero_nodes[slot]["root"] as Node3D).position

func set_aim_marker(p: Vector3, on: bool) -> void:
	aim_marker.visible = on
	aim_marker.position = p + Vector3(0, 0.06, 0)
	aim_marker.rotation.y = _t * 2.0

func show_range(p: Vector2, r: float, on: bool) -> void:
	range_ring.visible = on
	if on:
		range_ring.position = _v3(p, 0.07)
		range_ring.scale = Vector3.ONE * r * 2.55

# ================================================================ events -> juice
func _node_for(kind: String, id) -> Node3D:
	match kind:
		"h":
			return hero_nodes[int(id)]["root"]
		"e":
			var en = enemy_nodes.get(int(id))
			return en["root"] if en else null
		"s":
			var sn = soldier_nodes.get(int(id))
			return sn["root"] if sn else null
	return null

func _model_for(kind: String, id) -> UnitModel:
	match kind:
		"h":
			return hero_nodes[int(id)]["model"]
		"e":
			var en = enemy_nodes.get(int(id))
			return en["model"] if en else null
		"s":
			var sn = soldier_nodes.get(int(id))
			return sn["model"] if sn else null
	return null

func _near(p: Vector3) -> bool:
	return Vfx.visible_at(p)

## ---------------------------------------------------------------- OCTOPO palettes
## Guide colour system: our side = ally family by tier, enemies = enemy family by tier,
## states (heal / gold / stun) use their own codes.
var PAL_TOWER := {
	"archer": Fx.ALLY["low"],
	"mage": Fx.ALLY["ultra"],
	"artillery": Fx.ALLY["high"],
	"barracks": Fx.ALLY["low"],
	"soldier": Fx.ALLY["low"],
}
var PAL_ENEMY: Array = Fx.ENEMY["low"]
var PAL_DUST: Array = Fx.STATE["dust"]
var PAL_HEAL: Array = Fx.STATE["heal"]
var PAL_GOLD: Array = Fx.STATE["gold"]
var dmg_acc := {}      # enemy id -> merged damage feedback (guide: readability with overlapping effects)

func _enemy_pal(kind: String) -> Array:
	if Data.ENEMIES.get(kind, {}).get("boss", false):
		return Fx.ENEMY["ultra"]
	if kind == "darkknight":
		return Fx.ENEMY["medium"]
	if kind == "shaman":
		return Fx.ENEMY["high"]
	return Fx.ENEMY["low"]

func _hero_pal(slot: int) -> Array:
	return Data.HEROES[slots[slot]["hero"]]["palette"]

func _src_pal(slot: int, tag: String, magic: bool) -> Array:
	if slot >= 0:
		return _hero_pal(slot)
	if PAL_TOWER.has(tag):
		return PAL_TOWER[tag]
	return PAL_TOWER["mage"] if magic else PAL_TOWER["archer"]

func _fwd3(face: float) -> Vector3:
	return Vector3(sin(face), 0, cos(face))

func handle_events(evs: Array) -> void:
	Vfx.focus = cam.focus
	for ev in evs:
		var t: String = ev[0]
		match t:
			"atk":
				_atk_fx(ev)
			"proj":
				var from := Vector3(ev[2], ev[3], ev[4])
				if not _near(from):
					continue
				var tgt: Node3D = null
				if int(ev[5]) >= 0:
					tgt = _node_for("e", ev[5])
				Vfx.shot(ev[1], from, tgt, Vector3(ev[6], 0.4, ev[7]), ev[8])
			"hit":
				var p := Vector3(ev[1], 0.8, ev[2])
				if not _near(p):
					continue
				var m2 := _model_for("e", ev[5])
				if m2:
					m2.flash()
					m2.punch_scale(1.2, 0.8, 0.3)
					var en = enemy_nodes.get(int(ev[5]))
					if en and en["fly"]:
						p.y += 1.6
				var slot: int = ev[6] if ev.size() > 6 else -1
				var tag: String = ev[7] if ev.size() > 7 else ""
				var dmg: float = ev[3]
				var mine := slot == local_slot
				# priority: my hits = skill-level, other heroes = basic, towers/soldiers = ambient
				var prio := 2 if mine else (1 if slot >= 0 else 0)
				Octo.impact(p, _src_pal(slot, tag, ev[4] == 1), clampf(0.6 + dmg / 30.0, 0.6, 1.5), prio)
				if tag == "mage":
					Octo.lightning(p + Vector3(randf_range(-0.6, 0.6), 1.4, randf_range(-0.6, 0.6)), p, PAL_TOWER["mage"], 4, 0.1)
				_acc_damage(int(ev[5]), p, dmg, ev[4] == 1, mine)
				if mine or randf() < 0.4:
					Sfx.play("thud", -14.0, randf_range(1.0, 1.4))
			"boom":
				_boom_fx(ev)
			"die":
				_flush_damage(int(ev[1]))
				var dp := Vector3(ev[2], 0.0, ev[3])
				if _near(dp):
					var en2 = enemy_nodes.get(int(ev[1]))
					if en2 and en2["fly"]:
						dp.y += 1.4
					Octo.death(dp, _enemy_pal(en2["kind"]) if en2 else PAL_ENEMY)
					Vfx.coin_burst(dp, 3)
					if int(ev[4]) >= 10:          # small bounties: coin burst + HUD counter only
						hud.gold_pop(dp + Vector3(0, 1.0, 0), ev[4])
					Sfx.play("poof", -10.0, randf_range(0.9, 1.2))
			"sdie":
				var sp2 := Vector3(ev[2], 0, ev[3])
				if _near(sp2):
					Octo.death(sp2, PAL_TOWER["soldier"])
			"leak":
				hud.leak_alert(int(ev[1]), int(ev[2]))
				Octo.burst(Vector3(ev[3], 0, ev[4]), Fx.ENEMY["high"], 1.2, 0.15)
				Sfx.play("sad", -6.0, 1.6)
			"build":
				var bpos: Vector2 = map.spots[int(ev[1])]["pos"]
				var b3 := _v3(bpos)
				if _near(b3):
					var lvl := int(ev[3])
					get_tree().create_timer(0.18).timeout.connect(func():
						Vfx.dust_ring(b3, 1.6)
						Vfx.debris(b3, 6, Color("b77b45"))
						Octo.impact(b3 + Vector3(0, 0.6, 0), PAL_TOWER.get(ev[2], PAL_DUST), 1.2)
						Sfx.play("pop", -4.0, 0.7))
					if lvl > 1:
						Octo.level_up(b3, Fx.ALLY["high"])
						Sfx.play("chime", -6.0)
			"sell":
				var sp3: Vector2 = map.spots[int(ev[1])]["pos"]
				Octo.burst(_v3(sp3), PAL_GOLD, 1.0)
				Vfx.coin_burst(_v3(sp3), 10)
				hud.gold_pop(_v3(sp3, 1.5), ev[2])
				Sfx.play("chime", -6.0, 1.3)
			"heal":
				var hp3 := Vector3(ev[1], 0, ev[2])
				if _near(hp3):
					Octo.plus_rise(hp3, PAL_HEAL[0], 5, 0.5)
					Vfx.ground_ring(hp3, Color(0.5, 1.5, 0.6, 0.9), 0.3, 1.8, 0.4)
					if ev[3] > 0.0:
						hud.damage_number(hp3 + Vector3(0, 2.2, 0), ev[3], false, Color("8fff8a"), "+")
			"eheal":
				var ep := Vector3(ev[1], 0, ev[2])
				if _near(ep):
					Octo.plus_rise(ep, Color("9cff6a"), 4, 1.2)
					Octo.decal(ep, "rune", Fx.STATE["heal"], 1.4, 0.7, 2.0)
			"lvl":
				var slot2 := int(ev[1])
				var lp := hero_pos(slot2)
				Octo.level_up(lp, _hero_pal(slot2))
				hud.callout(lp + Vector3(0, 2.8, 0), "LEVEL %d!" % int(ev[2]), Data.COL_GOLD)
				Sfx.play("chime", -4.0, 1.2)
			"wave":
				hud.wave_banner(int(ev[1]))
				Sfx.play("clash", -4.0, 0.8)
			"boss":
				hud.banner("BOSS!", Color("ff6b8a"), 0.9, 110)
				cam.add_trauma(0.4)
				Sfx.play("boom", -2.0, 0.5)
			"called":
				hud.toast("웨이브 조기 호출! +%d G" % int(ev[2]), Data.COL_GOLD)
				Octo.burst(Vector3(0, 0, MapDef.CASTLE_R + 0.2), PAL_GOLD, 1.2)
			"msg":
				if int(ev[1]) == local_slot:
					hud.toast(ev[2], Color("ff9aac"))
			"hero_die":
				var dp2 := Vector3(ev[2], 0, ev[3])
				Octo.death(dp2, _hero_pal(int(ev[1])))
				Octo.burst(dp2, _hero_pal(int(ev[1])), 1.0)
				hud.callout(dp2 + Vector3(0, 2.0, 0), "%s 쓰러짐!" % slots[int(ev[1])]["name"], Color("ff9aac"))
				Sfx.play("sad", -6.0)
			"respawn":
				Octo.level_up(Vector3(ev[2], 0, ev[3]), _hero_pal(int(ev[1])))
			"dash_end":
				var de := Vector3(ev[3], 0, ev[4])
				if ev[2] == "charge":
					Octo.burst(de, _hero_pal(int(ev[1])), 1.1, 0.15)
					Octo.decal(de, "crack", _hero_pal(int(ev[1])), 1.3, 1.0)
				else:
					Vfx.dust_ring(de, 0.8)
			"shake":
				cam.add_trauma(ev[1])
			"skill":
				_skill_fx(ev)
			"end":
				pass

## merge hits on the same target for 0.22 s; mine are big, others small/dim (or hidden if tiny)
func _acc_damage(id: int, p: Vector3, dmg: float, magic: bool, mine: bool) -> void:
	var a = dmg_acc.get(id)
	if a == null:
		a = {"sum": 0.0, "magic": magic, "mine": false, "pos": p, "t": _t + 0.22}
		dmg_acc[id] = a
	a["sum"] += dmg
	a["mine"] = a["mine"] or mine
	a["pos"] = p

var _nums_t := 0.0
var _nums_n := 0

## guide readability: merge per target AND cap how many numbers appear per 0.25 s window
func _flush_damage(id: int) -> void:
	var a = dmg_acc.get(id)
	if a == null:
		return
	dmg_acc.erase(id)
	if _t - _nums_t > 0.25:
		_nums_t = _t
		_nums_n = 0
	var cap := 3 if a["mine"] else 1
	if _nums_n >= cap and a["sum"] < 150.0:
		return
	_nums_n += 1
	if a["mine"] or a["sum"] >= 12.0:
		hud.damage_number(a["pos"] + Vector3(0, 0.6, 0), a["sum"], a["magic"], Color(-1, 0, 0), "", a["mine"])

func _atk_fx(ev: Array) -> void:
	match ev[1]:
		"t":
			var tn = tower_nodes.get(int(ev[2]))
			if tn == null:
				return
			var tm: TowerModel = tn["model"]
			tm.fire()
			if not _near(tm.position):
				return
			var top := tm.position + Vector3(0, 2.4 if ev[3] != "artillery" else 1.5, 0)
			Octo.muzzle(top, _fwd3(tn["aim"]), PAL_TOWER.get(ev[3], PAL_DUST), 1.0 if ev[3] != "artillery" else 1.6)
			if ev[3] == "artillery":
				Vfx.puff(top, Color("f4f0e8"), 0.45, Vector3(0, 0.6, 0), 0.6)
				Sfx.play("boom", -12.0, 1.6)
			else:
				Sfx.play("whoosh", -16.0, 1.4)
		"h":
			var slot := int(ev[2])
			var hn: Dictionary = hero_nodes[slot]
			var m: UnitModel = hn["model"]
			m.play_attack(ev[3])
			var root: Node3D = hn["root"]
			if not _near(root.position):
				return
			var face: float = hn.get("face", 0.0)
			var pal := _hero_pal(slot)
			match ev[3]:
				"melee":
					Octo.slash(root.position + Vector3(0, 0.7, 0), face + PI, pal, 1.9, 130.0, 0.7)
				"spin":
					Octo.slash(root.position + Vector3(0, 0.6, 0), face, pal, 1.9, 340.0, 0.6, 0.22)
				_:
					Octo.muzzle(root.position + Vector3(0, 1.0, 0) + _fwd3(face) * 0.5, _fwd3(face), pal)
			Sfx.play("whoosh", -12.0, 1.2)
		"s":
			var sn = soldier_nodes.get(int(ev[2]))
			if sn:
				(sn["model"] as UnitModel).play_attack("melee")
				var r: Node3D = sn["root"]
				if _near(r.position):
					Octo.slash(r.position + Vector3(0, 0.5, 0), sn["face"] + PI, PAL_TOWER["soldier"], 1.0, 110.0, 0.35, 0.14, 0)
		"e":
			var en = enemy_nodes.get(int(ev[2]))
			if en:
				(en["model"] as UnitModel).play_attack("melee")
				var r2: Node3D = en["root"]
				if _near(r2.position):
					var big: bool = Data.ENEMIES[en["kind"]].get("boss", false)
					Octo.slash(r2.position + Vector3(0, 0.5, 0), en["face"] + PI, _enemy_pal(en["kind"]), 2.2 if big else 1.0, 110.0, 0.5 if big else 0.3, 0.16, 2 if big else 0)

func _boom_fx(ev: Array) -> void:
	var bp := Vector3(ev[2], 0.0, ev[3])
	if not _near(bp):
		return
	var r: float = ev[4]
	match ev[1]:
		"fireball":
			Octo.burst(bp, Data.HEROES["wizard"]["palette"], r * 0.6)
			Vfx.dust_ring(bp, 0.6)
			Sfx.play("boom", -10.0, 1.4)
		"shell":
			Octo.burst(bp, PAL_TOWER["artillery"], r * 0.6, 0.12)
			Octo.decal(bp, "crack", PAL_TOWER["artillery"], r * 0.8, 1.0)
			Vfx.debris(bp, 6, Color("9a6a3a"))
			Sfx.play("boom", -7.0, 1.0)
		"meteor":
			Octo.burst(bp, Data.HEROES["wizard"]["palette"], 3.0, 0.6)
			Octo.decal(bp, "crack", Fx.ALLY["ultra"], 3.4, 1.3)
			Octo.flame_ring(bp, 2.6, Data.HEROES["wizard"]["palette"], 0.9)
			Vfx.debris(bp, 12, Color("7a5a3a"))
			Sfx.play("boom", -2.0, 0.6)
		"leap":
			Octo.burst(bp, Data.HEROES["valkyrie"]["palette"], 1.8, 0.45)
			Octo.decal(bp, "crack", Data.HEROES["valkyrie"]["palette"], 2.4, 1.2)
			Vfx.debris(bp, 10, Color("9a6a3a"))
			Vfx.dust_ring(bp, 1.4)
			Sfx.play("boom", -4.0, 0.8)
		"ogre":
			Octo.burst(bp, Fx.ENEMY["ultra"], 1.6, 0.4)
			Octo.decal(bp, "crack", Fx.ENEMY["ultra"], r, 1.2)
			Vfx.debris(bp, 8, Color("7a5a3a"))
			Sfx.play("boom", -4.0, 0.6)

func _skill_fx(ev: Array) -> void:
	var slot := int(ev[1])
	var p := Vector3(ev[3], 0, ev[4])
	var col: Color = Data.PLAYER_COLORS[slot]
	var hk: String = slots[slot]["hero"]
	var pal := _hero_pal(slot)
	var hn: Node3D = hero_nodes[slot]["root"]
	var label: String = ""
	var near := _near(p)
	match ev[2]:
		"slam":
			label = Data.HEROES[hk]["q"]["name"]
			if near:
				Octo.charge(p + Vector3(0, 0.6, 0), pal, 0.12, 1.4)
				Octo.burst(p, pal, 2.0, 0.6)
				Octo.decal(p, "crack", pal, 2.8, 1.2)
				Vfx.debris(p, 12, Color("9a6a3a"))
				Sfx.play("boom", -3.0, 0.8)
		"shout":
			label = Data.HEROES[hk]["e"]["name"]
			if near:
				for i in 3:
					get_tree().create_timer(i * 0.1).timeout.connect(func():
						Vfx.ground_ring(p, Color(1.8, 0.5, 0.3, 1.0), 0.6, 9.0, 0.45)
						Vfx.ground_ring(p, Color(1.8, 1.3, 0.4, 1.0), 0.4, 6.0, 0.35, "ring_soft"))
				Octo.impact(p + Vector3(0, 1.4, 0), pal, 1.6)
				Octo.decal(p, "rune", pal, 4.2, 1.0, 1.0)
				Sfx.play("clash", -5.0, 1.3)
		"charge":
			label = Data.HEROES[hk]["space"]["name"]
			Octo.dash_trail(p, Vector3(ev[5], 0, ev[6]), pal)
			Octo.muzzle(p + Vector3(0, 0.8, 0), Vector3(ev[5], 0, ev[6]) - p, pal, 1.6)
			Sfx.play("whoosh", -4.0, 0.7)
		"volley":
			label = Data.HEROES[hk]["q"]["name"]
			var aim_face: float = hero_nodes[slot].get("face", 0.0)
			for i in 7:
				var a := aim_face + deg_to_rad(-30.0 + i * 10.0)
				Octo.streak(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + _fwd3(a) * 2.2, Octo._hdr(pal[0], 1.6), 0.06, 0.18)
			Octo.muzzle(p + Vector3(0, 1.0, 0) + _fwd3(aim_face) * 0.5, _fwd3(aim_face), pal, 1.4)
			Sfx.play("whoosh", -6.0, 1.6)
		"pierce":
			label = Data.HEROES[hk]["e"]["name"]
			var a3 := p + Vector3(0, 1.0, 0)
			var b3 := Vector3(ev[5], 1.0, ev[6])
			Octo.charge(a3, pal, 0.12, 1.0)
			Octo.streak(a3, b3, Octo._hdr(Color.WHITE, 2.4), 0.12, 0.3)
			Octo.streak(a3, b3, Octo._hdr(pal[0], 1.8), 0.38, 0.38)
			Octo.streak(a3, b3, Octo._hdr(pal[1], 1.2), 0.7, 0.25)
			for k in 5:
				Vfx.puff(a3.lerp(b3, k / 4.0), pal[2], 0.25, Vector3(0, 0.3, 0), 0.4, k * 0.03)
			Octo.impact(b3, pal, 1.2)
			Sfx.play("whoosh", -3.0, 1.8)
		"roll":
			Octo.dash_trail(p, Vector3(ev[5], 0, ev[6]), pal)
			Sfx.play("whoosh", -8.0, 1.5)
		"meteor":
			label = Data.HEROES[hk]["q"]["name"]
			Octo.decal(p, "rune", Fx.ALLY["ultra"], 3.5, 1.0, 2.5)
			Vfx.meteor(p, 0.85)
			Sfx.play("whoosh", -4.0, 0.5)
		"nova":
			label = Data.HEROES[hk]["e"]["name"]
			Octo.burst(p, pal, 1.6, 0.25)
			Octo.flame_ring(p, 3.0, pal, 0.8)
			Vfx.dust_ring(p, 1.2)
			Sfx.play("boom", -5.0, 1.2)
		"blink":
			var to := Vector3(ev[5], 0, ev[6])
			Octo.charge(p + Vector3(0, 0.8, 0), Fx.ALLY["ultra"], 0.1, 1.2)
			Octo.lightning(p + Vector3(0, 0.8, 0), to + Vector3(0, 0.8, 0), Fx.ALLY["ultra"], 8, 0.2)
			Octo.burst(to, Fx.ALLY["ultra"], 1.0)
			Octo.decal(to, "rune", Fx.ALLY["ultra"], 1.5, 0.8, 3.0)
			Sfx.play("pop", -5.0, 1.6)
		"axe":
			label = Data.HEROES[hk]["e"]["name"]
			Octo.axe(p, Vector3(ev[5], 0, ev[6]), hn, 0.9, pal)
			Sfx.play("whoosh", -4.0, 0.9)
		"leap":
			label = Data.HEROES[hk]["space"]["name"]
			Octo.charge(p + Vector3(0, 0.5, 0), pal, 0.15, 1.2)
			Vfx.dust_ring(p, 1.0)
			Sfx.play("whoosh", -5.0, 0.7)
		"whirl":
			label = Data.HEROES[hk]["q"]["name"]
			var z := Vfx.zone_ring(Vector3.ZERO, 2.2, Color(1.6, 1.0, 0.5), 2.5, true)
			z.reparent(hn, false)
			z.position = Vector3(0, 0.05, 0)
			for i in 14:
				get_tree().create_timer(i * 0.18).timeout.connect(func():
					if is_instance_valid(hn):
						Octo.slash(hn.position + Vector3(0, 0.6, 0), i * 1.9, pal, 2.1, 300.0, 0.55, 0.2))
		"heal":
			label = Data.HEROES[hk]["q"]["name"]
			Octo.decal(p, "rune", PAL_HEAL, 4.8, 1.2, 1.2)
			Octo.charge(p + Vector3(0, 1.0, 0), PAL_HEAL, 0.15, 2.0)
			Octo.shards(p, PAL_HEAL, 10, 4.2, 0.9)
			Octo.plus_rise(p, PAL_HEAL[0], 10, 3.0)
			Sfx.play("chime", -4.0, 1.4)
		"sanct":
			label = Data.HEROES[hk]["e"]["name"]
			Vfx.zone_ring(p, 3.5, Color(1.6, 1.4, 0.5), 5.0, true)
			Octo.decal(p, "rune", pal, 3.5, 1.4, 0.6)
			Octo.shards(p, pal, 12, 3.4, 1.2)
			for i in 9:
				get_tree().create_timer(0.5 + i * 0.5).timeout.connect(func():
					Vfx.sparks(p + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2)), pal[0], 6, 2.0, 0.8, "star5", 0.14, 2.0, Vector3.UP, 20.0))
			Sfx.play("chime", -5.0, 0.8)
		"lightdash":
			label = Data.HEROES[hk]["space"]["name"]
			Octo.dash_trail(p, Vector3(ev[5], 0, ev[6]), pal)
			Octo.streak(p + Vector3(0, 0.8, 0), Vector3(ev[5], 0.8, ev[6]), Octo._hdr(pal[0], 2.0), 0.3, 0.35)
			Octo.plus_rise(Vector3(ev[5], 0, ev[6]), PAL_HEAL[0], 4, 0.5)
			Sfx.play("chime", -6.0, 1.6)
	if label != "" and near:
		hud.callout(p + Vector3(0, 2.8, 0), label + "!", col.lightened(0.3))
