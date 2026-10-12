class_name BarView
extends Control
## Полоска прогресса с подписью внутри.

var value := 0.0
var color := Color(0.45, 0.85, 0.4)
var text := ""


static func make(p_value: float, p_color: Color, p_text := "") -> BarView:
	var b := BarView.new()
	b.value = clampf(p_value, 0.0, 1.0)
	b.color = p_color
	b.text = p_text
	b.custom_minimum_size = Vector2(120, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(8)
	draw_style_box(bg, r)
	if value > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		fill.set_corner_radius_all(8)
		draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(maxf(16.0, size.x * value), size.y)))
	if not text.is_empty():
		var font := get_theme_default_font()
		var fs := 16
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
