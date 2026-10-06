class_name Arena
extends Node3D
## "Ruined cat arena" dressing for the crossroads map (reference: stylized hand-painted
## cat-arena environment). Dusky navy surroundings, glowing lime grass along the lanes,
## cracked sandstone slab roads, pale broken flagstones, a cat-idol temple in place of the
## castle, and ruins / purple mushrooms / clay pots / black cat statues clustered by the roads.
## Purely visual: gameplay positions all come from MapDef.
## Static geometry is baked into a few chunked meshes (colour + face tone in vertex colours).

const LIME := Color("8fd12c")
const LIME_HI := Color("c8e64a")
const LIME_GLOW := Color("e2f76a")
const LIME_EDGE := Color("3f9322")
const DIRT := Color("b2a85c")
const MID := Color("4c9634")
const DEEP := Color("27542a")
const SAND := [Color("fce8c0"), Color("f7deae"), Color("fdeed0"), Color("f2d4a0")]
const FLAG := [Color("dbe8c6"), Color("cfe0b8"), Color("e4ecd2"), Color("c6dbaa")]
const STONE := Color("e4e8cc")
const LEAF := [Color("23603f"), Color("2c7048"), Color("1c5235"), Color("2f6a3a")]
const ROCK := Color("b9c4d6")
const BRICK := Color("7d4c3c")
const PURPLE := Color("a8409a")
const CLAY := Color("d77a3c")
const CAT_BLACK := Color("3a3550")
const CAT_EYE := Color("62f0ff")
const CHUNK := 24.0
const EXT := 50.0            # ground texture covers [-EXT, EXT]^2

var map: MapDef
var cam: Camera3D
var rng := RandomNumberGenerator.new()
var spot_nodes := {}
var pool: OmniLight3D
var _chunks := {}
var _prims := {}
var _g := Transform3D.IDENTITY     # current group transform for prop helpers
var _eye_mats: Array[StandardMaterial3D] = []
var _taken: Array[Vector3] = []    # x, z, radius of placed vignettes
var _t := 0.0
var _tree_x := []
var _tree_c := []
var _tuft_x := []
var _tuft_c := []

# ================================================================ mesh building
## Flat-shaded triangle soup; enforces Godot's clockwise front faces from the given normal.
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv_rect := Rect2(-50.0, -50.0, 100.0, 100.0)   # matches EXT

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		if (b - a).cross(d - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
		for p: Vector3 in [a, b, d]:
			v.append(p)
			n.append(nrm)
			c.append(col)
			uv.append(Vector2((p.x - uv_rect.position.x) / uv_rect.size.x, (p.z - uv_rect.position.y) / uv_rect.size.y))

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nrm: Vector3, col: Color) -> void:
		tri(a, b, d, nrm, col)
		tri(a, d, e, nrm, col)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func _shade(c: Color, t: float) -> Color:
	return Color(c.r * t, c.g * t, c.b * t)

func _chunk(p: Vector3) -> MB:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = MB.new()
	return _chunks[key]

## Unit primitive, flattened: [verts, normals] in clockwise order.
func _prim(kind: String, a := 0.0, seg := 12) -> Array:
	var key := "%s%.2f_%d" % [kind, a, seg]
	if _prims.has(key):
		return _prims[key]
	var src: PrimitiveMesh
	match kind:
		"box":
			src = BoxMesh.new()
		"ball":
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = seg
			s.rings = maxi(3, seg / 2)
			src = s
		"cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = a
			cm.bottom_radius = 1.0
			cm.height = 1.0
			cm.radial_segments = seg
			cm.rings = 1
			src = cm
		"torus":
			var tm := TorusMesh.new()
			tm.inner_radius = a
			tm.outer_radius = 1.0
			tm.rings = seg
			tm.ring_segments = 6
			src = tm
	var arr := src.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := idx.size() if idx.size() > 0 else vs.size()
	var mb := MB.new()
	for t in range(0, count, 3):
		var i0 := idx[t] if idx.size() > 0 else t
		var i1 := idx[t + 1] if idx.size() > 0 else t + 1
		var i2 := idx[t + 2] if idx.size() > 0 else t + 2
		var fn := (vs[i1] - vs[i0]).cross(vs[i2] - vs[i0])
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		if fn.dot(ns[i0] + ns[i1] + ns[i2]) < 0.0:
			fn = -fn
		mb.tri(vs[i0], vs[i1], vs[i2], fn, Color.WHITE)
	var out := [mb.v, mb.n]
	_prims[key] = out
	return out

## Bake a transformed primitive into the chunk mesh, toning faces by how much they face the sky.
func _put(prim: Array, col: Color, xf: Transform3D) -> void:
	var mb := _chunk(xf.origin)
	var vs: PackedVector3Array = prim[0]
	var ns: PackedVector3Array = prim[1]
	var nb := xf.basis.inverse().transposed()
	for i in vs.size():
		var nn := (nb * ns[i]).normalized()
		mb.v.append(xf * vs[i])
		mb.n.append(nn)
		mb.c.append(_shade(col, lerpf(0.68, 1.0, nn.y * 0.5 + 0.5)))
		mb.uv.append(Vector2.ZERO)

func _at(pos: Vector3, yaw := 0.0) -> void:
	_g = Transform3D(Basis(Vector3.UP, yaw), pos)

func _box(size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO) -> void:
	_put(_prim("box"), col, _g * Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos))

func _ball(r: float, col: Color, pos: Vector3, scl := Vector3.ONE, seg := 10, rot := Vector3.ZERO) -> void:
	_put(_prim("ball", 0.0, seg), col, _g * Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl * r), pos))

func _cyl(rt: float, rb: float, h: float, col: Color, pos: Vector3, rot := Vector3.ZERO, seg := 12) -> void:
	_put(_prim("cyl", snappedf(rt / rb, 0.05), seg), col, _g * Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(rb, h, rb)), pos))

func _torus(r_in: float, r_out: float, col: Color, pos: Vector3, scl := Vector3.ONE) -> void:
	_put(_prim("torus", snappedf(r_in / r_out, 0.05), 14), col, _g * Transform3D(Basis.from_scale(scl * r_out), pos))

