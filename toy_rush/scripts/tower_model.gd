class_name TowerModel
extends Node3D
## Procedural toy towers. Silhouette stays constant per type; size, details, roof color and
## flags grow with level (readable from far away, Kingdom Rush style).

var kind := ""
var level := 1
var turret: Node3D       # yaws toward the target
var top: Node3D          # punch-scaled on fire
var figure: UnitModel
var _tw: Tween

const STONE := Color("cfc7b8")
const STONE_D := Color("a99f8f")
const WOOD := Color("b77b45")
const ROOF_LV := [Color("4a7fd1"), Color("3f6fc9"), Color("2f5fc0")]

func build(p_kind: String, p_level: int) -> TowerModel:
	kind = p_kind
	level = p_level
	var s := 1.0 + 0.1 * (level - 1)
	scale = Vector3.ONE * s
	_cyl(self, 1.05, 1.15, 0.25, STONE_D, Vector3(0, 0.12, 0))     # plinth
	match kind:
		"archer": _archer()
		"barracks": _barracks()
		"mage": _mage()
		"artillery": _artillery()
	return self

# ------------------------------------------------------------------ helpers
func _mi(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, glow := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = Mats.glow(col, glow) if glow > 0.0 else Mats.prop(col, 0.8, 1.4)
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)
	return m

func _cyl(parent: Node3D, rt: float, rb: float, h: float, col: Color, pos: Vector3, rot := Vector3.ZERO, seg := 20) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	return _mi(parent, c, col, pos, rot)

