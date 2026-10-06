class_name Hud
extends CanvasLayer
## 2D overlay: top info, HP bars, damage numbers, banners, elixir flask, reroll / fight buttons.
## Style: chunky rounded font, white text, thick dark outline, drop shadow; elastic motion everywhere.

signal reroll_pressed
signal fight_pressed
signal restart_pressed

var cam: Camera3D
var font: SystemFont
var root: Control
var bars := {}                # Unit -> Dictionary
var enemy_flags: Label
var player_flags: Label
var round_label: Label
var timer_label: Label
var timer_ring: RingGauge
var flask: Flask
var elixir_label: Label
var reroll_btn: Button
var reroll_label: Label
var fight_btn: Button
var cost_badges: Array[Control] = []
var flash_rect: ColorRect
var result_panel: Control
var phase_label: Label
var _toast: Label

func _ready() -> void:
	layer = 5
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Lilita One", "Arial Rounded MT Bold", "Segoe UI Black", "Arial Black"])
	font.font_weight = 900
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

# ---------------------------------------------------------------- style helpers
func ls(size: int, color := Color.WHITE, outline := 10, shadow := 5) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = Color("1d1530")
	s.shadow_size = 0
	s.shadow_color = Color(0.1, 0.05, 0.2, 0.55)
	s.shadow_offset = Vector2(0, shadow)
	return s

func label(text: String, size: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = ls(size, color, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func box(color: Color, radius := 12, border := 4, border_col := Color("1d1530")) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.shadow_color = Color(0.1, 0.05, 0.2, 0.35)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, 5)
	sb.anti_aliasing = true
	return sb

func panel(color: Color, rect: Rect2, radius := 12, border := 4) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(color, radius, border))
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func juicy_button(text: String, color: Color, rect: Rect2, fsize := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.pivot_offset = rect.size * 0.5
	b.focus_mode = Control.FOCUS_NONE
	var n := box(color, 22, 5)
	n.shadow_size = 1
	n.shadow_offset = Vector2(0, 7)
	var h := box(color.lightened(0.12), 22, 5)
	h.shadow_size = 1
	h.shadow_offset = Vector2(0, 7)
	var pr := box(color.darkened(0.1), 22, 5)
	var d := box(Color("8a8aa0"), 22, 5)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color("1d1530"))
	b.add_theme_constant_override("outline_size", 10)
	b.button_down.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.88, 0.88), 0.06)
		Sfx.play("click", -6.0))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	return b

func pop_in(c: Control, from := 0.3, dur := 0.45) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func bump(c: Control, amt := 1.3) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * amt
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- layout
## Anchor-aware placement: anchor (0..1) on the full screen, pos/size in pixels relative to that anchor.
func place(c: Control, anchor: Vector2, pos: Vector2, sz: Vector2) -> Control:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y
	c.pivot_offset = sz * 0.5
	return c

func _build_top() -> void:
	# enemy (left)
	var fl := panel(Color(0.1, 0.08, 0.2, 0.45), Rect2(0, 0, 120, 58), 16, 0)
	root.add_child(place(fl, Vector2(0, 0), Vector2(16, 16), Vector2(120, 58)))
	var flag := FlagIcon.new()
	flag.position = Vector2(12, 8)
	flag.size = Vector2(40, 42)
	fl.add_child(flag)
	enemy_flags = label("0", 40)
	enemy_flags.position = Vector2(56, 2)
	enemy_flags.size = Vector2(56, 54)
	fl.add_child(enemy_flags)
	var en := label("RivalBot", 26, Color("ffb0c0"), 8)
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(place(en, Vector2(0, 0), Vector2(20, 76), Vector2(220, 34)))
	# round & timer (right)
	round_label = label("Round 1", 34)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(place(round_label, Vector2(1, 0), Vector2(-236, 14), Vector2(220, 44)))
	var tp := panel(Color(0.1, 0.08, 0.2, 0.55), Rect2(0, 0, 140, 58), 18, 0)
	root.add_child(place(tp, Vector2(1, 0), Vector2(-156, 62), Vector2(140, 58)))
	timer_label = label("25", 38)
	timer_label.position = Vector2(4, 2)
	timer_label.size = Vector2(76, 54)
	timer_label.pivot_offset = timer_label.size * 0.5
	tp.add_child(timer_label)
	timer_ring = RingGauge.new()
	timer_ring.position = Vector2(84, 6)
	timer_ring.size = Vector2(46, 46)
	tp.add_child(timer_ring)
	phase_label = label("", 28, Color("fff4c0"), 8)
	root.add_child(place(phase_label, Vector2(0.5, 0), Vector2(-300, 128), Vector2(600, 40)))

