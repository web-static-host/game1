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


## Значки (износ, нет работника, мороз) — отдельным слоем поверх темноты, чтобы их было видно
## и в неосвещённых комнатах.
var _signs: Node2D


func _ready() -> void:
	_signs = Node2D.new()
	_signs.z_index = 11
	_signs.draw.connect(_draw_signs)
	add_child(_signs)


func _process(_delta: float) -> void:
	queue_redraw()
	if _signs != null:
		_signs.queue_redraw()


func _draw_signs() -> void:
	if colony == null:
		return
	for p in colony.projects:
		if p.wear >= Colony.WEAR_WARN[0] and not p.repairing:
			_draw_wear_sign(p)
		if colony.is_workplace(p) and p.kind != Project.Kind.BRIDGE and not p.paused and colony.assigned_to(p).is_empty():
			_draw_no_worker_sign(p)
		if colony.home_freezing(p):
			_draw_frost_sign(p)


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
	# Бур — поверх хода, который сверлит.
	for p in colony.projects:
		if p.kind == Project.Kind.DRILL and p.phase == Project.Phase.DONE:
			_draw_drill(p, _rect_px(p.rect), 1.0)
	_draw_dig_progress()
	_draw_drops(font)
	_draw_gas()
	for p in colony.projects:
		_draw_supply(p, font)
	# Падающая порода.
	for f in colony.physics.fx:
		var t := clampf(f[3] / Physics.FX_TIME, 0.0, 1.0)
		var pos: Vector2 = (f[0] as Vector2).lerp(f[1], t * t)
		var px := view.cell_to_local(Vector2i.ZERO) + pos * TILE
		var col := ChunkView.rock_color(f[2], 0.5)
		draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col)
		draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col.darkened(0.3), false, 2.0)
	# Лампы там, где сейчас идёт работа на стройке или в шахте.
	for c in colony.work_lamps:
		var at := view.cell_to_local(c) + Vector2(TILE * 0.5, 2)
		_glow(at + Vector2(0, 8), TILE * 2.2, Color(1.0, 0.86, 0.45, 0.3))
		draw_line(at + Vector2(-6, -2), at + Vector2(6, -2), Color(0.3, 0.3, 0.32), 2.0)
		draw_circle(at + Vector2(0, 3), 4, LAMP)
	_draw_zone(colony.project_by_id(selected_project) if selected_project != 0 else null)
	if preview.size != Vector2i.ZERO:
		var r := _rect_px(preview)
		var col := Color(0.4, 1.0, 0.45) if preview_ok else Color(1.0, 0.35, 0.3)
		draw_rect(r, Color(col, 0.18))
		draw_rect(r, col, false, 3.0)
		_label(font, r.position + Vector2(4, -8), preview_text, col)


## Цвета по материалу стен: [задняя стена, рама, линии кладки].
const WALLS := {
	"wood": [Color(0.8, 0.56, 0.35), Color(0.48, 0.31, 0.19), Color(0.74, 0.51, 0.31)],
	"stone": [Color(0.7, 0.73, 0.8), Color(0.42, 0.45, 0.55), Color(0.6, 0.63, 0.71)],
	"brick": [Color(0.84, 0.43, 0.32), Color(0.5, 0.24, 0.18), Color(0.95, 0.84, 0.74)],
	"iron": [Color(0.64, 0.7, 0.78), Color(0.34, 0.39, 0.47), Color(0.52, 0.58, 0.66)],
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
				_draw_furniture(p, r, RoomType.base_type(p.equip_target), 0.25 + 0.6 * t)
			var bar := Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 16, 6)
			draw_rect(bar, BAR_BG)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
			_dashed_rect(r, PAUSED if p.paused else BUILD_EDGE, 2.5)
		else:
			_draw_furniture(p, r, p.purpose, 1.0)
			if p.purpose == RoomType.NONE and p.phase == Project.Phase.DONE:
				_draw_question(r)
	elif p.kind == Project.Kind.LIFT:
		_draw_lift(p, r)
	elif p.kind != Project.Kind.DRILL:
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


## Корабль: койки в два яруса, пульт, иллюминаторы; снаружи — нос, стабилизаторы, опоры.
const HULL := Color(0.78, 0.8, 0.84)
const HULL_DARK := Color(0.45, 0.48, 0.55)


func _draw_ship(p: Project, r: Rect2, alpha: float) -> void:
	# Нос справа, стабилизаторы слева, опоры снизу — вокруг комнаты.
	var mid := r.get_center().y
	draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y + 4), Vector2(r.end.x + TILE * 2.2, mid),
		Vector2(r.end.x, r.end.y - 4)]), Color(HULL, alpha))
	draw_polyline(PackedVector2Array([Vector2(r.end.x, r.position.y + 4), Vector2(r.end.x + TILE * 2.2, mid),
		Vector2(r.end.x, r.end.y - 4)]), Color(HULL_DARK, alpha), 3.0)
	for sgn in [-1.0, 1.0]:
		var base: Vector2 = Vector2(r.position.x, mid + sgn * r.size.y * 0.35)
		draw_colored_polygon(PackedVector2Array([base, base + Vector2(-TILE * 1.4, sgn * TILE * 1.2),
			base + Vector2(TILE * 0.8, 0)]), Color(0.85, 0.35, 0.3, alpha))
	for k in 3:
		var lx := r.position.x + r.size.x * (0.2 + 0.3 * k)
		draw_line(Vector2(lx, r.end.y), Vector2(lx - 6, r.end.y + 10), Color(HULL_DARK, alpha), 3.0)
	# Иллюминаторы под потолком.
	for k in 4:
		var wc := Vector2(r.position.x + r.size.x * (0.15 + 0.23 * k), r.position.y + 14)
		draw_circle(wc, 7, Color(HULL_DARK, alpha))
		draw_circle(wc, 5, Color(0.55, 0.8, 1.0, alpha))
	# Койки в два яруса вдоль стены.
	var n := 5
	for i in n:
		var bx := r.position.x + 8 + i * (r.size.x - 70) / n
		var bw := (r.size.x - 70) / n - 6
		for lvl in 2:
			var by := r.end.y - 14 - lvl * 22
			_rbox(Rect2(bx, by, bw, 9), 3, Color(0.5, 0.55, 0.65, alpha))
			_rbox(Rect2(bx + 2, by - 4, bw * 0.35, 5), 2, Color(0.95, 0.95, 0.92, alpha))
	# Пульт с огоньками.
	var cx := r.end.x - 52
	_rbox(Rect2(cx, r.end.y - 34, 44, 28), 5, Color(0.3, 0.33, 0.4, alpha), Color(0.15, 0.16, 0.2, alpha), 2)
	var blink := int(Time.get_ticks_msec() / 500) % 3
	for k in 3:
		draw_circle(Vector2(cx + 9 + k * 13, r.end.y - 25), 3.5,
			Color(0.4, 1.0, 0.5, alpha) if k == blink else Color(0.25, 0.45, 0.3, alpha))


## Космодром: бетонный стол, башня обслуживания; ракета на столе (во время сборки — в лесах).
func _draw_launchpad(p: Project, r: Rect2, alpha: float) -> void:
	_rbox(Rect2(r.position.x + 4, r.end.y - 16, r.size.x - 8, 12), 3, Color(0.62, 0.62, 0.6, alpha), Color(0.4, 0.4, 0.4, alpha), 2)
	var tx := r.end.x - TILE * 0.8
	for y in range(int(r.position.y - TILE * 12), int(r.end.y - 16), 18):
		draw_line(Vector2(tx - 8, y), Vector2(tx + 8, y + 18), Color(0.75, 0.3, 0.25, alpha), 2.0)
		draw_line(Vector2(tx + 8, y), Vector2(tx - 8, y + 18), Color(0.75, 0.3, 0.25, alpha), 2.0)
	draw_line(Vector2(tx - 8, r.position.y - TILE * 12), Vector2(tx - 8, r.end.y - 16), Color(0.6, 0.25, 0.2, alpha), 3.0)
	draw_line(Vector2(tx + 8, r.position.y - TILE * 12), Vector2(tx + 8, r.end.y - 16), Color(0.6, 0.25, 0.2, alpha), 3.0)
	var t := 0.0
	if not p.rocket.is_empty():
		t = 1.0
	elif not p.equip_rocket.is_empty():
		t = clampf(p.equip_done / RoomType.ROCKET_WORK, 0.0, 1.0) if p.equip_paid else 0.0
	else:
		return
	var nuclear := p.rocket == "nuclear" or p.equip_rocket == "nuclear"
	var cx := r.get_center().x - TILE * 0.6
	var w := TILE * 2.4
	var top := r.end.y - 16 - TILE * 14
	var body := Rect2(cx - w * 0.5, top + TILE * 2.5, w, r.end.y - 16 - top - TILE * 2.5)
	var a := alpha * (0.35 + 0.65 * t)
	# Корпус растёт снизу вверх по мере сборки.
	var built := Rect2(body.position.x, body.end.y - body.size.y * maxf(t, 0.05), body.size.x, body.size.y * maxf(t, 0.05))
	_rbox(body, 6, Color(HULL, alpha * 0.18), Color(HULL_DARK, alpha * 0.4), 1)
	_rbox(built, 6, Color(HULL, a), Color(HULL_DARK, a), 2)
	if t >= 0.999:
		draw_colored_polygon(PackedVector2Array([Vector2(body.position.x, body.position.y), Vector2(cx, top),
			Vector2(body.end.x, body.position.y)]), Color(0.85, 0.3, 0.28, alpha) if not nuclear else Color(0.3, 0.75, 0.4, alpha))
		for sgn in [-1.0, 1.0]:
			var fx: float = cx + sgn * w * 0.5
			draw_colored_polygon(PackedVector2Array([Vector2(fx, body.end.y - TILE * 2.5), Vector2(fx + sgn * TILE, body.end.y),
				Vector2(fx, body.end.y)]), Color(0.85, 0.3, 0.28, alpha))
		draw_circle(Vector2(cx, body.position.y + TILE * 2), 9, Color(HULL_DARK, alpha))
		draw_circle(Vector2(cx, body.position.y + TILE * 2), 6.5, Color(0.55, 0.8, 1.0, alpha))
		if nuclear:
			draw_circle(Vector2(cx, body.end.y - TILE * 3), 8, Color(1.0, 0.85, 0.2, alpha))


