extends SceneTree
## Integration check on the actual Main scene, with input events and optional GPU captures.
var failures: Array[String] = []
var game: Node
var layer: Node
var output := "res://docs/ui-concepts/runtime/verified"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	layer = root.get_node("CodexToybox")
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(4.5).timeout
	_check(game.view != null and game.hud != null, "actual solo game initialized")
	if game.view == null:
		quit(1)
		return
	# Freeze the same composition for all three looks without altering normal game code.
	game.set_process(false)
	game.set_physics_process(false)
	game.cam.set_process(false)
	_stage_scene()
	await create_timer(0.6).timeout
	game.view.set_process(false)
	_freeze_models(game.view)
	await create_timer(0.25).timeout
	var state := str(game.sim.snapshot())
	var camera_transform: Transform3D = game.cam.transform
	var camera_fov: float = game.cam.fov
	var environment: WorldEnvironment = _first_type(game.view, "WorldEnvironment")
	var original_environment: Environment = environment.environment
	var actor: UnitModel = game.view.hero_nodes[0]["model"]
	var mesh: MeshInstance3D = _first_type(actor, "MeshInstance3D")
	var original_material: Material = mesh.material_override
	var original_mesh: Mesh = mesh.mesh
	await _capture("00-claude")
	await _key(KEY_F7)
	_check(layer.current_preset == 1, "F7 selects Toybox via real input event")
	_check(environment.environment != original_environment, "environment override uses private resource")
	_check(mesh.material_override != original_material, "actor material override uses private resource")
	_check(mesh.material_override.diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY, "soft toy diffuse applied")
	_check(mesh.material_override.next_pass == null, "ink outline removed in Toybox")
	_check(game.cam.transform == camera_transform and game.cam.fov == camera_fov, "camera/aim basis preserved")
	_check(str(game.sim.snapshot()) == state, "preset leaves simulation unchanged")
	_check(actor.mats.has(mesh.material_override), "hit flash targets displayed preset material")
	await _capture("01-toybox")
	await _key(KEY_F8)
	_check(layer.current_preset == 2, "F8 selects Warm Toybox via input")
	_check(str(game.sim.snapshot()) == state, "warm preset leaves simulation unchanged")
	await _capture("02-warm-toybox")
	await _key(KEY_F6)
	_check(layer.current_preset == 0, "F6 selects original look")
	_check(environment.environment == original_environment, "exact original environment restored")
	_check(mesh.material_override == original_material and mesh.mesh == original_mesh, "exact original mesh and material restored")
	_check(actor.mats.has(original_material), "original hit-flash material restored")
	_check(_all_restored(), "all surviving mesh/multimesh/UI/light resources restored")
	await _capture("03-restored")
	# Spawn after a preset was selected, as enemies and upgraded towers do during play.
	await _key(KEY_F7)
	var spawned := UnitModel.new().build("wizard", Color("3fa9f5"))
	spawned.position = Vector3(4, 0, 4)
	game.view.add_child(spawned)
	for i in 4: await process_frame
	var spawned_mesh: MeshInstance3D = _first_type(spawned, "MeshInstance3D")
	_check(spawned_mesh.material_override.diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY, "new entities inherit active preset")
	_check(spawned.mats.has(spawned_mesh.material_override), "new entity hit-flash references remain connected")
	spawned.flash(Color.WHITE, 1.2, 0.2)
	_check(spawned_mesh.material_override.emission.r > 1.0, "hit flash visible on overridden material")
	await create_timer(0.3).timeout
	_check(spawned_mesh.material_override.emission.r < 0.01, "hit flash returns to zero")
	spawned.set_ghost(true)
	await _key(KEY_F8)
	_check(spawned_mesh.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(spawned_mesh.material_override.albedo_color.a, 0.35), "ghost opacity survives preset switch")
	var source_material = layer._records[spawned_mesh.get_instance_id()]["material"]
	await _key(KEY_F6)
	_check(spawned_mesh.material_override == source_material, "new entity restores its own original material")
	_check(is_equal_approx(spawned_mesh.material_override.albedo_color.a, 0.35), "ghost opacity survives return to original")
	spawned.set_ghost(false)
	spawned.queue_free()
	await create_timer(1.2).timeout
	_check(not layer._models.has(spawned.get_instance_id()) if is_instance_valid(spawned) else true, "freed entity is released")
	await _key(KEY_F7)
	# Rebuild the presentation scene while active (lobby -> game transition).
	var old_view_id: int = game.view.get_instance_id()
	game._on_back_to_lobby()
	await create_timer(0.15).timeout
	_check(game.showcase != null, "return to lobby works under active preset")
	game._start_game()
	await create_timer(0.4).timeout
	_check(game.view != null and game.view.get_instance_id() != old_view_id, "new game builds under active preset")
	_check(layer.current_preset == 1, "preset persists across game/lobby transition")
	await _key(KEY_F6)
	_check(_all_restored(), "original look restores after scene transition")
	var path := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path)
	var report := {"passed": failures.is_empty(), "failures": failures, "renderer": DisplayServer.get_name(), "screenshots": DisplayServer.get_name() != "headless", "requirements": ["F6/F7/F8 input", "private overrides", "exact restoration", "unchanged sim/camera", "new entities", "hit flash", "scene transitions"]}
	var file := FileAccess.open(path.path_join("verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CODEX_PRESET_VERIFY: ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _freeze_models(node: Node) -> void:
	if node is UnitModel: node.set_process(false)
	for child in node.get_children(): _freeze_models(child)

func _stage_scene() -> void:
	# Use the game's validated build path for a representative tower/hero/forest view.
	var spot: Dictionary = {}
	for candidate in game.map.spots:
		if candidate["lane"] == 0:
			spot = candidate
			break
	if spot.is_empty(): return
	game.sim.heroes[0].pos = spot["pos"] + Vector2(1.2, 0.8)
	game.sim.request_build(0, spot["id"], "barracks")
	game.sim.debug_spawn(0, "goblin", 3, 0.45)
	game.sim.heroes[0].e_cd = 3.0
	game.last_snap = game.sim.snapshot()
	game.view.apply_snapshot(game.last_snap)
	game.hud.update_state(game.last_snap)
	game.cam.snap_to(game.view._v3(game.sim.heroes[0].pos))
	for tower in game.last_snap["t"]:
		if tower[0] == spot["id"]:
			game.hud.open_menu(spot["id"], tower)
			game.hud.menu_press(0)
			break

func _first_type(node: Node, kind: String):
	if node.is_class(kind): return node
	for child in node.get_children():
		var result = _first_type(child, kind)
		if result != null: return result
	return null

func _key(key: int) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = key
	Input.parse_input_event(release)
	for i in 3: await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path)
	var image := root.get_texture().get_image()
	_check(image.save_png(path.path_join(name + ".png")) == OK, "capture " + name)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
	print("VERIFY ", "PASS " if condition else "FAIL ", message)

func _all_restored() -> bool:
	for id in layer._records:
		var record: Dictionary = layer._records[id]
		var node = record["node"].get_ref()
		if not is_instance_valid(node): continue
		if node is MeshInstance3D:
			if node.material_override != record["material"] or node.mesh != record["mesh"]: return false
			for i in record["surfaces"].size():
				if node.get_surface_override_material(i) != record["surfaces"][i]: return false
		elif node is MultiMeshInstance3D:
			if node.material_override != record["material"] or node.multimesh != record["multimesh"]: return false
		elif node is WorldEnvironment:
			if node.environment != record["environment"]: return false
		elif node is DirectionalLight3D:
			for property in ["light_color", "light_energy", "shadow_enabled", "shadow_opacity", "shadow_blur", "light_angular_distance", "transform"]:
				if node.get(property) != record[property]: return false
		elif node is Label:
			if node.label_settings != record["label_settings"]: return false
		elif node is Panel or node is Button:
			for style_name in record["styles"]:
				if node.get_theme_stylebox(style_name) != record["styles"][style_name]: return false
	return true
