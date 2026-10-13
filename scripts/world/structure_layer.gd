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
const ROOM_FLOOR := Color(0.55, 0.36, 0.22)
const LAMP := Color(1.0, 0.9, 0.55)
const BEAM := Color(0.66, 0.44, 0.25)
const BEAM_DARK := Color(0.45, 0.29, 0.16)
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
	_draw_drops(font)
	_draw_gas()
	for p in colony.projects:
		_draw_supply(p, font)
		if p.wear >= Colony.WEAR_WARN[0] and not p.repairing:
			_draw_wear_sign(p)
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
	"wood": [Color(0.8, 0.56, 0.35), Color(0.48, 0.31, 0.19), Color(0.74, 0.51, 0.31)],
	"clay": [Color(0.9, 0.68, 0.5), Color(0.62, 0.4, 0.27), Color(0.84, 0.6, 0.43)],
	"stone": [Color(0.7, 0.73, 0.8), Color(0.42, 0.45, 0.55), Color(0.6, 0.63, 0.71)],
	"brick": [Color(0.84, 0.43, 0.32), Color(0.5, 0.24, 0.18), Color(0.95, 0.84, 0.74)],
	"metal": [Color(0.64, 0.7, 0.78), Color(0.34, 0.39, 0.47), Color(0.52, 0.58, 0.66)],
}
const BED_FRAME := Color(0.56, 0.36, 0.22)
const BLANKETS := [Color(0.31, 0.6, 0.95), Color(0.94, 0.4, 0.55), Color(0.38, 0.78, 0.45), Color(0.98, 0.72, 0.25)]
const SOIL := Color(0.38, 0.25, 0.17)
const MUSHROOM := Color(0.98, 0.95, 0.88)
const MUSHROOM_CAPS := [Color(1.0, 0.47, 0.35), Color(1.0, 0.78, 0.3), Color(0.6, 0.45, 1.0)]
const CRATE := Color(0.8, 0.58, 0.34)


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
			if p.purpose == RoomType.NONE and p.phase == Project.Phase.DONE:
				_draw_question(r)
	else:
		_draw_supports(p, r, 1.0 - p.wear * 0.5)
	if p.wear > 0.4:
		_draw_cracks(p, r)
	if p.repairing:
		var t := clampf(p.repair_done / maxf(1.0, p.repair_work), 0.0, 1.0) if p.repair_paid else 0.0
		var bar := Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 16, 6)
		draw_rect(bar, BAR_BG)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Color(0.4, 0.7, 1.0))
		_dashed_rect(r, Color(0.4, 0.7, 1.0), 2.5)
	if p.id == selected_project:
		draw_rect(r.grow(2), Color.WHITE, false, 2.0)


