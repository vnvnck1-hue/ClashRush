class_name UnitModel
extends Node3D
## Procedurally built 2~2.5 head-tall toy figure. Faces -Z.
## Owns all "juice" motion: breathing, hop-walk, attack swings, squash & stretch, hit flash.

const SKIN := Color("f4ad7a")

var kind := ""
var tint := Color("3fa9f5")
var squash: Node3D        # squash & stretch + lean pivot (at feet)
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon: Node3D
var mats: Array[StandardMaterial3D] = []

var walk := 0.0           # 0..1 blend of hop cycle
var _t := 0.0
var _phase := 0.0
var _squash_v := Vector2.ONE  # extra scale from impulses (x,y)
var _sq_tween: Tween
var _flash_tween: Tween
var attack_lean := 0.0    # forward lean from attacks (radians)
var hop_offset := 0.0

func build(p_kind: String, p_tint: Color) -> UnitModel:
	kind = p_kind
	tint = p_tint
	_phase = randf() * TAU
	squash = _node(self, Vector3.ZERO)
	torso = _node(squash, Vector3.ZERO)
	match kind:
		"king": _build_king()
		"queen": _build_queen()
		"brawler": _build_brawler()
		"archer": _build_archer()
		"goblin": _build_goblin()
		"wizard": _build_wizard()
		"valkyrie": _build_valkyrie()
		"giant": _build_giant()
		"cleric": _build_cleric()
		"footman": _build_footman()
		"orc": _build_orc()
		"wolf": _build_wolf()
		"shaman": _build_shaman()
		"bat": _build_bat()
		"darkknight": _build_darkknight()
		"ogre": _build_ogre()
	return self

# ------------------------------------------------------------------ helpers
func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _mat(color: Color) -> StandardMaterial3D:
	var m := Mats.toy(color)
	mats.append(m)
	return m

