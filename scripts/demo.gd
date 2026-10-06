class_name Demo
extends CanvasLayer
## Scripted feature showcase (run with `-- --demo`, record with `--write-movie`).
## Drives the real input path with a fake cursor and shows feature captions.

var game: Node
var cursor: DemoCursor
var cap_panel: Panel
var cap_num: Label
var cap_text: Label
var kfont: SystemFont
var _n := 0

func _ready() -> void:
	layer = 20
	kfont = SystemFont.new()
	kfont.font_names = PackedStringArray(["Malgun Gothic", "Segoe UI"])
	kfont.font_weight = 800
	cap_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.22, 0.86)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(4)
	sb.border_color = Color("ffd23f")
	cap_panel.add_theme_stylebox_override("panel", sb)
	cap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(cap_panel, Vector2(0.5, 0), Vector2(-344, 172), Vector2(688, 96))
	add_child(cap_panel)
	cap_num = _label(34, Color("1d1530"))
	var chip := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("ffd23f")
	cs.set_corner_radius_all(22)
	chip.add_theme_stylebox_override("panel", cs)
	chip.position = Vector2(18, 20)
	chip.size = Vector2(56, 56)
	cap_panel.add_child(chip)
	cap_num.position = Vector2(0, 0)
	cap_num.size = Vector2(56, 56)
	chip.add_child(cap_num)
	cap_text = _label(27, Color.WHITE)
	cap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cap_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	cap_text.position = Vector2(90, 6)
	cap_text.size = Vector2(580, 84)
	cap_panel.add_child(cap_text)
	cap_panel.modulate.a = 0.0
	cursor = DemoCursor.new()
	cursor.size = Vector2(64, 64)
	cursor.position = Vector2(560, 900)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cursor)

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	var s := LabelSettings.new()
	s.font = kfont
	s.font_size = size
	s.font_color = col
	s.outline_size = 0 if col != Color.WHITE else 6
	s.outline_color = Color("1d1530")
	l.label_settings = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _place(c: Control, anchor: Vector2, pos: Vector2, sz: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y
	c.pivot_offset = sz * 0.5

# ---------------------------------------------------------------- helpers
func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func caption(text: String) -> void:
	_n += 1
	cap_num.text = str(_n)
	cap_text.text = text
	cap_panel.modulate.a = 1.0
	cap_panel.scale = Vector2(0.6, 0.6)
	var tw := cap_panel.create_tween()
	tw.tween_property(cap_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_caption() -> void:
	var tw := cap_panel.create_tween()
	tw.tween_property(cap_panel, "modulate:a", 0.0, 0.25)

func move_to(p: Vector2, dur := 0.5) -> void:
	var tw := cursor.create_tween()
	tw.tween_property(cursor, "position", p, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished

func _btn(pressed: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	game._unhandled_input(e)

func drag(from_world: Vector3, to_world: Vector3, dur := 0.9) -> void:
	var a: Vector2 = game.cam.unproject_position(from_world)
	var b: Vector2 = game.cam.unproject_position(to_world)
	await move_to(a, 0.55)
	cursor.press(true)
	_btn(true, a)
	await wait(0.18)
	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k := clampf(t / dur, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var p := a.lerp(b, k) + Vector2(0, -sin(k * PI) * 40.0)
		cursor.position = p
		var m := InputEventMouseMotion.new()
		m.position = p
		game._unhandled_input(m)
		await get_tree().process_frame
	await wait(0.2)
	cursor.press(false)
	_btn(false, b)

func click_button(b: Button) -> void:
	var p := b.get_global_rect().get_center()
	await move_to(p, 0.6)
	cursor.press(true)
	b.button_down.emit()
	await wait(0.16)
	cursor.press(false)
	b.button_up.emit()
	b.pressed.emit()

# ---------------------------------------------------------------- script
func run() -> void:
	var g := game
	g.demo_hold = true
	await title_card("TOY CLASH", "Clash Mini 스타일 오토배틀러 · Godot 프로토타입 시연")
	# deterministic tray for the showcase
	g.shop[0] = ["brawler", "archer", "brawler"]
	g._refresh_tray(true)
	await wait(1.4)

	caption("라운드 시작! 엘릭서 +6, 나무 트레이에 미니 3개가 올라옵니다")
	await wait(2.6)

	caption("트레이의 미니를 드래그해 내 진영에 배치 (엘릭서 소모)")
	await drag(g.world.tray_slots[0], World.tile_pos(1, 3))
	await wait(1.3)

	caption("같은 미니를 겹쳐 놓으면 ★ 스타 업그레이드!")
	await drag(g.world.tray_slots[2], World.tile_pos(1, 3))
	await wait(1.8)

	caption("리롤 버튼으로 트레이를 새로 뽑기 (라운드당 1회 무료)")
	await click_button(g.hud.reroll_btn)
	g.shop[0] = ["giant", "archer", "wizard"]
	g._refresh_tray(true)
	await wait(1.6)

	caption("엘릭서가 모자라면 배치할 수 없어요")
	await drag(g.world.tray_slots[0], World.tile_pos(3, 2))
	await wait(1.5)

	caption("아처는 가장 먼 적을 노리는 원거리 유닛")
	await drag(g.world.tray_slots[1], World.tile_pos(3, 1))
	await wait(1.3)

	caption("배치한 유닛은 드래그로 자리를 옮길 수 있어요")
	await drag(World.tile_pos(1, 3) + Vector3(0, 0.3, 0), World.tile_pos(2, 3))
	await wait(1.2)
	await move_to(Vector2(360, 330), 0.6)
	caption("위쪽 반투명 유닛 = 적의 지난 라운드 배치 (고스트)")
	await wait(2.4)

	caption("준비 완료! FIGHT! → 적 배치 공개와 함께 CLASH!!")
	await click_button(g.hud.fight_btn)
	await move_to(Vector2(640, 1240), 0.5)
	await wait(1.4)
	caption("자동 전투: 유닛이 스스로 이동하고 공격합니다")
	await wait(3.0)
	caption("히어로는 에너지가 차면 슈퍼 스킬 발동 (킹: 그라운드 슬램)")
	await _wait_round_end(32.0)
	caption("라운드 승리 시 깃발 획득 · 먼저 깃발 2개면 매치 승리")
	await wait(2.6)
	caption("다음 라운드: 엘릭서 이월, 적 고스트를 보고 카운터 배치")
	await wait(3.2)
	hide_caption()
	await title_card("TOY CLASH", "Prototype M0 · Made with Godot 4.7")
	get_tree().quit()

func _wait_round_end(max_t: float) -> void:
	var t := 0.0
	while t < max_t and game.state != game.S.RESULT:
		t += get_process_delta_time()
		await get_tree().process_frame
	await wait(0.4)

func title_card(title: String, sub: String) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.08, 0.28, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var t: Label = game.hud.label(title, 120, Data.COL_GOLD, 22)
	t.label_settings.outline_color = Color("5a2a08")
	t.label_settings.shadow_offset = Vector2(0, 10)
	_place(t, Vector2(0.5, 0.5), Vector2(-360, -200), Vector2(720, 170))
	root.add_child(t)
	var s := _label(30, Color.WHITE)
	s.text = sub
	_place(s, Vector2(0.5, 0.5), Vector2(-340, -20), Vector2(680, 60))
	root.add_child(s)
	t.scale = Vector2(2.2, 2.2)
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("pop", -4.0, 0.8)
	await wait(2.3)
	var tw2 := root.create_tween()
	tw2.tween_property(root, "modulate:a", 0.0, 0.45)
	await tw2.finished
	root.queue_free()

class DemoCursor extends Control:
	var down := false
	var _ring := 0.0
	func press(on: bool) -> void:
		down = on
		if on:
			_ring = 1.0
	func _process(delta: float) -> void:
		_ring = maxf(_ring - delta * 3.0, 0.0)
		queue_redraw()
	func _draw() -> void:
		var tip := Vector2(0, 0)
		if _ring > 0.0:
			draw_arc(tip, 18.0 + (1.0 - _ring) * 26.0, 0, TAU, 32, Color(1, 1, 1, _ring), 5.0)
		var s := 0.85 if down else 1.0
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 40), Vector2(10, 31), Vector2(18, 48), Vector2(25, 45), Vector2(17, 29), Vector2(30, 29)])
		var o := PackedVector2Array()
		for p in pts:
			o.append(p * s)
		var sh := PackedVector2Array()
		for p in o:
			sh.append(p + Vector2(3, 5))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
		draw_colored_polygon(o, Color.WHITE)
		o.append(o[0])
		draw_polyline(o, Color("1d1530"), 3.5, true)
