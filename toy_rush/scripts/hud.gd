class_name Hud
extends CanvasLayer
## In-game HUD (v0.3 "royal blue" skin matched to the reference):
## glossy blue panels with navy borders, hero portraits, wave banner + horn, compass minimap,
## Q/E tiles with yellow key badges, upgrade/sell card. Also floating texts, bars, result screen.

signal menu_action(action: String, spot: int, kind: String)
signal result_closed

const NAVY := Color("0f1d55")
const BLUE := Color("2a5fd8")
const BLUE_L := Color("4a86f5")
const BLUE_D := Color("1b3f9e")
const GOLD := Color("ffd23f")
const GREEN := Color("4fdc4a")
const RED := Color("f0506e")
const CYAN := Color("3fd3ff")
const LANE_LETTERS := ["N", "E", "S", "W"]

var cam: Camera3D
var map: MapDef
var font: SystemFont
var root: Control
var local_slot := 0
var slots: Array = []
var snap := {}

var lives_l: Label
var gold_l: Label
var wave_l: Label
var timer_l: Label
var lane_rows: Array = []
var minimap: Minimap
var hero_panel: Control
var hp_fill: Panel
var xp_fill: Panel
var hp_text: Label
var lvl_l: Label
var skill_boxes: Array = []
var respawn_l: Label
var prompt_l: Label
var toast_l: Label
var arrows: Array = []
var bars := {}
var menu: Control
var menu_spot := -1
var menu_items: Array = []
var menu_sel := -1
var tip: Panel
var tip_title: Label
var tip_desc: Label
var tip_bars: Array = []
var result_panel: Control
var horn: HornIcon
var _last_gold := -1
var _last_lives := -1

func _ready() -> void:
	layer = 5
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Malgun Gothic", "Segoe UI"])
	font.font_weight = 800
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

func setup(p_map: MapDef, p_slots: Array, p_local: int, p_cam: Camera3D) -> void:
	map = p_map
	slots = p_slots
	local_slot = p_local
	cam = p_cam
	_build_top()
	_build_lanes()
	_build_minimap()
	_build_hero_bar()
	_build_misc()

# ================================================================ style helpers
func ls(size: int, color := Color.WHITE, outline := 8) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = NAVY
	s.shadow_color = Color(0.03, 0.07, 0.25, 0.6)
	s.shadow_offset = Vector2(0, 3)
	return s

func label(text: String, size: int, color := Color.WHITE, outline := 8, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = ls(size, color, outline)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func box(color: Color, radius := 12, border := 3, border_col := NAVY) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.anti_aliasing = true
	return sb

## Signature panel: blue fill, thick navy border, hard drop shadow.
func blue_box(radius := 16, fill := BLUE, border := 4, border_col := NAVY) -> StyleBoxFlat:
	var sb := box(fill, radius, border, border_col)
	sb.shadow_color = Color(0.03, 0.07, 0.25, 0.85)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 5)
	return sb

func panel(color: Color, radius := 12, border := 3) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(color, radius, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func blue_panel(radius := 16, fill := BLUE, border := 4, border_col := NAVY) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", blue_box(radius, fill, border, border_col))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## glossy highlight strip on the top half of a panel
func gloss(parent: Control, sz: Vector2, radius := 12) -> void:
	var g := panel(Color(1, 1, 1, 0.13), radius, 0)
	parent.add_child(at(g, Vector2(6, 5), Vector2(sz.x - 12, sz.y * 0.42)))

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

func at(c: Control, pos: Vector2, sz: Vector2) -> Control:
	c.position = pos
	c.size = sz
	c.pivot_offset = sz * 0.5
	return c

func bump(c: Control, amt := 1.25) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * amt
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func button(text: String, color: Color, fsize := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled"]:
		var c := color
		if st == "hover":
			c = color.lightened(0.12)
		elif st == "pressed":
			c = color.darkened(0.1)
		elif st == "disabled":
			c = Color("8a8aa0")
		b.add_theme_stylebox_override(st, blue_box(18, c, 4))
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", NAVY)
	b.add_theme_constant_override("outline_size", 8)
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2(0.9, 0.9), 0.06)
		Sfx.play("click", -6.0))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	return b

func portrait(hero: String, sz: Vector2, border_col: Color, radius := 14) -> Control:
	var frame := blue_panel(radius, border_col.darkened(0.15), 3, NAVY)
	frame.size = sz
	var tr := TextureRect.new()
	tr.texture = Portraits.get_tex(hero)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(at(tr, Vector2(3, 3), sz - Vector2(6, 6)))
	frame.clip_contents = true
	return frame

# ================================================================ layout
func _build_top() -> void:
	# lives pill
	var lp := blue_panel(26)
	root.add_child(place(lp, Vector2(0, 0), Vector2(14, 12), Vector2(140, 52)))
	gloss(lp, Vector2(140, 52), 20)
	var heart := Icon.new()
	heart.shape = "heart"
	lp.add_child(at(heart, Vector2(6, 4), Vector2(46, 44)))
	lives_l = label("20", 32, Color.WHITE, 8, HORIZONTAL_ALIGNMENT_LEFT)
	lp.add_child(at(lives_l, Vector2(60, 2), Vector2(76, 48)))
	# gold pill
	var gp := blue_panel(26)
	root.add_child(place(gp, Vector2(0, 0), Vector2(164, 12), Vector2(176, 52)))
	gloss(gp, Vector2(176, 52), 20)
	var coin := Icon.new()
	coin.shape = "coin"
	gp.add_child(at(coin, Vector2(6, 4), Vector2(46, 44)))
	gold_l = label("500", 32, Color.WHITE, 8, HORIZONTAL_ALIGNMENT_LEFT)
	gp.add_child(at(gold_l, Vector2(60, 2), Vector2(112, 48)))
	# wave banner (top center)
	var wb := blue_panel(18)
	root.add_child(place(wb, Vector2(0.5, 0), Vector2(-170, 8), Vector2(300, 54)))
	gloss(wb, Vector2(300, 54), 14)
	var skull := Icon.new()
	skull.shape = "skull"
	wb.add_child(at(skull, Vector2(16, 6), Vector2(42, 42)))
	wave_l = label("웨이브 0/10", 30, Color.WHITE, 8)
	wb.add_child(at(wave_l, Vector2(60, 2), Vector2(230, 50)))
	var tab := blue_panel(12, BLUE_D, 3)
	root.add_child(place(tab, Vector2(0.5, 0), Vector2(-120, 58), Vector2(200, 34)))
	timer_l = label("", 19, Color.WHITE, 6)
	tab.add_child(at(timer_l, Vector2(0, 0), Vector2(200, 32)))
	horn = HornIcon.new()
	horn.font = font
	root.add_child(place(horn, Vector2(0.5, 0), Vector2(126, 2), Vector2(78, 72)))