## Бур — машина 3×3: корпус с мотором сзади, сверло спереди (куда едет; стоит — вниз).
## Сверло крутится, пока бур сверлит.
func _draw_drill(p: Project, r: Rect2, alpha: float) -> void:
	var dir := p.drill_dir if p.drill_dir != Vector2i.ZERO else Vector2i.DOWN
	var body := r.grow(-3)
	var face := r
	if dir == Vector2i.DOWN:
		body.size.y = TILE * 2 - 4
		face = Rect2(r.position.x, r.position.y + TILE * 2, r.size.x, TILE)
	elif dir == Vector2i.RIGHT:
		body.size.x = TILE * 2 - 4
		face = Rect2(r.position.x + TILE * 2, r.position.y, TILE, r.size.y)
	else:
		body.position.x += TILE + 2
		body.size.x = TILE * 2 - 4
		face = Rect2(r.position.x, r.position.y, TILE, r.size.y)
	_rbox(body, 6, Color(0.88, 0.62, 0.16, alpha), Color(0.45, 0.3, 0.1, alpha), 2)
	# Решётка мотора и лампа: горит, когда есть энергия.
	var mc := body.get_center()
	for k in 3:
		var off := (k - 1) * 7.0
		if dir == Vector2i.DOWN:
			draw_line(mc + Vector2(-12, off), mc + Vector2(12, off), Color(0.45, 0.3, 0.1, alpha), 2.0)
		else:
			draw_line(mc + Vector2(off, -12), mc + Vector2(off, 12), Color(0.45, 0.3, 0.1, alpha), 2.0)
	var lamp_on := colony.powered() or p.fuel > 0.0
	draw_circle(body.position + Vector2(9, 9), 4, Color(LAMP, alpha) if lamp_on else Color(0.35, 0.35, 0.38, alpha))
	var d := Vector2(dir)
	var side := Vector2(-d.y, d.x)
	var base_c := face.get_center() - d * TILE * 0.5
	var tip := face.get_center() + d * TILE * 0.45
	var half := side * TILE * 1.3
	draw_colored_polygon(PackedVector2Array([base_c - half, base_c + half, tip]), Color(0.6, 0.62, 0.68, alpha))
	var spin := Time.get_ticks_msec() * 0.01 if colony._drill_active(p) and lamp_on else 0.0
	for k in 3:
		var t := fmod(spin + k / 3.0, 1.0)
		var m := base_c.lerp(tip, t)
		var w := half * (1.0 - t)
		draw_line(m - w, m + w, Color(0.3, 0.31, 0.35, alpha), 2.0)


## Лифт: железные направляющие вдоль шахты, трос и кабина (у грузового — с ящиками).
const LIFT_STEEL := Color(0.55, 0.58, 0.64)
const LIFT_CAB := Color(0.86, 0.62, 0.22)


func _draw_lift(p: Project, r: Rect2) -> void:
	var dark := Color(0.2, 0.21, 0.24)
	var cab_col := Color(0.5, 0.56, 0.62) if p.cargo else LIFT_CAB
	if p.lift_vertical():
		for x in [r.position.x + 3, r.end.x - 3]:
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), dark, 5.0)
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), LIFT_STEEL, 3.0)
		var y := r.end.y - TILE
		if p.lift_pos != Project.LIFT_UNSET:
			y = view.cell_to_local(Vector2i(0, 0)).y + p.lift_pos * TILE
		# Кабина — на высоту человека (2 м) над полом клетки, где стоит.
		var cab := Rect2(r.position.x + 5, y - TILE + 2, r.size.x - 10, TILE * 2 - 2)
		draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, cab.position.y), Color(0.15, 0.15, 0.17), 2.0)
		_draw_cabin(cab, cab_col, p)
	else:
		draw_line(Vector2(r.position.x, r.end.y - 3), Vector2(r.end.x, r.end.y - 3), LIFT_STEEL, 4.0)
		draw_line(Vector2(r.position.x, r.position.y + 4), Vector2(r.end.x, r.position.y + 4), LIFT_STEEL, 3.0)
		var x0 := r.position.x
		if p.lift_pos != Project.LIFT_UNSET:
			x0 = view.cell_to_local(Vector2i(0, 0)).x + p.lift_pos * TILE
		var cab := Rect2(x0 - TILE * 0.5 + 2, r.end.y - TILE * 2 - 2, TILE * 2 - 4, TILE * 2)
		_draw_cabin(cab, cab_col, p)


func _draw_cabin(cab: Rect2, col: Color, p: Project) -> void:
	_rbox(cab, 5, Color(col, 0.35), col.darkened(0.3), 3)
	if p.cargo and not p.lift_load.is_empty():
		var n := mini(4, 1 + int(colony._load_total(p.lift_load)) / 10)
		for i in n:
			var bx := cab.position.x + 4 + (i % 2) * (cab.size.x * 0.5 - 4)
			var by := cab.end.y - 12 - (i / 2) * 11
			_rbox(Rect2(bx, by, cab.size.x * 0.5 - 8, 10), 2, Color(0.65, 0.45, 0.25), Color(0.4, 0.27, 0.15), 1)
	# Лампочка: горит, когда лифт под током.
	draw_circle(Vector2(cab.get_center().x, cab.position.y + 5), 3.0,
		LAMP if colony.lift_powered(p) else Color(0.35, 0.35, 0.38))


## Радиус действия выбранной комнаты: насос, вентиляция, дегазация — квадрат вокруг центра;
## очаг и генератор — полное тепло и до куда доходит (от стен комнаты).
func _draw_zone(p: Project) -> void:
	if p == null or p.kind != Project.Kind.ROOM or p.phase != Project.Phase.DONE:
		return
	var rad := RoomType.effect_radius(p)
	if rad > 0:
		var c := p.rect.get_center()
		var col := Color(0.45, 0.75, 1.0) if p.purpose != RoomType.VENT else Color(0.6, 0.95, 1.0)
		var zr := _rect_px(Rect2i(c - Vector2i(rad, rad), Vector2i(rad * 2 + 1, rad * 2 + 1)))
		draw_rect(zr, Color(col, 0.13))
		_dashed_rect(zr, Color(col, 0.85), 3.0)
		return
	if p.purpose == RoomType.HEARTH or p.purpose in RoomType.GENERATORS:
		var zone := RoomType.heat_zone(p, colony.research.has("insulation"))
		var reach := _rect_px(p.rect.grow(zone.y))
		var full := _rect_px(p.rect.grow(zone.x))
		draw_rect(reach, Color(1.0, 0.6, 0.2, 0.09))
		_dashed_rect(reach, Color(1.0, 0.6, 0.2, 0.6), 2.5)
		draw_rect(full, Color(1.0, 0.45, 0.15, 0.12))
		_dashed_rect(full, Color(1.0, 0.5, 0.2, 0.9), 3.0)


func _draw_room_shell(p: Project, r: Rect2) -> void:
	var tex := room_texture(p.material, p.rect.size.x)
	if tex != null:
		draw_texture_rect(tex, r, false)
	else:
		_draw_room_walls(p, r)
	# Лестница у стены, за которой снаружи порода или уступ: по ней выбираются наверх.
	if colony.edge_ladder(p, -1):
		_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
	if colony.edge_ladder(p, 1):
		_ladder(r.end.x - TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0)
	# Лампочки — по одной на каждые 3 м; горят, когда в комнате включён свет.
	if colony.research.has("electricity") and colony.is_underground(p):
		var n := RoomType.blocks(p)
		for i in n:
			var lamp := Vector2(r.position.x + r.size.x * (i + 0.5) / n, r.position.y + 10)
			draw_line(lamp + Vector2(0, -5), lamp, Color(0.25, 0.25, 0.3), 2.0)
			if p.lit:
				_glow(lamp + Vector2(0, 6), r.size.y * 0.9, Color(1.0, 0.86, 0.45, 0.28))
				draw_circle(lamp + Vector2(0, 4), 5, LAMP)
				draw_circle(lamp + Vector2(-1.5, 2.5), 1.6, Color.WHITE)
			else:
				draw_circle(lamp + Vector2(0, 4), 5, Color(0.35, 0.35, 0.38))


## Готовая картинка комнаты (рендер из Blender, assets/rooms/) или null — тогда рисуем сами.
static var _room_tex := {}
static func room_texture(material: String, w: int) -> Texture2D:
	var key := "%s_%d" % [material, w]
	if not _room_tex.has(key):
		var path := "res://assets/rooms/%s.png" % key
		_room_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _room_tex[key]


## Стены, пол и рама, нарисованные кодом (для материалов без готовой картинки).
func _draw_room_walls(p: Project, r: Rect2) -> void:
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
		"iron":
			# Железные панели с заклёпками.
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



