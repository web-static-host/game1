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
	_draw_stockpile(font)
	for p in colony.projects:
		if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
			_draw_done(p)
	for p in colony.projects:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			_draw_site(p, font)
	_draw_dig_progress()
	# Падающая порода.
	for f in colony.physics.fx:
		var t := clampf(f[3] / Physics.FX_TIME, 0.0, 1.0)
		var pos: Vector2 = (f[0] as Vector2).lerp(f[1], t * t)
		var px := view.cell_to_local(Vector2i.ZERO) + pos * TILE
		var col := ChunkView.rock_color(f[2], 0.5)
		draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col)
		draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col.darkened(0.3), false, 2.0)
	if preview.size != Vector2i.ZERO:
		var r := _rect_px(preview)
		var col := Color(0.4, 1.0, 0.45) if preview_ok else Color(1.0, 0.35, 0.3)
		draw_rect(r, Color(col, 0.18))
		draw_rect(r, col, false, 3.0)
		_label(font, r.position + Vector2(4, -8), preview_text, col)


## Цвета по материалу стен: [задняя стена, рама, линии кладки].
const WALLS := {
	"wood": [Color(0.86, 0.73, 0.55), Color(0.52, 0.36, 0.2), Color(0.74, 0.6, 0.42)],
	"clay": [Color(0.88, 0.76, 0.64), Color(0.66, 0.45, 0.32), Color(0.8, 0.66, 0.54)],
	"stone": [Color(0.74, 0.74, 0.76), Color(0.45, 0.45, 0.5), Color(0.62, 0.62, 0.66)],
}
const BED_FRAME := Color(0.45, 0.3, 0.18)
const BLANKETS := [Color(0.35, 0.5, 0.8), Color(0.75, 0.35, 0.4), Color(0.4, 0.65, 0.45), Color(0.8, 0.65, 0.3)]
const SOIL := Color(0.3, 0.2, 0.13)
const MUSHROOM := Color(0.92, 0.88, 0.8)
const MUSHROOM_CAP := Color(0.75, 0.42, 0.3)
const CRATE := Color(0.62, 0.45, 0.25)


func _draw_done(p: Project) -> void:
	var r := _rect_px(p.rect)
	if p.is_water_structure():
		_draw_deck(p, r, 1.0)
	elif p.kind == Project.Kind.ROOM:
		_draw_room_shell(p, r)
		if p.phase == Project.Phase.EQUIP:
			var w := RoomType.job_work(p)
			var t := clampf(p.equip_done / w, 0.0, 1.0) if p.equip_paid else 0.0
			if p.equip_ladder:
				_draw_furniture(p, r, p.purpose, 1.0)
				_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 0.25 + 0.6 * t)
			else:
				_draw_furniture(p, r, p.equip_target, 0.25 + 0.6 * t)
			var bar := Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 16, 6)
			draw_rect(bar, BAR_BG)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
			_dashed_rect(r, PAUSED if p.paused else BUILD_EDGE, 2.5)
		else:
			_draw_furniture(p, r, p.purpose, 1.0)
	else:
		_draw_supports(p, r, 1.0)
	if p.id == selected_project:
		draw_rect(r.grow(2), Color.WHITE, false, 2.0)


func _draw_room_shell(p: Project, r: Rect2) -> void:
	var c: Array = WALLS.get(p.material, WALLS["wood"])
	draw_rect(r, c[0])
	match p.material:
		"wood":
			# Доски.
			var y := r.position.y + 10
			while y < r.end.y - 6:
				draw_line(Vector2(r.position.x + 5, y), Vector2(r.end.x - 5, y), c[2], 1.5)
				y += 10
		"stone":
			# Кладка блоками со смещением.
			var row := 0
			var y := r.position.y + 5
			while y < r.end.y - 6:
				draw_line(Vector2(r.position.x + 5, y), Vector2(r.end.x - 5, y), c[2], 1.5)
				var x := r.position.x + 5 + (20 if row % 2 else 0)
				while x < r.end.x - 5:
					draw_line(Vector2(x, y), Vector2(x, minf(y + 16, r.end.y - 6)), c[2], 1.5)
					x += 40
				y += 16
				row += 1
		_:
			# Глиняная штукатурка: мягкие пятна.
			for k in int(r.size.x / 18.0):
				var px := r.position.x + 10 + k * 18 + WorldGen.hash01(p.id, k, 61) * 8.0
				var py := r.position.y + 12 + WorldGen.hash01(p.id, k, 62) * (r.size.y - 30)
				draw_circle(Vector2(px, py), 4 + WorldGen.hash01(p.id, k, 63) * 4, c[2])
	draw_rect(Rect2(r.position.x, r.end.y - 6, r.size.x, 6), ROOM_FLOOR)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5), c[1])
	draw_rect(Rect2(r.position.x, r.position.y, 5, r.size.y), c[1])
	draw_rect(Rect2(r.end.x - 5, r.position.y, 5, r.size.y), c[1])
	# Лестница — только у заглублённой комнаты, иначе вход с уровня земли.
	if p.ladder:
		_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
	var lamp := Vector2(r.get_center().x, r.position.y + 9)
	draw_circle(lamp, 14, Color(LAMP, 0.18))
	draw_circle(lamp, 5, LAMP)