func _draw_room_shell(p: Project, r: Rect2) -> void:
	var c: Array = WALLS.get(p.material, WALLS["wood"])
	var wall: Color = c[0]
	draw_rect(r, wall)
	match p.material:
		"wood":
			# Доски — полосы чуть разного тона.
			var y := r.position.y
			var i := 0
			while y < r.end.y:
				var h := minf(12.0, r.end.y - y)
				draw_rect(Rect2(r.position.x, y, r.size.x, h), wall if i % 2 == 0 else c[2])
				draw_line(Vector2(r.position.x, y + h - 1), Vector2(r.end.x, y + h - 1), Color(c[1], 0.35), 1.0)
				y += 12
				i += 1
		"metal":
			# Стальные панели с заклёпками.
			var x := r.position.x + 5
			while x < r.end.x - 5:
				draw_line(Vector2(x, r.position.y + 5), Vector2(x, r.end.y - 6), c[2], 2.0)
				draw_circle(Vector2(x + 5, r.position.y + 12), 1.8, c[1])
				draw_circle(Vector2(x + 5, r.end.y - 14), 1.8, c[1])
				x += 24
		"stone", "brick":
			# Кладка блоками со смещением, у каждого блока светлый верх.
			var bh := 10.0 if p.material == "brick" else 16.0
			var bw := 24.0 if p.material == "brick" else 40.0
			var row := 0
			var y := r.position.y + 5
			while y < r.end.y - 6:
				var h := minf(bh, r.end.y - 6 - y)
				var x := r.position.x + 5 - (bw * 0.5 if row % 2 else 0.0)
				while x < r.end.x - 5:
					var bx := maxf(x, r.position.x + 5)
					var bwid := minf(x + bw, r.end.x - 5) - bx
					if bwid > 2:
						var tone := WorldGen.hash01(int(x), int(y), p.id) * 0.08
						draw_rect(Rect2(bx + 1, y + 1, bwid - 2, h - 2), wall.lightened(tone) if p.material == "stone" else wall.darkened(tone))
						draw_line(Vector2(bx + 2, y + 2), Vector2(bx + bwid - 3, y + 2), Color(1, 1, 1, 0.22), 1.5)
					x += bw
				y += bh
				row += 1
			# Швы.
			y = r.position.y + 5
			while y < r.end.y - 6:
				draw_line(Vector2(r.position.x + 5, y), Vector2(r.end.x - 5, y), Color(c[2], 0.8), 1.5)
				y += bh
		_:
			# Глиняная штукатурка: мягкие пятна.
			for k in int(r.size.x / 18.0):
				var px := r.position.x + 10 + k * 18 + WorldGen.hash01(p.id, k, 61) * 8.0
				var py := r.position.y + 12 + WorldGen.hash01(p.id, k, 62) * (r.size.y - 30)
				draw_circle(Vector2(px, py), 4 + WorldGen.hash01(p.id, k, 63) * 4, c[2])
	# Тень под потолком.
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 16), Vector2(r.position.x, r.position.y + 16)]),
		PackedColorArray([Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	# Пол — доски с бликом.
	draw_rect(Rect2(r.position.x, r.end.y - 7, r.size.x, 7), ROOM_FLOOR)
	draw_line(Vector2(r.position.x, r.end.y - 6), Vector2(r.end.x, r.end.y - 6), ROOM_FLOOR.lightened(0.25), 1.5)
	# Рама тоном стены, со скруглёнными углами.
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = c[1]
	frame.set_border_width_all(5)
	frame.set_corner_radius_all(6)
	draw_style_box(frame, r)
	# Лестница у стены, за которой снаружи порода или уступ: по ней выбираются наверх.
	if p.ladder or _wall_outside(p, -1):
		_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
	if _wall_outside(p, 1):
		_ladder(r.end.x - TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
	# Лампа горит, только когда есть электричество.
	if colony.powered() and colony.is_underground(p):
		var lamp := Vector2(r.get_center().x, r.position.y + 10)
		_glow(lamp + Vector2(0, 6), r.size.y * 0.9, Color(1.0, 0.86, 0.45, 0.28))
		draw_line(lamp + Vector2(0, -5), lamp, Color(0.25, 0.25, 0.3), 2.0)
		draw_circle(lamp + Vector2(0, 4), 5, LAMP)
		draw_circle(lamp + Vector2(-1.5, 2.5), 1.6, Color.WHITE)


## Мягкое световое пятно: веер треугольников от яркого центра к прозрачному краю.
func _glow(c: Vector2, rad: float, col: Color) -> void:
	var edge := Color(col, 0.0)
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		draw_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad]),
			PackedColorArray([col, edge, edge]))


## Прямоугольник со скруглением (мебель, плашки).
func _rbox(r: Rect2, rad: int, col: Color, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(rad)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, r)


## Снаружи у стены комнаты (side −1 — слева, 1 — справа) на уровне пола не выйти.
func _wall_outside(p: Project, side: int) -> bool:
	var x := p.rect.position.x - 1 if side < 0 else p.rect.end.x
	var floor_y := p.rect.end.y - 1
	return not colony.world.is_open(x, floor_y) and colony.world.is_open(x, p.rect.position.y)


## Комната построена, но не обустроена — большой знак вопроса посередине.
func _draw_question(r: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(clampf(r.size.y * 0.75, 28.0, 72.0))
	var c := r.get_center()
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
	draw_circle(c, fs * 0.55, Color(0.98, 0.72, 0.25, 0.35 * pulse))
	var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := c + Vector2(-w * 0.5, fs * 0.36)
	draw_string_outline(font, p, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.25, 0.15, 0.05, 0.9))
	draw_string(font, p, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.3))