func _build_bottom() -> void:
	# player flag (right, above tray)
	var pf := panel(Color(0.1, 0.08, 0.2, 0.45), Rect2(0, 0, 130, 58), 16, 0)
	root.add_child(place(pf, Vector2(1, 1), Vector2(-150, -440), Vector2(130, 58)))
	var flag := FlagIcon.new()
	flag.position = Vector2(12, 8)
	flag.size = Vector2(40, 42)
	pf.add_child(flag)
	player_flags = label("0", 40)
	player_flags.position = Vector2(56, 2)
	player_flags.size = Vector2(60, 54)
	pf.add_child(player_flags)
	var pn := label("You", 26, Color("bfe4ff"), 8)
	root.add_child(place(pn, Vector2(1, 1), Vector2(-150, -380), Vector2(130, 32)))
	# elixir flask
	flask = Flask.new()
	flask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(place(flask, Vector2(1, 1), Vector2(-172, -330), Vector2(150, 160)))
	elixir_label = label("6", 64, Color.WHITE, 12)
	elixir_label.position = Vector2(0, 32)
	elixir_label.size = Vector2(150, 110)
	elixir_label.pivot_offset = elixir_label.size * 0.5
	flask.add_child(elixir_label)
	# reroll
	reroll_btn = juicy_button("", Color("27c6b0"), Rect2(0, 0, 110, 110), 30)
	var rs := box(Color("27c6b0"), 55, 5)
	rs.shadow_size = 1
	rs.shadow_offset = Vector2(0, 7)
	reroll_btn.add_theme_stylebox_override("normal", rs)
	reroll_btn.add_theme_stylebox_override("hover", box(Color("3ad8c2"), 55, 5))
	reroll_btn.add_theme_stylebox_override("pressed", box(Color("1fa894"), 55, 5))
	reroll_btn.add_theme_stylebox_override("disabled", box(Color("8a8aa0"), 55, 5))
	var ic := RerollIcon.new()
	ic.position = Vector2(22, 20)
	ic.size = Vector2(66, 66)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reroll_btn.add_child(ic)
	reroll_btn.pressed.connect(func(): reroll_pressed.emit())
	root.add_child(place(reroll_btn, Vector2(1, 1), Vector2(-152, -150), Vector2(110, 110)))
	reroll_label = label("x1", 36)
	reroll_label.position = Vector2(58, 62)
	reroll_label.size = Vector2(60, 44)
	reroll_btn.add_child(reroll_label)
	# fight
	fight_btn = juicy_button("FIGHT!", Color("ff9f1c"), Rect2(0, 0, 200, 84), 40)
	fight_btn.pressed.connect(func(): fight_pressed.emit())
	root.add_child(place(fight_btn, Vector2(0, 1), Vector2(40, -116), Vector2(300, 86)))
	# tray cost badges (positioned each frame)
	for i in 3:
		var b := panel(Data.COL_ELIXIR, Rect2(0, 0, 54, 54), 27, 4)
		var l := label("2", 32)
		l.position = Vector2(0, -2)
		l.size = Vector2(54, 54)
		b.add_child(l)
		b.visible = false
		root.add_child(b)
		cost_badges.append(b)
	_toast = label("", 40, Color("ff5f9e"), 10)
	root.add_child(place(_toast, Vector2(0.5, 0.5), Vector2(-300, -40), Vector2(600, 80)))
	_toast.modulate.a = 0.0

# ---------------------------------------------------------------- state setters
func set_round(n: int) -> void:
	round_label.text = "Round %d" % n
	bump(round_label, 1.25)