func _eye(pos: Vector3, r: float, scl := Vector3.ONE, col := CAT_EYE, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	var m := Mats.emissive(col, 2.4)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eye_mats.append(m)
	(parent if parent else self).add_child(mi)
	var xf := Transform3D(Basis.from_scale(scl), pos)
	mi.transform = xf if parent else _g * xf

## Extruded polygon (xz) with a bevelled top edge: every slab, flagstone and ring segment.
func _prism(mb: MB, poly: PackedVector2Array, y0: float, y1: float, bevel: float, col: Color) -> void:
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= poly.size()
	var inner := PackedVector2Array()
	for p in poly:
		var to_c := cen - p
		inner.append(p + to_c.normalized() * minf(bevel, to_c.length() * 0.4))
	var yb := y1 - bevel * 0.8
	var k := poly.size()
	var cy := Vector3(cen.x, y1, cen.y)
	for i in k:
		var j := (i + 1) % k
		var a := inner[i]
		var b := inner[j]
		mb.tri(cy, Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3.UP, col)
		var oa := poly[i]
		var ob := poly[j]
		var edge := ob - oa
		var out := Vector2(edge.y, -edge.x).normalized()
		if out.dot((oa + ob) * 0.5 - cen) < 0.0:
			out = -out
		var out3 := Vector3(out.x, 0, out.y)
		if bevel > 0.0:
			mb.quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(ob.x, yb, ob.y), Vector3(oa.x, yb, oa.y),
				(out3 + Vector3.UP * 1.2).normalized(), _shade(col, 0.88))
		mb.quad(Vector3(oa.x, yb, oa.y), Vector3(ob.x, yb, ob.y), Vector3(ob.x, y0, ob.y), Vector3(oa.x, y0, oa.y),
			out3, _shade(col, 0.66))

func _slab(poly: PackedVector2Array, y0: float, y1: float, bevel: float, col: Color, mb: MB = null) -> void:
	_prism(mb if mb else _chunk(Vector3(poly[0].x, 0, poly[0].y)), poly, y0, y1, bevel, col)

static func _shrink(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (cen - p).normalized() * d)
	return out

func _stone_poly(center: Vector2, size: float, sides := 5) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var start := rng.randf() * TAU
	for i in sides:
		var a := start + TAU * (i + rng.randf_range(-0.22, 0.22)) / sides
		poly.append(center + Vector2(cos(a), sin(a)) * size * rng.randf_range(0.7, 1.0))
	return poly

static func _arc_poly(c: Vector2, r0: float, r1: float, a0: float, a1: float, steps := 4) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		poly.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in steps + 1:
		var a := lerpf(a1, a0, float(i) / steps)
		poly.append(c + Vector2(cos(a), sin(a)) * r0)
	return poly

func _pick(arr: Array) -> Color:
	return arr[rng.randi() % arr.size()]

static func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)

# ================================================================ build
func build(p_map: MapDef, p_cam: Camera3D) -> void:
	map = p_map
	cam = p_cam
	rng.seed = 1234
	_env()
	_ground()
	_roads()
	_plaza()
	_temple()
	_spawns()
	_spots()
	_flagstones()
	_props()
	_trees_and_tufts()
	_commit()

func _commit() -> void:
	var mat := Mats.painted()
	for key in _chunks:
		var mb: MB = _chunks[key]
		if mb.v.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mb.mesh()
		mi.material_override = mat
		add_child(mi)
	_chunks.clear()

func _env() -> void:
	var we := WorldEnvironment.new()
	we.environment = Look.arena_environment()
	add_child(we)
	add_child(Look.arena_sun())
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("8fa6ff")
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(10, 6, 12), Vector3.ZERO, Vector3.UP)
	# a soft pool of light that follows the camera focus: the play area is the bright "court"
	pool = OmniLight3D.new()
	pool.light_color = Color("f2ffd0")
	pool.light_energy = 1.1
	pool.omni_range = 15.0
	pool.omni_attenuation = 1.3
	pool.shadow_enabled = false
	add_child(pool)
	# screen vignette sinks the edges into the night like the reference render
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	var gr := Gradient.new()
	gr.set_color(0, Color(0.07, 0.09, 0.16, 0.0))
	gr.set_color(1, Color(0.07, 0.09, 0.16, 0.62))
	gr.add_point(0.55, Color(0.07, 0.09, 0.16, 0.0))
	gt.gradient = gr
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vig)

func _process(delta: float) -> void:
	_t += delta
	if cam and pool:
		var f: Vector3 = cam.get("focus") if cam.get("focus") != null else Vector3.ZERO
		pool.position = f + Vector3(0, 6.5, 0)
	var e := 2.1 + 0.6 * sin(_t * 1.7)
	for m in _eye_mats:
		m.emission_energy_multiplier = e

# ================================================================ ground
## Distance from the nearest paved edge (road, plaza or build pad).
func _edge_dist(p: Vector2) -> float:
	var e := map.dist_to_any_road(p) - MapDef.ROAD_W * 0.5
	e = minf(e, p.length() - (MapDef.HORN_R + 0.45))
	for sp in map.spots:
		e = minf(e, p.distance_to(sp["pos"]) - 1.55)
	return e

func _ground() -> void:
	var mb := MB.new()
	var E := 70.0
	mb.quad(Vector3(-E, 0, -E), Vector3(E, 0, -E), Vector3(E, 0, E), Vector3(-E, 0, E), Vector3.UP, Color.WHITE)
	var tex := _ground_texture()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.26
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.texture_repeat = false
	var mi := MeshInstance3D.new()
	mi.mesh = mb.mesh()
	mi.material_override = m
	add_child(mi)
	# boxy terrain rim far outside the play area, sunk into the night
	for i in 34:
		var a := TAU * i / 34.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(44.0, 50.0)
		var p := Vector2(cos(a), sin(a)) * r
		var sz := Vector3(rng.randf_range(6, 11), rng.randf_range(1.0, 3.5), rng.randf_range(6, 11))
		_at(_v3(p), -a)
		_box(sz, Color("4a3426"), Vector3(0, sz.y * 0.5 - 0.1, 0))
		_box(Vector3(sz.x + 0.3, 0.3, sz.z + 0.3), DEEP, Vector3(0, sz.y, 0))
	_g = Transform3D.IDENTITY

