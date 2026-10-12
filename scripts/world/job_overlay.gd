class_name JobOverlay
extends Node2D
## Рисует заказанные клетки и прогресс работ поверх мира.

const TILE := ChunkView.TILE
const QUEUED := Color(1.0, 0.82, 0.25, 0.28)
const QUEUED_EDGE := Color(1.0, 0.82, 0.25, 0.9)
const WAITING_EDGE := Color(1.0, 1.0, 1.0, 0.35)
const BAR_BG := Color(0, 0, 0, 0.6)
const BAR := Color(0.45, 0.9, 0.4)

var view: WorldView


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var dig := view.dig
	if dig == null or dig.order.is_empty():
		return
	var active := {}
	for c in dig.active_jobs():
		active[c] = true
	for c in dig.order:
		var r := Rect2(view.cell_to_local(c), Vector2(TILE, TILE)).grow(-2)
		draw_rect(r, QUEUED)
		draw_rect(r, QUEUED_EDGE if active.has(c) else WAITING_EDGE, false, 2.0)
		if active.has(c):
			var need := dig.dig_time(c)
			var t := clampf(dig.progress[c] / need, 0.0, 1.0) if need > 0.0 else 1.0
			var bar := Rect2(r.position.x + 2, r.end.y - 7, r.size.x - 4, 5)
			draw_rect(bar, BAR_BG)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
