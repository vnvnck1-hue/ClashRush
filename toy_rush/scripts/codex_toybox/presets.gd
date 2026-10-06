extends Node
## Optional presentation layer. No dependency on Claude's Look/Mats implementation.
## Original resources are retained; presets use private copies and are fully reversible.
const RoundedBox := preload("res://scripts/codex_toybox/rounded_box.gd")
const SkinOverlay := preload("res://scripts/codex_toybox/skin_overlay.gd")
const NAMES := ["F6 원래 룩", "F7 토이박스", "F8 웜 토이박스"]
const INK := Color("302443")
const CREAM := Color("fff0d2")
const BLUE := Color("52aff2")
const CORAL := Color("f58b72")

var current_preset := 0
var _records: Dictionary = {}
var _materials: Dictionary = {}
var _models: Dictionary = {}
var _textures: Dictionary = {}
var _material_sources: Dictionary = {}
var _edges: Dictionary = {}
var _live_panels: Dictionary = {}
var _hud: CanvasLayer
var _badge: Label
var _camera_signature := 0.0
var _cleanup_time := 0.0

func _ready() -> void:
	process_priority = 100
	get_tree().node_added.connect(_node_added)
	_build_badge()
	for arg in OS.get_cmdline_user_args():
		if arg == "--codex-look=toybox": current_preset = 1
		elif arg == "--codex-look=warm": current_preset = 2
	if current_preset != 0 and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("TOY RUSH · Codex 토이박스 프리뷰 [F6 / F7 / F8]")
	call_deferred("_scan_scene")

func _build_badge() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 120
	add_child(_hud)
	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_badge.position = Vector2(14, -42)
	_badge.size = Vector2(360, 28)
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", Color("fff4dd"))
	_badge.add_theme_color_override("font_outline_color", INK)
	_badge.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_badge)
	_update_badge()

func _update_badge() -> void:
	if is_instance_valid(_badge):
		_badge.text = "%s   ·   F6 / F7 / F8 비교" % NAMES[current_preset]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if key >= KEY_F6 and key <= KEY_F8:
			set_preset(key - KEY_F6)
			get_viewport().set_input_as_handled()

func set_preset(index: int) -> void:
	if index < 0 or index >= NAMES.size(): return
	_restore()
	current_preset = index
	_materials.clear()
	_material_sources.clear()
	_textures.clear()
	if index != 0:
		for id in _records:
			var record: Dictionary = _records[id]
			var node = record["node"].get_ref()
			if is_instance_valid(node): _apply(node, record)
		_replace_flash_materials()
	_update_badge()
	print("CODEX_LOOK: ", NAMES[index], " (render/UI only)")

func _node_added(node: Node) -> void:
	if node is GeometryInstance3D or node is WorldEnvironment or node is DirectionalLight3D or node is UnitModel or node is Panel or node is Button or node is Label or node is Hud.SkillBox or node is Hud.TipBar:
		call_deferred("_discover_ref", weakref(node))

func _discover_ref(ref: WeakRef) -> void:
	var node = ref.get_ref()
	if is_instance_valid(node): _discover(node)

func _scan_scene() -> void:
	_walk(get_tree().root)
	_replace_flash_materials()
	_update_badge()

func _walk(node: Node) -> void:
	if node == self: return
	_discover(node)
	for child in node.get_children(): _walk(child)

