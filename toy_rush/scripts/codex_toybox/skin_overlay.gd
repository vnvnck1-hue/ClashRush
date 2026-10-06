extends Control
## Presentation-only overlay; the underlying UI retains inputs, state and cooldowns.
var target: WeakRef
var skill := false
var action_bar := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var node = target.get_ref() if target != null else null
	if not is_instance_valid(node): return
	if action_bar:
		_draw_action(node)
		return
	if not skill:
		if size.x > 20 and size.y > 25:
			draw_line(Vector2(12, 4), Vector2(size.x - 12, 4), Color(1, 1, 1, 0.45), 2.0, true)
			draw_line(Vector2(12, size.y - 3), Vector2(size.x - 12, size.y - 3), Color(0.15, 0.08, 0.25, 0.18), 2.0, true)
		return
	var ink := Color("302443")
	var rect := Rect2(Vector2(8, 5), Vector2(size.x - 12, size.y - 12))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("9b6ee9") if node.cd <= 0.0 else Color("615280")
	box.set_corner_radius_all(15)
	box.set_border_width_all(3)
	box.border_color = Color("d8c5ff")
	box.shadow_color = ink
	box.shadow_offset = Vector2(0, 4)
	box.shadow_size = 1
	draw_style_box(box, rect)
	var center := rect.get_center()
	Hud.SkillGlyph.draw_glyph(self, node.hero, node.key, center + Vector2(0, 3), 23.0, node.cd <= 0.0)
	if node.cd > 0.0:
		draw_arc(center, 27, -PI * 0.5, -PI * 0.5 + TAU * node.cd, 32, Color("cde7ff"), 4.0, true)
		draw_string_outline(node.font, Vector2(15, size.y - 15), "%ds" % int(ceil(node.secs)), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 25, 20, 3, ink)
		draw_string(node.font, Vector2(15, size.y - 15), "%ds" % int(ceil(node.secs)), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 25, 20, Color.WHITE)
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("fff0d2")
	badge.border_color = ink
	badge.set_border_width_all(2)
	badge.set_corner_radius_all(7)
	draw_style_box(badge, Rect2(Vector2.ZERO, Vector2(28, 28)))
	draw_string(node.font, Vector2(0, 22), node.key, HORIZONTAL_ALIGNMENT_CENTER, 28, 20, ink)

func _draw_action(node: Control) -> void:
	var ink := Color("302443")
	var sell: bool = node.item["action"] == "sell"
	var afford: bool = sell or node.item["cost"] <= node.hud.snap.get("g", 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f5ddba") if sell else Color("f58b72")
	if not afford: box.bg_color = Color("a59ca8")
	box.border_color = ink
	box.set_corner_radius_all(12)
	box.set_border_width_all(2)
	box.shadow_offset = Vector2(0, 3)
	box.shadow_size = 1
	box.shadow_color = Color(0.18, 0.10, 0.25, 0.4)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	draw_line(Vector2(10, 4), Vector2(size.x - 10, 4), Color(1, 1, 1, 0.5), 2.0, true)
	var text: String = "판매" if sell else ("업그레이드" if node.item["action"] == "upgrade" else "건설")
	var color := ink if sell else Color.WHITE
	var f: Font = node.hud.font
	draw_string(f, Vector2(16, size.y * 0.5 + 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
	var center := Vector2(size.x - 79, size.y * 0.5)
	draw_circle(center, 10, Color("d49927"))
	draw_circle(center, 7, Color("ffda64"))
	draw_string(f, Vector2(size.x - 64, size.y * 0.5 + 8), str(absi(node.item["cost"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