## Полка у задней стены: доска с бликом сверху, тенью снизу и кронштейнами.
func _shelf(x0: float, x1: float, y: float, alpha: float) -> void:
	var wood := Color(BED_FRAME.lightened(0.1), alpha)
	draw_rect(Rect2(x0, y + 3, x1 - x0, 4), Color(0, 0, 0, 0.18 * alpha))
	_rbox(Rect2(x0, y - 1, x1 - x0, 4), 1, wood, Color(BED_FRAME.darkened(0.35), alpha), 1)
	draw_line(Vector2(x0 + 2, y - 0.5), Vector2(x1 - 2, y - 0.5), Color(1, 1, 1, 0.25 * alpha), 1.0)
	var n := maxi(2, int((x1 - x0) / (TILE * 2.0)) + 1)
	for i in n:
		var bx := lerpf(x0 + 6, x1 - 6, float(i) / (n - 1))
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 1.5, y + 3), Vector2(bx + 1.5, y + 3), Vector2(bx + 1.5, y + 9), Vector2(bx - 1.5, y + 5)]),
			Color(BED_FRAME.darkened(0.25), alpha))


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


## Мебель-картинки (assets/furniture/<комната>/<предмет>.png, нарезка art_src/rooms/cut_sheets.py).
const FURN_PX_PER_M := 128.0
## Пол комнаты-картинки: верх нижнего бруса рамы (0,14 м).
const FURN_FLOOR := 0.14
static var _furn := {}
static func furniture(room: String, item: String) -> Texture2D:
	var key := room + "/" + item
	if not _furn.has(key):
		var path := "res://assets/furniture/%s.png" % key
		_furn[key] = load(path) if ResourceLoader.exists(path) else null
	return _furn[key]


## Предмет низом на bottom, по центру cx (размер — из картинки, 128 px на метр).
## shadow: 1 — мягкая тень на полу под предметом, 2 — тень на стене за ним (вниз-вправо).
func _furn_at(t: Texture2D, cx: float, bottom: float, alpha: float, shadow := 0, scale := 1.0) -> void:
	var sz := t.get_size() / FURN_PX_PER_M * TILE * scale
	var rect := Rect2(cx - sz.x * 0.5, bottom - sz.y, sz.x, sz.y)
	if shadow == 1:
		_soft_ellipse(Vector2(cx, bottom - 1.0), sz.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	elif shadow == 2:
		draw_texture_rect(t, Rect2(rect.position + Vector2(1.5, 2.5), rect.size), false, Color(0, 0, 0, 0.22 * alpha))
	draw_texture_rect(t, rect, false, Color(1, 1, 1, alpha))


## Сплюснутое мягкое пятно: тёмный центр, прозрачный край.
func _soft_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([col])
	var edge := Color(col, 0.0)
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		cols.append(edge)
	for i in 20:
		draw_polygon(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), PackedColorArray([cols[0], cols[i + 1], cols[i + 2]]))


## Стойки на задней стене комнаты-картинки (art_src/rooms/build_rooms.py: через 3 м и в углах),
## в метрах от левого края комнаты, с учётом сужения к задней стене. Полки на них не вешаем.
static func wall_posts(w: int) -> Array[float]:
	var out: Array[float] = [0.6, w - 0.6]
	for x in range(3, w, 3):
		out.append(0.5 + (x - 0.2) * (w - 1.0) / (w - 0.4))
	return out


const BED_COLORS := ["blue", "pink", "green", "yellow"]
const HOME_DECOR := ["shelf_plant", "shelf_toy", "shelf_vine", "picture_mountain", "picture_sun", "picture_leaf"]


## Жилая из картинок: кровать на каждые 2 м (там же, где спят гаврики — bed_rect), над ней
## полка или картинка — не на стойке стены и без повторов в комнате; в свободной клетке —
## тумбочка или шкаф.
func _draw_home_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.beds(p)
	var spare := RoomType.usable_width(p) - n * 2 >= 1
	var lay := _inside(p, r, n * 2.0 + (1.0 if spare else 0.0))
	var posts := wall_posts(p.rect.size.x)
	var used := {}
	var start := int(WorldGen.hash01(p.id, 0, 90) * HOME_DECOR.size())
	for i in n:
		var cx: float = lay.x + (i * 2 + 1) * lay.unit
		var slot_l: float = (cx - lay.unit - r.position.x) / TILE
		for k in HOME_DECOR.size():
			var item: String = HOME_DECOR[(start + i + k) % HOME_DECOR.size()]
			var tex := furniture("home", item)
			if used.has(item) or tex == null:
				continue
			if not _hang_fit(tex, r, slot_l, slot_l + lay.unit * 2 / TILE, posts, fy, alpha):
				continue
			used[item] = true
			break
		var bed := furniture("home", "bed_" + BED_COLORS[(p.id + i) % BED_COLORS.size()])
		_furn_at(bed, cx, fy, alpha, 1, _fit(bed, lay.unit * 2))
	if spare:
		var side := furniture("home", "nightstand" if p.id % 2 == 0 else "bookcase")
		if side != null:
			_furn_at(side, lay.x + (n * 2 + 0.5) * lay.unit, fy, alpha, 1, _fit(side, lay.unit))


## Мебель — только внутри комнаты: между лестницей (или боковой стеной) и правой стеной, с
## отступом от стен (задняя стена уже пола). Место делится на units частей (метров по задумке);
## если не хватает — части уже. Возвращает x — левый край, unit — ширина части в px.
func _inside(p: Project, r: Rect2, units: float) -> Dictionary:
	var lo := r.position.x + TILE * (1.1 if p.ladder else RACK_INSET)
	var hi := r.end.x - TILE * RACK_INSET
	var unit := minf(TILE, (hi - lo) / units)
	return {"x": (lo + hi - unit * units) * 0.5, "unit": unit}


## Настенные предметы висят на одной линии, заметно ниже потолка: картинки и инструменты —
## верхом на высоте HANG_TOP (м над полом), полки — доской на SHELF_BOARD.
const HANG_TOP := 1.95
const SHELF_BOARD := 1.5
func _furn_hang(t: Texture2D, cx: float, fy: float, alpha: float, scale := 1.0) -> void:
	var h := t.get_height() / FURN_PX_PER_M * TILE * scale
	var top := fy - TILE * HANG_TOP
	if t.resource_path.get_file().begins_with("shelf_"):
		top = fy - TILE * SHELF_BOARD - _board_row(t) * h
	_furn_at(t, cx, top + h, alpha, 2, scale)


## Повесить предмет на стену над местом [a, b] (м от левого края комнаты): как _decor_x, а если
## между стойками он не помещается — уменьшить под самый широкий свободный промежуток. В любой
## комнате, даже маленькой, на стене что-то висит. Возвращает false, если места нет совсем.
func _hang_fit(t: Texture2D, r: Rect2, a: float, b: float, posts: Array[float], fy: float, alpha: float) -> bool:
	var wm := t.get_width() / FURN_PX_PER_M
	var dx := _decor_x(a, b, wm, posts)
	if not is_nan(dx):
		_furn_hang(t, r.position.x + dx * TILE, fy, alpha)
		return true
	# Свободные промежутки между стойками внутри [a, b].
	var cuts: Array[float] = [a + 0.05]
	for pst in posts:
		if pst > a and pst < b:
			cuts.append_array([pst - 0.14, pst + 0.14])
	cuts.append(b - 0.05)
	var best := Vector2(0, 0)    # (центр, ширина)
	for i in range(0, cuts.size() - 1, 2):
		var gw := cuts[i + 1] - cuts[i]
		if gw > best.y:
			best = Vector2((cuts[i] + cuts[i + 1]) * 0.5, gw)
	if best.y < 0.3:
		return false
	_furn_hang(t, r.position.x + best.x * TILE, fy, alpha, minf(1.0, best.y / wm))
	return true


## Доля высоты, на которой у полки доска (самая широкая строка картинки).
static var _boards := {}
func _board_row(t: Texture2D) -> float:
	if not _boards.has(t):
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var best := 0
		var best_n := -1
		for y in img.get_height():
			var n := 0
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.5:
					n += 1
			if n > best_n:
				best_n = n
				best = y
		_boards[t] = float(best) / img.get_height()
	return _boards[t]


## Масштаб, при котором предмет помещается в ширину width (px) с зазором; крупнее не делаем.
func _fit(t: Texture2D, width: float) -> float:
	return minf(1.0, (width - TILE * 0.06) / (t.get_width() / FURN_PX_PER_M * TILE))


## Где повесить предмет шириной wm (м) над местом [a, b]: по центру, а если там стойка —
## сдвинуть в сторону, где он помещается. NAN — не помещается нигде.
static func _decor_x(a: float, b: float, wm: float, posts: Array[float]) -> float:
	var half := wm * 0.5
	var clear := 0.14    # половина стойки и зазор
	var tries: Array[float] = [(a + b) * 0.5]
	for pst in posts:
		tries.append(pst - clear - half)
		tries.append(pst + clear + half)
	tries.sort_custom(func(u: float, v: float) -> bool: return absf(u - (a + b) * 0.5) < absf(v - (a + b) * 0.5))
	for c in tries:
		if c - half < a + 0.05 or c + half > b - 0.05:
			continue
		var ok := true
		for pst in posts:
			if absf(c - pst) < half + clear:
				ok = false
				break
		if ok:
			return c
	return NAN


const CRATES := ["wood", "stone", "brick", "coal", "iron", "copper", "silver", "gold", "uranium", "diamond", "salt", "clay", "limestone",
	"iron_ore", "copper_ore", "silver_ore", "gold_ore", "uranium_ore"]
## Полки стеллажа: верх планок над полом (м, печатает art_src/rooms/cut_sheets.py для rack_tall),
## по три ящика на полку — между массивными стойками 1,64 м. Всё нарисовано строго спереди, как комната.
const RACK_LEVELS := [0.219, 0.836]
const RACK_SLOTS := 3
const RACK_SLOT_DX := 0.545
const CRATE_SCALE := 0.9
const RACK_INSET := 0.35  # отступ стеллажей от боковой стены, м (задняя стена уже пола)
const RACK_POST := 23.0    # толщина стойки стеллажа в пикселях спрайта (rack_tall.png)


