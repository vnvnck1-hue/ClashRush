class_name Lobby
extends CanvasLayer
## Title screen + lobby (4 slots, hero select). The 3D hero showcase lives in Main.

signal solo_pressed(name: String)
signal host_pressed(name: String)
signal join_pressed(name: String, ip: String)
signal hero_clicked(hero: String)
signal start_pressed
signal leave_pressed
signal hero_hovered(hero: String)

var hud_style: Hud          # reuse style helpers
var root: Control
var title_box: Control
var lobby_box: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var status_l: Label
var slot_cards: Array = []
var hero_cards := {}
var start_btn: Button
var wait_l: Label
var info_l: Label

func _ready() -> void:
	layer = 6
	hud_style = Hud.new()
	add_child(hud_style)
	hud_style.layer = 0
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_title()
	_build_lobby()
	show_title()

func H() -> Hud:
	return hud_style

func _edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", H().font)
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_stylebox_override("normal", H().box(Color("fff8e6"), 14, 3))
	e.add_theme_stylebox_override("focus", H().box(Color("ffffff"), 14, 4, Color("3fa9f5")))
	e.add_theme_color_override("font_color", Color("1d1530"))
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return e

func _build_title() -> void:
	title_box = Control.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_box)
	var logo := H().label("TOY RUSH", 120, Data.COL_GOLD, 22)
	logo.label_settings.outline_color = Color("5a2a08")
	logo.label_settings.shadow_offset = Vector2(0, 10)
	title_box.add_child(H().place(logo, Vector2(0.5, 0), Vector2(-500, 40), Vector2(1000, 160)))
	var sub := H().label("4인 협동 · 영웅 직접 조종 · 장난감 왕국 디펜스", 28, Color.WHITE, 8)
	title_box.add_child(H().place(sub, Vector2(0.5, 0), Vector2(-500, 190), Vector2(1000, 40)))
	var card := H().blue_panel(24)
	title_box.add_child(H().place(card, Vector2(0.5, 0.5), Vector2(-260, -90), Vector2(520, 380)))
	var nl := H().label("닉네임", 20, Color("fff4c0"), 5)
	card.add_child(H().at(nl, Vector2(20, 14), Vector2(140, 44)))
	name_edit = _edit("용사%d" % (randi() % 900 + 100), "이름")
	card.add_child(H().at(name_edit, Vector2(160, 14), Vector2(340, 44)))
	var solo := H().button("솔로 플레이 (봇 3명과 함께)", Color("6cbf3c"), 26)
	card.add_child(H().at(solo, Vector2(20, 74), Vector2(480, 64)))
	solo.pressed.connect(func(): solo_pressed.emit(name_edit.text))
	var host := H().button("LAN 방 만들기", Color("3fa9f5"), 26)
	card.add_child(H().at(host, Vector2(20, 150), Vector2(480, 64)))
	host.pressed.connect(func(): host_pressed.emit(name_edit.text))
	ip_edit = _edit("127.0.0.1", "호스트 IP")
	card.add_child(H().at(ip_edit, Vector2(20, 228), Vector2(220, 60)))
	var join := H().button("LAN 참가", Color("ff9f1c"), 26)
	card.add_child(H().at(join, Vector2(250, 226), Vector2(250, 64)))
	join.pressed.connect(func(): join_pressed.emit(name_edit.text, ip_edit.text))
	status_l = H().label("", 20, Color("ffb0c0"), 5)
	card.add_child(H().at(status_l, Vector2(10, 300), Vector2(500, 30)))
	var keys := H().label("WASD 이동 · 마우스 조준 · 좌클릭 공격 · Q/E 스킬 · SPACE 이동기 · F 건설 · Tab 전체 맵", 20, Color.WHITE, 6)
	card.add_child(H().at(keys, Vector2(-120, 336), Vector2(760, 30)))