func _build_lanes() -> void:
	for k in 4:
		var mine := k == local_slot
		var row := blue_panel(14, BLUE_L if mine else BLUE, 4, CYAN.lightened(0.4) if mine else NAVY)
		root.add_child(place(row, Vector2(0, 0), Vector2(32 if mine else 14, 82 + k * 72), Vector2(290, 62)))
		gloss(row, Vector2(290, 62), 10)
		var badge := blue_panel(10, Data.PLAYER_COLORS[k], 3)
		row.add_child(at(badge, Vector2(-6, 6), Vector2(40, 50)))
		var letter := label(LANE_LETTERS[k], 26, Color.WHITE, 7)
		badge.add_child(at(letter, Vector2(0, 0), Vector2(40, 50)))
		var hk: String = slots[k]["hero"]
		var pt := portrait(hk, Vector2(52, 52), Data.PLAYER_COLORS[k], 10)
		row.add_child(at(pt, Vector2(38, 5), Vector2(52, 52)))
		var name_l := label(Data.HEROES[hk]["name"], 20, Color.WHITE, 6, HORIZONTAL_ALIGNMENT_LEFT)
		row.add_child(at(name_l, Vector2(98, 4), Vector2(120, 26)))
		var who := label(slots[k]["name"], 13, Color("cfe0ff"), 4, HORIZONTAL_ALIGNMENT_LEFT)
		row.add_child(at(who, Vector2(186, 6), Vector2(100, 22)))
		var bar_bg := panel(NAVY, 6, 0)
		row.add_child(at(bar_bg, Vector2(98, 32), Vector2(150, 18)))
		var fill := panel(GREEN, 5, 0)
		row.add_child(at(fill, Vector2(101, 35), Vector2(144, 12)))
		var shine := panel(Color(1, 1, 1, 0.3), 3, 0)
		row.add_child(at(shine, Vector2(104, 36), Vector2(138, 4)))
		var cnt := label("", 15, Color("ffd0d8"), 5, HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(at(cnt, Vector2(232, 30), Vector2(54, 22)))
		if mine:
			var arrow := label("▶", 22, Color.WHITE, 6)
			root.add_child(place(arrow, Vector2(0, 0), Vector2(4, 98 + k * 72), Vector2(28, 30)))
		lane_rows.append({"row": row, "fill": fill, "cnt": cnt, "mine": mine})

func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.map = map
	minimap.hud = self
	minimap.font = font
	root.add_child(place(minimap, Vector2(1, 0), Vector2(-268, 8), Vector2(256, 256)))

func _build_hero_bar() -> void:
	var hk: String = slots[local_slot]["hero"]
	var col: Color = Data.PLAYER_COLORS[local_slot]
	hero_panel = blue_panel(22)
	root.add_child(place(hero_panel, Vector2(0.5, 1), Vector2(-350, -116), Vector2(720, 106)))
	gloss(hero_panel, Vector2(720, 106), 18)
	var pt := portrait(hk, Vector2(124, 124), col, 22)
	root.add_child(place(pt, Vector2(0.5, 1), Vector2(-368, -144), Vector2(124, 124)))
	var nm := label(Data.HEROES[hk]["name"], 30, Color.WHITE, 8, HORIZONTAL_ALIGNMENT_LEFT)
	hero_panel.add_child(at(nm, Vector2(124, 6), Vector2(110, 40)))
	var lv_bg := blue_panel(14, BLUE_L, 3)
	hero_panel.add_child(at(lv_bg, Vector2(216, 10), Vector2(96, 32)))
	lvl_l = label("Lv. 1", 20, Color.WHITE, 6)
	lv_bg.add_child(at(lvl_l, Vector2(0, 0), Vector2(96, 32)))
	var hb := panel(NAVY, 9, 0)
	hero_panel.add_child(at(hb, Vector2(124, 50), Vector2(258, 28)))
	hp_fill = panel(GREEN, 7, 0)
	hero_panel.add_child(at(hp_fill, Vector2(128, 54), Vector2(250, 20)))
	var shine := panel(Color(1, 1, 1, 0.32), 4, 0)
	hero_panel.add_child(at(shine, Vector2(132, 55), Vector2(242, 6)))
	hp_text = label("", 18, Color.WHITE, 6)
	hero_panel.add_child(at(hp_text, Vector2(124, 50), Vector2(258, 28)))
	var xb := panel(NAVY, 5, 0)
	hero_panel.add_child(at(xb, Vector2(124, 84), Vector2(258, 12)))
	xp_fill = panel(GOLD, 4, 0)
	hero_panel.add_child(at(xp_fill, Vector2(127, 86), Vector2(0, 8)))
	var keys := ["Q", "E", "SPACE"]
	for i in 3:
		var sb := SkillBox.new()
		sb.key = keys[i]
		sb.hero = hk
		sb.title = Data.HEROES[hk][keys[i].to_lower()]["name"]
		sb.font = font
		hero_panel.add_child(at(sb, Vector2(396 + i * 106, -18), Vector2(100 if i < 2 else 112, 116)))
		skill_boxes.append(sb)
	respawn_l = label("", 28, Color("ffc0cb"), 8)
	root.add_child(place(respawn_l, Vector2(0.5, 1), Vector2(-250, -196), Vector2(500, 40)))

func _build_misc() -> void:
	prompt_l = label("", 24, Color("fff4c0"), 8)
	root.add_child(place(prompt_l, Vector2(0.5, 1), Vector2(-300, -178), Vector2(600, 36)))
	toast_l = label("", 30, Color.WHITE, 9)
	root.add_child(place(toast_l, Vector2(0.5, 0), Vector2(-400, 100), Vector2(800, 50)))
	toast_l.modulate.a = 0.0
	for k in 4:
		var a := DangerArrow.new()
		a.color = Data.PLAYER_COLORS[k]
		a.size = Vector2(54, 54)
		a.visible = false
		root.add_child(a)
		arrows.append(a)
	tip = blue_panel(18, BLUE_D, 4)
	tip.visible = false
	root.add_child(tip)
	tip.size = Vector2(320, 180)
	tip_title = label("", 24, Color.WHITE, 6, HORIZONTAL_ALIGNMENT_LEFT)
	tip.add_child(at(tip_title, Vector2(16, 8), Vector2(296, 32)))
	tip_desc = label("", 16, Color("dce8ff"), 4, HORIZONTAL_ALIGNMENT_LEFT)
	tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tip.add_child(at(tip_desc, Vector2(16, 40), Vector2(296, 48)))

# ================================================================ per-frame update
func update_state(s: Dictionary) -> void:
	snap = s
	var g: int = s.get("g", 0)
	var l: int = s.get("l", 0)
	if g != _last_gold:
		gold_l.text = str(g)
		if _last_gold >= 0:
			bump(gold_l, 1.15)
		_last_gold = g
	if l != _last_lives:
		lives_l.text = str(l)
		if _last_lives >= 0:
			bump(lives_l, 1.4)
			lives_l.label_settings.font_color = Color("ff9aac")
			get_tree().create_timer(0.6).timeout.connect(func(): lives_l.label_settings.font_color = Color.WHITE)
		_last_lives = l
	wave_l.text = "웨이브 %d/%d" % [s.get("w", 0), s.get("wn", 10)]
	var wt: float = s.get("wt", -1.0)
	var running: bool = s.get("ph", "") != "won" and s.get("ph", "") != "lost"
	if wt >= 0.0 and running:
		var bonus := int(ceil(wt)) if s.get("w", 0) > 0 else 0
		timer_l.text = "다음 웨이브 %d초%s" % [int(ceil(wt)), ("  +%dG" % bonus) if bonus > 0 else ""]
		horn.active = true
	else:
		timer_l.text = "웨이브 진행 중"
		horn.active = false
	var d: PackedFloat32Array = s.get("d", PackedFloat32Array([0, 0, 0, 0]))
	var counts := [0, 0, 0, 0]
	var es: PackedFloat32Array = s.get("e", PackedFloat32Array())
	var i := 0
	while i + 7 < es.size():
		counts[map.lane_of_point(Vector2(es[i + 2], es[i + 3]))] += 1
		i += 8
	var hs: Array = s.get("h", [])
	for k in 4:
		var r: Dictionary = lane_rows[k]
		if hs.size() > k:
			var hrow: Array = hs[k]
			var ratio: float = 0.0 if hrow[6] == 1 else clampf(hrow[4] / maxf(hrow[5], 1.0), 0.0, 1.0)
			(r["fill"] as Panel).size.x = 144.0 * ratio
			(r["fill"] as Panel).add_theme_stylebox_override("panel", box(GREEN if ratio > 0.35 else RED, 5, 0))
		(r["cnt"] as Label).text = "적 %d" % counts[k] if counts[k] > 0 else ""
		var row: Panel = r["row"]
		var hot: bool = d[k] > 0.6
		var pulse := fmod(Time.get_ticks_msec() / 280.0, 2.0) < 1.0
		var border: Color = (CYAN.lightened(0.4) if r["mine"] else NAVY)
		if hot:
			border = RED if pulse else Color("ffb0c0")
		row.add_theme_stylebox_override("panel", blue_box(14, BLUE_L if r["mine"] else BLUE, 4, border))
	if hs.size() > local_slot:
		var h: Array = hs[local_slot]
		var ratio2: float = clampf(h[4] / maxf(h[5], 1.0), 0.0, 1.0)
		hp_fill.size.x = 250.0 * ratio2
		hp_fill.add_theme_stylebox_override("panel", box(GREEN if ratio2 > 0.35 else RED, 7, 0))
		hp_text.text = "%d / %d" % [int(h[4]), int(h[5])]
		var lv_txt := "Lv. %d" % int(h[8])
		if lvl_l.text != lv_txt:
			lvl_l.text = lv_txt
			bump(lvl_l.get_parent(), 1.4)
		xp_fill.size.x = 252.0 * float(h[9])
		var qcd: float = Data.HEROES[slots[local_slot]["hero"]]["q"]["cd"]
		var ecd: float = Data.HEROES[slots[local_slot]["hero"]]["e"]["cd"]
		(skill_boxes[0] as SkillBox).cd = h[10]
		(skill_boxes[0] as SkillBox).secs = h[10] * qcd
		(skill_boxes[1] as SkillBox).cd = h[11]
		(skill_boxes[1] as SkillBox).secs = h[11] * ecd
		if h.size() > 16:
			var scd: float = Data.HEROES[slots[local_slot]["hero"]]["space"]["cd"]
			(skill_boxes[2] as SkillBox).cd = h[16]
			(skill_boxes[2] as SkillBox).secs = h[16] * scd
		respawn_l.text = "부활까지 %d초" % int(ceil(h[7])) if h[6] == 1 else ""
	minimap.queue_redraw()
	_update_arrows(d)

func _update_arrows(d: PackedFloat32Array) -> void:
	var vp := root.get_viewport_rect().size
	for k in 4:
		var a: DangerArrow = arrows[k]
		if k == local_slot or d[k] < 0.55:
			a.visible = false
			continue
		var world := map.pos_at(k, map.length(k) * 0.6)
		var w3 := Vector3(world.x, 0, world.y)
		var sp := cam.unproject_position(w3)
		var on_screen := not cam.is_position_behind(w3) and Rect2(Vector2(60, 60), vp - Vector2(120, 120)).has_point(sp)
		if on_screen:
			a.visible = false
			continue
		a.visible = true
		var c := vp * 0.5
		var dir := (sp - c).normalized()
		if cam.is_position_behind(w3):
			dir = -dir
		var t := minf((vp.x * 0.5 - 50.0) / maxf(absf(dir.x), 0.001), (vp.y * 0.5 - 50.0) / maxf(absf(dir.y), 0.001))
		a.position = c + dir * t - a.size * 0.5
		a.rotation = dir.angle()
		a.pivot_offset = a.size * 0.5
		a.pulse = fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0

func set_prompt(text: String) -> void:
	prompt_l.text = text

# ================================================================ bars & popups
func bar(id: String, world: Vector3, ratio: float, color: Color, w: int, name_txt: String) -> void:
	var b = bars.get(id)
	if b == null:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)
		root.move_child(c, 0)
		var bg := panel(NAVY, 5, 0)
		c.add_child(at(bg, Vector2(0, 0), Vector2(w, 12)))
		var fill := panel(color, 4, 0)
		c.add_child(at(fill, Vector2(2, 2), Vector2(w - 4, 8)))
		var shine := panel(Color(1, 1, 1, 0.3), 2, 0)
		c.add_child(at(shine, Vector2(4, 3), Vector2(w - 8, 3)))
		if name_txt != "":
			var nl := label(name_txt, 15, Color.WHITE, 5)
			c.add_child(at(nl, Vector2(-30, -21), Vector2(w + 60, 18)))
		b = {"c": c, "fill": fill, "w": w, "frame": 0}
		bars[id] = b
	var cc: Control = b["c"]
	if cam.is_position_behind(world):
		cc.visible = false
		return
	cc.visible = true
	cc.position = cam.unproject_position(world) - Vector2(b["w"] * 0.5, 6)
	(b["fill"] as Panel).size.x = (b["w"] - 4) * clampf(ratio, 0.0, 1.0)
	b["frame"] = Engine.get_process_frames()