## Склад из картинок: стеллаж на каждые 3 м, ящики с ресурсами по запасам (снизу вверх),
## у задней стены, под потолком большой комнаты — таль.
func _draw_storage_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var rk := _draw_racks(p, r, furniture("storage", "rack_tall"), RACK_POST, fy, alpha)
	# Ящики: сколько каждого ресурса лежит именно в этой комнате (Colony.held_in).
	var keys: Array = p.held.keys()
	keys.sort()
	var crates: Array[Texture2D] = []
	for key in keys:
		if CRATES.has(key):    # нефть, метан и прочее — без ящиков
			crates.append_array(_boxes_of(p, key, rk, [furniture("storage", "crate_" + key)]))
	_fill_racks(rk, crates, RACK_LEVELS, fy, alpha)
	# Брус тали — между лестницами (если есть), блок с крюком — в проходе за первым стеллажом;
	# в маленьком складе прохода нет — только брус с лебёдкой.
	var left := r.position.x + TILE * (1.05 if colony.edge_ladder(p, -1) else 0.5)
	var right := r.end.x - TILE * (1.05 if colony.edge_ladder(p, 1) else 0.5)
	_draw_hoist(left, right, rk.start + rk.rw + rk.gap * 0.5 if rk.racks > 1 else NAN, fy - TILE * 2.34, alpha)


## Стеллажи у задней стены, как на складе и в амбаре: на каждый блок в 3 м — один; справа
## отступ от стены, слева всегда свободна клетка под лестницу (есть она или нет) — комнаты одной
## ширины выглядят одинаково. Крайние — к краям, между ними проходы. post — стойка в px спрайта.
## Возвращает раскладку: start, rw (ширина), gap (проход), racks, per_shelf, cap (ёмкость комнаты).
func _draw_racks(p: Project, r: Rect2, rack: Texture2D, post: float, fy: float, alpha: float) -> Dictionary:
	var racks := maxi(1, p.rect.size.x / 3)
	var lo := r.position.x + TILE * 1.1
	var hi := r.end.x - TILE * RACK_INSET
	var rw := minf(TILE * 2, (hi - lo) / racks)
	var gap := (hi - lo - racks * rw) / maxi(1, racks - 1)
	var start := lo if racks > 1 else (lo + hi - rw) * 0.5
	for k in racks:
		_draw_rack(rack, start + k * (rw + gap) + rw * 0.5, fy, rw, post, alpha)
	var inner := rw / TILE - 2 * post / FURN_PX_PER_M
	return {"start": start, "rw": rw, "gap": gap, "racks": racks,
		"per_shelf": clampi(int(inner / RACK_SLOT_DX + 0.01), 1, RACK_SLOTS),
		"cap": float(RoomType.CAPACITY_PER_CELL * RoomType.usable_width(p))}


## Ящики (корзины) ресурса key по запасу в комнате: каждый — на долю ёмкости, виды по очереди.
func _boxes_of(p: Project, key: String, rk: Dictionary, kinds: Array) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var per: float = rk.cap / (rk.racks * rk.per_shelf * RACK_LEVELS.size())
	for i in ceili(colony.held_in(p, key) / per):
		out.append(kinds[(i + p.id) % kinds.size()])
	return out


## Ставит ящики на полки стеллажей снизу вверх, слева направо.
func _fill_racks(rk: Dictionary, boxes: Array[Texture2D], levels: Array, fy: float, alpha: float) -> void:
	var row: int = rk.racks * rk.per_shelf
	for slot in mini(boxes.size(), row * levels.size()):
		var j := slot % row
		var k: int = j / rk.per_shelf
		var cx: float = rk.start + k * (rk.rw + rk.gap) + rk.rw * 0.5 \
			+ (j % rk.per_shelf - (rk.per_shelf - 1) * 0.5) * RACK_SLOT_DX * TILE
		_furn_at(boxes[slot], cx, fy - levels[slot / row] * TILE, alpha, 0, CRATE_SCALE)


## Амбар: стеллажи как на складе, корзины с едой (рыба и грибы — «food», ягоды), над стеллажами —
## жердь с подвешенными связками.
const GRANARY_LEVELS := [0.227, 0.828]
const GRANARY_POST := 21.0
const BASKETS := {"food": ["basket_mushroom"], "fish": ["basket_fish"], "berries": ["basket_berries"]}
const HANGERS := ["hang_fish", "hang_garlic", "hang_pepper", "hang_herbs", "hang_onion"]
func _draw_granary_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var rk := _draw_racks(p, r, furniture("granary", "rack_tall"), GRANARY_POST, fy, alpha)
	var baskets: Array[Texture2D] = []
	for key in BASKETS:
		var kinds := []
		for b in BASKETS[key]:
			kinds.append(furniture("granary", b))
		baskets.append_array(_boxes_of(p, key, rk, kinds))
	_fill_racks(rk, baskets, GRANARY_LEVELS, fy, alpha)
	# Жердь — над стеллажами, как на прототипе.
	var left: float = rk.start - TILE * 0.1
	var right: float = rk.start + rk.racks * rk.rw + (rk.racks - 1) * rk.gap + TILE * 0.1
	var top := fy - TILE * 2.3
	_draw_span("granary", "rod", left, right, top, alpha)
	# Связки — по одной на 0,6 м, не над верёвками, без повторов подряд.
	var k := TILE / FURN_PX_PER_M
	var n := int((right - left - TILE * 0.5) / (TILE * 0.6))
	var first := int(WorldGen.hash01(p.id, 0, 91) * HANGERS.size())
	for i in n:
		var t := furniture("granary", HANGERS[(first + i) % HANGERS.size()])
		var cx := left + TILE * 0.25 + (i + 0.5) * (right - left - TILE * 0.5) / n
		var hs := t.get_size() * k * 0.85
		draw_texture_rect(t, Rect2(cx - hs.x * 0.5, top + 47 * k, hs.x, hs.y), false, Color(1, 1, 1, alpha))


## Предмет, растянутый от left до right: торцы <name>_l, <name>_r и повторяющийся <name>_mid.
func _draw_span(room: String, name: String, left: float, right: float, top: float, alpha: float) -> void:
	var l := furniture(room, name + "_l")
	var m := furniture(room, name + "_mid")
	var rt := furniture(room, name + "_r")
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var x := left + l.get_width() * k
	var end := right - rt.get_width() * k
	while x < end:
		var seg := minf(m.get_width() * k, end - x)
		draw_texture_rect_region(m, Rect2(x, top, seg, m.get_height() * k), Rect2(0, 0, seg / k, m.get_height()), mod)
		x += seg
	draw_texture_rect(l, Rect2(left, top, l.get_width() * k, l.get_height() * k), false, mod)
	draw_texture_rect(rt, Rect2(end, top, rt.get_width() * k, rt.get_height() * k), false, mod)


## Ферма: грядка на каждые 2 м, на ней грибы трёх стадий роста (в холоде — блёклые); с
## электричеством над грибами лампы роста на стене — горят, когда есть энергия. Выше на стене — по предмету
## над грядкой, без повторов и не на стойках.
const FARM_DECOR := ["tools", "can", "gauge", "hose"]
func _draw_farm_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.farm_slots(p)
	var lay := _inside(p, r, n * 2.0)
	var posts := wall_posts(p.rect.size.x)
	var first := int(WorldGen.hash01(p.id, 0, 92) * FARM_DECOR.size())
	var grow := clampf(p.farm_progress / RoomType.FARM_CYCLE, 0.0, 1.0)
	var shoots := furniture("farm", "shoots_%d" % (1 + mini(2, int(grow * 3.0))))
	var tint := Color(1, 1, 1, alpha) if colony.farm_warm(p) else Color(0.72, 0.75, 0.85, alpha)
	var lamp: Texture2D = null
	if colony.research.has("electricity"):
		lamp = furniture("farm", "lamp_on" if colony.powered() else "lamp_off")
	var bed := furniture("farm", "bed")
	var sc := _fit(bed, lay.unit * 2)
	var k := TILE / FURN_PX_PER_M * sc
	for i in n:
		var cx: float = lay.x + (i * 2 + 1) * lay.unit
		var slot_l: float = (cx - lay.unit - r.position.x) / TILE
		if i < FARM_DECOR.size():
			var deco := furniture("farm", FARM_DECOR[(first + i) % FARM_DECOR.size()])
			_hang_fit(deco, r, slot_l, slot_l + lay.unit * 2 / TILE, posts, fy, alpha)
		if lamp != null:
			# Лампа на настенных креплениях — прямо над грибами, как на прототипе.
			var lsz := lamp.get_size() * k
			draw_texture_rect(lamp, Rect2(cx - lsz.x * 0.5, fy - TILE * 0.9 * sc - lsz.y, lsz.x, lsz.y), false, Color(1, 1, 1, alpha))
		var sz := shoots.get_size() * k
		draw_texture_rect(shoots, Rect2(cx - sz.x * 0.5, fy - (bed.get_height() - 7) * k - sz.y, sz.x, sz.y), false, tint)
		_furn_at(bed, cx, fy, alpha, 1, sc)