func _draw_furniture(p: Project, r: Rect2, purpose: int, alpha: float) -> void:
	var floor_y := r.end.y - 6
	var x0 := view.cell_to_local(Vector2i(RoomType.floor_start(p), 0)).x
	match purpose:
		RoomType.HOME:
			for i in RoomType.beds(p):
				var bx := x0 + i * TILE * 2 + 4
				var bw := TILE * 2 - 8
				draw_rect(Rect2(bx, floor_y - 14, bw, 14), Color(BED_FRAME, alpha))
				draw_rect(Rect2(bx + 2, floor_y - 20, bw - 4, 8), Color(BLANKETS[(p.id + i) % BLANKETS.size()], alpha))
				draw_rect(Rect2(bx + 3, floor_y - 24, 14, 7), Color(0.95, 0.95, 0.92, alpha))
				draw_rect(Rect2(bx, floor_y - 26, 4, 26), Color(BED_FRAME, alpha))
		RoomType.STORAGE:
			var w := RoomType.usable_width(p)
			var room_cap := RoomType.CAPACITY_PER_CELL * w
			# Полка на половине высоты и ящики по видам ресурсов: чем больше, тем больше ящиков.
			draw_line(Vector2(x0 + 4, floor_y - 40), Vector2(x0 + w * TILE - 4, floor_y - 40), Color(BED_FRAME, alpha), 3.0)
			var slots := w * 2
			var slot := 0
			var keys: Array = colony.inventory.keys()
			keys.sort()
			for k in keys:
				if RoomType.BULK.has(k) or not RoomType.stores(p, k):
					continue
				var total_cap := colony.storage_capacity(k)
				if total_cap <= 0:
					continue
				var mine := colony.stored_split(k).x * room_cap / total_cap
				var boxes := ceili(mine / 10.0)
				for i in boxes:
					if slot >= slots * 2:
						break
					var lvl := (slot / slots) % 2
					var bx := x0 + 6 + (slot % slots) * TILE * 0.5
					var by := floor_y - 16 - lvl * 40
					draw_rect(Rect2(bx, by, 14, 16), Color(CRATE, alpha))
					draw_rect(Rect2(bx + 3, by + 3, 8, 6), Color(res_color(k), alpha))
					draw_rect(Rect2(bx, by, 14, 16), Color(CRATE.darkened(0.35), alpha), false, 1.0)
					slot += 1
		RoomType.FARM:
			var w := RoomType.usable_width(p)
			draw_rect(Rect2(x0 + 2, floor_y - 8, w * TILE - 4, 8), Color(SOIL, alpha))
			var grow := clampf(p.farm_progress / RoomType.FARM_CYCLE, 0.0, 1.0)
			for i in w * 2:
				var mx := x0 + 8 + i * TILE * 0.5
				var h := 6.0 + 10.0 * fmod(grow + WorldGen.hash01(p.id, i, 70), 1.0)
				draw_line(Vector2(mx, floor_y - 8), Vector2(mx, floor_y - 8 - h), Color(MUSHROOM, alpha), 3.0)
				draw_circle(Vector2(mx, floor_y - 8 - h), 4.0 + h * 0.15, Color(MUSHROOM_CAP, alpha))
		RoomType.DINING:
			var w := RoomType.usable_width(p)
			var tx := x0 + 8
			while tx + 40 < x0 + w * TILE:
				draw_rect(Rect2(tx, floor_y - 18, 40, 4), Color(BED_FRAME, alpha))
				draw_line(Vector2(tx + 6, floor_y - 14), Vector2(tx + 6, floor_y), Color(BED_FRAME, alpha), 3.0)
				draw_line(Vector2(tx + 34, floor_y - 14), Vector2(tx + 34, floor_y), Color(BED_FRAME, alpha), 3.0)
				draw_circle(Vector2(tx + 20, floor_y - 21), 4, Color(0.9, 0.9, 0.85, alpha))
				draw_rect(Rect2(tx - 8, floor_y - 9, 8, 3), Color(BED_FRAME.lightened(0.2), alpha))
				draw_rect(Rect2(tx + 40, floor_y - 9, 8, 3), Color(BED_FRAME.lightened(0.2), alpha))
				tx += 64


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
		# Закреплённые срезы и срез, где сейчас ставят крепь.
		for i in p.supported:
			_draw_slice_support(p, i, 1.0)
		if p.support_slice >= 0:
			_draw_slice_support(p, p.support_slice, 0.25 + 0.6 * clampf(p.support_progress / p.slice_work(), 0.0, 1.0))
	elif p.phase == Project.Phase.BUILD and not p.needs_support.is_empty():
		for i in p.supported:
			_draw_slice_support(p, i, 1.0)
	if p.phase != Project.Phase.DIG:
		var t := clampf(p.build_done / p.build_work(), 0.0, 1.0) if p.paid else 0.0
		if p.is_water_structure():
			_draw_deck(p, r, 0.3 + 0.7 * t)
		elif p.kind == Project.Kind.ROOM:
			var wall: Color = WALLS.get(p.material, WALLS["wood"])[0]
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * t, r.size.x, r.size.y * t), Color(wall, 0.55))
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