func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _sphere(parent: Node3D, r: float, color: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return _mesh(parent, s, color, pos, scl)

func _hemi(parent: Node3D, r: float, color: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r
	s.is_hemisphere = true
	s.radial_segments = 24
	s.rings = 8
	return _mesh(parent, s, color, pos, scl)

func _capsule(parent: Node3D, r: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 16
	c.rings = 6
	return _mesh(parent, c, color, pos, scl, rot)

func _cyl(parent: Node3D, rt: float, rb: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 20
	c.rings = 1
	return _mesh(parent, c, color, pos, scl, rot)

func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, color, pos, Vector3.ONE, rot)

func _torus(parent: Node3D, ri: float, ro: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 24
	t.ring_segments = 10
	return _mesh(parent, t, color, pos, scl, rot)

func _team_col() -> Color:
	return tint

## Standard chibi skeleton: legs, egg body, big head, stubby arms with fists.
func _base(body_col: Color, skin := SKIN, body_r := 0.2, head_r := 0.21, leg_col := Color("6b4a2f"), fist_r := 0.075) -> void:
	leg_l = _node(torso, Vector3(-0.09, 0.13, 0))
	leg_r = _node(torso, Vector3(0.09, 0.13, 0))
	_capsule(leg_l, 0.065, 0.2, leg_col, Vector3(0, -0.06, 0))
	_capsule(leg_r, 0.065, 0.2, leg_col, Vector3(0, -0.06, 0))
	_sphere(leg_l, 0.075, leg_col.darkened(0.25), Vector3(0, -0.12, -0.03), Vector3(1, 0.7, 1.3))
	_sphere(leg_r, 0.075, leg_col.darkened(0.25), Vector3(0, -0.12, -0.03), Vector3(1, 0.7, 1.3))
	_sphere(torso, body_r, body_col, Vector3(0, 0.27, 0), Vector3(1.0, 0.95, 0.9))
	# team belt
	_torus(torso, body_r * 0.86, body_r * 1.02, _team_col(), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 1.2, 0.92))
	head = _node(torso, Vector3(0, 0.36 + body_r * 0.7 + head_r * 0.55, 0))
	_sphere(head, head_r, skin, Vector3.ZERO)
	# eyes (face -Z)
	var eye_col := Color("2a1d1a")
	_sphere(head, head_r * 0.13, eye_col, Vector3(-head_r * 0.36, head_r * 0.08, -head_r * 0.92), Vector3(0.8, 1.2, 0.5))
	_sphere(head, head_r * 0.13, eye_col, Vector3(head_r * 0.36, head_r * 0.08, -head_r * 0.92), Vector3(0.8, 1.2, 0.5))
	_sphere(head, head_r * 0.16, skin.darkened(0.06), Vector3(0, -head_r * 0.12, -head_r * 0.98))
	arm_l = _node(torso, Vector3(-body_r * 1.0, 0.36, 0))
	arm_r = _node(torso, Vector3(body_r * 1.0, 0.36, 0))
	_capsule(arm_l, 0.055, 0.2, body_col.darkened(0.08), Vector3(-0.02, -0.08, 0), Vector3(0, 0, -0.35))
	_capsule(arm_r, 0.055, 0.2, body_col.darkened(0.08), Vector3(0.02, -0.08, 0), Vector3(0, 0, 0.35))
	_sphere(arm_l, fist_r, skin, Vector3(-0.06, -0.17, 0))
	_sphere(arm_r, fist_r, skin, Vector3(0.06, -0.17, 0))
	weapon = _node(arm_r, Vector3(0.06, -0.17, 0))

# ------------------------------------------------------------------ characters
func _build_king() -> void:
	var gold := Color("f2b632")
	_base(Color("e2a431"), SKIN, 0.23, 0.23, Color("7a3b2a"), 0.1)
	# cape
	_sphere(torso, 0.24, Color("c9362f"), Vector3(0, 0.27, 0.15), Vector3(1.05, 1.15, 0.45))
	_sphere(torso, 0.2, Color("f3ead8"), Vector3(0, 0.43, 0.1), Vector3(1.25, 0.35, 0.8))  # fur collar
	# shoulder pads
	_sphere(torso, 0.1, gold.lightened(0.1), Vector3(-0.21, 0.42, 0), Vector3(1, 0.7, 1))
	_sphere(torso, 0.1, gold.lightened(0.1), Vector3(0.21, 0.42, 0), Vector3(1, 0.7, 1))
	# hair, beard & mustache
	var hair := Color("9a4f2a")
	_sphere(head, 0.235, hair, Vector3(0, 0.03, 0.05), Vector3(1.05, 0.95, 1.02))
	_sphere(head, 0.17, hair, Vector3(0, -0.12, -0.1), Vector3(1.1, 0.9, 0.8))
	_capsule(head, 0.05, 0.28, hair.lightened(0.1), Vector3(0, -0.04, -0.2), Vector3(0, 0, PI * 0.5))
	_capsule(head, 0.03, 0.12, hair.darkened(0.2), Vector3(-0.08, 0.08, -0.2), Vector3(0, 0, 1.3))
	_capsule(head, 0.03, 0.12, hair.darkened(0.2), Vector3(0.08, 0.08, -0.2), Vector3(0, 0, -1.3))
	# crown
	_cyl(head, 0.2, 0.19, 0.12, gold, Vector3(0, 0.22, 0))
	for i in 5:
		var a := TAU * i / 5.0
		_sphere(head, 0.04, gold.lightened(0.2), Vector3(cos(a) * 0.19, 0.31, sin(a) * 0.19))
	_sphere(head, 0.045, Color("e63d5c"), Vector3(0, 0.22, -0.195))
	# gold gauntlets (big fists)
	_sphere(arm_r, 0.12, gold, Vector3(0.06, -0.17, 0))
	_sphere(arm_l, 0.12, gold, Vector3(-0.06, -0.17, 0))

func _build_queen() -> void:
	var purple := Color("8e4fc4")
	_base(Color("6b3aa0"), SKIN, 0.2, 0.21, Color("3d2466"))
	_sphere(head, 0.23, purple, Vector3(0, 0.05, 0.05), Vector3(1.05, 1.0, 1.05))  # hair bob
	_sphere(head, 0.12, purple.darkened(0.15), Vector3(0, -0.05, 0.19))
	_cyl(head, 0.11, 0.1, 0.07, Color("f2b632"), Vector3(0, 0.23, 0))
	_sphere(head, 0.03, Color("ff5fa2"), Vector3(0, 0.24, -0.1))
	# crossbow
	_box(weapon, Vector3(0.05, 0.05, 0.34), Color("7a4a26"), Vector3(0, 0, -0.1))
	_torus(weapon, 0.14, 0.17, Color("5a5a66"), Vector3(0, 0, -0.24), Vector3(0, 0, 0), Vector3(1, 0.4, 0.45))
	_sphere(torso, 0.08, Color("ff5fa2"), Vector3(0, 0.3, -0.17))

func _build_brawler() -> void:
	var hair := Color("ffd23f")
	_base(Color("9a6034"), SKIN, 0.19, 0.21, Color("5b3a22"))
	# hair mop + mustache
	_sphere(head, 0.2, hair, Vector3(0, 0.07, 0.05), Vector3(1.1, 0.85, 1.05))
	_capsule(head, 0.045, 0.26, hair.darkened(0.05), Vector3(0, -0.07, -0.2), Vector3(0, 0, PI * 0.5))
	# horned helmet
	_hemi(head, 0.18, Color("b8bfcc"), Vector3(0, 0.1, 0))
	_cyl(head, 0.0, 0.05, 0.16, Color("fff5e0"), Vector3(-0.19, 0.2, 0), Vector3(0, 0, 0.7))
	_cyl(head, 0.0, 0.05, 0.16, Color("fff5e0"), Vector3(0.19, 0.2, 0), Vector3(0, 0, -0.7))
	# big sword
	_box(weapon, Vector3(0.07, 0.42, 0.025), Color("dfe6ee"), Vector3(0, 0.24, 0))
	_box(weapon, Vector3(0.18, 0.04, 0.05), Color("f2b632"), Vector3(0, 0.03, 0))
	_capsule(weapon, 0.025, 0.1, Color("6b4a2f"), Vector3(0, -0.03, 0))

func _build_archer() -> void:
	var pink := Color("ff6fae")
	_base(Color("4fae55"), SKIN, 0.18, 0.2, Color("3d6b3a"))
	_sphere(head, 0.22, pink, Vector3(0, 0.04, 0.05), Vector3(1.05, 1.02, 1.05))  # hood
	_cyl(head, 0.0, 0.08, 0.14, pink, Vector3(0, 0.1, 0.23), Vector3(-1.9, 0, 0))  # hood tip
	_sphere(head, 0.1, Color("ff9f5a"), Vector3(0, 0.1, -0.14), Vector3(1.2, 0.5, 0.6))  # bangs
	# bow in left hand
	var bow := _node(arm_l, Vector3(-0.06, -0.17, 0))
	_torus(bow, 0.2, 0.23, Color("8a5a2b"), Vector3.ZERO, Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.35))
	# quiver
	_cyl(torso, 0.05, 0.05, 0.26, Color("8a5a2b"), Vector3(0.08, 0.36, 0.17), Vector3(0.4, 0, -0.3))

func _build_goblin() -> void:
	var skin := Color("8fd14f")
	_base(Color("7a5230"), skin, 0.17, 0.2, Color("5a3a20"), 0.07)
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(-0.23, 0.04, 0), Vector3(0, 0, 1.3))
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(0.23, 0.04, 0), Vector3(0, 0, -1.3))
	_sphere(head, 0.07, skin.darkened(0.1), Vector3(0, -0.04, -0.2), Vector3(1, 0.8, 1))  # big nose
	_hemi(head, 0.17, Color("3fa0d8"), Vector3(0, 0.08, 0.02))  # blue bandana
	_box(weapon, Vector3(0.04, 0.2, 0.02), Color("dfe6ee"), Vector3(0, 0.12, 0))