func _build_lobby() -> void:
	lobby_box = Control.new()
	lobby_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lobby_box)
	var t := H().label("영웅 선택", 54, Color.WHITE, 12)
	lobby_box.add_child(H().place(t, Vector2(0.5, 0), Vector2(-300, 10), Vector2(600, 70)))
	info_l = H().label("", 20, Color("fff4c0"), 6)
	lobby_box.add_child(H().place(info_l, Vector2(0.5, 0), Vector2(-500, 76), Vector2(1000, 30)))
	for i in 4:
		var c := H().blue_panel(16)
		lobby_box.add_child(H().place(c, Vector2(0, 0), Vector2(22, 104 + i * 84), Vector2(270, 76)))
		var badge := H().blue_panel(10, Data.PLAYER_COLORS[i], 3)
		c.add_child(H().at(badge, Vector2(-8, 11), Vector2(40, 54)))
		var bl := H().label(Hud.LANE_LETTERS[i], 26, Color.WHITE, 7)
		badge.add_child(H().at(bl, Vector2.ZERO, Vector2(40, 54)))
		var lane := H().label("%s 라인" % Data.LANE_NAMES[i], 18, Color("cfe0ff"), 5, HORIZONTAL_ALIGNMENT_LEFT)
		c.add_child(H().at(lane, Vector2(40, 6), Vector2(120, 24)))
		var nm := H().label("", 24, Color.WHITE, 6, HORIZONTAL_ALIGNMENT_LEFT)
		c.add_child(H().at(nm, Vector2(40, 30), Vector2(224, 30)))
		var hero := H().label("", 18, Color("fff4c0"), 5, HORIZONTAL_ALIGNMENT_RIGHT)
		c.add_child(H().at(hero, Vector2(120, 6), Vector2(140, 24)))
		var tag := H().label("", 15, Color("c0c0d8"), 4, HORIZONTAL_ALIGNMENT_LEFT)
		c.add_child(H().at(tag, Vector2(40, 54), Vector2(224, 20)))
		slot_cards.append({"card": c, "name": nm, "hero": hero, "tag": tag})
	for j in 5:
		var hk: String = Data.HERO_ORDER[j]
		var d: Dictionary = Data.HEROES[hk]
		var hc := HeroCard.new()
		hc.hero = hk
		hc.lobby = self
		hc.mouse_filter = Control.MOUSE_FILTER_STOP
		lobby_box.add_child(H().place(hc, Vector2(0.5, 1), Vector2(-620 + j * 248, -232), Vector2(236, 190)))
		var bg := H().blue_panel(18)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hc.add_child(H().at(bg, Vector2.ZERO, Vector2(236, 190)))
		var pt := H().portrait(hk, Vector2(64, 64), Hud.BLUE_L, 14)
		hc.add_child(H().at(pt, Vector2(8, -40), Vector2(64, 64)))
		var n := H().label(d["name"], 30, Color.WHITE, 8)
		hc.add_child(H().at(n, Vector2(40, 4), Vector2(196, 38)))
		var r := H().label(d["role"], 17, Data.COL_GOLD, 5)
		hc.add_child(H().at(r, Vector2(0, 38), Vector2(236, 22)))
		var bl := H().label(d["blurb"], 15, Color("e8e4ff"), 4)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hc.add_child(H().at(bl, Vector2(8, 60), Vector2(220, 40)))
		var sk := H().label("Q  %s\nE  %s\nSPACE  %s" % [d["q"]["name"], d["e"]["name"], d["space"]["name"]], 15, Color.WHITE, 4, HORIZONTAL_ALIGNMENT_LEFT)
		hc.add_child(H().at(sk, Vector2(16, 98), Vector2(210, 60)))
		var who := H().label("", 16, Color.WHITE, 5)
		hc.add_child(H().at(who, Vector2(0, 156), Vector2(236, 26)))
		hero_cards[hk] = {"card": hc, "bg": bg, "who": who}
	start_btn = H().button("게임 시작!", Color("ff9f1c"), 34)
	lobby_box.add_child(H().place(start_btn, Vector2(1, 0), Vector2(-300, 120), Vector2(280, 80)))
	start_btn.pressed.connect(func(): start_pressed.emit())
	wait_l = H().label("호스트가 시작하기를 기다리는 중...", 20, Color("fff4c0"), 6)
	lobby_box.add_child(H().place(wait_l, Vector2(1, 0), Vector2(-420, 130), Vector2(400, 60)))
	var leave := H().button("나가기", Color("8a6fa8"), 24)
	lobby_box.add_child(H().place(leave, Vector2(1, 0), Vector2(-300, 210), Vector2(280, 60)))
	leave.pressed.connect(func(): leave_pressed.emit())

func show_title(msg := "") -> void:
	visible = true
	title_box.visible = true
	lobby_box.visible = false
	status_l.text = msg

func show_lobby(is_host: bool, info: String) -> void:
	visible = true
	title_box.visible = false
	lobby_box.visible = true
	start_btn.visible = is_host
	wait_l.visible = not is_host
	info_l.text = info

func refresh(slots: Array, my_peer: int) -> void:
	for i in 4:
		var s: Dictionary = slots[i]
		var c: Dictionary = slot_cards[i]
		(c["name"] as Label).text = s["name"] + ("  (나)" if s["peer"] == my_peer else "")
		(c["hero"] as Label).text = Data.HEROES[s["hero"]]["name"] if s["hero"] != "" else ""
		(c["tag"] as Label).text = "AI 봇" if s["peer"] == 0 else ("호스트" if s["peer"] == 1 else "플레이어")
	for hk in hero_cards:
		var hc: Dictionary = hero_cards[hk]
		var owner := -1
		for i in 4:
			if slots[i]["hero"] == hk:
				owner = i
		var mine: bool = owner >= 0 and slots[owner]["peer"] == my_peer
		var border: Color = Data.PLAYER_COLORS[owner] if owner >= 0 else Hud.NAVY
		var bgc: Color = Hud.BLUE if not mine else Hud.BLUE_L
		(hc["bg"] as Panel).add_theme_stylebox_override("panel", H().blue_box(18, bgc, 6 if mine else 4, border))
		(hc["who"] as Label).text = ("%s · %s" % [slots[owner]["name"], "봇" if slots[owner]["peer"] == 0 else "선택됨"]) if owner >= 0 else "선택 가능"
		if mine:
			H().bump(hc["card"], 1.06)

class HeroCard extends Control:
	var hero := ""
	var lobby
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			lobby.hero_clicked.emit(hero)
			Sfx.play("click", -4.0)
			accept_event()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			lobby.hero_hovered.emit(hero)
			create_tween().tween_property(self, "scale", Vector2(1.04, 1.04), 0.12)
		elif what == NOTIFICATION_MOUSE_EXIT:
			create_tween().tween_property(self, "scale", Vector2.ONE, 0.12)