func set_timer(t: float, total: float) -> void:
	var s := int(ceil(t))
	var txt := "%02d" % s
	if timer_label.text != txt:
		timer_label.text = txt
		if s <= 5 and s > 0:
			timer_label.label_settings.font_color = Color("ff6b6b")
			bump(timer_label, 1.3)
		else:
			timer_label.label_settings.font_color = Color.WHITE
	timer_ring.value = clampf(t / total, 0.0, 1.0)
	timer_ring.queue_redraw()

func set_flags(player: int, enemy: int) -> void:
	if player_flags.text != str(player):
		player_flags.text = str(player)
		bump(player_flags.get_parent(), 1.35)
	if enemy_flags.text != str(enemy):
		enemy_flags.text = str(enemy)
		bump(enemy_flags.get_parent(), 1.35)

func set_elixir(v: int) -> void:
	if elixir_label.text != str(v):
		elixir_label.text = str(v)
		bump(elixir_label, 1.3)
	flask.level = clampf(v / 10.0, 0.0, 1.0)

func set_rerolls(n: int) -> void:
	reroll_label.text = "x%d" % n
	reroll_btn.disabled = n <= 0

func set_deploy_controls(on: bool) -> void:
	fight_btn.visible = on
	reroll_btn.disabled = not on or reroll_label.text == "x0"
	if on:
		pop_in(fight_btn)

func set_phase(text: String) -> void:
	phase_label.text = text

func update_cost_badges(slots: Array, positions: Array[Vector3]) -> void:
	for i in 3:
		var b := cost_badges[i]
		if i < slots.size() and slots[i] != "":
			var was_hidden := not b.visible
			b.visible = true
			var p := cam.unproject_position(positions[i] + Vector3(0.36, 0.0, 0.32))
			b.position = p - b.size * 0.5
			(b.get_child(0) as Label).text = str(Data.get_def(slots[i])["cost"])
			if was_hidden:
				pop_in(b)
		else:
			b.visible = false

# ---------------------------------------------------------------- unit bars
func register_unit(u: Unit) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(84, 22)
	root.add_child(c)
	root.move_child(c, 0)
	var bg := panel(Color("1d1530"), Rect2(14, 2, 70, 18), 8, 0)
	c.add_child(bg)
	var lag := panel(Color("fff4e0"), Rect2(17, 5, 64, 12), 5, 0)
	c.add_child(lag)
	var fill := panel(u.color(), Rect2(17, 5, 64, 12), 5, 0)
	c.add_child(fill)
	var shine := panel(Color(1, 1, 1, 0.35), Rect2(20, 6, 58, 4), 2, 0)
	c.add_child(shine)
	var star := panel(Data.COL_GOLD, Rect2(0, 0, 26, 24), 6, 3)
	c.add_child(star)
	var sl := label(str(u.star), 18, Color("5a3a00"), 0)
	sl.position = Vector2(0, -1)
	sl.size = Vector2(26, 24)
	star.add_child(sl)
	var en: Panel = null
	if u.hero:
		en = panel(Color("ffd23f"), Rect2(17, 20, 0, 6), 3, 0)
		var enbg := panel(Color("1d1530"), Rect2(14, 18, 70, 10), 4, 0)
		c.add_child(enbg)
		c.move_child(enbg, c.get_child_count() - 1)
		c.add_child(en)
	bars[u] = {"c": c, "fill": fill, "lag": lag, "star": sl, "en": en, "lag_v": 1.0, "shown": 1.0}

func unregister_unit(u: Unit) -> void:
	if bars.has(u):
		bars[u]["c"].queue_free()
		bars.erase(u)