func _build_wizard() -> void:
	var robe := Color("3d72d9")
	_base(robe, SKIN, 0.19, 0.2, robe.darkened(0.3))
	_cyl(torso, 0.14, 0.24, 0.3, robe, Vector3(0, 0.18, 0))  # robe skirt
	_sphere(head, 0.11, Color("6b4a2f"), Vector3(0, -0.13, -0.08), Vector3(1.2, 0.6, 0.8))  # beard stub
	_cyl(head, 0.3, 0.3, 0.035, Color("5b2da0"), Vector3(0, 0.13, 0))  # brim
	_cyl(head, 0.0, 0.17, 0.36, Color("6f3ac0"), Vector3(0, 0.3, 0.04), Vector3(-0.25, 0, 0))
	# fire orb
	var orb := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	orb.mesh = s
	orb.material_override = Mats.glow(Color("ffb13b"), 2.2)
	orb.position = Vector3(0, 0.05, -0.02)
	weapon.add_child(orb)

func _build_valkyrie() -> void:
	var hair := Color("ff8a2a")
	_base(Color("b5452f"), SKIN, 0.2, 0.21, Color("6b3a22"))
	_sphere(head, 0.21, hair, Vector3(0, 0.07, 0.04), Vector3(1.08, 0.9, 1.05))
	_capsule(head, 0.06, 0.26, hair, Vector3(-0.17, -0.12, 0.05), Vector3(0.2, 0, 0.3))
	_capsule(head, 0.06, 0.26, hair, Vector3(0.17, -0.12, 0.05), Vector3(0.2, 0, -0.3))
	_hemi(head, 0.16, Color("c9ced8"), Vector3(0, 0.12, 0))
	# double axe
	_capsule(weapon, 0.025, 0.46, Color("6b4a2f"), Vector3(0, 0.12, 0))
	_cyl(weapon, 0.14, 0.14, 0.03, Color("dfe6ee"), Vector3(0.09, 0.3, 0), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8))
	_cyl(weapon, 0.14, 0.14, 0.03, Color("dfe6ee"), Vector3(-0.09, 0.3, 0), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8))