func _process(_delta: float) -> void:
	var f := Engine.get_process_frames()
	for id in bars.keys():
		var b: Dictionary = bars[id]
		if f - b["frame"] > 2:
			(b["c"] as Control).queue_free()
			bars.erase(id)
	if menu and menu_spot >= 0:
		_position_menu()

func _float_text(world: Vector3, text: String, size: int, col: Color, rise := 50.0, life := 0.8) -> void:
	if cam.is_position_behind(world):
		return
	var l := label(text, size, col, 7)
	l.size = Vector2(160, 40)
	l.position = cam.unproject_position(world) - l.size * 0.5 + Vector2(randf_range(-10, 10), 0)
	l.pivot_offset = l.size * 0.5
	root.add_child(l)
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - rise, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(0.9, 0.9), 0.3).set_delay(0.12)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(life - 0.25)
	tw.chain().tween_callback(l.queue_free)

func damage_number(world: Vector3, amount: float, magic := false, col := Color(-1, 0, 0), prefix := "", mine := true) -> void:
	var c := col if col.r >= 0.0 else (Color("e8c0ff") if magic else Color.WHITE)
	var size := 18 + int(minf(amount, 80.0) * 0.22)
	if not mine:
		size = 14 + int(minf(amount, 80.0) * 0.1)
		c = c.lerp(Color("b8c4e8"), 0.5)
	_float_text(world, prefix + str(int(round(amount))), size, c, 30.0, 0.5)

