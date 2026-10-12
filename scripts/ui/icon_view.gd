class_name IconView
extends Control
## Значок ресурса (key) или кнопки (glyph) в интерфейсе.

var key := ""
var glyph := ""
var tint := Color(0.92, 0.94, 0.98)


static func make(p_key: String, size_px := 26.0, p_glyph := "", p_tint := Color(0.92, 0.94, 0.98)) -> IconView:
	var v := IconView.new()
	v.key = p_key
	v.glyph = p_glyph
	v.tint = p_tint
	v.custom_minimum_size = Vector2(size_px, size_px)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.45
	if not glyph.is_empty():
		ResIcon.draw_glyph(self, glyph, c, r, tint)
	elif not key.is_empty():
		ResIcon.draw(self, key, c, r)