const RES_COLORS := {
	"wood": Color(0.55, 0.38, 0.2), "stone": Color(0.6, 0.6, 0.62), "clay": Color(0.66, 0.42, 0.3),
	"food": Color(0.85, 0.25, 0.3), "coal": Color(0.15, 0.14, 0.13), "iron": Color(0.69, 0.33, 0.18),
	"copper": Color(0.25, 0.68, 0.57), "silver": Color(0.84, 0.87, 0.9), "gold": Color(0.95, 0.79, 0.23),
	"uranium": Color(0.53, 0.88, 0.31), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.91, 0.87, 0.9),
	"oil": Color(0.1, 0.08, 0.06), "limestone": Color(0.81, 0.78, 0.69),
	"soil": Color(0.36, 0.25, 0.16), "sand": Color(0.85, 0.75, 0.52), "gravel": Color(0.55, 0.52, 0.47),
}


static func res_color(k: String) -> Color:
	return RES_COLORS.get(k, Color(0.6, 0.6, 0.6))


func _ground_y(x: float) -> float:
	return view.cell_to_local(Vector2i.ZERO).y + colony.world.gen.surface_smooth(x) * TILE


## Ресурсы, которым не хватило места на складах, лежат кучами у базы;
## пустая порода — в отвале справа от базы.
func _draw_stockpile(font: Font) -> void:
	var home := colony.home
	var bulk := 0
	for k in RoomType.BULK:
		bulk += colony.inventory.get(k, 0)
	if bulk > 0:
		var cx := home.x + 4.0
		var base := Vector2(view.cell_to_local(Vector2i(0, 0)).x + cx * TILE, _ground_y(cx))
		var rad := clampf(sqrt(bulk) * 3.0, 10.0, TILE * 3.0)
		var pts := PackedVector2Array()
		for i in 13:
			var a := PI + i * PI / 12.0
			pts.append(base + Vector2(cos(a) * rad * 1.4, sin(a) * rad * 0.7))
		draw_colored_polygon(pts, res_color("sand").lerp(res_color("soil"), 0.5))
		draw_circle(base + Vector2(-rad * 0.3, -rad * 0.45), rad * 0.18, res_color("gravel"))
		_label(font, base + Vector2(-20, -rad * 0.8 - 6), "отвал %d" % bulk, Color(0.95, 0.9, 0.8))
	var keys: Array = colony.inventory.keys()
	keys.sort()
	var i := 0
	for k in keys:
		if RoomType.BULK.has(k):
			continue
		var ground := colony.stored_split(k).y
		if ground <= 0:
			continue
		var cx := home.x - 3.0 - i * 1.6
		i += 1
		var base := Vector2(view.cell_to_local(Vector2i(0, 0)).x + cx * TILE, _ground_y(cx))
		var col := res_color(k)
		if k == "wood":
			# Штабель брёвен.
			var logs := clampi(ceili(ground / 4.0), 1, 10)
			var row := 0
			var left := logs
			while left > 0:
				var in_row := mini(left, 4 - row)
				for j in in_row:
					var c := base + Vector2((j - (in_row - 1) * 0.5) * 9.0, -5.0 - row * 8.0)
					draw_circle(c, 4.5, col)
					draw_circle(c, 2.0, col.lightened(0.35))
				left -= in_row
				row += 1
		else:
			var rad := clampf(sqrt(ground) * 2.2, 5.0, TILE * 0.9)
			var pts := PackedVector2Array()
			for j in 11:
				var a := PI + j * PI / 10.0
				pts.append(base + Vector2(cos(a) * rad, sin(a) * rad * 0.8))
			draw_colored_polygon(pts, col)
			draw_circle(base + Vector2(-rad * 0.3, -rad * 0.5), rad * 0.2, col.lightened(0.25))
		_label(font, base + Vector2(-8, -30), str(ground), Color(1, 1, 1, 0.9))