## Очаг: печь на каждые 3 м (каменная, кирпичная; с газом — отопительный котёл вместо печи),
## горит, когда топится; от печи труба в потолок, рядом её топливо (дрова, у кирпичной — уголь).
## Котлы соединены трубами отопления с вентилями. На стене между печами — кочерга и совок.
func _draw_hearth_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.stoves(p)
	var lay := _inside(p, r, n * 3.0)
	var done := p.phase == Project.Phase.DONE
	var gas := p.gas_boiler and done
	var kind := "gas" if gas else ("brick" if p.brick_stoves and done else "stone")
	var stove := furniture("hearth", kind + ("_on" if p.burning else "_off"))
	var fuel := null if gas else furniture("hearth", "coal" if kind == "brick" else "logs")
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var xs: Array[float] = []
	for i in n:
		xs.append(lay.x + (i * 3 + 1.5) * lay.unit - (TILE * 0.35 if fuel != null else 0.0))
	var sh := stove.get_height() * k
	if gas:
		# Трубы отопления — за котлами, от первого котла до правой стены, на уровне патрубков.
		var right: float = lay.x + n * 3 * lay.unit
		for pipe in [["pipe_red", 0.32], ["pipe_blue", 0.68]]:
			var t := furniture("hearth", pipe[0])
			_tile_h(t, xs[0], right, fy - sh * (1.0 - pipe[1]) - t.get_height() * k * 0.5, alpha)
		var valve := furniture("hearth", "valve")
		for i in n:
			var vx: float = (xs[i] + xs[i + 1]) * 0.5 if i + 1 < n else (xs[i] + right) * 0.5 + TILE * 0.2
			var vs := valve.get_size() * k
			draw_texture_rect(valve, Rect2(vx - vs.x * 0.5, fy - sh * 0.68 - vs.y * 0.5, vs.x, vs.y), false, mod)
	var chimney := furniture("hearth", "chimney")
	if not gas:
		_tools_between(p, r, lay, xs, furniture("hearth", "tools"), fy, alpha)
	for i in n:
		var cw := chimney.get_width() * k
		_tile_v(chimney, xs[i] - cw * 0.5, fy - TILE * 2.62, fy - sh + 4 * k, alpha)
		if p.burning and alpha >= 1.0:
			_glow(Vector2(xs[i], fy - sh * 0.4), TILE * 2.2, Color(0.3, 0.55, 1.0, 0.18) if gas else Color(1.0, 0.6, 0.25, 0.22))
		_furn_at(stove, xs[i], fy, alpha, 1)
		if fuel != null:
			_furn_at(fuel, xs[i] + stove.get_width() * k * 0.5 + fuel.get_width() * k * 0.5 + TILE * 0.05, fy, alpha, 1)



## Инструменты на стене между печами (по одним на промежуток); у единственной печи — где есть
## место, мимо стоек и трубы.
func _tools_between(p: Project, r: Rect2, lay: Dictionary, xs: Array[float], tools: Texture2D, fy: float, alpha: float) -> void:
	var posts := wall_posts(p.rect.size.x)
	if xs.size() > 1:
		for i in xs.size() - 1:
			_hang_fit(tools, r, (xs[i] - r.position.x) / TILE + 1.1, (xs[i + 1] - r.position.x) / TILE - 0.6, posts, fy, alpha)
		return
	var around: Array[float] = posts.duplicate()
	around.append((xs[0] - r.position.x) / TILE)
	around.sort()
	_hang_fit(tools, r, (lay.x - r.position.x) / TILE, (lay.x + 3 * lay.unit - r.position.x) / TILE, around, fy, alpha)


## Высота потолка над полом (м) — до неё идут трубы.
const CEILING := 2.62
## Центры блоков по 3 м внутри комнаты (по одной машине на блок).
func _block_centers(lay: Dictionary, n: int, shift := 0.0) -> Array[float]:
	var xs: Array[float] = []
	for i in n:
		xs.append(lay.x + (i * 3 + 1.5) * lay.unit + shift * TILE)
	return xs


## Масштаб группы предметов в ряд (с зазорами), чтобы она поместилась в ширину width (px).
func _group_fit(items: Array, width: float) -> float:
	var w := TILE * 0.1 * items.size()
	for t in items:
		w += t.get_width() / FURN_PX_PER_M * TILE
	return minf(1.0, width / w)


## Мастер работает в этой комнате (печь для обжига горит, пока идёт обжиг).
func _crafting(p: Project) -> bool:
	for u in colony.units:
		if u.state == Unit.State.WORK and u.task == Unit.Task.CRAFT and u.project_id == p.id:
			return true
	return false


## Обжиговая: печь на каждые 3 м — горит, пока мастер обжигает; слева глина, справа кирпичи,
## труба в потолок, на стене лопата и кочерга.
func _draw_kiln_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var on := _crafting(p)
	var kiln := furniture("kiln", "kiln_on" if on else "kiln_off")
	var chimney := furniture("hearth", "chimney")
	var clay := furniture("kiln", "clay")
	var bricks := furniture("kiln", "bricks")
	# Глина, печь и кирпичи в ряд; не помещаются в блок — всё мельче.
	var sc := _group_fit([clay, kiln, bricks], lay.unit * 3)
	var k := TILE / FURN_PX_PER_M * sc
	var xs := _block_centers(lay, n, 0.0)
	var kw := kiln.get_width() * k
	_tools_between(p, r, lay, xs, furniture("kiln", "tools"), fy, alpha)
	for x in xs:
		x += (clay.get_width() - bricks.get_width()) * k * 0.5
		_tile_v(chimney, x - chimney.get_width() * k * 0.5, fy - TILE * CEILING, fy - kiln.get_height() * k + 4 * k, alpha)
		if on and alpha >= 1.0:
			_glow(Vector2(x, fy - TILE * 0.3), TILE * 2.0, Color(1.0, 0.6, 0.25, 0.22))
		_furn_at(kiln, x, fy, alpha, 1, sc)
		_furn_at(clay, x - kw * 0.5 - clay.get_width() * k * 0.5 - TILE * 0.03, fy, alpha, 1, sc)
		_furn_at(bricks, x + kw * 0.5 + bricks.get_width() * k * 0.5 + TILE * 0.03, fy, alpha, 1, sc)


## Генераторная: генератор на каждые 3 м — на угле и дровах (топка, маховик, динамо, рядом уголь,
## труба в потолок) или на метане (синий двигатель, газовая труба с вентилем с потолка). Что
## комната даёт ток, видно сразу: от динамо провода к гирлянде лампочек под потолком и щитку —
## всё горит, когда генератор работает.
func _draw_generator_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var gas := p.purpose == RoomType.GAS_GEN
	var on := p.burning
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var machine := furniture("generator", ("gas" if gas else "coal") + ("_on" if on else "_off"))
	var coal := furniture("hearth", "coal")
	var sc := _group_fit([machine] if gas else [coal, machine], lay.unit * 3)
	var mw := machine.get_width() * k * sc
	var mh := machine.get_height() * k * sc
	var xs := _block_centers(lay, n, 0.0 if gas else coal.get_width() / FURN_PX_PER_M * sc * 0.5)
	# Гирлянда под потолком от левого края до щитка справа.
	var panel := furniture("generator", "panel_on" if on else "panel_off")
	var ps := panel.get_size() * k
	var line_y := fy - TILE * 2.25
	var right: float = lay.x + n * 3 * lay.unit
	_tile_h(furniture("generator", "bulbs_on" if on else "bulbs_off"), lay.x + TILE * 0.1, right - ps.x, line_y, alpha)
	draw_texture_rect(panel, Rect2(right - ps.x, line_y - ps.y * 0.3, ps.x, ps.y), false, mod)
	var cable := Color(0.12, 0.12, 0.14, alpha)
	var chimney := furniture("hearth", "chimney")
	var pipe := furniture("generator", "gas_pipe")
	var valve := furniture("generator", "valve")
	for x in xs:
		var top := fy - mh
		# Провод от динамо (справа) вверх к гирлянде.
		var dx := x + mw * 0.36
		draw_line(Vector2(dx, top + 6 * k), Vector2(dx, line_y + 4 * k), cable, maxf(2.0, 4 * k))
		if gas:
			var gx := x + (0.17 - 0.5) * mw
			_tile_v(pipe, gx - pipe.get_width() * k * 0.5, fy - TILE * CEILING, top + 8 * k, alpha)
			var vs := valve.get_size() * k
			draw_texture_rect(valve, Rect2(gx - vs.x * 0.5, (fy - TILE * CEILING + top) * 0.5 - vs.y * 0.5, vs.x, vs.y), false, mod)
		else:
			var cx := x + (0.145 - 0.5) * mw
			_tile_v(chimney, cx - chimney.get_width() * k * 0.5, fy - TILE * CEILING, top + 4 * k, alpha)
			_furn_at(coal, x - mw * 0.5 - coal.get_width() * k * sc * 0.5, fy, alpha, 1, sc)
		if on and alpha >= 1.0:
			_glow(Vector2(x, fy - mh * 0.5), TILE * 2.0, Color(0.3, 0.55, 1.0, 0.16) if gas else Color(1.0, 0.75, 0.3, 0.18))
		_furn_at(machine, x, fy, alpha, 1, sc)


## Насосная: насос на каждые 3 м, справа бак с водой; от насоса труба в потолок; под потолком —
## водопровод с вентилями и манометрами. Насос «крутится», когда комната работает.
func _draw_pump_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var on := p.phase == Project.Phase.DONE and not p.paused
	var pump := furniture("pump", "pump_on" if on else "pump_off")
	var tank := furniture("pump", "tank")
	var pipe_v := furniture("pump", "pipe_v")
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var line_y := fy - TILE * 2.1
	var right: float = lay.x + n * 3 * lay.unit
	var pipe_h := furniture("pump", "pipe_h")
	_tile_h(pipe_h, lay.x + TILE * 0.1, right - TILE * 0.1, line_y - pipe_h.get_height() * k * 0.5, alpha)
	var sc := _group_fit([pump, tank], lay.unit * 3)
	var pw := pump.get_width() * k * sc
	var tw := tank.get_width() * k * sc
	for i in n:
		var b0: float = lay.x + i * 3 * lay.unit
		var x: float = b0 + (lay.unit * 3 - pw - tw) * 0.5 + pw * 0.5
		var px := x + (0.465 - 0.5) * pw
		_tile_v(pipe_v, px - pipe_v.get_width() * k * 0.5, fy - TILE * CEILING, fy - pump.get_height() * k * sc + 4 * k, alpha)
		# На водопроводе — вентиль левее трубы насоса и манометр правее, если помещаются в блок.
		for it in [["valve", -1], ["gauge", 1]]:
			var t := furniture("pump", it[0])
			var ts := t.get_size() * k * sc
			var tx: float = px + it[1] * (ts.x * 0.5 + TILE * 0.15)
			if tx - ts.x * 0.5 >= b0 and tx + ts.x * 0.5 <= b0 + lay.unit * 3:
				draw_texture_rect(t, Rect2(tx - ts.x * 0.5, line_y - ts.y * 0.5, ts.x, ts.y), false, mod)
		_furn_at(pump, x, fy, alpha, 1, sc)
		_furn_at(tank, x + pw * 0.5 + tw * 0.5 + TILE * 0.05, fy, alpha, 1, sc)