func _draw_furniture(p: Project, r: Rect2, purpose: int, alpha: float) -> void:
	var floor_y := r.end.y - 6
	var x0 := view.cell_to_local(Vector2i(RoomType.floor_start(p), 0)).x
	match purpose:
		RoomType.HOME:
			for i in RoomType.beds(p):
				var bx := x0 + i * TILE * 2 + 4
				var bw := TILE * 2 - 8
				var blanket: Color = BLANKETS[(p.id + i) % BLANKETS.size()]
				_rbox(Rect2(bx, floor_y - 12, bw, 12), 3, Color(BED_FRAME, alpha))
				_rbox(Rect2(bx, floor_y - 26, 5, 26), 2, Color(BED_FRAME.darkened(0.15), alpha))
				_rbox(Rect2(bx + 6, floor_y - 22, 15, 9), 4, Color(0.98, 0.97, 0.94, alpha))
				_rbox(Rect2(bx + 18, floor_y - 21, bw - 18, 12), 6, Color(blanket, alpha), Color(blanket.darkened(0.25), alpha), 1)
				draw_line(Vector2(bx + 23, floor_y - 18), Vector2(bx + bw - 5, floor_y - 18), Color(1, 1, 1, 0.35 * alpha), 2.0)
		RoomType.STORAGE, RoomType.GRANARY:
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
					_rbox(Rect2(bx, by, 14, 16), 3, Color(CRATE, alpha), Color(CRATE.darkened(0.35), alpha), 1)
					draw_line(Vector2(bx + 2, by + 2), Vector2(bx + 12, by + 14), Color(CRATE.darkened(0.2), alpha), 1.5)
					_rbox(Rect2(bx + 3, by + 3, 8, 6), 2, Color(res_color(k), alpha))
					slot += 1
		RoomType.FARM:
			var w := RoomType.usable_width(p)
			_rbox(Rect2(x0 + 2, floor_y - 9, w * TILE - 4, 9), 4, Color(SOIL, alpha), Color(SOIL.darkened(0.3), alpha), 1)
			var grow := clampf(p.farm_progress / RoomType.FARM_CYCLE, 0.0, 1.0)
			var warm := colony.farm_warm(p)
			for i in w * 2:
				var mx := x0 + 8 + i * TILE * 0.5
				var h := 6.0 + 10.0 * fmod(grow + WorldGen.hash01(p.id, i, 70), 1.0)
				var cap: Color = MUSHROOM_CAPS[(p.id + i) % MUSHROOM_CAPS.size()]
				if not warm:
					cap = cap.lerp(Color(0.6, 0.62, 0.7), 0.6) # в холоде грибы блёклые
				var top := Vector2(mx, floor_y - 9 - h)
				draw_line(Vector2(mx, floor_y - 9), top, Color(MUSHROOM, alpha), 3.0)
				var rad := 4.0 + h * 0.18
				if warm:
					draw_circle(top, rad * 1.9, Color(cap, 0.12 * alpha))
				var dome := PackedVector2Array()
				for j in 9:
					var a := PI + PI * j / 8.0
					dome.append(top + Vector2(cos(a) * rad, sin(a) * rad * 0.85 + 1.5))
				draw_colored_polygon(dome, Color(cap, alpha))
				draw_circle(top + Vector2(-rad * 0.35, -rad * 0.3), rad * 0.22, Color(1, 1, 1, 0.75 * alpha))
		RoomType.PUMP:
			# Насос и труба вверх через потолок.
			var px := x0 + TILE * 1.2
			draw_rect(Rect2(px - 14, floor_y - 26, 28, 26), Color(0.35, 0.45, 0.55, alpha))
			draw_rect(Rect2(px - 4, r.position.y, 8, floor_y - 26 - r.position.y), Color(0.45, 0.5, 0.55, alpha))
			var a := Time.get_ticks_msec() / 300.0
			draw_arc(Vector2(px + 26, floor_y - 18), 10, 0, TAU, 16, Color(0.55, 0.38, 0.2, alpha), 3.0)
			draw_line(Vector2(px + 26, floor_y - 18), Vector2(px + 26, floor_y - 18) + Vector2(cos(a), sin(a)) * 10, Color(0.55, 0.38, 0.2, alpha), 3.0)
			draw_line(Vector2(px + 14, floor_y - 18), Vector2(px + 26, floor_y - 18), Color(0.45, 0.5, 0.55, alpha), 3.0)
		RoomType.VENT:
			# Вентилятор в стене и короб воздуховода.
			var cx := x0 + RoomType.usable_width(p) * TILE * 0.5
			var cy := (r.position.y + floor_y) * 0.5
			draw_rect(Rect2(x0 + 4, r.position.y + 6, RoomType.usable_width(p) * TILE - 8, 10), Color(0.55, 0.58, 0.62, alpha))
			draw_circle(Vector2(cx, cy), 20, Color(0.3, 0.33, 0.38, alpha))
			var a := Time.get_ticks_msec() / 120.0
			for k in 3:
				var dir := Vector2(cos(a + k * TAU / 3.0), sin(a + k * TAU / 3.0))
				draw_line(Vector2(cx, cy), Vector2(cx, cy) + dir * 17, Color(0.85, 0.88, 0.92, alpha), 5.0)
			draw_circle(Vector2(cx, cy), 4, Color(0.2, 0.2, 0.22, alpha))
		RoomType.HEARTH:
			# Каменный очаг; горит — огонь и тёплый свет вокруг.
			var cx := x0 + RoomType.usable_width(p) * TILE * 0.5
			var base := Rect2(cx - 26, floor_y - 34, 52, 34)
			_rbox(base, 6, Color(0.62, 0.6, 0.66, alpha), Color(0.4, 0.38, 0.44, alpha), 2)
			_rbox(Rect2(cx - 16, floor_y - 22, 32, 22), 8, Color(0.16, 0.1, 0.1, alpha))
			_rbox(Rect2(cx - 30, floor_y - 40, 60, 8), 3, Color(0.52, 0.5, 0.56, alpha))
			if p.burning and alpha >= 1.0:
				var tt := Time.get_ticks_msec() / 1000.0
				_glow(Vector2(cx, floor_y - 12), r.size.y * 1.4, Color(1.0, 0.6, 0.25, 0.25))
				for k in 3:
					var fx := cx + (k - 1) * 8.0
					var fh := 12.0 + 5.0 * sin(tt * 7.0 + k * 2.0)
					draw_colored_polygon(PackedVector2Array([Vector2(fx - 6, floor_y - 2), Vector2(fx + 6, floor_y - 2), Vector2(fx + sin(tt * 5.0 + k) * 2.0, floor_y - 2 - fh)]),
						Color(1.0, 0.5, 0.15))
					draw_colored_polygon(PackedVector2Array([Vector2(fx - 3, floor_y - 2), Vector2(fx + 3, floor_y - 2), Vector2(fx, floor_y - 2 - fh * 0.6)]),
						Color(1.0, 0.85, 0.35))
			# Поленница.
			for k in 3:
				draw_circle(Vector2(cx + 40 + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 4.5, Color(0.66, 0.44, 0.25, alpha))
				draw_circle(Vector2(cx + 40 + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 2.0, Color(0.9, 0.75, 0.5, alpha))
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
		var dark := Color(BEAM_DARK, alpha)
		var x := r.position.x + TILE * 0.5
		while x < r.end.x:
			for sx in [-8.0, 8.0]:
				draw_line(Vector2(x + sx + 1.5, r.end.y), Vector2(x + sx + 1.5, r.position.y + 3), dark, 4.5)
				draw_line(Vector2(x + sx, r.end.y), Vector2(x + sx, r.position.y + 3), col, 4.5)
			draw_line(Vector2(x - 13, r.position.y + 5), Vector2(x + 13, r.position.y + 5), dark, 6.0)
			draw_line(Vector2(x - 13, r.position.y + 3), Vector2(x + 13, r.position.y + 3), col, 6.0)
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
	var dark := Color(BEAM_DARK, alpha)
	var y := top + 8
	while y < bottom:
		draw_line(Vector2(cx - 7, y + 1.5), Vector2(cx + 7, y + 1.5), dark, 3.0)
		draw_line(Vector2(cx - 7, y), Vector2(cx + 7, y), col, 3.0)
		y += 10
	for sx in [-8.0, 8.0]:
		draw_line(Vector2(cx + sx + 1, top), Vector2(cx + sx + 1, bottom), dark, 3.5)
		draw_line(Vector2(cx + sx, top), Vector2(cx + sx, bottom), col, 3.5)


const RES_COLORS := {
	"wood": Color(0.55, 0.38, 0.2), "stone": Color(0.6, 0.6, 0.62), "clay": Color(0.66, 0.42, 0.3),
	"food": Color(0.55, 0.72, 0.85), "berries": Color(0.85, 0.25, 0.3), "coal": Color(0.15, 0.14, 0.13), "iron": Color(0.69, 0.33, 0.18),
	"copper": Color(0.25, 0.68, 0.57), "silver": Color(0.84, 0.87, 0.9), "gold": Color(0.95, 0.79, 0.23),
	"uranium": Color(0.53, 0.88, 0.31), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.91, 0.87, 0.9),
	"oil": Color(0.1, 0.08, 0.06), "limestone": Color(0.81, 0.78, 0.69),
	"soil": Color(0.36, 0.25, 0.16), "sand": Color(0.85, 0.75, 0.52), "gravel": Color(0.55, 0.52, 0.47),
}


static func res_color(k: String) -> Color:
	return RES_COLORS.get(k, Color(0.6, 0.6, 0.6))


## Плашки над стройкой: значок ресурса и «принесено/нужно»; красная — взять неоткуда.
func _draw_supply(p: Project, font: Font) -> void:
	var items := colony.supply_status(p)
	if items.is_empty():
		return
	var r := _rect_px(p.rect)
	var fs := 18
	var widths: Array[float] = []
	var total := 0.0
	for e in items:
		var w := 34.0 + font.get_string_size("%d/%d" % [e[1], e[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
		widths.append(w)
		total += w + 6.0
	var x := r.get_center().x - (total - 6.0) * 0.5
	var y := r.position.y - 36.0
	for i in items.size():
		var e: Array = items[i]
		var box := Rect2(x, y, widths[i], 28)
		var bg := Color(0.17, 0.13, 0.16, 0.9) if e[3] else Color(0.86, 0.3, 0.25, 0.95)
		_rbox(Rect2(box.position + Vector2(0, 3), box.size), 14, bg.darkened(0.4))
		_rbox(box, 14, bg, bg.lightened(0.15), 1)
		ResIcon.draw(self, e[0], Vector2(x + 16, y + 14), 10)
		var tp := Vector2(x + 30, y + 21)
		draw_string(Fonts.black(), tp, "%d/%d" % [e[1], e[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		x += widths[i] + 6.0


## Добытое, лежащее на земле: кучка значков и число.
func _draw_drops(font: Font) -> void:
	for c: Vector2i in colony.drops:
		var d: Dictionary = colony.drops[c]
		var p := view.cell_to_local(c) + Vector2(TILE * 0.5, TILE)
		# На естественной поверхности — по сглаженной линии земли.
		if c.y == colony.world.gen.surface_y(c.x) - 1 and not colony.world.is_dug(c.x, c.y + 1):
			p.y = _ground_y(c.x + 0.5)
		var i := 0
		for k in d:
			var n: int = d[k]
			var piles := clampi(ceili(n / 3.0), 1, 4)
			for j in piles:
				ResIcon.draw(self, k, p + Vector2((j - (piles - 1) * 0.5) * 9.0 + i * 6.0, -7.0 - (j % 2) * 5.0 - i * 9.0), 8.0)
			i += 1
			if i >= 2:
				break
		var total := 0
		for k in d:
			total += int(d[k])
		_label(font, p + Vector2(-6, -26 - i * 6), str(total), Color(1, 1, 1, 0.9))


## Метан: зеленоватая дымка, гуще — опаснее.
func _draw_gas() -> void:
	for c: Vector2i in colony.elements.gas:
		var g: float = colony.elements.gas[c]
		var col := Color(0.55, 0.8, 0.25, clampf(g * 0.8, 0.05, 0.55))
		if g >= Elements.GAS_EXPLOSIVE:
			col = Color(0.75, 0.85, 0.2, clampf(g * 0.8, 0.2, 0.65))
		draw_rect(Rect2(view.cell_to_local(c), Vector2(TILE, TILE)), col)


## Трещины на ветхой постройке — тем больше, чем сильнее износ.
func _draw_cracks(p: Project, r: Rect2) -> void:
	var n := int((p.wear - 0.4) * 12.0) + 1
	var col := Color(0.15, 0.1, 0.08, 0.35 + p.wear * 0.4)
	for k in n:
		var a := r.position + Vector2(10 + WorldGen.hash01(p.id, k, 81) * (r.size.x - 20), 8 + WorldGen.hash01(p.id, k, 82) * (r.size.y - 20))
		var b := a + Vector2(WorldGen.hash01(p.id, k, 83) * 14 - 7, 9)
		var c := b + Vector2(WorldGen.hash01(p.id, k, 84) * 14 - 7, 9)
		draw_polyline(PackedVector2Array([a, b, c]), col, 2.0)


## Знак «нужен ремонт» над ветхой постройкой (мигает, если вот-вот рухнет).
func _draw_wear_sign(p: Project) -> void:
	var r := _rect_px(p.rect)
	var col := Color(1.0, 0.7, 0.2) if p.wear < Colony.WEAR_WARN[1] else Color(1.0, 0.3, 0.25)
	if p.wear >= Colony.WEAR_WARN[1] and int(Time.get_ticks_msec() / 400) % 2 == 0:
		col = col.lightened(0.4)
	var c := Vector2(r.end.x - 14, r.position.y - 16)
	draw_circle(c, 15, Color(0, 0, 0, 0.55))
	ResIcon.draw_glyph(self, "warning", c, 12, col)


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
