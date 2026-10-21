class_name FogLayer
extends Node2D
## Неразведанные края карты: по бокам от того, куда доходили гаврики, — темнота
## с плавной границей. Карта открывается по мере продвижения гавриков.

const TILE := ChunkView.TILE
const FADE_CELLS := 8.0
const DARK := Color(0.04, 0.05, 0.08, 1.0)

var view: WorldView
var colony: Colony


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if colony == null:
		return
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var top := view.camera.position.y - half.y - TILE
	var bottom := view.camera.position.y + half.y + TILE
	var left_edge := view.cell_to_local(Vector2i(colony.explored_min, 0)).x
	var right_edge := view.cell_to_local(Vector2i(colony.explored_max + 1, 0)).x
	var screen_left := view.camera.position.x - half.x - TILE
	var screen_right := view.camera.position.x + half.x + TILE
	var f := FADE_CELLS * TILE
	var clear := Color(DARK, 0.0)
	if screen_left < left_edge:
		draw_rect(Rect2(screen_left, top, maxf(0.0, left_edge - f - screen_left), bottom - top), DARK)
		draw_polygon(PackedVector2Array([
			Vector2(left_edge - f, top), Vector2(left_edge, top), Vector2(left_edge, bottom), Vector2(left_edge - f, bottom)]),
			PackedColorArray([DARK, clear, clear, DARK]))
	if screen_right > right_edge:
		draw_rect(Rect2(right_edge + f, top, maxf(0.0, screen_right - right_edge - f), bottom - top), DARK)
		draw_polygon(PackedVector2Array([
			Vector2(right_edge, top), Vector2(right_edge + f, top), Vector2(right_edge + f, bottom), Vector2(right_edge, bottom)]),
			PackedColorArray([clear, DARK, DARK, clear]))