## Дегазация: один синий бак метана — чем больше комната, тем больше бак (3 / 6 / 9 м), рядом
## компрессор; под потолком — газовая труба с раструбами-заборниками на концах и манометрами,
## от неё труба вниз к баку.
func _draw_degas_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var tank := furniture("degas", "tank_%d" % clampi(n, 1, 3))
	var comp := furniture("degas", "compressor")
	var span: float = n * 3 * lay.unit
	var total := (tank.get_width() + comp.get_width()) * k + TILE * 0.1
	var sc := minf(1.0, (span - TILE * 0.2) / total)
	var x0: float = lay.x + (span - total * sc) * 0.5
	var tw := tank.get_width() * k * sc
	var tank_x := x0 + tw * 0.5
	# Газовая труба под потолком, на концах раструбы (правый — зеркально).
	var line_y := fy - TILE * 2.15
	var pipe := furniture("degas", "pipe")
	var intake := furniture("degas", "intake")
	var is_ := intake.get_size() * k * 0.8
	var left: float = lay.x + TILE * 0.05
	var right: float = lay.x + span - TILE * 0.05
	_tile_h(pipe, left + is_.x * 0.6, right - is_.x * 0.6, line_y - pipe.get_height() * k * 0.5, alpha)
	draw_texture_rect(intake, Rect2(left, line_y - is_.y * 0.5, is_.x, is_.y), false, mod)
	draw_texture_rect(intake, Rect2(right, line_y - is_.y * 0.5, -is_.x, is_.y), false, mod)
	# Труба вниз к баку.
	var pc := Color(0.5, 0.53, 0.58, alpha)
	draw_rect(Rect2(tank_x - TILE * 0.06, line_y, TILE * 0.12, fy - tank.get_height() * k * sc - line_y + 4), pc)
	var gauge := furniture("degas", "gauge")
	var gs := gauge.get_size() * k
	for i in n:
		var gx: float = lay.x + (i * 3 + 0.9) * lay.unit
		if absf(gx - tank_x) > TILE * 0.4:
			draw_texture_rect(gauge, Rect2(gx - gs.x * 0.5, line_y - gs.y * 0.3, gs.x, gs.y), false, mod)
	_furn_at(tank, tank_x, fy, alpha, 1, sc)
	_furn_at(comp, x0 + tw + TILE * 0.1 * sc + comp.get_width() * k * sc * 0.5, fy, alpha, 1, sc)


## Вентиляция: установка на каждые 3 м; под потолком — воздуховод во всю комнату, над каждой
## установкой — решётка и короб в потолок. Что комната охлаждает и работает от тока, видно сразу:
## при энергии лопасти крутятся, из решёток вниз идёт холодный воздух со снежинками.
func _draw_vent_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var on := p.phase == Project.Phase.DONE and not p.paused and colony.powered()
	var fan := furniture("vent", "fan_on" if on else "fan_off")
	var sc := _fit(fan, lay.unit * 3)
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var xs := _block_centers(lay, n, 0.0)
	var duct := furniture("vent", "duct_h")
	var dh := duct.get_height() * k
	var top := fy - TILE * 2.38
	var right: float = lay.x + n * 3 * lay.unit
	_tile_h(duct, lay.x + TILE * 0.05, right - TILE * 0.05, top, alpha)
	var grille := furniture("vent", "grille")
	var gw := grille.get_width() * k
	var box := furniture("vent", "duct_v")
	var air := furniture("vent", "air")
	var thermo := furniture("vent", "thermo")
	for i in n:
		var x: float = xs[i]
		_tile_v(box, x - box.get_width() * k * 0.5, fy - TILE * CEILING, top + 2, alpha)
		draw_texture_rect(grille, Rect2(x - gw * 0.5, top, gw, dh), false, mod)
		if on:
			var asz := air.get_size() * k
			draw_texture_rect(air, Rect2(x - asz.x * 0.5, top + dh * 0.8, asz.x, asz.y), false, Color(1, 1, 1, 0.85 * alpha))
		_furn_at(fan, x, fy, alpha, 1, sc)
	# Термометр — на стене возле первой установки (между установками или справа от неё).
	var a := (xs[0] - r.position.x) / TILE + 0.85 * sc
	var b: float = minf(a + 0.9, (lay.x + n * 3 * lay.unit - r.position.x) / TILE)
	if b - a < 0.3:     # справа места нет — слева от установки
		b = (xs[0] - r.position.x) / TILE - 0.85 * sc
		a = maxf(b - 0.9, (lay.x - r.position.x) / TILE)
	_hang_fit(thermo, r, a, b, wall_posts(p.rect.size.x), fy, alpha)


## Кузница: на каждые 3 м — горн с мехами (угли горят, пока кузнец работает), наковальня на пне,
## бочка с водой; перед горном — ящик руды и стопка слитков; от колпака горна — труба в потолок;
## на стене между горнами — клещи и молот.
func _draw_forge_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0)
	var on := _crafting(p)
	var forge := furniture("forge", "forge_on" if on else "forge_off")
	var anvil := furniture("forge", "anvil")
	var barrel := furniture("forge", "barrel")
	var ore := furniture("forge", "ore")
	var ingots := furniture("forge", "ingots")
	var chimney := furniture("hearth", "chimney")
	var sc := _group_fit([forge, anvil, barrel], lay.unit * 3)
	var k := TILE / FURN_PX_PER_M * sc
	var gap := TILE * 0.08 * sc
	var row := (forge.get_width() + anvil.get_width() + barrel.get_width()) * k + 2 * gap
	var fxs: Array[float] = []
	for i in n:
		var x0: float = lay.x + i * 3 * lay.unit + (lay.unit * 3 - row) * 0.5
		var fx := x0 + forge.get_width() * k * 0.5
		fxs.append(fx)
		var hood := x0 + forge.get_width() * k * 0.657
		_tile_v(chimney, hood - chimney.get_width() * k * 0.5, fy - TILE * CEILING, fy - forge.get_height() * k + 3 * k, alpha)
		if on and alpha >= 1.0:
			_glow(Vector2(hood, fy - TILE * 0.5 * sc), TILE * 2.0, Color(1.0, 0.55, 0.2, 0.22))
		_furn_at(forge, fx, fy, alpha, 1, sc)
		var ax := x0 + forge.get_width() * k + gap + anvil.get_width() * k * 0.5
		_furn_at(anvil, ax, fy, alpha, 1, sc)
		_furn_at(barrel, ax + anvil.get_width() * k * 0.5 + gap + barrel.get_width() * k * 0.5, fy, alpha, 1, sc)
		_furn_at(ore, x0 + ore.get_width() * k * 0.45, fy + TILE * 0.04, alpha, 1, sc)
		_furn_at(ingots, x0 + forge.get_width() * k * 0.8, fy + TILE * 0.04, alpha, 1, sc)
	_tools_between(p, r, lay, fxs, furniture("forge", "tools"), fy, alpha)


## Столовая: стол с лавкой на каждые 3 м, на столе — свой набор посуды; на стене — полки и меню.
const DINING_WALL := ["shelf_vine", "menu", "shelf_plates"]
const DINING_TABLEWARE := ["bowl", "jug_blue", "mug_red", "fruit", "mug_blue", "jug_red", "bowl", "mug_green"]
func _draw_dining_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := maxi(1, p.rect.size.x / 3)
	var lay := _inside(p, r, n * 3.0)
	var table := furniture("dining", "table")
	var k := TILE / FURN_PX_PER_M
	var first := int(WorldGen.hash01(p.id, 0, 93) * DINING_TABLEWARE.size())
	for i in n:
		var cx: float = lay.x + (i * 3 + 1.5) * lay.unit
		_wall_item(p, r, "dining", DINING_WALL[i % DINING_WALL.size()], cx, lay.unit * 3, fy, alpha)
		var sc := _fit(table, lay.unit * 3)
		_furn_at(table, cx, fy, alpha, 1, sc)
		var ware: Array[Texture2D] = []
		for j in 4:
			ware.append(furniture("dining", DINING_TABLEWARE[(first + i * 3 + j) % DINING_TABLEWARE.size()]))
		_place_row(ware, cx, table.get_width() * k * sc * 0.8, fy - (table.get_height() - 3) * k * sc, alpha)
		var bench := furniture("dining", "bench")
		_furn_at(bench, cx, fy + TILE * 0.06, alpha, 1, sc)


## Лаборатория: стол-тумба на каждые 3 м, на столах — свои приборы (прибор с экраном светится,
## когда есть энергия); на стене — доска, чертёж и полка с книгами.
const LAB_WALL := ["board", "poster", "shelf_books"]
const LAB_SETS := [["tubes", "still"], ["microscope", "crystal", "rock", "gold"], ["flask", "device"]]
func _draw_lab_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := maxi(1, p.rect.size.x / 3)
	var lay := _inside(p, r, n * 3.0)
	var desk := furniture("lab", "desk")
	var k := TILE / FURN_PX_PER_M
	for i in n:
		var cx: float = lay.x + (i * 3 + 1.5) * lay.unit
		_wall_item(p, r, "lab", LAB_WALL[i % LAB_WALL.size()], cx, lay.unit * 3, fy, alpha)
		var sc := _fit(desk, lay.unit * 3)
		_furn_at(desk, cx, fy, alpha, 1, sc)
		var tools: Array[Texture2D] = []
		for name in LAB_SETS[i % LAB_SETS.size()]:
			if name == "device":
				name = "device_on" if colony.powered() else "device_off"
			tools.append(furniture("lab", name))
		_place_row(tools, cx, desk.get_width() * k * sc * 0.85, fy - (desk.get_height() - 3) * k * sc, alpha)