## Hand-painted grass: lime that glows along the paths (with yellow drifts and olive dirt
## strokes), a deep-green lip tucked against every paved edge, fading to dark forest green.
func _ground_texture() -> ImageTexture:
	var N := 512
	var ppu := N / (EXT * 2.0)
	var GRID := 128
	var dimg := Image.create(GRID, GRID, false, Image.FORMAT_L8)
	for y in GRID:
		for x in GRID:
			var p := Vector2(-EXT + (x + 0.5) * EXT * 2.0 / GRID, -EXT + (y + 0.5) * EXT * 2.0 / GRID)
			var v := clampf((_edge_dist(p) + 1.0) / 21.0, 0.0, 1.0)
			dimg.set_pixel(x, y, Color(v, v, v))
	dimg.resize(N, N, Image.INTERPOLATE_BILINEAR)
	var dd := dimg.get_data()
	var mk := func(seed_v: int, freq_world: float, oct: int) -> PackedByteArray:
		var n := FastNoiseLite.new()
		n.seed = seed_v
		n.frequency = freq_world / ppu
		n.fractal_octaves = oct
		var im := n.get_image(N, N)
		im.convert(Image.FORMAT_L8)
		return im.get_data()
	var n1: PackedByteArray = mk.call(4, 0.09, 3)
	var n2: PackedByteArray = mk.call(9, 0.16, 4)
	var n3: PackedByteArray = mk.call(21, 0.9, 2)
	var out := PackedByteArray()
	out.resize(N * N * 3)
	for i in N * N:
		var e := dd[i] / 255.0 * 21.0 - 1.0
		var a := n1[i] / 255.0
		var d := n2[i] / 255.0
		var f := n3[i] / 255.0
		var lime := LIME.lerp(LIME_HI, smoothstep(0.42, 0.74, a))
		lime = lime.lerp(DIRT, smoothstep(0.64, 0.68, d) * 0.65)
		lime = lime.lerp(LIME_GLOW, (1.0 - smoothstep(0.6, 3.5, e)) * 0.35)
		var far := MID.lerp(DEEP, smoothstep(5.0, 15.0, e + (a - 0.5) * 6.0))
		far = far.lerp(DIRT.darkened(0.45), smoothstep(0.66, 0.7, d) * 0.4)
		var col := far.lerp(lime, 1.0 - smoothstep(2.5, 8.0, e + (d - 0.5) * 3.0))
		col = col.lerp(LIME_HI if f > 0.5 else LIME_EDGE, absf(f - 0.5) * 0.3)
		col = col.lerp(LIME_EDGE, (1.0 - smoothstep(0.0, 0.7, e)) * 0.7)
		out[i * 3] = int(clampf(col.r, 0.0, 1.0) * 255.0)
		out[i * 3 + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
		out[i * 3 + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGB8, out)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ================================================================ sandstone roads
const ROAD_TOP := 0.09

func _roads() -> void:
	var W := MapDef.ROAD_W
	for k in 4:
		var pts: PackedVector2Array = map.lanes[k]
		for i in range(1, pts.size()):
			_road_strip(pts[i - 1], pts[i], W)
		for i in pts.size():
			if pts[i].length() < MapDef.HORN_R:
				continue    # the plaza covers the castle end
			_rosette(pts[i], W * 0.5 + 0.25, ROAD_TOP + 0.012)
		# a few chips and cracked corners lying on the road
		for i in 8:
			var d := rng.randf_range(3.0, map.length(k) - 6.0)
			var t := map.dir_at(k, d)
			var p := map.pos_at(k, d) + Vector2(-t.y, t.x) * rng.randf_range(-1.0, 1.0)
			_slab(_stone_poly(p, rng.randf_range(0.08, 0.15), 4), ROAD_TOP - 0.02, ROAD_TOP + 0.045, 0.02, Color("dcb174"))

## Slabs along one straight road segment: slanted seams, split into 1-3 bands across.
func _road_strip(a: Vector2, b: Vector2, W: float) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var nrm := Vector2(-dir.y, dir.x)
	var cuts: Array[float] = []      # seam position along the road
	var slant: Array[float] = []     # seam skew (left edge vs right edge)
	var s := 0.0
	while s < L:
		cuts.append(s)
		slant.append(rng.randf_range(-0.22, 0.22) if s > 0.0 else 0.0)
		s += rng.randf_range(1.0, 1.6)
	cuts.append(L)
	slant.append(0.0)
	for i in cuts.size() - 1:
		var r := rng.randf()
		var bands: Array = [-0.5, 0.5]
		if r < 0.45:
			bands = [-0.5, rng.randf_range(-0.15, 0.15), 0.5]
		elif r < 0.6:
			bands = [-0.5, -0.17 + rng.randf_range(-0.05, 0.05), 0.17 + rng.randf_range(-0.05, 0.05), 0.5]
		for j in bands.size() - 1:
			var w0: float = bands[j]
			var w1: float = bands[j + 1]
			var s00: float = cuts[i] + slant[i] * w0 * 2.0
			var s01: float = cuts[i] + slant[i] * w1 * 2.0
			var s10: float = cuts[i + 1] + slant[i + 1] * w0 * 2.0
			var s11: float = cuts[i + 1] + slant[i + 1] * w1 * 2.0
			var poly := PackedVector2Array([
				a + dir * s00 + nrm * w0 * W, a + dir * s10 + nrm * w0 * W,
				a + dir * s11 + nrm * w1 * W, a + dir * s01 + nrm * w1 * W])
			_slab(_shrink(poly, 0.03), -0.06, ROAD_TOP + rng.randf_range(-0.012, 0.015), 0.04, _pick(SAND))

## Round joint: a centre slab ringed by sector slabs (gives the rounded walkway corners).
func _rosette(c: Vector2, R: float, top: float, sectors := 6) -> void:
	var inner := PackedVector2Array()
	for i in 8:
		inner.append(c + Vector2.from_angle(TAU * i / 8.0) * R * 0.38)
	_slab(_shrink(inner, 0.03), -0.06, top, 0.04, _pick(SAND))
	var off := rng.randf() * TAU
	for i in sectors:
		var a0 := off + TAU * i / sectors
		var a1 := off + TAU * (i + 1) / sectors
		_slab(_shrink(_arc_poly(c, R * 0.38, R, a0, a1, 3), 0.03), -0.06, top + rng.randf_range(-0.01, 0.01), 0.04, _pick(SAND))

# ================================================================ plaza + temple
func _plaza() -> void:
	var rings := [[3.4, 4.7, 12], [4.7, 6.0, 16], [6.0, MapDef.HORN_R + 0.2, 20]]
	for rg in rings:
		var off := rng.randf() * TAU
		var n: int = rg[2]
		for i in n:
			var a0 := off + TAU * i / n
			var a1 := off + TAU * (i + 1) / n
			_slab(_shrink(_arc_poly(Vector2.ZERO, rg[0], rg[1], a0, a1, 3), 0.035), -0.06, 0.12 + rng.randf_range(-0.012, 0.012), 0.045, _pick(SAND))
	# pale seal ring, broken open where each lane arrives
	var r0 := MapDef.HORN_R + 0.2
	var segs := 28
	for i in segs:
		var a0 := TAU * i / segs + 0.02
		var a1 := TAU * (i + 1) / segs - 0.02
		var mid := (a0 + a1) * 0.5
		var gate := false
		for k in 4:
			var ang := MapDef.rot(Vector2(0, -1), k).angle()
			if absf(angle_difference(mid, ang)) < 0.22:
				gate = true
		if gate:
			continue
		_slab(_arc_poly(Vector2.ZERO, r0, r0 + 0.5, a0, a1, 3), -0.06, 0.2 + rng.randf_range(-0.015, 0.02), 0.05, STONE.darkened(rng.randf_range(0.0, 0.08)))

func _temple() -> void:
	# stepped sandstone dais
	for st in [[3.5, 0.32, 0], [2.7, 0.62, 1]]:
		var poly := PackedVector2Array()
		for i in 8:
			poly.append(Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * st[0])
		_slab(poly, 0.0, st[1], 0.06, SAND[st[2]])
	# four columns carry the lane owners' banners
	var r := MapDef.CASTLE_R - 1.0
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		_column(p, 3.1, false)
		_at(p)
		_cyl(0.03, 0.03, 1.0, Color("6b4a2f"), Vector3(0, 4.25, 0), Vector3.ZERO, 6)
		_box(Vector3(0.7, 0.42, 0.04), Data.PLAYER_COLORS[i], Vector3(0.36, 4.5, 0))
		_g = Transform3D.IDENTITY
	# low ruined walls between the columns, open toward each lane
	for i in 4:
		var a := TAU * i / 4.0
		for sd in [-1.0, 1.0]:
			var mid_a: float = a + sd * 0.48
			var p := Vector2.from_angle(mid_a) * r * 0.86
			_stone_wall_at(p, mid_a + PI * 0.5, 1.5, 0.75)
	# the cat idol
	_at(Vector3(0, 0.62, 0))
	_cyl(1.25, 1.4, 0.4, STONE.darkened(0.1), Vector3(0, 0.2, 0), Vector3.ZERO, 16)
	var face := Color("d9dec6")
	_ball(1.0, face, Vector3(0, 1.1, -0.15), Vector3(1.0, 0.9, 0.95), 14)
	for sx in [-1.0, 1.0]:
		_ball(0.32, face, Vector3(0.55 * sx, 0.55, 0.65), Vector3(1, 0.6, 1.3), 10)
	_cyl(0.18, 0.28, 1.6, face, Vector3(-0.9, 0.7, -0.6), Vector3(1.0, 0, 0.6), 8)
	var hy := 2.25
	_ball(1.05, face, Vector3(0, hy, 0.15), Vector3(1.12, 0.86, 0.95), 16)
	for sx in [-1.0, 1.0]:
		_cyl(0.0, 0.42, 0.8, face, Vector3(0.68 * sx, hy + 0.85, 0.0), Vector3(0, 0, -0.35 * sx), 4)
		_cyl(0.0, 0.25, 0.5, Color("c8a7b8"), Vector3(0.66 * sx, hy + 0.8, 0.12), Vector3(0, 0, -0.35 * sx), 4)
		_eye(Vector3(0.42 * sx, hy + 0.08, 1.02), 0.3, Vector3(1, 1.05, 0.45))
		_box(Vector3(0.06, 0.38, 0.06), Color("10202a"), Vector3(0.42 * sx, hy + 0.08, 1.14))
		for w in 3:
			_box(Vector3(0.5, 0.025, 0.025), Color("8f9480"), Vector3(0.85 * sx, hy - 0.25 + w * 0.09, 0.95), Vector3(0, 0, 0.12 * (w - 1) * sx))
	_ball(0.1, Color("c8a7b8"), Vector3(0, hy - 0.18, 1.12), Vector3(1.3, 0.8, 0.8), 8)
	_g = Transform3D.IDENTITY
	# war horn on a stump (call next wave)
	_at(Vector3(0, 0.12, MapDef.CASTLE_R + 0.2))
	_cyl(0.3, 0.38, 0.6, Color("6e4224"), Vector3(0, 0.3, 0), Vector3.ZERO, 10)
	_cyl(0.06, 0.32, 1.2, Color("ffd23f"), Vector3(0.2, 0.95, 0), Vector3(0, 0, 1.2), 12)
	_g = Transform3D.IDENTITY

# ================================================================ enemy spawn caves
func _spawns() -> void:
	for k in 4:
		var p := map.spawn_pos(k)
		var dir := (map.pos_at(k, 2.0) - p).normalized()
		var root_pos := _v3(p - dir * 1.0)
		var yaw := atan2(dir.x, dir.y)
		_at(root_pos, yaw)
		var boulders := [[0.0, -2.2, 3.2, 2.4], [-2.8, -1.6, 2.2, 1.8], [2.8, -1.6, 2.3, 1.9], [-1.6, -3.6, 2.4, 2.6],
			[1.8, -3.8, 2.5, 2.8], [0.0, -4.6, 2.6, 3.4], [-4.3, -0.6, 1.4, 1.1], [4.3, -0.7, 1.5, 1.2]]
		for b in boulders:
			var c := ROCK.lerp(Color("9aa6bd"), rng.randf())
			_ball(1.0, c, Vector3(b[0], b[3] * 0.45, b[1]), Vector3(b[2], b[3] * 0.75, b[2]), 7, Vector3(0, rng.randf() * TAU, 0))
		_ball(2.6, MID, Vector3(0, 3.0, -3.6), Vector3(1.2, 0.35, 1.0), 9)
		for j in 3:
			_tree_local(Vector3(-1.4 + j * 1.4, 3.1, -3.8 + rng.randf_range(-0.4, 0.4)), 1.0)
		_box(Vector3(4.0, 0.3, 1.2), Color("2a2238"), Vector3(0, 0.05, 0.3))
		# banners on broken columns either side of the cave
		for sx in [-1.0, 1.0]:
			_column(_g * Vector3(sx * 2.7, 0, 1.4), 1.7, sx > 0.0)
			_at(root_pos, yaw)
			_cyl(0.03, 0.03, 1.2, Color("6b4a2f"), Vector3(sx * 2.7, 2.6, 1.4), Vector3.ZERO, 6)
			_box(Vector3(0.8, 0.9, 0.05), Data.PLAYER_COLORS[k], Vector3(sx * 2.7 + 0.42, 2.7, 1.4))
		var root := Node3D.new()
		add_child(root)
		root.position = root_pos
		root.rotation.y = yaw
		var mouth := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.7
		cm.bottom_radius = 1.7
		cm.height = 0.2
		mouth.mesh = cm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color("120d1e")
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mouth.material_override = mm
		mouth.rotation.x = PI * 0.5
		mouth.position = Vector3(0, 0.2, -0.05)
		mouth.scale = Vector3(1.0, 1.0, 1.25)
		root.add_child(mouth)
		for sx2 in [-0.45, 0.45]:
			_eye(Vector3(sx2, 1.1, 0.05), 0.12, Vector3(1, 0.75, 1), Color(1.0, 0.82, 0.3), root)
		_g = Transform3D.IDENTITY

# ================================================================ build pads
func _spots() -> void:
	for sp in map.spots:
		var n := Node3D.new()
		add_child(n)
		var c: Vector2 = sp["pos"]
		n.position = _v3(c)
		var mb := MB.new()
		# sandstone disc + sector ring, pale stone rim with gaps (a mini seal ring)
		var inner := PackedVector2Array()
		for i in 8:
			inner.append(Vector2.from_angle(TAU * i / 8.0) * 0.5)
		_prism(mb, _shrink(inner, 0.03), -0.06, 0.11, 0.04, _pick(SAND))
		var off := rng.randf() * TAU
		for i in 6:
			_prism(mb, _shrink(_arc_poly(Vector2.ZERO, 0.5, MapDef.SPOT_R, off + TAU * i / 6.0, off + TAU * (i + 1) / 6.0, 3), 0.03),
				-0.06, 0.1 + rng.randf_range(-0.01, 0.01), 0.04, _pick(SAND))
		for i in 8:
			_prism(mb, _arc_poly(Vector2.ZERO, MapDef.SPOT_R + 0.04, MapDef.SPOT_R + 0.3, off + TAU * i / 8.0 + 0.06, off + TAU * (i + 1) / 8.0 - 0.06, 3),
				-0.06, 0.16, 0.04, STONE.darkened(rng.randf_range(0.0, 0.08)))
		var mi := MeshInstance3D.new()
		mi.mesh = mb.mesh()
		mi.material_override = Mats.painted()
		n.add_child(mi)
		# lane-coloured sign post
		var post := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.04
		pc.bottom_radius = 0.04
		pc.height = 0.8
		post.mesh = pc
		post.material_override = Mats.prop(Color("6b4a2f"))
		post.position = Vector3(0.5, 0.45, -0.4)
		n.add_child(post)
		var sign := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.45, 0.32, 0.04)
		sign.mesh = sb
		sign.material_override = Mats.prop(Color("fff1d6"))
		sign.position = Vector3(0.5, 0.82, -0.4)
		sign.rotation.y = 0.3
		n.add_child(sign)
		var tag := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.18, 0.12, 0.05)
		tag.mesh = tb
		tag.material_override = Mats.prop(Data.PLAYER_COLORS[sp["lane"]])
		tag.position = Vector3(0.5, 0.82, -0.38)
		tag.rotation.y = 0.3
		n.add_child(tag)
		spot_nodes[sp["id"]] = n