func gold_pop(world: Vector3, amount: int) -> void:
	_float_text(world, "+%d" % amount, 22, Color("ffe27a"), 60.0, 0.9)

func callout(world: Vector3, text: String, col: Color) -> void:
	_float_text(world, text, 26, col, 45.0, 1.1)

func banner(text: String, color: Color, hold := 0.8, size := 96) -> void:
	var l := label(text, size, color, 18)
	l.label_settings.shadow_offset = Vector2(0, 8)
	root.add_child(place(l, Vector2(0.5, 0.5), Vector2(-500, -size * 0.75 - 120), Vector2(1000, size * 1.5)))
	l.scale = Vector2(2.4, 2.4)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(hold)
	tw.chain().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(l.queue_free)

func wave_banner(n: int) -> void:
	banner("WAVE %d" % n, Color.WHITE if n < 10 else Color("ff8aa0"), 0.7, 90)
	bump(wave_l.get_parent(), 1.2)

func toast(text: String, col := Color.WHITE) -> void:
	toast_l.text = text
	toast_l.label_settings.font_color = col
	toast_l.modulate.a = 1.0
	bump(toast_l, 1.2)
	var tw := toast_l.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(toast_l, "modulate:a", 0.0, 0.4)

func leak_alert(lane: int, n: int) -> void:
	toast("%s 라인 돌파! 생명 -%d" % [Data.LANE_NAMES[lane], n], Color("ff9aac"))
	bump(lane_rows[lane]["row"], 1.12)

# ================================================================ ring menu (build / upgrade / sell)
func menu_open() -> bool:
	return menu != null and menu_spot >= 0