func _discover(node: Node) -> void:
	if node == self or is_ancestor_of(node): return
	var id := node.get_instance_id()
	if node is UnitModel:
		if not _models.has(id):
			_models[id] = {"node": weakref(node), "mats": node.mats.duplicate()}
		return
	if _records.has(id): return
	var record := {"node": weakref(node)}
	if node is MeshInstance3D:
		if node.mesh == null: return
		record["mesh"] = node.mesh
		record["material"] = node.material_override
		var surface_materials: Array = []
		for i in node.mesh.get_surface_count(): surface_materials.append(node.get_surface_override_material(i))
		record["surfaces"] = surface_materials
		record["actor"] = _actor_owner(node) != null
	elif node is MultiMeshInstance3D:
		if node.multimesh == null: return
		record["multimesh"] = node.multimesh
		record["material"] = node.material_override
		record["actor"] = false
	elif node is WorldEnvironment:
		if node.environment == null: return
		record["environment"] = node.environment
	elif node is DirectionalLight3D:
		for property in ["light_color", "light_energy", "shadow_enabled", "shadow_opacity", "shadow_blur", "light_angular_distance", "transform"]:
			record[property] = node.get(property)
	elif node is Panel or node is Button:
		if not _in_interface(node): return
		var styles := {}
		var names := ["panel"] if node is Panel else ["normal", "hover", "pressed", "disabled"]
		for style_name in names:
			if node.has_theme_stylebox_override(style_name): styles[style_name] = node.get_theme_stylebox(style_name)
		if styles.is_empty(): return
		record["styles"] = styles
		if node is Button:
			var theme_values := {}
			for key in ["font_color", "font_outline_color"]:
				theme_values[key] = {"overridden": node.has_theme_color_override(key), "value": node.get_theme_color(key)}
			theme_values["outline_size"] = {"overridden": node.has_theme_constant_override("outline_size"), "value": node.get_theme_constant("outline_size")}
			record["theme_values"] = theme_values
	elif node is Label:
		if not _in_interface(node) or node.label_settings == null: return
		record["label_settings"] = node.label_settings
	elif node is Hud.SkillBox:
		record["skill_overlay"] = true
	elif node is Hud.TipBar:
		record["action_overlay"] = true
	else:
		return
	_records[id] = record
	if current_preset != 0: _apply(node, record)

func _actor_owner(node: Node) -> UnitModel:
	var parent := node.get_parent()
	while parent != null:
		if parent is UnitModel: return parent
		parent = parent.get_parent()
	return null