## Настенный предмет над местом шириной width с центром cx: на линии подвеса, не на стойке.
func _wall_item(p: Project, r: Rect2, room: String, name: String, cx: float, width: float, fy: float, alpha: float) -> void:
	var t := furniture(room, name)
	var a := (cx - width * 0.5 - r.position.x) / TILE
	_hang_fit(t, r, a, a + width / TILE, wall_posts(p.rect.size.x), fy, alpha)


## Предметы в ряд на поверхности (стол): поровну по ширине width с центром cx, низом на bottom.
func _place_row(items: Array[Texture2D], cx: float, width: float, bottom: float, alpha: float) -> void:
	for j in items.size():
		_furn_at(items[j], cx - width * 0.5 + (j + 0.5) * width / items.size(), bottom, alpha)


## Повторяющийся по горизонтали предмет (трубы) от left до right, верхом на top.
func _tile_h(t: Texture2D, left: float, right: float, top: float, alpha: float) -> void:
	var k := TILE / FURN_PX_PER_M
	var x := left
	while x < right - 0.5:
		var seg := minf(t.get_width() * k, right - x)
		draw_texture_rect_region(t, Rect2(x, top, seg, t.get_height() * k), Rect2(0, 0, seg / k, t.get_height()), Color(1, 1, 1, alpha))
		x += seg


## Повторяющийся по вертикали предмет (труба дымохода) с левым краем x от top до bottom.
func _tile_v(t: Texture2D, x: float, top: float, bottom: float, alpha: float) -> void:
	var k := TILE / FURN_PX_PER_M
	var y := top
	while y < bottom - 0.5:
		var seg := minf(t.get_height() * k, bottom - y)
		draw_texture_rect_region(t, Rect2(x, y, t.get_width() * k, seg), Rect2(0, 0, t.get_width(), seg / k), Color(1, 1, 1, alpha))
		y += seg


## Стеллаж шириной width: стойки как на спрайте, середина (полки) сжата.
func _draw_rack(t: Texture2D, cx: float, bottom: float, width: float, post_px: float, alpha: float) -> void:
	var k := TILE / FURN_PX_PER_M
	var sz := t.get_size()
	var h := sz.y * k
	var post := post_px * k
	var x := cx - width * 0.5
	var mod := Color(1, 1, 1, alpha)
	_soft_ellipse(Vector2(cx, bottom - 1.0), width * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	draw_texture_rect_region(t, Rect2(x, bottom - h, post, h), Rect2(0, 0, post_px, sz.y), mod)
	draw_texture_rect_region(t, Rect2(x + post, bottom - h, width - 2 * post, h), Rect2(post_px, 0, sz.x - 2 * post_px, sz.y), mod)
	draw_texture_rect_region(t, Rect2(x + width - post, bottom - h, post, h), Rect2(sz.x - post_px, 0, post_px, sz.y), mod)


## Таль: брус от left до right (торец, повторяющийся кусок, лебёдка справа), блок с цепью
## и крюком на block_x (NAN — без блока), между ними трос. top — верх бруса. Детали крупнее листа в HOIST_K раз.
const HOIST_K := 1.25
func _draw_hoist(left: float, right: float, block_x: float, top: float, alpha: float) -> void:
	var cap := furniture("storage", "hoist_cap")
	var beam := furniture("storage", "hoist_beam")
	var block := furniture("storage", "hoist_block")
	var winch := furniture("storage", "hoist_winch")
	if cap == null or beam == null or block == null or winch == null:
		return
	var k := TILE / FURN_PX_PER_M * HOIST_K
	var mod := Color(1, 1, 1, alpha)
	var winch_x := right - winch.get_width() * k
	var bw := beam.get_width() * k
	var x := left + cap.get_width() * k
	while x < winch_x:
		var seg := minf(bw, winch_x - x)
		draw_texture_rect_region(beam, Rect2(x, top, seg, beam.get_height() * k), Rect2(0, 0, seg / k, beam.get_height()), mod)
		x += seg
	draw_texture_rect(cap, Rect2(left, top, cap.get_width() * k, cap.get_height() * k), false, mod)
	if is_nan(block_x):
		draw_texture_rect(winch, Rect2(winch_x, top, winch.get_width() * k, winch.get_height() * k), false, mod)
		return
	# Трос: от шкива каретки (правый край) к барабану лебёдки (координаты в пикселях спрайтов).
	draw_line(Vector2(block_x + 25 * k, top + 38 * k), Vector2(winch_x + 12 * k, top + 46 * k), Color(0.55, 0.5, 0.45, alpha), maxf(1.0, 3 * k))
	draw_texture_rect(winch, Rect2(winch_x, top, winch.get_width() * k, winch.get_height() * k), false, mod)
	draw_texture_rect(block, Rect2(block_x - block.get_width() * k * 0.5, top, block.get_width() * k, block.get_height() * k), false, mod)


func _draw_furniture(p: Project, r: Rect2, purpose: int, alpha: float) -> void:
	var floor_y := r.end.y - 6
	var x0 := view.cell_to_local(Vector2i(RoomType.floor_start(p), 0)).x
	if purpose == RoomType.SHIP:
		_draw_ship(p, r, alpha)
		return
	if purpose == RoomType.LAUNCHPAD:
		_draw_launchpad(p, r, alpha)
		return
	if purpose == RoomType.HOME and furniture("home", "bed_blue") != null:
		_draw_home_furniture(p, r, alpha)
		return
	if purpose == RoomType.STORAGE and furniture("storage", "rack_tall") != null:
		_draw_storage_furniture(p, r, alpha)
		return
	if purpose == RoomType.GRANARY and furniture("granary", "rack_tall") != null:
		_draw_granary_furniture(p, r, alpha)
		return
	if purpose == RoomType.FARM and furniture("farm", "bed") != null:
		_draw_farm_furniture(p, r, alpha)
		return
	if purpose == RoomType.HEARTH and furniture("hearth", "stone_on") != null:
		_draw_hearth_furniture(p, r, alpha)
		return
	if purpose == RoomType.DINING and furniture("dining", "table") != null:
		_draw_dining_furniture(p, r, alpha)
		return
	if purpose == RoomType.LAB and furniture("lab", "desk") != null:
		_draw_lab_furniture(p, r, alpha)
		return
	if purpose == RoomType.KILN and furniture("kiln", "kiln_on") != null:
		_draw_kiln_furniture(p, r, alpha)
		return
	if purpose in RoomType.GENERATORS and furniture("generator", "coal_on") != null:
		_draw_generator_furniture(p, r, alpha)
		return
	if purpose == RoomType.PUMP and furniture("pump", "pump_on") != null:
		_draw_pump_furniture(p, r, alpha)
		return
	if purpose == RoomType.DEGAS and furniture("degas", "tank_1") != null:
		_draw_degas_furniture(p, r, alpha)
		return
	if purpose == RoomType.VENT and furniture("vent", "fan_on") != null:
		_draw_vent_furniture(p, r, alpha)
		return
	if purpose == RoomType.FORGE and furniture("forge", "forge_on") != null:
		_draw_forge_furniture(p, r, alpha)
		return
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
			# Полка на половине высоты и ящики по видам ресурсов: чем больше, тем больше ящиков.
			_shelf(x0 + 4, x0 + w * TILE - 4, floor_y - 40, alpha)
			var slots := w * 2
			var slot := 0
			var keys: Array = colony.inventory.keys()
			keys.sort()
			for k in keys:
				if RoomType.BULK.has(k) or not RoomType.stores(p, k):
					continue
				var mine := float(colony.held_in(p, k)) * RoomType.CAPACITY_PER_CELL * w / maxf(1.0, colony.room_cap(p, k))
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
			# Печи (по одной на 3 м): каменные серые, кирпичные красные; горят — огонь и свет.
			var n := RoomType.stoves(p)
			var span := RoomType.usable_width(p) * TILE
			var brick_made := p.brick_stoves and p.phase == Project.Phase.DONE
			var body := Color(0.72, 0.36, 0.26, alpha) if brick_made else Color(0.62, 0.6, 0.66, alpha)
			var edge := Color(0.45, 0.2, 0.15, alpha) if brick_made else Color(0.4, 0.38, 0.44, alpha)
			var top := Color(0.55, 0.28, 0.2, alpha) if brick_made else Color(0.52, 0.5, 0.56, alpha)
			for i in n:
				var cx := x0 + span * (i + 0.5) / n
				_rbox(Rect2(cx - 24, floor_y - 34, 48, 34), 5, body, edge, 2)
				for row in 3:
					draw_line(Vector2(cx - 22, floor_y - 10 - row * 9), Vector2(cx + 22, floor_y - 10 - row * 9), Color(1, 1, 1, 0.25 * alpha), 1.0)
				_rbox(Rect2(cx - 14, floor_y - 22, 28, 22), 8, Color(0.16, 0.1, 0.1, alpha))
				_rbox(Rect2(cx - 28, floor_y - 40, 56, 8), 3, top, Color(0, 0, 0, 0), 0)
				# Труба в потолок.
				draw_rect(Rect2(cx - 6, r.position.y + 4, 12, floor_y - 40 - r.position.y - 4), top.lightened(0.08))
				if p.gas_boiler and p.phase == Project.Phase.DONE:
					# Железный газовый котёл на печи: бак с заклёпками, манометр и газовая труба.
					var steel := Color(0.46, 0.5, 0.56, alpha)
					var b := Rect2(cx - 17, floor_y - 68, 34, 27)
					_rbox(b, 7, steel, Color(0.26, 0.29, 0.33, alpha), 2)
					draw_rect(Rect2(b.position.x + 2, b.position.y + 6, b.size.x - 4, 3), Color(1, 1, 1, 0.18 * alpha))
					for k in 4:
						draw_circle(Vector2(b.position.x + 6 + k * 7.3, b.end.y - 5), 1.6, Color(0.3, 0.32, 0.36, alpha))
					draw_circle(Vector2(cx + 9, b.position.y + 12), 4.5, Color(0.92, 0.9, 0.84, alpha))
					draw_line(Vector2(cx + 9, b.position.y + 12), Vector2(cx + 11, b.position.y + 9), Color(0.7, 0.15, 0.1, alpha), 1.2)
					draw_rect(Rect2(b.position.x - 8, b.position.y + 14, 9, 4), Color(0.75, 0.62, 0.2, alpha))
				if p.burning and alpha >= 1.0:
					var tt := Time.get_ticks_msec() / 1000.0 + i * 1.3
					_glow(Vector2(cx, floor_y - 12), r.size.y * 1.2, Color(1.0, 0.6, 0.25, 0.22))
					for k in 3:
						var fx := cx + (k - 1) * 7.0
						var fh := 11.0 + 5.0 * sin(tt * 7.0 + k * 2.0)
						draw_colored_polygon(PackedVector2Array([Vector2(fx - 5, floor_y - 2), Vector2(fx + 5, floor_y - 2), Vector2(fx + sin(tt * 5.0 + k) * 2.0, floor_y - 2 - fh)]),
							Color(0.3, 0.55, 1.0) if p.on_gas else Color(1.0, 0.5, 0.15))
						draw_colored_polygon(PackedVector2Array([Vector2(fx - 3, floor_y - 2), Vector2(fx + 3, floor_y - 2), Vector2(fx, floor_y - 2 - fh * 0.6)]),
							Color(0.7, 0.88, 1.0) if p.on_gas else Color(1.0, 0.85, 0.35))
			# Поленница у последней печи.
			var wx := x0 + span * (n - 0.5) / n + 32
			for k in 3:
				draw_circle(Vector2(wx + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 4.5, Color(0.66, 0.44, 0.25, alpha))
				draw_circle(Vector2(wx + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 2.0, Color(0.9, 0.75, 0.5, alpha))
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
	# Готовая шахта — крепь на каждом метре, как ставили при проходке, и рельсы.
	if p.kind == Project.Kind.MINE:
		for i in p.slice_count():
			_draw_slice_support(p, i, alpha)
		_draw_rails(r, alpha)
		return
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



## Рельсы для вагонеток по полу шахты: шпалы и рельс.
func _draw_rails(r: Rect2, alpha: float) -> void:
	var rail := Color(0.42, 0.42, 0.46, alpha)
	var y := r.end.y - 4
	var sx := r.position.x + 4
	while sx < r.end.x - 4:
		draw_line(Vector2(sx, y + 1), Vector2(minf(sx + 6, r.end.x - 4), y + 1), Color(BEAM_DARK, alpha), 3.0)
		sx += 10
	draw_line(Vector2(r.position.x + 2, y - 2), Vector2(r.end.x - 2, y - 2), rail, 2.0)


func _draw_site(p: Project, font: Font) -> void:
	var r := _rect_px(p.rect)
	var edge := DIG_EDGE if p.phase == Project.Phase.DIG else BUILD_EDGE
	if not p.blocked.is_empty():
		edge = BLOCKED
	if p.paused:
		edge = PAUSED
	if p.priority:
		# Приоритет — значок «!» в углу стройки.
		var at := r.position + Vector2(r.size.x - 12, 12)
		draw_circle(at, 10, Color(1.0, 0.72, 0.2))
		draw_string(font, at + Vector2(-3, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.25, 0.15, 0.05))
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
		if p.kind == Project.Kind.BRIDGE:
			# Мост строят по метру от берега: готовые метры — целиком, остальное — призраком.
			_draw_deck(p, r, 0.3)
			var m := colony.bridge_meters_done(p)
			if m > 0:
				var bw := m * TILE
				var br := Rect2(r.end.x - bw if colony.bridge_from_right(p) else r.position.x, r.position.y, bw, r.size.y)
				_draw_deck(p, br, 1.0)
		elif p.is_water_structure():
			_draw_deck(p, r, 0.3 + 0.7 * t)
		elif p.kind == Project.Kind.ROOM:
			var wall: Color = WALLS.get(p.material, WALLS["wood"])[0]
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * t, r.size.x, r.size.y * t), Color(wall, 0.55))
		elif p.kind == Project.Kind.DRILL:
			_draw_drill(p, r, 0.3 + 0.7 * t)
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
	"food": Color(0.9, 0.8, 0.62), "fish": Color(0.55, 0.72, 0.85), "berries": Color(0.85, 0.25, 0.3), "coal": Color(0.15, 0.14, 0.13), "iron": Color(0.69, 0.33, 0.18),
	"copper": Color(0.25, 0.68, 0.57), "silver": Color(0.84, 0.87, 0.9), "gold": Color(0.95, 0.79, 0.23),
	"uranium": Color(0.53, 0.88, 0.31), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.91, 0.87, 0.9),
	"oil": Color(0.1, 0.08, 0.06), "limestone": Color(0.81, 0.78, 0.69),
	"soil": Color(0.36, 0.25, 0.16), "sand": Color(0.85, 0.75, 0.52), "gravel": Color(0.55, 0.52, 0.47),
	"iron_ore": Color(0.52, 0.28, 0.18), "copper_ore": Color(0.2, 0.52, 0.44), "silver_ore": Color(0.63, 0.65, 0.69),
	"gold_ore": Color(0.72, 0.6, 0.21), "uranium_ore": Color(0.4, 0.65, 0.24),
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
		# Готовое у производства — в ящиках внутри комнаты, а не кучей на полу.
		var prod := colony.producer_at(c)
		if prod != null:
			_draw_output_crates(font, d, p, colony.output_held(prod) >= Colony.PRODUCE_CAP)
			continue
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