func open_menu(spot: int, tower: Array) -> void:
	close_menu()
	menu_spot = spot
	menu_sel = -1
	menu = Control.new()
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	var ring := RingBg.new()
	ring.size = Vector2(240, 240)
	ring.position = -ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(ring)
	menu_items.clear()
	var offs := [Vector2(0, -110), Vector2(110, 0), Vector2(0, 110), Vector2(-110, 0)]
	if tower.is_empty():
		for i in 4:
			var kind: String = Data.TOWER_ORDER[i]
			var cost: int = Data.TOWERS[kind]["cost"][0]
			menu_items.append({"action": "build", "kind": kind, "cost": cost, "off": offs[i], "key": str(i + 1),
				"title": Data.TOWERS[kind]["name"], "desc": Data.TOWERS[kind]["desc"], "level": 0})
	else:
		var kind2: String = Data.TOWER_ORDER[tower[1]]
		var lvl: int = tower[2]
		if lvl < 3:
			var c2: int = Data.TOWERS[kind2]["cost"][lvl]
			menu_items.append({"action": "upgrade", "kind": kind2, "cost": c2, "off": Vector2(0, -112), "key": "1",
				"title": "%s Lv.%d → Lv.%d" % [Data.TOWERS[kind2]["name"], lvl, lvl + 1], "desc": Data.TOWERS[kind2]["desc"], "level": lvl})
		var refund := int(round(Data.tower_total_cost(kind2, lvl) * Data.SELL_RATIO))
		menu_items.append({"action": "sell", "kind": kind2, "cost": -refund, "off": Vector2(64, 92), "key": "2" if lvl < 3 else "1",
			"title": "%s Lv.%d" % [Data.TOWERS[kind2]["name"], lvl], "desc": "판매 시 투자액의 60%%를 돌려받습니다", "level": lvl})
	for it in menu_items:
		var b := MenuButtonW.new()
		b.item = it
		b.hud = self
		b.size = Vector2(88, 88)
		b.position = it["off"] - b.size * 0.5
		menu.add_child(b)
		it["node"] = b
		b.scale = Vector2.ZERO
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ring.scale = Vector2(0.3, 0.3)
	ring.pivot_offset = ring.size * 0.5
	ring.create_tween().tween_property(ring, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_position_menu()
	if not tower.is_empty():
		_show_tip_tower()
	Sfx.play("pop", -8.0, 1.4)

func close_menu() -> void:
	if menu:
		menu.queue_free()
	menu = null
	menu_spot = -1
	menu_sel = -1
	tip.visible = false
	for b in tip_bars:
		b.queue_free()
	tip_bars.clear()

func _position_menu() -> void:
	var sp: Vector2 = map.spots[menu_spot]["pos"]
	menu.position = cam.unproject_position(Vector3(sp.x, 1.0, sp.y))
	if tip.visible:
		tip.position = menu.position + Vector2(140, -96)

func _stat_line(kind: String, lvl: int) -> String:
	var d: Dictionary = Data.TOWERS[kind]
	if kind == "barracks":
		return "병사 3명 · 길 막기 · HP %d" % int(d["soldier_hp"][lvl])
	return "공격 %d · %.1f초 · 사거리 %.1f" % [int(d["dmg"][lvl]), d["interval"][lvl], d["range"][lvl]]

## upgrade/sell card like the reference (title, stat line, yellow upgrade bar, red sell bar)
func _show_tip_tower() -> void:
	var up: Dictionary = {}
	var sell: Dictionary = {}
	for it in menu_items:
		if it["action"] == "upgrade":
			up = it
		elif it["action"] == "sell":
			sell = it
	var first: Dictionary = up if not up.is_empty() else sell
	tip_title.text = first["title"]
	tip_desc.text = _stat_line(first["kind"], mini(first["level"], 2))
	var y := 92.0
	for it in [up, sell]:
		if it.is_empty():
			continue
		var tb := TipBar.new()
		tb.item = it
		tb.hud = self
		tip.add_child(at(tb, Vector2(14, y), Vector2(292, 40)))
		tip_bars.append(tb)
		y += 46.0
	tip.size = Vector2(320, y + 6)
	tip.visible = true
	_position_menu()

## keyboard 1..4 / click. First press selects (tooltip + range preview), second confirms.
func menu_press(idx: int) -> void:
	if idx < 0 or idx >= menu_items.size():
		return
	var it: Dictionary = menu_items[idx]
	if menu_sel == idx:
		menu_action.emit(it["action"], menu_spot, it["kind"])
		close_menu()
		return
	menu_sel = idx
	for j in menu_items.size():
		(menu_items[j]["node"] as MenuButtonW).selected = j == idx
		(menu_items[j]["node"] as MenuButtonW).queue_redraw()
	for tb in tip_bars:
		(tb as TipBar).queue_redraw()
	if it["action"] == "build":
		for b in tip_bars:
			b.queue_free()
		tip_bars.clear()
		tip_title.text = it["title"]
		tip_desc.text = it["desc"] + "\n" + _stat_line(it["kind"], 0)
		var tb := TipBar.new()
		tb.item = it
		tb.hud = self
		tip.add_child(at(tb, Vector2(14, 92), Vector2(292, 40)))
		tip_bars.append(tb)
		tip.size = Vector2(320, 140)
		tip.visible = true
		_position_menu()
	Sfx.play("click", -6.0, 1.2)

func selected_range() -> float:
	if menu_sel < 0 or menu_sel >= menu_items.size():
		return 0.0
	var it: Dictionary = menu_items[menu_sel]
	if it["action"] == "sell":
		return 0.0
	return Data.TOWERS[it["kind"]]["range"][mini(it["level"], 2)]

# ================================================================ result
func show_result(won: bool, s: Dictionary, can_restart: bool) -> void:
	if result_panel:
		return
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(result_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.25, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.55, 0.5)
	var card := blue_panel(28)
	result_panel.add_child(place(card, Vector2(0.5, 0.5), Vector2(-360, -250), Vector2(720, 470)))
	gloss(card, Vector2(720, 470), 24)
	var title := label("승리!" if won else "패배...", 110, GOLD if won else Color("ff9aac"), 20)
	result_panel.add_child(place(title, Vector2(0.5, 0.5), Vector2(-500, -300), Vector2(1000, 160)))
	bump(title, 2.2)
	var l: int = s.get("l", 0)
	var stars := 0
	if won:
		stars = 3 if l >= 18 else (2 if l >= 10 else 1)
	var st := StarRow.new()
	st.count = stars
	result_panel.add_child(place(st, Vector2(0.5, 0.5), Vector2(-180, -120), Vector2(360, 100)))
	var stt: Dictionary = s.get("st", {})
	var info := label("남은 생명 %d  ·  처치 %d  ·  돌파 %d\n건설 %d  ·  웨이브 %d/%d" % [l, stt.get("kills", 0), stt.get("leaks", 0), stt.get("built", 0), s.get("w", 0), s.get("wn", 10)], 26, Color.WHITE, 7)
	result_panel.add_child(place(info, Vector2(0.5, 0.5), Vector2(-500, 0), Vector2(1000, 80)))
	var b := button("로비로 돌아가기" if can_restart else "호스트를 기다리는 중...", Color("ffb21f"), 30)
	b.disabled = not can_restart
	b.pressed.connect(func(): result_closed.emit())
	result_panel.add_child(place(b, Vector2(0.5, 0.5), Vector2(-170, 110), Vector2(340, 80)))

# ================================================================ custom widgets
class Icon extends Control:
	var shape := "coin"
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.42
		match shape:
			"heart":
				var pts := PackedVector2Array()
				for i in 40:
					var t := TAU * i / 40.0
					var x := 16.0 * pow(sin(t), 3)
					var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
					pts.append(c + Vector2(x, y) * r / 16.0)
				var o := PackedVector2Array()
				for p in pts:
					o.append(c + (p - c) * 1.2)
				draw_colored_polygon(o, Color("0f1d55"))
				draw_colored_polygon(pts, Color("ff5ea8"))
				draw_circle(c + Vector2(-r * 0.38, -r * 0.3), r * 0.2, Color(1, 1, 1, 0.75))
			"coin":
				draw_circle(c, r + 3, Color("0f1d55"))
				draw_circle(c, r, Color("ffb21f"))
				draw_circle(c, r * 0.72, Color("ffd84a"))
				draw_arc(c, r * 0.5, PI * 0.8, PI * 1.6, 12, Color("ffb21f"), 3.0)
				draw_circle(c + Vector2(-r * 0.32, -r * 0.32), r * 0.16, Color(1, 1, 1, 0.8))
			"skull":
				draw_circle(c + Vector2(0, -2), r + 3, Color("0f1d55"))
				draw_circle(c + Vector2(0, -2), r, Color("ffffff"))
				draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.4), Vector2(r, r * 0.55)), Color("ffffff"))
				draw_circle(c + Vector2(-r * 0.38, -2), r * 0.27, Color("0f1d55"))
				draw_circle(c + Vector2(r * 0.38, -2), r * 0.27, Color("0f1d55"))

