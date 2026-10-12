class_name StructureLayer
extends Node2D
## Рисует стройки и готовые постройки, прогресс копки и рамку новой стройки.

const TILE := ChunkView.TILE
const DIG_EDGE := Color(1.0, 0.82, 0.25, 0.95)
const DIG_FILL := Color(1.0, 0.82, 0.25, 0.16)
const BUILD_EDGE := Color(1.0, 0.55, 0.15, 0.95)
const PAUSED := Color(0.65, 0.65, 0.7, 0.9)
const BLOCKED := Color(1.0, 0.35, 0.3, 0.95)
const ROOM_WALL := Color(0.86, 0.79, 0.68)
const ROOM_FRAME := Color(0.48, 0.47, 0.5)
const ROOM_FLOOR := Color(0.38, 0.27, 0.18)
const LAMP := Color(1.0, 0.9, 0.55)
const BEAM := Color(0.55, 0.38, 0.2)
const BAR_BG := Color(0, 0, 0, 0.6)
const BAR := Color(0.45, 0.9, 0.4)

var view: WorldView
var colony: Colony
## Рамка новой стройки (size == 0 — нет).
var preview := Rect2i()
var preview_ok := false
var preview_text := ""
var selected_project := 0


func _process(_delta: float) -> void:
	queue_redraw()


func _rect_px(r: Rect2i) -> Rect2:
	return Rect2(view.cell_to_local(r.position), Vector2(r.size) * TILE)


func _draw() -> void:
	if colony == null:
		return
	var font := ThemeDB.fallback_font
	for p in colony.projects:
		if p.phase == Project.Phase.DONE:
			_draw_done(p)
	for p in colony.projects:
		if p.phase != Project.Phase.DONE:
			_draw_site(p, font)
	_draw_dig_progress()
	if preview.size != Vector2i.ZERO:
		var r := _rect_px(preview)
		var col := Color(0.4, 1.0, 0.45) if preview_ok else Color(1.0, 0.35, 0.3)
		draw_rect(r, Color(col, 0.18))
		draw_rect(r, col, false, 3.0)
		_label(font, r.position + Vector2(4, -8), preview_text, col)


func _draw_done(p: Project) -> void:
	var r := _rect_px(p.rect)
	if p.kind == Project.Kind.ROOM:
		draw_rect(r, ROOM_WALL)
		# Панели стен.
		var step := TILE * 2.0
		var x := r.position.x + step
		while x < r.end.x - 1:
			draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), ROOM_WALL.darkened(0.08), 2.0)
			x += step
		draw_rect(Rect2(r.position.x, r.end.y - 6, r.size.x, 6), ROOM_FLOOR)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5), ROOM_FRAME)
		draw_rect(Rect2(r.position.x, r.position.y, 5, r.size.y), ROOM_FRAME)
		draw_rect(Rect2(r.end.x - 5, r.position.y, 5, r.size.y), ROOM_FRAME)
		# Лестница — только у заглублённой комнаты, иначе вход с уровня земли.
		if p.ladder:
			_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
		var lamp := Vector2(r.get_center().x, r.position.y + 9)
		draw_circle(lamp, 14, Color(LAMP, 0.18))
		draw_circle(lamp, 5, LAMP)
	else:
		_draw_supports(p, r, 1.0)
	if p.id == selected_project:
		draw_rect(r.grow(2), Color.WHITE, false, 2.0)


## Крепь тоннеля: рамы поперёк, в шахте — лестница.
func _draw_supports(p: Project, r: Rect2, alpha: float) -> void:
	var col := Color(BEAM, alpha)
	if p.rect.size.y > p.rect.size.x:
		_ladder(r.get_center().x, r.position.y, r.end.y, alpha)
	else:
		var x := r.position.x + TILE * 0.5
		while x < r.end.x:
			draw_line(Vector2(x - 8, r.end.y), Vector2(x - 8, r.position.y + 3), col, 4.0)
			draw_line(Vector2(x + 8, r.end.y), Vector2(x + 8, r.position.y + 3), col, 4.0)
			draw_line(Vector2(x - 12, r.position.y + 3), Vector2(x + 12, r.position.y + 3), col, 5.0)
			x += TILE * 3.0


func _draw_site(p: Project, font: Font) -> void:
	var r := _rect_px(p.rect)
	var edge := DIG_EDGE if p.phase == Project.Phase.DIG else BUILD_EDGE
	if not p.blocked.is_empty():
		edge = BLOCKED
	if p.paused:
		edge = PAUSED
	if p.phase == Project.Phase.DIG:
		for c in colony.remaining_dig(p):
			draw_rect(Rect2(view.cell_to_local(c), Vector2(TILE, TILE)), DIG_FILL)
	else:
		var t := clampf(p.build_done / p.build_work(), 0.0, 1.0) if p.paid else 0.0
		if p.kind == Project.Kind.ROOM:
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * t, r.size.x, r.size.y * t), Color(ROOM_WALL, 0.55))
		else:
			_draw_supports(p, r, 0.3 + 0.7 * t)
		var bar := Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, 6)
		draw_rect(bar, BAR_BG)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
	_dashed_rect(r, edge, 2.5 if p.id != selected_project else 4.0)
	if p.paused:
		var c := r.get_center()
		draw_rect(Rect2(c + Vector2(-10, -12), Vector2(7, 24)), PAUSED)
		draw_rect(Rect2(c + Vector2(3, -12), Vector2(7, 24)), PAUSED)


func _draw_dig_progress() -> void:
	for u in colony.units:
		if u.task != Unit.Task.DIG or u.state != Unit.State.WORK:
			continue
		var c := u.target
		var need := colony.dig_time(c)
		if need <= 0.0:
			continue
		var t := clampf(colony.dig_progress.get(c, 0.0) / need, 0.0, 1.0)
		var r := Rect2(view.cell_to_local(c), Vector2(TILE, TILE))
		# Трещины по мере копки.
		var crack := Color(0, 0, 0, 0.25 + 0.4 * t)
		draw_line(r.get_center(), r.get_center() + Vector2(-9, -8) * t * 1.4, crack, 2.0)
		draw_line(r.get_center(), r.get_center() + Vector2(10, 4) * t * 1.4, crack, 2.0)
		draw_line(r.get_center(), r.get_center() + Vector2(-2, 11) * t * 1.4, crack, 2.0)
		var bar := Rect2(r.position.x + 3, r.end.y - 7, r.size.x - 6, 5)
		draw_rect(bar, BAR_BG)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)


func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, width, 10.0)


func _label(font: Font, p: Vector2, text: String, col: Color) -> void:
	if text.is_empty():
		return
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)


func _ladder(cx: float, top: float, bottom: float, alpha: float) -> void:
	var col := Color(BEAM, alpha)
	draw_line(Vector2(cx - 7, top), Vector2(cx - 7, bottom), col, 3.0)
	draw_line(Vector2(cx + 7, top), Vector2(cx + 7, bottom), col, 3.0)
	var y := top + 8
	while y < bottom:
		draw_line(Vector2(cx - 7, y), Vector2(cx + 7, y), col, 2.5)
		y += 10