## Ящики с готовым у входа в производство: чем больше, тем выше стопка (до трёх);
## на верхнем — значок продукта и сколько лежит (красным, когда склад полон).
func _draw_output_crates(font: Font, d: Dictionary, bottom: Vector2, full: bool) -> void:
	var total := 0
	var key := ""
	for k in d:
		total += int(d[k])
		if key.is_empty() or int(d[k]) > int(d.get(key, 0)):
			key = k
	var n := clampi(ceili(total / 34.0), 1, 3)
	var w := TILE * 0.8
	var h := TILE * 0.42
	for i in n:
		var box := Rect2(bottom.x - w * 0.5, bottom.y - 3 - h * (i + 1), w, h - 2)
		_rbox(box, 3, CRATE, CRATE.darkened(0.45), 2)
		draw_line(Vector2(box.position.x + 3, box.get_center().y), Vector2(box.end.x - 3, box.get_center().y), CRATE.darkened(0.3), 1.5)
	var top := bottom - Vector2(0, 3 + h * n + 9)
	ResIcon.draw(self, key, top, 8.0)
	_label(font, top + Vector2(10, 4), str(total), Color(1.0, 0.45, 0.4) if full else Color(1, 1, 1, 0.9))


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
	# Гаечный ключ: износ 70% — оранжевый, 90% — красный и мигает. В комнате — внутри,
	# вверху посередине; у тоннеля, моста и пристани — над ними.
	var col := Color(1.0, 0.7, 0.2) if p.wear < Colony.WEAR_WARN[1] else Color(1.0, 0.3, 0.25)
	if p.wear >= Colony.WEAR_WARN[1] and int(Time.get_ticks_msec() / 400) % 2 == 0:
		col = col.lightened(0.4)
	var c := Vector2(r.get_center().x, r.position.y + 22) if p.kind == Project.Kind.ROOM and p.rect.size.y >= 3 \
		else Vector2(r.get_center().x, r.position.y - 16)
	_signs.draw_circle(c, 15, Color(0, 0, 0, 0.55))
	_signs.draw_arc(c, 15, 0, TAU, 24, col, 2.0)
	ResIcon.draw_glyph(_signs, "repair", c, 11, col)


## Рабочая комната без работника: перечёркнутый человечек внутри, в левом верхнем углу.
func _draw_no_worker_sign(p: Project) -> void:
	var r := _rect_px(p.rect)
	# У пристани (настил в 1 клетку) — над ней.
	var c := Vector2(r.position.x + 22, r.position.y + 22) if p.rect.size.y >= 3 else Vector2(r.position.x + 16, r.position.y - 16)
	var col := Color(1.0, 0.45, 0.4)
	if int(Time.get_ticks_msec() / 600) % 2 == 0:
		col = col.lightened(0.3)
	_signs.draw_circle(c, 15, Color(0, 0, 0, 0.55))
	ResIcon.draw_glyph(_signs, "people", c, 11, col)
	_signs.draw_line(c + Vector2(-9, 9), c + Vector2(9, -9), col, 2.5)


## Жилой дом с морозом внутри: снежинка внутри комнаты, в правом верхнем углу.
func _draw_frost_sign(p: Project) -> void:
	var r := _rect_px(p.rect)
	var c := Vector2(r.end.x - 22, r.position.y + 22)
	var col := Color(0.6, 0.85, 1.0)
	if int(Time.get_ticks_msec() / 600) % 2 == 0:
		col = col.lightened(0.35)
	_signs.draw_circle(c, 15, Color(0, 0, 0, 0.55))
	ResIcon.draw_glyph(_signs, "frost", c, 11, col)


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