class HornIcon extends Control:
	var active := true
	var font: Font
	var _t := 0.0
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var wob := sin(_t * 6.0) * 0.08 if active else 0.0
		draw_set_transform(Vector2(34, 36), -0.35 + wob, Vector2.ONE)
		var body := PackedVector2Array([Vector2(-26, -6), Vector2(14, -22), Vector2(22, -22), Vector2(22, 22), Vector2(14, 22), Vector2(-26, 6)])
		var o := PackedVector2Array()
		for p in body:
			o.append(p * 1.15)
		draw_colored_polygon(o, Color("0f1d55"))
		draw_colored_polygon(body, Color("ffc21f") if active else Color("9a9ab0"))
		draw_rect(Rect2(Vector2(-30, -8), Vector2(10, 16)), Color("ffe27a") if active else Color("c0c0d0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(62, 52), 15, Color("0f1d55"))
		draw_circle(Vector2(62, 52), 12, Color("2a5fd8"))
		draw_string_outline(font, Vector2(48, 60), "F", HORIZONTAL_ALIGNMENT_CENTER, 28, 20, 4, Color("0f1d55"))
		draw_string(font, Vector2(48, 60), "F", HORIZONTAL_ALIGNMENT_CENTER, 28, 20, Color.WHITE)

class SkillBox extends Control:
	var key := "Q"
	var hero := ""
	var title := ""
	var font: Font
	var cd := 0.0
	var secs := 0.0
	var _ready_flash := 0.0
	var _was := 0.0
	func _process(delta: float) -> void:
		if _was > 0.001 and cd <= 0.001:
			_ready_flash = 1.0
			Sfx.play("tick", -12.0, 1.6)
		_was = cd
		_ready_flash = maxf(_ready_flash - delta * 2.5, 0.0)
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2(4, 18), Vector2(size.x - 8, 84))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("3a7cf0") if cd <= 0.001 else Color("27458f")
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(4)
		sb.border_color = Color("0f1d55") if _ready_flash <= 0.0 else Color(1, 1, 0.7)
		sb.shadow_color = Color(0.03, 0.07, 0.25, 0.85)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 4)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		draw_rect(Rect2(r.position + Vector2(8, 6), Vector2(r.size.x - 16, 26)), Color(1, 1, 1, 0.12))
		SkillGlyph.draw_glyph(self, hero, key, r.get_center() + Vector2(0, 2), 26.0, cd <= 0.001)
		if cd > 0.001:
			var c := r.get_center()
			var pts := PackedVector2Array([c])
			for i in 33:
				var a := -PI * 0.5 + TAU * cd * i / 32.0
				pts.append(c + Vector2(cos(a), sin(a)) * 40.0)
			draw_colored_polygon(pts, Color(0.02, 0.05, 0.2, 0.5))
			var t := "%ds" % int(ceil(secs))
			draw_string_outline(font, Vector2(r.position.x, r.end.y - 8), t, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 24, 6, Color("0f1d55"))
			draw_string(font, Vector2(r.position.x, r.end.y - 8), t, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, 24, Color.WHITE)
		# yellow key badge
		var kb := StyleBoxFlat.new()
		kb.bg_color = Color("ffd23f")
		kb.set_corner_radius_all(8)
		kb.set_border_width_all(3)
		kb.border_color = Color("0f1d55")
		var kw := 36.0 if key.length() == 1 else 74.0
		draw_style_box(kb, Rect2(Vector2(0, 4), Vector2(kw, 34)))
		draw_string(font, Vector2(0, 31), key, HORIZONTAL_ALIGNMENT_CENTER, kw, 24 if key.length() == 1 else 17, Color("0f1d55"))

## Tiny vector icons for each hero skill (reference shows pictogram skill tiles).
class SkillGlyph:
	static func draw_glyph(ci: CanvasItem, hero: String, key: String, c: Vector2, s: float, on: bool) -> void:
		var w := Color.WHITE if on else Color(0.8, 0.85, 1.0)
		var ink := Color("0f1d55")
		var id := hero + key
		match id:
			"kingQ":   # ground slam: fist + burst
				for i in 8:
					var a := TAU * i / 8.0
					ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s * 0.95, w, 4.0)
				ci.draw_circle(c, s * 0.45, ink)
				ci.draw_circle(c, s * 0.36, Color("ffd23f"))
			"kingE":   # shout: sound arcs
				ci.draw_circle(c + Vector2(-s * 0.4, 0), s * 0.22, w)
				for i in 3:
					ci.draw_arc(c + Vector2(-s * 0.4, 0), s * (0.45 + i * 0.25), -0.8, 0.8, 10, w, 4.0)
			"queenQ":  # volley: three arrows
				for i in 3:
					var o := c + Vector2(-s * 0.75 + i * s * 0.42, s * 0.55)
					var tip := o + Vector2(s * 0.35, -s * 0.95)
					ci.draw_line(o, tip, w, 4.0)
					ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, 6), tip + Vector2(4, -6), tip + Vector2(7, 8)]), w)
			"queenE":  # piercing arrow: one long arrow + glow
				ci.draw_line(c + Vector2(-s * 0.95, s * 0.5), c + Vector2(s * 0.8, -s * 0.45), Color(1, 0.8, 1, 0.5), 12.0)
				ci.draw_line(c + Vector2(-s * 0.95, s * 0.5), c + Vector2(s * 0.8, -s * 0.45), w, 4.0)
				var tp := c + Vector2(s * 0.8, -s * 0.45)
				ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(4, -6), tp + Vector2(-10, -4), tp + Vector2(-2, 10)]), w)
			"kingSPACE":  # shield charge
				for i in 3:
					ci.draw_line(c + Vector2(-s * 1.0, -s * 0.4 + i * s * 0.4), c + Vector2(-s * 0.35, -s * 0.4 + i * s * 0.4), w, 4.0)
				ci.draw_circle(c + Vector2(s * 0.25, 0), s * 0.62, ink)
				ci.draw_circle(c + Vector2(s * 0.25, 0), s * 0.52, Color("3a6fc4"))
				ci.draw_circle(c + Vector2(s * 0.25, 0), s * 0.2, Color("ffd23f"))
			"queenSPACE":  # roll: dash lines + ball
				ci.draw_circle(c + Vector2(s * 0.3, 0), s * 0.4, w)
				for i in 3:
					ci.draw_line(c + Vector2(-s * 0.95, -s * 0.35 + i * s * 0.35), c + Vector2(-s * 0.25, -s * 0.35 + i * s * 0.35), w, 4.0)
			"wizardQ": # meteor
				ci.draw_line(c + Vector2(-s * 0.9, -s * 0.9), c, Color("ffb13b"), 9.0)
				ci.draw_circle(c + Vector2(s * 0.1, s * 0.1), s * 0.45, Color("ff7a2a"))
				ci.draw_circle(c + Vector2(s * 0.1, s * 0.1), s * 0.25, Color("ffe27a"))
			"wizardE": # fire nova ring
				ci.draw_arc(c, s * 0.75, 0, TAU, 24, Color("ff7a2a"), 7.0)
				for i in 6:
					var a := TAU * i / 6.0
					ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.75, s * 0.2, Color("ffd23f"))
				ci.draw_circle(c, s * 0.25, Color("fff0c8"))
			"wizardSPACE": # blink: sparkle
				var pts := PackedVector2Array()
				for i in 8:
					var a := TAU * i / 8.0 - PI * 0.5
					pts.append(c + Vector2(cos(a), sin(a)) * (s * 0.9 if i % 2 == 0 else s * 0.3))
				ci.draw_colored_polygon(pts, Color("d9b0ff"))
			"valkyrieQ": # whirl spiral
				for i in 3:
					ci.draw_arc(c, s * (0.3 + i * 0.25), i * 1.5, i * 1.5 + 4.0, 16, w, 4.0)
			"valkyrieE": # thrown axe
				ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.5, -s * 0.5), Color("c98a4a"), 6.0)
				ci.draw_circle(c + Vector2(s * 0.5, -s * 0.5), s * 0.42, ink)
				ci.draw_circle(c + Vector2(s * 0.5, -s * 0.5), s * 0.34, Color("e8eef6"))
				ci.draw_arc(c, s * 0.95, PI * 0.9, PI * 1.6, 10, w, 3.0)
			"valkyrieSPACE": # leap arc + impact
				ci.draw_arc(c + Vector2(0, s * 0.4), s * 0.8, PI, TAU, 16, w, 4.0)
				ci.draw_circle(c + Vector2(s * 0.8, s * 0.4), s * 0.22, Color("ffd23f"))
			"clericQ": # heal cross
				ci.draw_rect(Rect2(c - Vector2(s * 0.22, s * 0.75), Vector2(s * 0.44, s * 1.5)), Color("6cff7a"))
				ci.draw_rect(Rect2(c - Vector2(s * 0.75, s * 0.22), Vector2(s * 1.5, s * 0.44)), Color("6cff7a"))
			"clericSPACE": # light dash
				for i in 3:
					ci.draw_line(c + Vector2(-s * 0.9, -s * 0.3 + i * s * 0.3), c + Vector2(s * 0.2, -s * 0.3 + i * s * 0.3), Color("fff07a"), 4.0)
				ci.draw_circle(c + Vector2(s * 0.45, 0), s * 0.35, Color("fffbe0"))
			"clericE": # sanctuary ring
				ci.draw_arc(c, s * 0.75, 0, TAU, 24, Color("ffe27a"), 5.0)
				ci.draw_circle(c, s * 0.25, Color("ffe27a"))
			_:
				ci.draw_circle(c, s * 0.5, w)

