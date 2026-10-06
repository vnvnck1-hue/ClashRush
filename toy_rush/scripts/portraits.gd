class_name Portraits
extends Node
## Renders a head-and-shoulders portrait of each hero model into a texture (SubViewport),
## used by the HUD lane list, hero panel and lobby cards (the reference's character icons).

static var inst: Portraits
var textures := {}
var _vps: Array[SubViewport] = []
var _frames := 0

func _ready() -> void:
	inst = self
	for hk in Data.HERO_ORDER:
		_make(hk)

static func get_tex(hero: String) -> Texture2D:
	if inst and inst.textures.has(hero):
		return inst.textures[hero]
	return null

func _make(hk: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(192, 192)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8d4ff")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Look.SUN_COLOR
	key.light_energy = 0.85
	key.transform = Transform3D(Basis.looking_at(Vector3(0.5, -0.6, -1.0).normalized(), Vector3.UP), Vector3.ZERO)
	root.add_child(key)
	var m := UnitModel.new().build(Data.HEROES[hk]["model"], Color("3fa9f5"))
	m.rotation.y = PI + 0.35
	root.add_child(m)
	m.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	var head_y := 0.75
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, -0.12, -1).normalized(), Vector3.UP), Vector3(0, head_y + 0.12, 1.55))
	cam.current = true
	textures[hk] = vp.get_texture()
	_vps.append(vp)

func _process(_d: float) -> void:
	# render a few frames, then freeze to save GPU
	_frames += 1
	if _frames == 4:
		for vp in _vps:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