# ================================================================ placement rules
func _free(p: Vector2, r: float, road_gap := 0.6) -> bool:
	if p.length() < MapDef.HORN_R + 1.4 + r:
		return false
	if absf(p.x) > 42.0 or absf(p.y) > 42.0:
		return false
	if map.dist_to_any_road(p) < MapDef.ROAD_W * 0.5 + road_gap + r:
		return false
	for sp in map.spots:
		if p.distance_to(sp["pos"]) < MapDef.SPOT_R + 0.9 + r:
			return false
	for k in 4:
		if p.distance_to(map.spawn_pos(k)) < 7.0 + r:
			return false
	for q in _taken:
		if Vector2(q.x, q.y).distance_to(p) < q.z + r:
			return false
	return true

## Random point beside a random lane, `e` units off the paved edge.
func _beside_road(e_min: float, e_max: float) -> Array:
	var k := rng.randi() % 4
	var d := rng.randf_range(4.0, map.length(k) - 3.0)
	var t := map.dir_at(k, d)
	var nrm := Vector2(-t.y, t.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var p := map.pos_at(k, d) + nrm * (MapDef.ROAD_W * 0.5 + rng.randf_range(e_min, e_max))
	return [p, t, nrm]

# ================================================================ broken flagstones on the grass
func _flagstones() -> void:
	var tries := 0
	var placed := 0
	while placed < 110 and tries < 3000:
		tries += 1
		var big := rng.randf() < 0.4
		var r := rng.randf_range(0.6, 1.15) if big else rng.randf_range(0.25, 0.45)
		var b := _beside_road(0.15, 4.5)
		var p: Vector2 = b[0]
		if not _free(p, r, 0.05):
			continue
		_taken.append(Vector3(p.x, p.y, r + 0.1))
		_slab(_stone_poly(p, r, 5 if big else 4), -0.03, 0.035, 0.03, _pick(FLAG))
		if big and rng.randf() < 0.55:
			var dir := Vector2.from_angle(rng.randf() * TAU)
			_slab(_stone_poly(p + dir * (r + 0.14), r * 0.35, 4), -0.03, 0.03, 0.02, _pick(FLAG))
		placed += 1
	# broken arcs around the plaza, echoing the reference's outer ring
	for i in 10:
		var a0 := rng.randf() * TAU
		var r0 := MapDef.HORN_R + rng.randf_range(1.1, 1.6)
		var poly := _arc_poly(Vector2.ZERO, r0, r0 + rng.randf_range(0.35, 0.55), a0, a0 + rng.randf_range(0.12, 0.22), 3)
		var c := (poly[0] + poly[poly.size() - 1]) * 0.5
		if map.dist_to_any_road(c) < MapDef.ROAD_W * 0.5 + 0.6:
			continue
		_slab(poly, -0.03, 0.04, 0.025, _pick(FLAG))
	# flagstones are flat: props may sit on top of them
	_taken.clear()

# ================================================================ props
func _props() -> void:
	var kinds := ["pillars", "pillars", "mushrooms", "mushrooms", "mushrooms", "pot", "wall", "wall",
		"cat", "rocks", "rocks", "logs", "pot"]
	var tries := 0
	var placed := 0
	while placed < 64 and tries < 4000:
		tries += 1
		var kind: String = kinds[rng.randi() % kinds.size()]
		var r := 1.6 if kind in ["pillars", "wall"] else 1.0
		var b := _beside_road(0.9 + r * 0.5, 3.8)
		var p: Vector2 = b[0]
		if not _free(p, r, 0.3):
			continue
		_taken.append(Vector3(p.x, p.y, r + 1.4))
		var t: Vector2 = b[1]
		var nrm: Vector2 = b[2]
		var along := atan2(-t.y, t.x)      # yaw that lines a prop's local +x up with the road
		var face := atan2(-nrm.x, -nrm.y)  # yaw that turns a prop's local +z toward the road
		match kind:
			"pillars":
				_column(_v3(p), rng.randf_range(1.8, 2.6), false)
				var p2 := p + t * rng.randf_range(0.9, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0) + nrm * 0.4
				_column(_v3(p2), rng.randf_range(0.35, 0.7), true)
				_fallen_drum(_v3(p - t * 1.0 - nrm * 0.3), along + rng.randf_range(-0.6, 0.6))
				if rng.randf() < 0.6:
					_mushroom(_v3(p + t * 0.6 - nrm * 0.6), rng.randf_range(0.9, 1.3))
			"mushrooms":
				for i in rng.randi_range(2, 4):
					var o := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
					_mushroom(_v3(p + o), rng.randf_range(0.7, 1.5) * (1.4 if i == 0 else 1.0))
				for i in 3:
					_tuft(p + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)), true)
			"pot":
				_pot(_v3(p), rng.randf_range(1.0, 1.35), _v3(nrm * -0.6 + t * rng.randf_range(-0.3, 0.3)))
				_rock(_v3(p - nrm * 0.7 + t * 0.5), 0.6)
				if rng.randf() < 0.5:
					_pot(_v3(p + t * 0.75 - nrm * 0.35), 0.65, Vector3.ZERO)
			"wall":
				var length := rng.randf_range(2.2, 3.4)
				_stone_wall_at(p - nrm * 0.3, along, length, rng.randf_range(0.55, 0.75))
				if rng.randf() < 0.6:
					_shelf_items(_v3(p - nrm * 0.3 - t * (length * 0.3), 0.6), t)
				else:
					_mushroom(_v3(p + t * (length * 0.5 + 0.3)), 1.1)
			"cat":
				_cat_statue(_v3(p), rng.randf_range(0.9, 1.1), face)
				_log_disc(_v3(p + t * 0.9 + nrm * 0.2), along + 0.4, true)
			"rocks":
				_rock(_v3(p), rng.randf_range(1.0, 1.6))
				_rock(_v3(p + t * 0.8 + nrm * 0.3), rng.randf_range(0.5, 0.8))
				if rng.randf() < 0.4:
					_rock(_v3(p - t * 0.7), 0.9, Color("d38d3c"))
			"logs":
				_log_disc(_v3(p), along, true)
				_log_disc(_v3(p + t * 0.45), along + 0.2, true)
				_log_disc(_v3(p - nrm * 0.5), 0.0, false)
		placed += 1
	_g = Transform3D.IDENTITY

