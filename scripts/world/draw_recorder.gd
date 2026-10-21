class_name DrawRecorder
extends RefCounted
## Записывает команды рисования (как у CanvasItem), чтобы потом быстро повторить их.
## Гаврика собирают из многих фигур с вычислениями — делаем это один раз на позу,
## а дальше только повторяем готовые команды.

var _cmds: Array = []


func draw_polygon(points: PackedVector2Array, colors: PackedColorArray) -> void:
	_cmds.append([0, points, colors])


func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	_cmds.append([1, points, color])


func draw_circle(pos: Vector2, radius: float, color: Color) -> void:
	_cmds.append([2, pos, radius, color])


func draw_line(from: Vector2, to: Vector2, color: Color, width := -1.0, antialiased := false) -> void:
	_cmds.append([3, from, to, color, width, antialiased])


func draw_polyline(points: PackedVector2Array, color: Color, width := -1.0, antialiased := false) -> void:
	_cmds.append([4, points, color, width, antialiased])


func replay(ci: CanvasItem) -> void:
	for c in _cmds:
		match c[0]:
			0:
				ci.draw_polygon(c[1], c[2])
			1:
				ci.draw_colored_polygon(c[1], c[2])
			2:
				ci.draw_circle(c[1], c[2], c[3])
			3:
				ci.draw_line(c[1], c[2], c[3], c[4], c[5])
			4:
				ci.draw_polyline(c[1], c[2], c[3], c[4])


func size() -> int:
	return _cmds.size()