func _build_giant() -> void:
	_base(Color("8a5a34"), SKIN, 0.24, 0.19, Color("4e3420"), 0.12)
	_sphere(torso, 0.13, SKIN, Vector3(-0.23, 0.42, 0), Vector3(1.1, 0.9, 1))  # shoulders
	_sphere(torso, 0.13, SKIN, Vector3(0.23, 0.42, 0), Vector3(1.1, 0.9, 1))
	_sphere(head, 0.09, Color("c98a4a"), Vector3(0, -0.1, -0.12), Vector3(1.4, 0.6, 0.8))  # stubble
	_capsule(torso, 0.05, 0.5, Color("5b3a22"), Vector3(0, 0.33, 0), Vector3(0, 0, 0.9), Vector3(1, 1, 1))  # strap
	_capsule(head, 0.03, 0.12, Color("5b3a22"), Vector3(-0.08, 0.1, -0.17), Vector3(0, 0, 1.4))  # angry brows
	_capsule(head, 0.03, 0.12, Color("5b3a22"), Vector3(0.08, 0.1, -0.17), Vector3(0, 0, -1.4))

func _glow_orb(parent: Node3D, r: float, col: Color, pos: Vector3) -> void:
	var orb := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	orb.mesh = s
	orb.material_override = Mats.glow(col, 2.2)
	orb.position = pos
	parent.add_child(orb)

