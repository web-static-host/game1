class_name IconButton
extends Button
## Кнопка нижнего меню: векторный значок и подпись под ним.

var glyph := ""
var caption := ""
const ICON_COLOR := Color(0.92, 0.94, 0.98)
const ICON_PRESSED := Color(0.12, 0.09, 0.05)


static func make(p_glyph: String, p_caption: String, w := 96.0, h := 80.0) -> IconButton:
	var b := IconButton.new()
	b.glyph = p_glyph
	b.caption = p_caption
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	return b


func set_caption(text: String) -> void:
	caption = text
	queue_redraw()


func _draw() -> void:
	var col := ICON_PRESSED if button_pressed else ICON_COLOR
	if disabled:
		col = Color(col, 0.4)
	var font := get_theme_default_font()
	var has_caption := not caption.is_empty()
	var icon_c := Vector2(size.x * 0.5, size.y * (0.4 if has_caption else 0.5))
	ResIcon.draw_glyph(self, glyph, icon_c, minf(size.x, size.y) * (0.22 if has_caption else 0.3), col)
	if has_caption:
		var fs := 15
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y - 9), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