func _column(p: Vector3, h: float, broken: bool) -> void:
	_at(p, rng.randf() * 0.5)
	var col := Color("f1d39a")
	_box(Vector3(0.7, 0.16, 0.7), col.darkened(0.08), Vector3(0, 0.08, 0))
	_box(Vector3(0.58, 0.1, 0.58), col, Vector3(0, 0.21, 0))
	_cyl(0.24, 0.27, 0.08, col, Vector3(0, 0.3, 0), Vector3.ZERO, 14)
	_cyl(0.22, 0.24, h, col, Vector3(0, 0.34 + h * 0.5, 0), Vector3.ZERO, 14)
	if broken:
		_cyl(0.17, 0.21, 0.14, col.darkened(0.05), Vector3(0.03, 0.4 + h, 0), Vector3(0.35, 0, 0.25), 7)
	else:
		_cyl(0.3, 0.22, 0.1, col, Vector3(0, 0.39 + h, 0), Vector3.ZERO, 14)
		_box(Vector3(0.66, 0.12, 0.66), col, Vector3(0, 0.5 + h, 0))
		_box(Vector3(0.58, 0.05, 0.58), col.lightened(0.08), Vector3(0, 0.585 + h, 0))
	_g = Transform3D.IDENTITY

func _fallen_drum(p: Vector3, yaw: float) -> void:
	_at(p, yaw)
	var col := Color("eccb8e")
	var length := rng.randf_range(0.5, 0.9)
	_cyl(0.23, 0.23, length, col, Vector3(0, 0.23, 0), Vector3(0, 0, PI * 0.5), 14)
	_cyl(0.18, 0.18, 0.02, col.darkened(0.15), Vector3(length * 0.5 + 0.005, 0.23, 0), Vector3(0, 0, PI * 0.5), 10)
	_g = Transform3D.IDENTITY