func _build_cleric() -> void:
	var robe := Color("fff4dc")
	_base(robe, SKIN, 0.19, 0.2, Color("c9a35a"))
	_cyl(torso, 0.14, 0.25, 0.32, robe, Vector3(0, 0.17, 0))
	_torus(torso, 0.22, 0.26, Color("ffc93c"), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_cyl(torso, 0.05, 0.05, 0.3, Color("ffc93c"), Vector3(0, 0.2, -0.2), Vector3(0.25, 0, 0))
	_sphere(head, 0.225, Color("ffe08a"), Vector3(0, 0.04, 0.05), Vector3(1.05, 0.95, 1.05))
	_sphere(head, 0.2, Color("ffe7a8"), Vector3(0, 0.07, 0.09), Vector3(1.1, 1.0, 1.0))
	_torus(head, 0.15, 0.18, Color("ffd23f"), Vector3(0, 0.33, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	_sphere(torso, 0.16, Color("ffffff"), Vector3(-0.17, 0.4, 0.17), Vector3(0.5, 1.1, 0.25))
	_sphere(torso, 0.16, Color("ffffff"), Vector3(0.17, 0.4, 0.17), Vector3(0.5, 1.1, 0.25))
	_capsule(weapon, 0.02, 0.6, Color("c98a4a"), Vector3(0, 0.15, 0))
	_glow_orb(weapon, 0.07, Color("8ff0ff"), Vector3(0, 0.47, 0))

func _build_footman() -> void:
	var steel := Color("b9c3d3")
	_base(Color("4a7fd1"), SKIN, 0.18, 0.19, Color("39507a"))
	_hemi(head, 0.2, steel, Vector3(0, 0.03, 0), Vector3(1.05, 1.1, 1.05))
	_box(head, Vector3(0.04, 0.12, 0.05), steel.darkened(0.1), Vector3(0, -0.02, -0.19))
	_cyl(head, 0.0, 0.04, 0.12, Color("e84a5f"), Vector3(0, 0.22, 0))
	_box(weapon, Vector3(0.05, 0.32, 0.02), Color("dfe6ee"), Vector3(0, 0.18, 0))
	var shield := _node(arm_l, Vector3(-0.08, -0.15, -0.04))
	_cyl(shield, 0.15, 0.15, 0.04, Color("3a6fc4"), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_cyl(shield, 0.06, 0.06, 0.05, Color("ffd23f"), Vector3(0, 0, -0.01), Vector3(PI * 0.5, 0, 0))

func _build_orc() -> void:
	var skin := Color("6fae4a")
	_base(Color("8a5a34"), skin, 0.23, 0.2, Color("4e3420"), 0.1)
	_sphere(torso, 0.12, skin, Vector3(-0.22, 0.42, 0), Vector3(1.1, 0.85, 1))
	_sphere(torso, 0.12, skin, Vector3(0.22, 0.42, 0), Vector3(1.1, 0.85, 1))
	_cyl(head, 0.0, 0.03, 0.08, Color("fff5e0"), Vector3(-0.07, -0.1, -0.18), Vector3(-0.3, 0, 0))
	_cyl(head, 0.0, 0.03, 0.08, Color("fff5e0"), Vector3(0.07, -0.1, -0.18), Vector3(-0.3, 0, 0))
	_capsule(head, 0.05, 0.2, Color("2a2a2a"), Vector3(0, 0.18, 0.02), Vector3(PI * 0.5, 0, 0))
	_capsule(weapon, 0.05, 0.36, Color("8a5a34"), Vector3(0, 0.16, 0))
	_sphere(weapon, 0.09, Color("7a4a26"), Vector3(0, 0.32, 0))

func _build_wolf() -> void:
	var fur := Color("8f8a9e")
	leg_l = _node(torso, Vector3(-0.1, 0.12, -0.15))
	leg_r = _node(torso, Vector3(0.1, 0.12, -0.15))
	var bl := _node(torso, Vector3(-0.1, 0.12, 0.17))
	var br := _node(torso, Vector3(0.1, 0.12, 0.17))
	for lg in [leg_l, leg_r, bl, br]:
		_capsule(lg, 0.05, 0.18, fur.darkened(0.2), Vector3(0, -0.04, 0))
	_sphere(torso, 0.2, fur, Vector3(0, 0.25, 0.02), Vector3(0.9, 0.8, 1.5))
	head = _node(torso, Vector3(0, 0.36, -0.28))
	_sphere(head, 0.15, fur, Vector3.ZERO)
	_sphere(head, 0.08, fur.lightened(0.15), Vector3(0, -0.04, -0.13), Vector3(0.9, 0.8, 1.4))
	_sphere(head, 0.03, Color("1d1530"), Vector3(0, -0.02, -0.25))
	_cyl(head, 0.0, 0.05, 0.12, fur.darkened(0.1), Vector3(-0.08, 0.13, 0.02))
	_cyl(head, 0.0, 0.05, 0.12, fur.darkened(0.1), Vector3(0.08, 0.13, 0.02))
	_sphere(head, 0.025, Color("ffd23f"), Vector3(-0.06, 0.04, -0.12))
	_sphere(head, 0.025, Color("ffd23f"), Vector3(0.06, 0.04, -0.12))
	_capsule(torso, 0.04, 0.24, fur, Vector3(0, 0.33, 0.36), Vector3(-0.9, 0, 0))
	_torus(torso, 0.13, 0.16, _team_col(), Vector3(0, 0.35, -0.18), Vector3(PI * 0.5, 0, 0))
	arm_l = _node(torso, Vector3.ZERO)
	arm_r = _node(torso, Vector3.ZERO)
	weapon = _node(head, Vector3(0, -0.05, -0.15))

func _build_shaman() -> void:
	var skin := Color("8fd14f")
	_base(Color("6b3aa0"), skin, 0.17, 0.2, Color("4a2a6a"), 0.07)
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(-0.23, 0.04, 0), Vector3(0, 0, 1.3))
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(0.23, 0.04, 0), Vector3(0, 0, -1.3))
	_sphere(head, 0.15, Color("f3ead8"), Vector3(0, 0.0, -0.1), Vector3(1.1, 1.2, 0.6))
	_sphere(head, 0.03, Color("ff4040"), Vector3(-0.06, 0.03, -0.19))
	_sphere(head, 0.03, Color("ff4040"), Vector3(0.06, 0.03, -0.19))
	var cols := [Color("ff5f7e"), Color("ffd23f"), Color("3fa9f5")]
	for i in 3:
		_cyl(head, 0.0, 0.03, 0.18, cols[i], Vector3(-0.08 + i * 0.08, 0.22, 0.05), Vector3(0.3, 0, -0.3 + i * 0.3))
	_capsule(weapon, 0.02, 0.5, Color("8a5a34"), Vector3(0, 0.12, 0))
	_glow_orb(weapon, 0.06, Color("9cff6a"), Vector3(0, 0.38, 0))

func _build_bat() -> void:
	var c := Color("5b3a8a")
	_sphere(torso, 0.17, c, Vector3(0, 0.0, 0), Vector3(1, 0.9, 1))
	head = _node(torso, Vector3(0, 0.12, -0.08))
	_sphere(head, 0.12, c.lightened(0.1), Vector3.ZERO)
	_cyl(head, 0.0, 0.05, 0.12, c, Vector3(-0.07, 0.12, 0))
	_cyl(head, 0.0, 0.05, 0.12, c, Vector3(0.07, 0.12, 0))
	_sphere(head, 0.03, Color("ffde4a"), Vector3(-0.045, 0.02, -0.1))
	_sphere(head, 0.03, Color("ffde4a"), Vector3(0.045, 0.02, -0.1))
	arm_l = _node(torso, Vector3(-0.12, 0.02, 0))
	arm_r = _node(torso, Vector3(0.12, 0.02, 0))
	_sphere(arm_l, 0.22, c.darkened(0.15), Vector3(-0.2, 0, 0.02), Vector3(1.2, 0.12, 0.7))
	_sphere(arm_r, 0.22, c.darkened(0.15), Vector3(0.2, 0, 0.02), Vector3(1.2, 0.12, 0.7))
	_torus(torso, 0.1, 0.12, _team_col(), Vector3(0, -0.08, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	weapon = _node(head, Vector3(0, 0, -0.1))

func _build_darkknight() -> void:
	var armor := Color("4a4a5e")
	_base(armor, Color("7a7a8e"), 0.22, 0.2, Color("2e2e3a"), 0.09)
	_sphere(torso, 0.12, armor.lightened(0.15), Vector3(-0.22, 0.42, 0), Vector3(1.1, 0.8, 1))
	_sphere(torso, 0.12, armor.lightened(0.15), Vector3(0.22, 0.42, 0), Vector3(1.1, 0.8, 1))
	_sphere(head, 0.22, armor.lightened(0.05), Vector3(0, 0.02, 0), Vector3(1.0, 1.05, 1.0))
	_box(head, Vector3(0.24, 0.035, 0.05), Color("ff3b3b"), Vector3(0, 0.02, -0.2))
	_cyl(head, 0.0, 0.04, 0.16, Color("c0392b"), Vector3(0, 0.26, 0.02), Vector3(-0.4, 0, 0))
	_box(weapon, Vector3(0.08, 0.5, 0.025), Color("8a8fa0"), Vector3(0, 0.28, 0))
	_box(weapon, Vector3(0.22, 0.05, 0.05), Color("2e2e3a"), Vector3(0, 0.03, 0))
	_sphere(torso, 0.22, Color("6a1f2a"), Vector3(0, 0.28, 0.15), Vector3(1.0, 1.1, 0.4))

func _build_ogre() -> void:
	var skin := Color("9a7bc4")
	_base(Color("6b4a2f"), skin, 0.27, 0.2, Color("4e3420"), 0.14)
	_sphere(torso, 0.15, skin, Vector3(-0.26, 0.44, 0), Vector3(1.1, 0.9, 1))
	_sphere(torso, 0.15, skin, Vector3(0.26, 0.44, 0), Vector3(1.1, 0.9, 1))
	_sphere(torso, 0.17, skin.lightened(0.1), Vector3(0, 0.25, -0.13), Vector3(1.2, 0.9, 0.6))
	_cyl(head, 0.0, 0.035, 0.1, Color("fff5e0"), Vector3(-0.08, -0.12, -0.16), Vector3(-0.4, 0, 0))
	_cyl(head, 0.0, 0.035, 0.1, Color("fff5e0"), Vector3(0.08, -0.12, -0.16), Vector3(-0.4, 0, 0))
	_cyl(head, 0.0, 0.05, 0.14, Color("e8e0c8"), Vector3(-0.13, 0.16, 0), Vector3(0, 0, 0.5))
	_cyl(head, 0.0, 0.05, 0.14, Color("e8e0c8"), Vector3(0.13, 0.16, 0), Vector3(0, 0, -0.5))
	_capsule(weapon, 0.06, 0.5, Color("6b4a2f"), Vector3(0, 0.22, 0))
	_sphere(weapon, 0.14, Color("5b3a22"), Vector3(0, 0.46, 0))
	for i in 4:
		var a := TAU * i / 4.0
		_cyl(weapon, 0.0, 0.03, 0.08, Color("c9ced8"), Vector3(cos(a) * 0.13, 0.48, sin(a) * 0.13), Vector3(sin(a) * 1.4, 0, -cos(a) * 1.4))

# ------------------------------------------------------------------ animation
func _process(delta: float) -> void:
	_t += delta
	var breath := sin(_t * 5.0 + _phase) * 0.035 * (1.0 - walk)
	var hop := absf(sin(_t * 12.0 + _phase)) * walk
	hop_offset = hop * 0.11
	var land := (1.0 - hop) * walk * 0.12
	var sy := (1.0 + breath - land + hop * 0.06) * _squash_v.y
	var sx := (1.0 - breath * 0.6 + land * 0.8) * _squash_v.x
	squash.scale = Vector3(sx, sy, sx)
	squash.position.y = hop_offset
	squash.rotation.x = -walk * 0.18 - attack_lean
	squash.rotation.z = sin(_t * 6.0 + _phase) * 0.06 * walk
	if leg_l:
		leg_l.rotation.x = sin(_t * 12.0 + _phase) * 0.7 * walk
		leg_r.rotation.x = -sin(_t * 12.0 + _phase) * 0.7 * walk
	if kind == "bat":
		var f := sin(_t * 20.0 + _phase)
		arm_l.rotation.z = f * 0.7
		arm_r.rotation.z = -f * 0.7
		squash.position.y = 0.06 * sin(_t * 20.0 + _phase + 1.0)
		return
	if arm_l and not _arm_busy:
		arm_l.rotation.x = -sin(_t * 12.0 + _phase) * 0.6 * walk + sin(_t * 5.0 + _phase) * 0.05
		arm_r.rotation.x = sin(_t * 12.0 + _phase) * 0.6 * walk - sin(_t * 5.0 + _phase) * 0.05

var _arm_busy := false

## Squash impulse: goes to (sx, sy) then springs back with overshoot.
func punch_scale(sx: float, sy: float, dur := 0.35) -> void:
	if _sq_tween:
		_sq_tween.kill()
	_squash_v = Vector2(sx, sy)
	_sq_tween = create_tween()
	_sq_tween.tween_property(self, "_squash_v", Vector2.ONE, dur).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Attack animation. Returns seconds until the impact frame.
func play_attack(style: String) -> float:
	_arm_busy = true
	var tw := create_tween()
	var wind := 0.13
	var strike := 0.06
	match style:
		"melee":
			tw.set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-2.6, 0, 0.3), wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", -0.3, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(0.9, 0, -0.2), strike).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			tw.tween_property(self, "attack_lean", 0.45, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"arrow":
			tw.set_parallel(true)
			tw.tween_property(arm_l, "rotation", Vector3(-1.5, 0, 0), wind)
			tw.tween_property(arm_r, "rotation", Vector3(-1.3, 0, 0.6), wind)
			tw.tween_property(self, "attack_lean", -0.25, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(self, "attack_lean", -0.1, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_l, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.25)
		"fireball":
			wind = 0.2
			tw.set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-3.0, 0, 0.2), wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", -0.35, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-1.2, 0, 0), strike)
			tw.tween_property(self, "attack_lean", 0.3, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"spin":
			wind = 0.12
			tw.tween_property(squash, "rotation:y", -0.6, wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(squash, "rotation:y", TAU, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): squash.rotation.y = 0.0)
			strike = 0.05
	tw.chain().tween_callback(func(): _arm_busy = false)
	if style != "spin":
		punch_scale(0.9, 1.12, 0.4)
	return wind + strike

func flash(col := Color(1, 1, 1), energy := 1.4, dur := 0.12) -> void:
	if _flash_tween:
		_flash_tween.kill()
	for m in mats:
		m.emission = col * energy
	_flash_col = col
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, energy, 0.0, dur)

var _flash_col := Color(1, 1, 1)
func _set_flash(v: float) -> void:
	for m in mats:
		m.emission = _flash_col * v

func set_ghost(on: bool) -> void:
	for m in mats:
		if on:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			m.emission = Color(0.25, 0.3, 0.45)
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = 1.0
			m.emission = Color(0, 0, 0)