## Мостик: настил над водой, сваи и перила. Пристань: широкий настил и навес на берегу.
func _draw_deck(p: Project, r: Rect2, alpha: float) -> void:
	var plank := Color(0.6, 0.43, 0.25, alpha)
	var dark := Color(0.42, 0.29, 0.16, alpha)
	var deck_y := r.end.y - (8 if p.kind == Project.Kind.PIER else 6)
	draw_rect(Rect2(r.position.x, deck_y, r.size.x, r.end.y - deck_y), plank)
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, deck_y), Vector2(x, r.end.y), dark, 1.0)
		x += 8
	# Сваи уходят в воду.
	x = r.position.x + 4
	while x < r.end.x:
		draw_rect(Rect2(x, r.end.y, 5, TILE * 1.5), dark)
		x += TILE * (1.5 if p.kind == Project.Kind.PIER else 2.0)
	if p.kind == Project.Kind.BRIDGE:
		draw_line(Vector2(r.position.x, deck_y - 16), Vector2(r.end.x, deck_y - 16), plank, 3.0)
		x = r.position.x + 2
		while x < r.end.x:
			draw_line(Vector2(x, deck_y - 16), Vector2(x, deck_y), plank, 2.0)
			x += TILE
	else:
		# Навес рыбаков на береговом конце.
		var land_left := Mat.is_solid(colony.world.get_mat(p.rect.position.x, p.rect.position.y + 1))
		var hx := r.position.x if land_left else r.end.x - TILE * 1.6
		var hw := TILE * 1.6
		draw_rect(Rect2(hx + 4, deck_y - TILE * 1.3, hw - 8, TILE * 1.3), Color(0.72, 0.56, 0.36, alpha))
		draw_colored_polygon(PackedVector2Array([
			Vector2(hx - 4, deck_y - TILE * 1.3), Vector2(hx + hw * 0.5, deck_y - TILE * 2.1),
			Vector2(hx + hw + 4, deck_y - TILE * 1.3)]), Color(0.55, 0.25, 0.2, alpha))
		# Сети на шестах.
		draw_line(Vector2(hx + hw + 10, deck_y), Vector2(hx + hw + 10, deck_y - 30), dark, 2.0)



## Крепь одного среза: стойки по краям и верхняя балка (в шахте — пролёт лестницы).
func _draw_slice_support(p: Project, i: int, alpha: float) -> void:
	var cells := p.slice_cells(i)
	if cells.is_empty():
		return
	var col := Color(BEAM, alpha)
	var a := view.cell_to_local(cells[0])
	var b := view.cell_to_local(cells[cells.size() - 1]) + Vector2(TILE, TILE)
	if p.vertical():
		_ladder((a.x + b.x) * 0.5, a.y, b.y, alpha)
		return
	draw_line(Vector2(a.x + 4, a.y + 3), Vector2(a.x + 4, b.y), col, 4.0)
	draw_line(Vector2(b.x - 4, a.y + 3), Vector2(b.x - 4, b.y), col, 4.0)
	draw_line(Vector2(a.x, a.y + 3), Vector2(b.x, a.y + 3), col, 5.0)