func _in_interface(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is Hud or parent is Lobby: return true
		parent = parent.get_parent()
	return false

func _apply(node: Node, record: Dictionary) -> void:
	if node is MeshInstance3D:
		var original: Mesh = record["mesh"]
		var actor: bool = record["actor"]
		# Bevel only opaque box props/character parts, never ground/roads/decal planes.
		if original is BoxMesh and original.size.y >= 0.18 and original.size.x < 20.0:
			node.mesh = RoundedBox.make(original.size)
		if record["material"] != null:
			node.material_override = _material(record["material"], actor)
		else:
			for i in original.get_surface_count():
				var material = record["surfaces"][i]
				if material == null: material = original.surface_get_material(i)
				if material != null: node.set_surface_override_material(i, _material(material, actor))
	elif node is MultiMeshInstance3D:
		var original: MultiMesh = record["multimesh"]
		if original.use_colors:
			# Resource.duplicate can assign buffer before its format flags. Allocate in order.
			var copy := MultiMesh.new()
			copy.transform_format = original.transform_format
			copy.use_colors = original.use_colors
			copy.use_custom_data = original.use_custom_data
			copy.mesh = original.mesh
			copy.instance_count = original.instance_count
			copy.visible_instance_count = original.visible_instance_count
			for i in original.instance_count:
				if original.transform_format == MultiMesh.TRANSFORM_3D: copy.set_instance_transform(i, original.get_instance_transform(i))
				else: copy.set_instance_transform_2d(i, original.get_instance_transform_2d(i))
				copy.set_instance_color(i, _palette(original.get_instance_color(i), false))
				if original.use_custom_data: copy.set_instance_custom_data(i, original.get_instance_custom_data(i))
			node.multimesh = copy
		if record["material"] != null: node.material_override = _material(record["material"], false)
	elif node is WorldEnvironment:
		node.environment = _environment(record["environment"])
	elif node is DirectionalLight3D:
		# Keep zero-energy/inactive fill lights inactive.
		if float(record["light_energy"]) <= 0.0: return
		node.light_color = Color("fff3df") if current_preset == 1 else Color("ffe7c2")
		node.light_energy = 0.90 if current_preset == 1 else 0.94
		node.shadow_enabled = true
		node.shadow_opacity = 0.58
		node.shadow_blur = 1.8
		node.light_angular_distance = 2.0
		# Compose light in screen space; preserve camera projection, zoom and input basis.
		_update_sun(node)
	elif node is Panel or node is Button:
		_apply_panel(node, record)
	elif node is Hud.SkillBox:
		_add_edge(node, true)
	elif node is Hud.TipBar:
		_add_edge(node, false, true)
	elif node is Label:
		var settings := record["label_settings"].duplicate() as LabelSettings
		if _on_cream_panel(node):
			settings.font_color = INK
			settings.outline_size = 0
			settings.shadow_size = 0
			settings.shadow_color = Color.TRANSPARENT
			settings.shadow_offset = Vector2.ZERO
		else:
			settings.outline_size = mini(settings.outline_size, 3)
			settings.outline_color = INK
		node.label_settings = settings

func _environment(original: Environment) -> Environment:
	var result := original.duplicate() as Environment
	result.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	result.ambient_light_energy = 0.36
	result.ambient_light_sky_contribution = 1.0
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("cddcf5")
	material.sky_horizon_color = Color("ecf1fa")
	material.ground_bottom_color = Color("8daa78")
	material.ground_horizon_color = Color("bfd1a7")
	material.sun_angle_max = 0.0
	sky.sky_material = material
	result.sky = sky
	result.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	result.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	result.tonemap_exposure = 0.98
	result.tonemap_white = 4.0
	result.adjustment_enabled = true
	result.adjustment_brightness = 1.0
	result.adjustment_contrast = 1.07
	result.adjustment_saturation = 1.08 if current_preset == 1 else 1.11
	result.ssao_enabled = true
	result.ssao_radius = 0.55
	result.ssao_intensity = 0.65
	result.ssao_power = 1.0
	result.glow_enabled = true
	result.glow_intensity = 0.16
	result.glow_bloom = 0.0
	result.glow_hdr_threshold = 2.4
	return result

func _material(original: Material, actor: bool) -> Material:
	if not original is StandardMaterial3D: return original
	var source := original as StandardMaterial3D
	# Preserve all rings, VFX, transparent smoke and unshaded decals.
	if source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or (not actor and source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return original
	var id := source.get_instance_id()
	if _materials.has(id): return _materials[id]
	var result := source.duplicate() as StandardMaterial3D
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	result.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	result.metallic = 0.0
	result.metallic_specular = 0.28 if actor else 0.18
	result.roughness = 0.56 if actor else 0.88
	result.rim_enabled = actor
	result.rim = 0.12
	result.rim_tint = 0.6
	result.next_pass = null
	result.albedo_color = _palette(source.albedo_color, actor)
	if source.albedo_texture is NoiseTexture2D:
		if not _textures.has(source.albedo_texture.get_instance_id()):
			var texture := source.albedo_texture.duplicate() as NoiseTexture2D
			var ramp := Gradient.new()
			ramp.set_color(0, Color("66b548"))
			ramp.set_color(1, Color("89cc59"))
			ramp.add_point(0.5, Color("78c14f"))
			texture.color_ramp = ramp
			_textures[source.albedo_texture.get_instance_id()] = texture
		result.albedo_texture = _textures[source.albedo_texture.get_instance_id()]
	_materials[id] = result
	_material_sources[id] = weakref(original)
	return result

func _palette(color: Color, actor: bool) -> Color:
	var result := color
	if not actor:
		if color.h > 0.18 and color.h < 0.46 and color.s > 0.25:
			result = Color.from_hsv(lerpf(color.h, 0.265, 0.22), color.s * 0.84, minf(color.v * 1.06, 0.92), color.a)
		elif color.h > 0.09 and color.h < 0.17 and color.v > 0.65:
			result = color.lerp(Color("f4dda2"), 0.28)
		elif color.s < 0.3 and color.v > 0.4:
			result = color.lerp(Color("a5a7c4"), 0.13)
	if current_preset == 2:
		result = result.lerp(Color(result.r, result.g * 0.98, result.b * 0.90, result.a), 0.45)
	result.a = color.a
	return result

func _replace_flash_materials() -> void:
	for id in _models:
		var record: Dictionary = _models[id]
		var model = record["node"].get_ref()
		if not is_instance_valid(model): continue
		var original: Array = record["mats"]
		for i in mini(original.size(), model.mats.size()):
			model.mats[i] = original[i] if current_preset == 0 else _material(original[i], true)

func _sync_actor_state() -> void:
	# Preserve live hit flashes / death ghosts when switching looks mid-animation.
	# Only these transient per-actor values travel back; authored shading is untouched.
	for id in _models:
		var record: Dictionary = _models[id]
		var model = record["node"].get_ref()
		if not is_instance_valid(model): continue
		var original: Array = record["mats"]
		for i in mini(original.size(), model.mats.size()):
			var active: StandardMaterial3D = model.mats[i]
			var source: StandardMaterial3D = original[i]
			if source == active: continue
			source.emission = active.emission
			source.transparency = active.transparency
			var color := source.albedo_color
			color.a = active.albedo_color.a
			source.albedo_color = color

func _apply_panel(node: Control, record: Dictionary) -> void:
	for style_name in record["styles"]:
		var original = record["styles"][style_name]
		if not original is StyleBoxFlat: continue
		# Decorative translucent gloss strips must not gain opaque frames/shadows.
		if original.bg_color.a < 0.5: continue
		var style := original.duplicate() as StyleBoxFlat
		var dark := style.bg_color.get_luminance() < 0.22
		if node is Button:
			style.bg_color = CORAL if style_name != "disabled" else Color("b5abc0")
			if style_name == "hover": style.bg_color = CORAL.lightened(0.12)
			if style_name == "pressed": style.bg_color = CORAL.darkened(0.12)
		elif node.size.x >= 100 and node.size.y >= 40 and style.bg_color.a > 0.5:
			style.bg_color = BLUE if _is_hero_dock(node) else CREAM
		elif dark:
			style.bg_color = INK
		style.set_border_width_all(2 if node.size.y >= 30 else 1)
		style.border_color = INK.lightened(0.15)
		if original.border_color.r > 0.5 and original.border_color.r > original.border_color.g * 1.3:
			style.border_color = original.border_color
		if node.size.y >= 30:
			style.set_corner_radius_all(mini(18, int(node.size.y * 0.3)))
			style.shadow_color = Color(0.15, 0.10, 0.22, 0.32)
			style.shadow_size = 3
			style.shadow_offset = Vector2(0, 4)
		node.add_theme_stylebox_override(style_name, style)
		if node is Panel:
			record["applied_panel"] = style
			_live_panels[node.get_instance_id()] = record
			if node.size.x >= 100 and node.size.y >= 40: _add_edge(node, false)
	if node is Button:
		node.add_theme_color_override("font_color", Color.WHITE)
		node.add_theme_color_override("font_outline_color", INK)
		node.add_theme_constant_override("outline_size", 2)

func _add_edge(node: Control, skill: bool, action_bar := false) -> void:
	var id := node.get_instance_id()
	if _edges.has(id): return
	var edge := SkinOverlay.new()
	edge.target = weakref(node)
	edge.skill = skill
	edge.action_bar = action_bar
	node.add_child(edge)
	if not skill and not action_bar: node.move_child(edge, 0)
	_edges[id] = weakref(edge)

func _is_hero_dock(node: Control) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is Hud: return parent.hero_panel == node
		parent = parent.get_parent()
	return false

func _on_cream_panel(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is Panel and parent.has_theme_stylebox_override("panel"):
			var style = parent.get_theme_stylebox("panel")
			if style is StyleBoxFlat and style.bg_color.a >= 0.8:
				var color: Color = style.bg_color
				return color.r > 0.85 and color.g > 0.8 and color.b > 0.6
		parent = parent.get_parent()
	return false

func _update_sun(light: DirectionalLight3D) -> void:
	var camera := light.get_viewport().get_camera_3d()
	if camera == null: return
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	var direction := -right * 0.7 + forward * 0.25
	direction.y = 1.1
	light.basis = Basis.looking_at(-direction.normalized(), Vector3.UP)

func _process(delta: float) -> void:
	_cleanup_time += delta
	if _cleanup_time >= 1.0:
		_cleanup_time = 0.0
		for table in [_records, _models]:
			for id in table.keys():
				if table[id]["node"].get_ref() == null: table.erase(id)
		for id in _material_sources.keys():
			if _material_sources[id].get_ref() == null:
				_material_sources.erase(id)
				_materials.erase(id)
	if current_preset == 0: return
	_replace_flash_materials()
	_sync_actor_state()
	# The original HUD regenerates danger/health styles every update. Skin the latest
	# style after it runs, preserving its color-coded warning border for the next F6.
	for id in _live_panels:
		var record: Dictionary = _live_panels[id]
		var panel = record["node"].get_ref()
		if not is_instance_valid(panel): continue
		var latest = panel.get_theme_stylebox("panel")
		if latest != record.get("applied_panel"):
			record["styles"]["panel"] = latest
			_apply_panel(panel, record)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var signature := camera.global_basis.x.x + camera.global_basis.x.z
		if not is_equal_approx(signature, _camera_signature):
			_camera_signature = signature
			for id in _records:
				var node = _records[id]["node"].get_ref()
				if is_instance_valid(node) and node is DirectionalLight3D and node.light_energy > 0.0: _update_sun(node)

func _restore() -> void:
	if current_preset != 0: _sync_actor_state()
	for id in _edges:
		var edge = _edges[id].get_ref()
		if is_instance_valid(edge):
			edge.hide()
			edge.queue_free()
	_edges.clear()
	_live_panels.clear()
	for id in _records:
		var record: Dictionary = _records[id]
		var node = record["node"].get_ref()
		if not is_instance_valid(node): continue
		if node is MeshInstance3D:
			node.mesh = record["mesh"]
			node.material_override = record["material"]
			for i in record["surfaces"].size(): node.set_surface_override_material(i, record["surfaces"][i])
		elif node is MultiMeshInstance3D:
			node.multimesh = record["multimesh"]
			node.material_override = record["material"]
		elif node is WorldEnvironment:
			node.environment = record["environment"]
		elif node is DirectionalLight3D:
			for property in ["light_color", "light_energy", "shadow_enabled", "shadow_opacity", "shadow_blur", "light_angular_distance", "transform"]: node.set(property, record[property])
		elif node is Panel or node is Button:
			for style_name in record["styles"]: node.add_theme_stylebox_override(style_name, record["styles"][style_name])
			if node is Button:
				for key in ["font_color", "font_outline_color"]:
					var value: Dictionary = record["theme_values"][key]
					if value["overridden"]: node.add_theme_color_override(key, value["value"])
					else: node.remove_theme_color_override(key)
				var value: Dictionary = record["theme_values"]["outline_size"]
				if value["overridden"]: node.add_theme_constant_override("outline_size", value["value"])
				else: node.remove_theme_constant_override("outline_size")
		elif node is Label:
			node.label_settings = record["label_settings"]
	var previous := current_preset
	current_preset = 0
	_replace_flash_materials()
	current_preset = previous
