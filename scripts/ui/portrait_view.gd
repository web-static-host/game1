class_name PortraitView
extends Control
## Портрет гаврика в карточке: рисуем существо крупно по его внешности.

var looks := {}
var body_w := 70.0


static func make(p_looks: Dictionary, p_size: float, p_body_w: float) -> PortraitView:
	var v := PortraitView.new()
	v.looks = p_looks
	v.body_w = p_body_w
	v.custom_minimum_size = Vector2(p_size, p_size)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _draw() -> void:
	if looks.is_empty():
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.06)
	bg.set_corner_radius_all(12)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var h := CreatureArt.height_of(body_w, looks)
	var at := Vector2(size.x * 0.5, size.y * 0.5 + h * 0.5 + 4.0)
	if not ModelSprites.draw_creature(self, "idle", at, body_w, looks):
		CreatureArt.draw(self, at, body_w, looks, 1.0)