func _mushroom(p: Vector3, s: float) -> void:
	_at(p, rng.randf() * TAU)
	var tilt := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	_cyl(0.055 * s, 0.08 * s, 0.4 * s, Color("f3e6c8"), Vector3(0, 0.2 * s, 0), tilt, 8)
	var cap := PURPLE.lerp(Color("8c3590"), rng.randf())
	var cy := 0.4 * s
	_cyl(0.2 * s, 0.24 * s, 0.04 * s, Color("e7c9d8"), Vector3(0, cy, 0), Vector3.ZERO, 12)
	_ball(0.25 * s, cap, Vector3(0, cy + 0.02 * s, 0), Vector3(1, 0.55, 1), 12)
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.5
		_ball(0.04 * s, Color("ffd65a"), Vector3(cos(a) * 0.15 * s, cy + 0.1 * s, sin(a) * 0.15 * s), Vector3(1, 0.5, 1), 6)
	_ball(0.035 * s, Color("ffd65a"), Vector3(0, cy + 0.15 * s, 0), Vector3(1, 0.5, 1), 6)
	_g = Transform3D.IDENTITY

func _pot(p: Vector3, s: float, spill := Vector3.ZERO) -> void:
	_at(p, rng.randf() * TAU)
	_ball(0.28 * s, CLAY, Vector3(0, 0.26 * s, 0), Vector3(1, 0.92, 1), 14)
	_cyl(0.15 * s, 0.2 * s, 0.14 * s, CLAY.darkened(0.05), Vector3(0, 0.52 * s, 0), Vector3.ZERO, 14)
	_torus(0.13 * s, 0.21 * s, CLAY.lightened(0.08), Vector3(0, 0.6 * s, 0), Vector3(1, 0.7, 1))
	_cyl(0.13 * s, 0.13 * s, 0.01, Color("4a2414"), Vector3(0, 0.6 * s, 0), Vector3.ZERO, 12)
	_g = Transform3D.IDENTITY
	if spill == Vector3.ZERO:
		return
	var puddle := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.45 * s
	pc.bottom_radius = 0.45 * s
	pc.height = 0.01
	pc.radial_segments = 18
	puddle.mesh = pc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("4a92e8")
	wm.roughness = 0.12
	wm.metallic_specular = 0.9
	wm.emission_enabled = true
	wm.emission = Color("2c5ec0")
	wm.emission_energy_multiplier = 0.15
	puddle.material_override = wm
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.position = p + spill * s + Vector3(0, 0.015, 0)
	puddle.scale = Vector3(1.3, 1, 0.8)
	puddle.rotation.y = atan2(-spill.z, spill.x)
	add_child(puddle)