func _box(parent: Node3D, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(parent, b, col, pos, rot)

func _sphere(parent: Node3D, r: float, col: Color, pos: Vector3, scl := Vector3.ONE, glow := 0.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _mi(parent, s, col, pos, Vector3.ZERO, scl, glow)

func _flag(parent: Node3D, pos: Vector3, col: Color) -> void:
	_cyl(parent, 0.025, 0.025, 0.7, Color("6b4a2f"), pos + Vector3(0, 0.35, 0))
	_box(parent, Vector3(0.32, 0.2, 0.02), col, pos + Vector3(0.17, 0.58, 0))

func _roof() -> Color:
	return ROOF_LV[level - 1]

# ------------------------------------------------------------------ types
func _archer() -> void:
	var h := 1.5 + 0.25 * (level - 1)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(self, 0.08, 0.1, h, WOOD, Vector3(sx * 0.48, 0.25 + h * 0.5, sz * 0.48), Vector3(-sz * 0.08, 0, sx * 0.08))
	_box(self, Vector3(0.62, 0.06, 0.06), WOOD.darkened(0.15), Vector3(0, 0.25 + h * 0.4, 0.5), Vector3(0, 0, 0.6))
	_box(self, Vector3(0.62, 0.06, 0.06), WOOD.darkened(0.15), Vector3(0, 0.25 + h * 0.4, -0.5), Vector3(0, 0, -0.6))
	top = Node3D.new()
	top.position = Vector3(0, 0.25 + h, 0)
	add_child(top)
	_box(top, Vector3(1.35, 0.14, 1.35), WOOD.lightened(0.1), Vector3.ZERO)
	for i in 4:
		var a := i * PI * 0.5
		_box(top, Vector3(1.35, 0.3, 0.08), WOOD, Vector3(sin(a) * 0.64, 0.2, cos(a) * 0.64), Vector3(0, a, 0))
	# roof
	var roof := _cyl(top, 0.0, 0.95, 0.75 + 0.1 * level, _roof(), Vector3(0, 1.05, 0), Vector3.ZERO, 4)
	roof.rotation.y = PI * 0.25
	for i in 4:
		var a := i * PI * 0.5 + PI * 0.25
		_cyl(top, 0.04, 0.04, 0.7, WOOD.darkened(0.2), Vector3(sin(a) * 0.55, 0.5, cos(a) * 0.55))
	if level >= 2:
		_flag(top, Vector3(0, 1.4 + 0.1 * level, 0), Color("ffd23f"))
	if level >= 3:
		_sphere(top, 0.12, Color("ffd23f"), Vector3(0, 1.48, 0))
	turret = Node3D.new()
	turret.position = Vector3(0, 0.08, 0)
	top.add_child(turret)
	figure = UnitModel.new().build("archer", Color("3fa9f5"))
	figure.scale = Vector3.ONE * 0.75
	turret.add_child(figure)

func _barracks() -> void:
	var w := 1.5 + 0.12 * (level - 1)
	_box(self, Vector3(w, 0.95, w * 0.85), STONE, Vector3(0, 0.72, 0))
	_box(self, Vector3(0.42, 0.6, 0.06), Color("6b4a2f"), Vector3(0, 0.55, w * 0.43))     # door
	_cyl(self, 0.21, 0.21, 0.06, Color("6b4a2f"), Vector3(0, 0.85, w * 0.43), Vector3(PI * 0.5, 0, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(w * 1.15, 0.75, w * 0.95)
	_mi(self, roof, _roof(), Vector3(0, 1.57, 0))
	top = Node3D.new()
	top.position = Vector3(0, 1.2, 0)
	add_child(top)
	for sx in [-1.0, 1.0]:
		_cyl(self, 0.24, 0.26, 1.35 + 0.15 * level, STONE_D, Vector3(sx * w * 0.55, 0.85, -w * 0.38))
		_cyl(self, 0.0, 0.32, 0.45, _roof(), Vector3(sx * w * 0.55, 1.75 + 0.15 * level, -w * 0.38))
	_flag(self, Vector3(0, 1.9, 0), Color("e84a5f") if level < 3 else Color("ffd23f"))
	# shield emblem
	_cyl(self, 0.2, 0.2, 0.05, Color("3a6fc4"), Vector3(0, 1.08, w * 0.44), Vector3(PI * 0.5, 0, 0))
	_cyl(self, 0.08, 0.08, 0.06, Color("ffd23f"), Vector3(0, 1.08, w * 0.45), Vector3(PI * 0.5, 0, 0))

func _mage() -> void:
	var purple := Color("7b4fd1")
	var h := 1.7 + 0.3 * (level - 1)
	_cyl(self, 0.55, 0.75, h, Color("d9d2ea"), Vector3(0, 0.25 + h * 0.5, 0))
	_cyl(self, 0.62, 0.62, 0.12, purple.darkened(0.2), Vector3(0, 0.25 + h * 0.75, 0))
	top = Node3D.new()
	top.position = Vector3(0, 0.25 + h, 0)
	add_child(top)
	_cyl(top, 0.7, 0.6, 0.2, purple.darkened(0.1), Vector3(0, 0.05, 0))
	_cyl(top, 0.0, 0.62, 1.1 + 0.15 * level, purple, Vector3(0, 0.7, 0))
	turret = Node3D.new()
	top.add_child(turret)
	var orb_y := 1.55 + 0.15 * level
	_sphere(top, 0.16 + 0.04 * level, Color(0.85, 0.6, 1.0), Vector3(0, orb_y, 0), Vector3.ONE, 2.2)
	for i in level + 1:
		var a := TAU * i / float(level + 1)
		_sphere(top, 0.06, Color(0.9, 0.7, 1.0), Vector3(cos(a) * 0.45, orb_y - 0.4, sin(a) * 0.45), Vector3.ONE, 1.8)
	# window
	_box(self, Vector3(0.22, 0.32, 0.06), Color(0.6, 0.4, 1.0), Vector3(0, 0.25 + h * 0.5, 0.62))

func _artillery() -> void:
	var r := 0.95 + 0.06 * (level - 1)
	_cyl(self, r, r * 1.08, 0.75, STONE, Vector3(0, 0.6, 0), Vector3.ZERO, 12)
	for i in 8:
		var a := TAU * i / 8.0
		_box(self, Vector3(0.28, 0.24, 0.24), STONE_D, Vector3(cos(a) * r * 0.92, 1.06, sin(a) * r * 0.92), Vector3(0, -a, 0))
	top = Node3D.new()
	top.position = Vector3(0, 1.0, 0)
	add_child(top)
	turret = Node3D.new()
	top.add_child(turret)
	_sphere(turret, 0.42, Color("5b5b6e"), Vector3(0, 0.1, 0), Vector3(1, 0.7, 1))
	var n := 1 if level < 3 else 2
	for i in n:
		var x := 0.0 if n == 1 else (-0.18 + i * 0.36)
		_cyl(turret, 0.15 + 0.02 * level, 0.2 + 0.02 * level, 0.95, Color("3a3a48"), Vector3(x, 0.35, -0.42), Vector3(-1.0, 0, 0))
		_cyl(turret, 0.2 + 0.02 * level, 0.2 + 0.02 * level, 0.08, Color("ffc93c"), Vector3(x, 0.62, -0.8), Vector3(-1.0, 0, 0))
	if level >= 2:
		for i in 3:
			_sphere(self, 0.13, Color("3a3a48"), Vector3(r * 0.7 + i * 0.05, 0.3, 0.6 - i * 0.22))

func aim_at(angle: float, delta: float) -> void:
	if turret:
		turret.rotation.y = lerp_angle(turret.rotation.y, angle + PI, 1.0 - exp(-delta * 12.0))

func fire() -> void:
	if top == null:
		return
	if _tw:
		_tw.kill()
	top.scale = Vector3(1.12, 0.86, 1.12)
	_tw = create_tween()
	_tw.tween_property(top, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if figure:
		figure.play_attack("arrow")