func _process(delta: float) -> void:
	if cam == null:
		return
	for key in bars.keys():
		var b: Dictionary = bars[key]
		var u: Unit = key
		var c: Control = b["c"]
		if not is_instance_valid(u) or not u.visible or not u.alive or not u.revealed or u.model.mats.is_empty() or u.model.mats[0].albedo_color.a < 0.9:
			c.visible = false
			continue
		var head := u.global_position + Vector3(0, (0.95 + 0.1) * u.model.scale.y + u.model.position.y, 0)
		if cam.is_position_behind(head):
			c.visible = false
			continue
		c.visible = true
		c.position = cam.unproject_position(head) - Vector2(46, 11)
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		b["shown"] = lerpf(b["shown"], ratio, 1.0 - exp(-delta * 25.0))
		if b["lag_v"] > ratio:
			b["lag_v"] = move_toward(b["lag_v"], ratio, delta * 0.8)
		else:
			b["lag_v"] = ratio
		(b["fill"] as Panel).size.x = 64.0 * b["shown"]
		(b["lag"] as Panel).size.x = 64.0 * b["lag_v"]
		(b["star"] as Label).text = str(u.star)
		if b["en"]:
			(b["en"] as Panel).size.x = 64.0 * u.energy / 100.0
			(b["en"] as Panel).modulate = Color(1.6, 1.6, 1.6) if u.energy >= 99.0 else Color.WHITE

# ---------------------------------------------------------------- floating text
func damage_number(world: Vector3, amount: float, team: int) -> void:
	if cam.is_position_behind(world):
		return
	var txt := str(int(round(amount))) if absf(amount - round(amount)) < 0.05 else "%.1f" % amount
	var col := Color("ffffff") if team == Data.TEAM_ENEMY else Color("ffd0d8")
	var l := label(txt, 30 + int(minf(amount, 8.0) * 2.0), col, 9)
	l.size = Vector2(80, 44)
	var p := cam.unproject_position(world) + Vector2(randf_range(-18, 18), 0)
	l.position = p - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	root.add_child(l)
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 60, 0.7).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(0.9, 0.9), 0.3).set_delay(0.12)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func callout(world: Vector3, text: String, color: Color) -> void:
	var l := label(text, 34, color, 10)
	l.size = Vector2(320, 50)
	var p := cam.unproject_position(world)
	l.position = p - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	root.add_child(l)
	l.scale = Vector2(0.2, 0.2)
	l.rotation = -0.08
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 40, 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

## Big center banner: punch in, hold, puff out.
func banner(text: String, color: Color, hold := 0.8, size := 120, y := 0.0) -> void:
	var l := label(text, size, color, 22)
	l.label_settings.shadow_offset = Vector2(0, 10)
	l.label_settings.outline_color = Color("5a2a08") if color == Data.COL_GOLD else Color("1d1530")
	root.add_child(place(l, Vector2(0.5, 0.5), Vector2(-360, -size * 0.75 + y), Vector2(720, size * 1.5)))
	l.scale = Vector2(2.6, 2.6)
	l.modulate.a = 0.0
	l.rotation = -0.06
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.tween_property(l, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(hold)
	tw.chain().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(l.queue_free)

func flash(a := 0.7, dur := 0.25) -> void:
	flash_rect.color = Color(1, 1, 1, a)
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, dur)

func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	for i in 4:
		tw.tween_property(_toast, "rotation", 0.05 * (1 if i % 2 == 0 else -1), 0.04)
	tw.tween_property(_toast, "rotation", 0.0, 0.04)
	tw.tween_interval(0.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.3)

func show_result(win: bool, draw := false) -> void:
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(result_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.2, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.45, 0.4)
	var txt := "DRAW" if draw else ("VICTORY!" if win else "DEFEAT")
	var col := Color("dfe6ee") if draw else (Data.COL_GOLD if win else Color("ff6b8a"))
	var l := label(txt, 130, col, 24)
	l.label_settings.shadow_offset = Vector2(0, 12)
	result_panel.add_child(place(l, Vector2(0.5, 0.5), Vector2(-360, -260), Vector2(720, 200)))
	pop_in(l, 3.0, 0.5)
	var b := juicy_button("PLAY AGAIN", Color("3fa9f5"), Rect2(0, 0, 340, 100), 42)
	b.pressed.connect(func(): restart_pressed.emit())
	result_panel.add_child(place(b, Vector2(0.5, 0.5), Vector2(-170, 20), Vector2(340, 100)))
	b.scale = Vector2.ZERO
	var tw := b.create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if win:
		var tw2 := l.create_tween().set_loops()
		tw2.tween_property(l, "rotation", 0.04, 0.5).set_trans(Tween.TRANS_SINE)
		tw2.tween_property(l, "rotation", -0.04, 0.5).set_trans(Tween.TRANS_SINE)