func _cat_statue(p: Vector3, s: float, yaw: float) -> void:
	_at(p, yaw)
	_box(Vector3(0.95, 0.5, 0.95), BRICK, Vector3(0, 0.25, 0))
	for i in 3:
		_box(Vector3(0.97, 0.03, 0.97), BRICK.darkened(0.3), Vector3(0, 0.1 + i * 0.14, 0))
	_box(Vector3(1.05, 0.1, 1.05), Color("bdb59f"), Vector3(0, 0.55, 0))
	var y := 0.6
	_ball(0.34 * s, CAT_BLACK, Vector3(0, y + 0.26 * s, -0.05), Vector3(1.0, 0.85, 0.95), 12)
	for sx in [-1.0, 1.0]:
		_ball(0.1 * s, CAT_BLACK, Vector3(0.18 * s * sx, y + 0.06 * s, 0.24 * s), Vector3(1, 0.6, 1.3), 8)
	_cyl(0.06 * s, 0.09 * s, 0.5 * s, CAT_BLACK, Vector3(0.3 * s, y + 0.15 * s, -0.25 * s), Vector3(1.2, 0, -0.6), 6)
	var hy := y + 0.66 * s
	_ball(0.32 * s, CAT_BLACK, Vector3(0, hy, 0.06 * s), Vector3(1.1, 0.88, 0.95), 14)
	for sx in [-1.0, 1.0]:
		_cyl(0.0, 0.13 * s, 0.24 * s, CAT_BLACK, Vector3(0.21 * s * sx, hy + 0.27 * s, 0.0), Vector3(0, 0, -0.35 * sx), 4)
		_eye(Vector3(0.13 * s * sx, hy + 0.03 * s, 0.32 * s), 0.1 * s, Vector3(1, 1.05, 0.5))
		_box(Vector3(0.02, 0.13, 0.02) * s, Color("10202a"), Vector3(0.13 * s * sx, hy + 0.03 * s, 0.37 * s))
	_g = Transform3D.IDENTITY

func _rock(p: Vector3, s: float, col := ROCK) -> void:
	_at(p, rng.randf() * TAU)
	_ball(0.32 * s, col, Vector3(0, 0.1 * s, 0), Vector3(1.25, 0.72, 1.0), 7)
	_ball(0.18 * s, col.lightened(0.06), Vector3(0.28 * s, 0.05 * s, 0.12 * s), Vector3(1.1, 0.75, 1), 6)
	_g = Transform3D.IDENTITY

func _log_disc(p: Vector3, yaw: float, standing: bool) -> void:
	_at(p, yaw)
	var rot := Vector3(PI * 0.5, 0, 0) if standing else Vector3.ZERO
	var y := 0.2 if standing else 0.04
	_cyl(0.2, 0.2, 0.08, Color("6e4224"), Vector3(0, y, 0), rot, 12)
	_cyl(0.15, 0.15, 0.09, Color("b9824a"), Vector3(0, y, 0), rot, 12)
	_g = Transform3D.IDENTITY

## Ruined wall: dark brick footing with pale stone blocks on top (the reference's left wall).
func _stone_wall_at(c: Vector2, yaw: float, length: float, h: float) -> void:
	_at(_v3(c), yaw)
	_box(Vector3(length, 0.22, 0.52), BRICK, Vector3(0, 0.11, 0))
	var x := -length * 0.5
	while x < length * 0.5 - 0.1:
		var bl := minf(rng.randf_range(0.55, 0.95), length * 0.5 - x)
		var bh := h - 0.2 + rng.randf_range(-0.05, 0.05)
		var col := Color("c9d2e0").lerp(Color("aeb9cc"), rng.randf())
		_box(Vector3(bl - 0.03, bh, 0.48), col, Vector3(x + bl * 0.5, 0.22 + bh * 0.5, rng.randf_range(-0.02, 0.02)), Vector3(0, rng.randf_range(-0.03, 0.03), 0))
		if rng.randf() < 0.15:
			_box(Vector3(bl * 0.35, 0.04, 0.2), MID.lightened(0.15), Vector3(x + bl * 0.5, 0.22 + bh + 0.02, 0))
		x += bl
	_g = Transform3D.IDENTITY