class Minimap extends Control:
	var map: MapDef
	var hud
	var font: Font
	const YAW := deg_to_rad(45.0)
	func _w2m(p: Vector2) -> Vector2:
		var f := Vector2(-sin(YAW), -cos(YAW))
		var r := Vector2(cos(YAW), -sin(YAW))
		var s := (size.x - 56.0) / 104.0
		return size * 0.5 + Vector2(p.dot(r), -p.dot(f)) * s
	func _draw() -> void:
		var c := size * 0.5
		var R := size.x * 0.5
		draw_circle(c + Vector2(0, 5), R, Color(0.03, 0.07, 0.25, 0.8))
		draw_circle(c, R, Color("0f1d55"))
		draw_circle(c, R - 4, Color("2a5fd8"))
		draw_circle(c, R - 22, Color("0f1d55"))
		draw_circle(c, R - 25, Color("7fd14a"))
		for k in 4:
			var pts: PackedVector2Array = map.lanes[k]
			var mp := PackedVector2Array()
			for p in pts:
				mp.append(_w2m(p))
			draw_polyline(mp, Color("e8c98a"), 7.0, true)
		draw_rect(Rect2(c - Vector2(8, 6), Vector2(16, 12)), Color("dfe6ee"))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -6), c + Vector2(0, -15), c + Vector2(10, -6)]), Color("2a5fd8"))
		var s: Dictionary = hud.snap
		for t in s.get("t", []):
			var sp: Vector2 = map.spots[t[0]]["pos"]
			draw_rect(Rect2(_w2m(sp) - Vector2(3, 3), Vector2(6, 6)), Color("2a5fd8"))
		var es: PackedFloat32Array = s.get("e", PackedFloat32Array())
		var i := 0
		while i + 7 < es.size():
			var big := int(es[i + 1]) == 6
			var ep := _w2m(Vector2(es[i + 2], es[i + 3]))
			draw_circle(ep, 6.0 if big else 3.6, Color("0f1d55"))
			draw_circle(ep, 4.5 if big else 2.4, Color("ff3b4f"))
			i += 8
		for h in s.get("h", []):
			if h[6] == 1:
				continue
			var hp := _w2m(Vector2(h[1], h[2]))
			var me: bool = h[0] == hud.local_slot
			draw_circle(hp, 8.0 if me else 6.5, Color("0f1d55"))
			draw_circle(hp, 6.0 if me else 4.6, Data.PLAYER_COLORS[h[0]])
			draw_circle(hp + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1, 0.7))
		# compass letters on the blue ring (screen-oriented like the camera)
		var dirs := {"N": Vector2(0, -60), "E": Vector2(60, 0), "S": Vector2(0, 60), "W": Vector2(-60, 0)}
		for k in dirs:
			var wp: Vector2 = dirs[k]
			var mp2 := _w2m(wp)
			var d := (mp2 - c).normalized()
			var lp := c + d * (R - 13.0)
			draw_circle(lp, 13, Color("0f1d55"))
			draw_circle(lp, 11, Color("2a5fd8"))
			draw_string(font, lp + Vector2(-14, 7), k, HORIZONTAL_ALIGNMENT_CENTER, 28, 18, Color.WHITE)

class DangerArrow extends Control:
	var color := Color.RED
	var pulse := false
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var s := 1.15 if pulse else 1.0
		var pts := PackedVector2Array([c + Vector2(22, 0) * s, c + Vector2(-14, -16) * s, c + Vector2(-6, 0) * s, c + Vector2(-14, 16) * s])
		var o := PackedVector2Array()
		for p in pts:
			o.append(c + (p - c) * 1.3)
		draw_colored_polygon(o, Color("0f1d55"))
		draw_colored_polygon(pts, color if pulse else color.darkened(0.2))
		draw_circle(c + Vector2(-20, 0), 6, Color("ff3b4f"))