# ---------------------------------------------------------------- custom drawn widgets
class RingGauge extends Control:
	var value := 1.0
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5 - 3.0
		draw_circle(c, r + 3.0, Color("1d1530"))
		draw_circle(c, r, Color("e8f4ff"))
		var col := Color("27c6b0") if value > 0.25 else Color("ff6b6b")
		if value > 0.001:
			var pts := PackedVector2Array([c])
			var n := 40
			for i in n + 1:
				var a := -PI * 0.5 + TAU * value * i / n
				pts.append(c + Vector2(cos(a), sin(a)) * (r - 3.0))
			draw_colored_polygon(pts, col)
		draw_circle(c, r * 0.28, Color("1d1530"))

class Flask extends Control:
	var level := 0.6
	var _shown := 0.6
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		_shown = lerpf(_shown, level, 1.0 - exp(-delta * 6.0))
		queue_redraw()
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.58)
		var r := size.x * 0.44
		# neck + cork
		draw_rect(Rect2(c.x - 24, 6, 48, 34), Color("1d1530"))
		draw_rect(Rect2(c.x - 19, 10, 38, 30), Color("cfe8ff"))
		draw_rect(Rect2(c.x - 26, 0, 52, 18), Color("1d1530"))
		draw_rect(Rect2(c.x - 22, 2, 44, 14), Color("d9a066"))
		draw_circle(c, r + 5.0, Color("1d1530"))
		draw_circle(c, r, Color(0.8, 0.9, 1.0, 0.85))
		# liquid: circular segment below a wobbling surface
		var rr := r - 5.0
		var k := clampf(1.0 - 2.0 * _shown, -0.999, 0.999)
		var a0 := asin(k)
		var pts := PackedVector2Array()
		var n := 32
		for i in n + 1:
			var a := lerpf(a0, PI - a0, float(i) / n)
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var y := c.y + rr * k
		var x0 := c.x - rr * cos(a0)
		var x1 := c.x + rr * cos(a0)
		var depth := rr * (1.0 - k)
		var amp := minf(2.5, depth * 0.15)
		for i in range(1, 8):
			var x := lerpf(x0, x1, float(i) / 8.0)
			pts.append(Vector2(x, y + sin(_t * 3.0 + x * 0.08) * amp))
		if _shown > 0.05:
			draw_colored_polygon(pts, Data.COL_ELIXIR)
			draw_circle(Vector2(c.x - rr * 0.35, y + rr * 0.35), rr * 0.12, Color(1, 0.7, 1, 0.5))
		# glass highlight
		draw_arc(c + Vector2(-r * 0.2, -r * 0.2), r * 0.62, PI * 1.05, PI * 1.45, 12, Color(1, 1, 1, 0.8), 7.0)

class FlagIcon extends Control:
	func _draw() -> void:
		draw_rect(Rect2(4, 2, 6, size.y - 4), Color("1d1530"))
		draw_rect(Rect2(6, 4, 3, size.y - 8), Color("fff4e0"))
		var pts := PackedVector2Array([Vector2(8, 4), Vector2(size.x - 2, 12), Vector2(8, 24)])
		draw_colored_polygon(PackedVector2Array([Vector2(6, 1), Vector2(size.x + 2, 12), Vector2(6, 27)]), Color("1d1530"))
		draw_colored_polygon(pts, Color("ffd23f"))

class RerollIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, size.x * 0.34, PI * 0.15, PI * 1.75, 24, Color("1d1530"), 14.0)
		draw_arc(c, size.x * 0.34, PI * 0.15, PI * 1.75, 24, Color.WHITE, 8.0)
		var tip := c + Vector2(cos(PI * 1.75), sin(PI * 1.75)) * size.x * 0.34
		var tri := PackedVector2Array([tip + Vector2(-2, -14), tip + Vector2(16, 4), tip + Vector2(-12, 10)])
		draw_colored_polygon(tri, Color.WHITE)