func _shelf_items(p: Vector3, along: Vector2) -> void:
	var cols := [Color("3e70d8"), Color("e07a2e"), Color("7a4fb0"), Color("3e70d8")]
	var x := 0.0
	for i in cols.size():
		var c: Color = cols[i]
		var q := p + _v3(along * x)
		_g = Transform3D(Basis.IDENTITY, q)
		if i % 2 == 0:
			_cyl(0.07, 0.07, 0.24, c, Vector3(0, 0.12, 0), Vector3.ZERO, 8)
			_cyl(0.035, 0.035, 0.08, c.lightened(0.2), Vector3(0, 0.28, 0), Vector3.ZERO, 6)
		else:
			_ball(0.13, c, Vector3(0, 0.12, 0), Vector3(1, 0.95, 1), 10)
			_cyl(0.05, 0.06, 0.06, c.darkened(0.2), Vector3(0, 0.26, 0), Vector3.ZERO, 8)
		x += rng.randf_range(0.28, 0.4)
	_g = Transform3D.IDENTITY

## Tree inside the current group transform (used on the cave hills).
func _tree_local(p: Vector3, s: float) -> void:
	var g := _pick(LEAF)
	_cyl(0.1 * s, 0.15 * s, 0.9 * s, Color("4a3426"), p + Vector3(0, 0.45 * s, 0), Vector3.ZERO, 6)
	_ball(0.7 * s, g, p + Vector3(0, 1.25 * s, 0), Vector3(1, 0.8, 1), 7)
	_ball(0.48 * s, g.lightened(0.08), p + Vector3(0.3 * s, 1.65 * s, -0.12 * s), Vector3.ONE, 6)

func _tuft(p: Vector2, bright: bool) -> void:
	var g := Color("5aae34").lerp(Color("7cc63e"), rng.randf()) if bright else Color("2f6a2e").lerp(Color("3f7f34"), rng.randf())
	for i in 3:
		var o := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		_tuft_x.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))).scaled(Vector3(0.05, rng.randf_range(0.22, 0.34), 0.05)), _v3(p + o, 0.1)))
		_tuft_c.append(g)

# ================================================================ trees (dark, faceted) and grass
func _trees_and_tufts() -> void:
	var tries := 0
	var placed := 0
	while placed < 300 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-43, 43), rng.randf_range(-43, 43))
		var dr := map.dist_to_any_road(p)
		if dr < 6.5 or not _free(p, 1.4, 1.0):
			continue
		var s := rng.randf_range(1.0, 1.7)
		var g := _pick(LEAF)
		_tree_x.append(["trunk", Transform3D(Basis.from_scale(Vector3(0.17, 1.0, 0.17) * s), _v3(p, 0.5 * s)), Color("4a3426")])
		_tree_x.append(["canopy", Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(0.85, 0.72, 0.85) * s), _v3(p, 1.35 * s)), g])
		_tree_x.append(["canopy", Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * 0.55 * s), _v3(p, 1.95 * s) + Vector3(0.3, 0, -0.12) * s), g.lightened(0.07)])
		_tree_x.append(["canopy", Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * 0.5 * s), _v3(p, 1.6 * s) + Vector3(-0.45, 0, 0.2) * s), g.darkened(0.08)])
		placed += 1
	# a few bushes and shrubs at the forest edge
	tries = 0
	placed = 0
	while placed < 70 and tries < 3000:
		tries += 1
		var b := _beside_road(3.0, 7.0)
		var p: Vector2 = b[0]
		if not _free(p, 0.6, 2.0):
			continue
		var s := rng.randf_range(0.8, 1.3)
		var g := _pick(LEAF).lightened(0.1)
		_tree_x.append(["canopy", Transform3D(Basis.from_scale(Vector3(0.5, 0.38, 0.5) * s), _v3(p, 0.22 * s)), g])
		_tree_x.append(["canopy", Transform3D(Basis.from_scale(Vector3.ONE * 0.32 * s), _v3(p, 0.18 * s) + Vector3(0.36, 0, 0.06) * s), g.lightened(0.08)])
		placed += 1
	for i in 900:
		var p := Vector2(rng.randf_range(-42, 42), rng.randf_range(-42, 42))
		var dr := map.dist_to_any_road(p) - MapDef.ROAD_W * 0.5
		if dr < 0.25 or p.length() < MapDef.HORN_R + 1.0:
			continue
		var near_spot := false
		for sp in map.spots:
			if p.distance_to(sp["pos"]) < MapDef.SPOT_R + 0.4:
				near_spot = true
				break
		if near_spot:
			continue
		_tuft(p, dr < 5.0)
	var canopy := _prim_mesh("ball", 0.0, 7)
	var trunk := _prim_mesh("cyl", 0.75, 6)
	var cone := _prim_mesh("cyl", 0.0, 4)
	var cx := []
	var cc := []
	var tx := []
	var tc := []
	for e in _tree_x:
		if e[0] == "trunk":
			tx.append(e[1])
			tc.append(e[2])
		else:
			cx.append(e[1])
			cc.append(e[2])
	_multi(canopy, cx, cc, true)
	_multi(trunk, tx, tc, true)
	_multi(cone, _tuft_x, _tuft_c, false)

func _prim_mesh(kind: String, a: float, seg: int) -> ArrayMesh:
	var pr := _prim(kind, a, seg)
	var vs: PackedVector3Array = pr[0]
	var ns: PackedVector3Array = pr[1]
	var mb := MB.new()
	for i in vs.size():
		mb.v.append(vs[i])
		mb.n.append(ns[i])
		var t := lerpf(0.68, 1.0, ns[i].y * 0.5 + 0.5)
		mb.c.append(Color(t, t, t))
		mb.uv.append(Vector2.ZERO)
	return mb.mesh()

func _multi(mesh: Mesh, xforms: Array, colors: Array, shadows: bool) -> void:
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
	mi.material_override = Mats.painted()
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