class RingBg extends Control:
	func _draw() -> void:
		var c := size * 0.5
		# dashed ring like the reference
		var n := 28
		for i in n:
			if i % 2 == 0:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				draw_arc(c, 108, a0, a1, 4, Color("0f1d55"), 9.0, true)
		draw_arc(c, 108, 0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)

class MenuButtonW extends Control:
	var item := {}
	var hud
	var selected := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			hud.menu_press(hud.menu_items.find(item))
			accept_event()
	func _draw() -> void:
		var c := size * 0.5
		var R := size.x * 0.5
		var afford: bool = item["cost"] <= hud.snap.get("g", 0) or item["action"] == "sell"
		var base := Color("2a5fd8")
		match item["kind"]:
			"archer": base = Color("3fae4a")
			"barracks": base = Color("2a5fd8")
			"mage": base = Color("8a4fe0")
			"artillery": base = Color("d0702e")
		if item["action"] == "upgrade":
			base = Color("2a5fd8")
		elif item["action"] == "sell":
			base = Color("f0506e")
		if not afford:
			base = base.darkened(0.45)
		draw_circle(c + Vector2(0, 4), R, Color(0.03, 0.07, 0.25, 0.8))
		draw_circle(c, R, Color("0f1d55"))
		draw_circle(c, R - 4, Color(1, 1, 0.75) if selected else Color("3fd3ff"))
		draw_circle(c, R - 8, base)
		draw_arc(c + Vector2(0, -6), R - 18, PI * 1.15, PI * 1.85, 12, Color(1, 1, 1, 0.3), 6.0)
		var f: Font = hud.font
		match item["action"]:
			"upgrade":
				var ar := PackedVector2Array([c + Vector2(0, -30), c + Vector2(20, -8), c + Vector2(8, -8), c + Vector2(8, 4), c + Vector2(-8, 4), c + Vector2(-8, -8), c + Vector2(-20, -8)])
				var ao := PackedVector2Array()
				for p in ar:
					ao.append(c + Vector2(0, -12) + (p - c - Vector2(0, -12)) * 1.25)
				draw_colored_polygon(ao, Color("0f1d55"))
				draw_colored_polygon(ar, Color("ffd23f"))
			"sell":
				draw_circle(c + Vector2(0, -8), 18, Color("0f1d55"))
				draw_circle(c + Vector2(0, -8), 15, Color("ffd23f"))
				draw_string(f, c + Vector2(-12, 1), "$", HORIZONTAL_ALIGNMENT_CENTER, 24, 22, Color("0f1d55"))
			_:
				var g: String = {"archer": "궁", "barracks": "병", "mage": "마", "artillery": "포"}.get(item["kind"], "?")
				if selected:
					g = "✔"
				draw_string_outline(f, Vector2(0, c.y + 2), g, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, 7, Color("0f1d55"))
				draw_string(f, Vector2(0, c.y + 2), g, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color.WHITE)
		# coin + cost pill
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color("0f1d55")
		pill.set_corner_radius_all(12)
		draw_style_box(pill, Rect2(Vector2(14, size.y - 32), Vector2(size.x - 28, 26)))
		draw_circle(Vector2(28, size.y - 19), 9, Color("ffc21f"))
		draw_circle(Vector2(28, size.y - 19), 6, Color("ffe27a"))
		draw_string(f, Vector2(36, size.y - 12), str(absi(item["cost"])), HORIZONTAL_ALIGNMENT_CENTER, size.x - 48, 18, Color.WHITE if afford else Color("ff9aa0"))
		var kb := StyleBoxFlat.new()
		kb.bg_color = Color("ffd23f")
		kb.set_corner_radius_all(6)
		kb.set_border_width_all(2)
		kb.border_color = Color("0f1d55")
		draw_style_box(kb, Rect2(Vector2(-2, -2), Vector2(24, 24)))
		draw_string(f, Vector2(-2, 16), item["key"], HORIZONTAL_ALIGNMENT_CENTER, 24, 16, Color("0f1d55"))

## clickable action bar inside the tooltip card (yellow upgrade / red sell / build)
class TipBar extends Control:
	var item := {}
	var hud
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var idx: int = hud.menu_items.find(item)
			if hud.menu_sel != idx:
				hud.menu_press(idx)
			hud.menu_press(idx)
			accept_event()
	func _draw() -> void:
		var sell: bool = item["action"] == "sell"
		var col := Color("f0506e") if sell else Color("ffd23f")
		var afford: bool = sell or item["cost"] <= hud.snap.get("g", 0)
		if not afford:
			col = Color("8a8aa0")
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(3)
		sb.border_color = Color(1, 1, 0.75) if hud.menu_items.find(item) == hud.menu_sel else Color("0f1d55")
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2(8, 5), Vector2(size.x - 16, size.y * 0.32)), Color(1, 1, 1, 0.22))
		var f: Font = hud.font
		var txt: String = "판매" if sell else ("업그레이드" if item["action"] == "upgrade" else "건설")
		var tc := Color.WHITE if sell else Color("0f1d55")
		draw_string(f, Vector2(18, 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tc)
		draw_circle(Vector2(size.x - 82, size.y * 0.5), 12, Color("0f1d55"))
		draw_circle(Vector2(size.x - 82, size.y * 0.5), 9, Color("ffc21f"))
		draw_string(f, Vector2(size.x - 66, 28), str(absi(item["cost"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tc)

class StarRow extends Control:
	var count := 0
	var _t := 0.0
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		for i in 3:
			var c := Vector2(size.x * (0.2 + i * 0.3), size.y * 0.5 - (12.0 if i == 1 else 0.0))
			var on := i < count and _t > 0.4 + i * 0.3
			var r := 40.0 * (1.0 + 0.15 * sin(_t * 4.0 + i)) if on else 36.0
			var pts := PackedVector2Array()
			for j in 10:
				var a := -PI * 0.5 + TAU * j / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (r if j % 2 == 0 else r * 0.45))
			var o := PackedVector2Array()
			for p in pts:
				o.append(c + (p - c) * 1.15)
			draw_colored_polygon(o, Color("0f1d55"))
			draw_colored_polygon(pts, Color("ffd23f") if on else Color("4a5590"))
