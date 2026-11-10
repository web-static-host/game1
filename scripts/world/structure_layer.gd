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
## Крепь и лестницы по материалу постройки: [цвет, тень].
const MAT_BEAM := {
	"wood": [BEAM, BEAM_DARK],
	"stone": [Color(0.66, 0.68, 0.72), Color(0.4, 0.42, 0.47)],
	"brick": [Color(0.78, 0.4, 0.3), Color(0.48, 0.22, 0.16)],
	"iron": [Color(0.6, 0.65, 0.72), Color(0.3, 0.34, 0.4)],
	"silver": [Color(0.88, 0.9, 0.94), Color(0.55, 0.58, 0.64)],
	"gold": [Color(1.0, 0.8, 0.25), Color(0.62, 0.45, 0.08)],
	"diamond": [Color(0.7, 0.95, 1.0), Color(0.3, 0.6, 0.75)],
}
const BAR_BG := Color(0, 0, 0, 0.6)
const BAR := Color(0.45, 0.9, 0.4)

var view: WorldView
var colony: Colony
## Рамка новой стройки (size == 0 — нет).
var preview := Rect2i()
## Места посадки корабля (кнопка «Места посадки»): первое — куда сядет следующий.
var landing: Array[Rect2i] = []
var preview_ok := false
var preview_text := ""
var selected_project := 0


## Значки (износ, нет работника, мороз) — отдельным слоем поверх темноты, чтобы их было видно
## и в неосвещённых комнатах.
var _signs: Node2D


## Слой рисуется в два узла. Этот (live = false) — неподвижное: стены, мебель, крепь, стройки,
## кучи, подписи; перерисовывается раз в STATIC_REFRESH с или когда камера ушла за нарисованное
## (раньше — всё каждый кадр, это была большая часть кадра). Дочерний (live = true) — то, что
## движется: лифты, буры, геоскважины, насосы, вентиляторы, огонь в печах, корабль, «?» у пустой
## комнаты, трещины копки, падающая порода и лампы, — каждый кадр, но их немного.
var live := false
var _live: StructureLayer
## Запуски ракет: [опорная точка ракеты (клетки, x/y дробные), картинка, когда стартовала (мс)].
## Ракета улетает мгновенно (в игре), а здесь — зажигание, дым и подъём с пламенем.
static var launches: Array = []
var _pad_rockets := {}
const LAUNCH_IGNITE := 1.3
const LAUNCH_TIME := 7.0
## Куда рисуем: сам узел (живой слой) или сборщик сеток (неподвижный слой).
var _c: Variant = self
var _batch := MeshBatch.new()
var _meshes: Array = []
const STATIC_REFRESH := 0.25
var _static_t := 0.0
var _drawn_vis := Rect2i()
var _drawn_sig := []


func _ready() -> void:
	if live:
		return
	_live = StructureLayer.new()
	_live.live = true
	_live.view = view
	_live.colony = colony
	add_child(_live)
	_signs = Node2D.new()
	_signs.z_index = 11
	_signs.draw.connect(_draw_signs)
	add_child(_signs)


func _process(delta: float) -> void:
	if live:
		var parent := get_parent() as StructureLayer
		colony = parent.colony
		selected_project = parent.selected_project
		queue_redraw()
		return
	if _live != null:
		_live.colony = colony
		_live.view = view
	_watch_launches()
	_static_t -= delta
	var sel := colony.project_by_id(selected_project) if colony != null and selected_project != 0 else null
	var sig := [selected_project, preview, preview_ok, preview_text, colony.projects.size() if colony != null else 0, view.origin,
		sel.order_len if sel != null else 0, _drills_sig(), landing.size(), view.camera.zoom.x if not landing.is_empty() else 0.0]
	var vis := _vis_rect().grow(-VIS_MARGIN + 2)
	if _static_t <= 0.0 or sig != _drawn_sig or not _drawn_vis.encloses(vis):
		_static_t = STATIC_REFRESH
		_drawn_sig = sig
		queue_redraw()
	if _signs != null:
		_signs.queue_redraw()


## Ракета на космодроме была и пропала — значит, улетела: запускаем анимацию старта.
func _watch_launches() -> void:
	if colony == null:
		return
	var seen := {}
	for p in colony.projects:
		if p.kind != Project.Kind.ROOM or p.purpose != RoomType.LAUNCHPAD:
			continue
		seen[p.id] = true
		var was: String = _pad_rockets.get(p.id, "")
		if not was.is_empty() and p.rocket.is_empty() and p.equip_rocket.is_empty():
			var st: Vector2 = _pad_layout(_rect_px(p.rect))["stand"]
			var stand := (st - view.cell_to_local(Vector2i.ZERO)) / TILE
			launches.append([stand, "rocket_nuclear" if was == "nuclear" else "rocket_chem", Time.get_ticks_msec()])
		_pad_rockets[p.id] = p.rocket
	for id in _pad_rockets.keys():
		if not seen.has(id):
			_pad_rockets.erase(id)
	var now := Time.get_ticks_msec()
	launches = launches.filter(func(l: Array) -> bool: return now - int(l[2]) < LAUNCH_TIME * 1000.0)


## Старт ракеты: зажигание (дрожит, клубы дыма у стола), потом подъём с ускорением —
## пламя из сопла и шлейф дыма, который остаётся висеть и расплывается.
func _draw_launches() -> void:
	var now := Time.get_ticks_msec()
	for l in launches:
		var t := (now - int(l[2])) / 1000.0
		var base := view.cell_to_local(Vector2i.ZERO) + (l[0] as Vector2) * TILE
		var lift := 0.0 if t < LAUNCH_IGNITE else 0.5 * 30.0 * TILE * pow(t - LAUNCH_IGNITE, 2.0)
		var shake := Vector2(sin(t * 70.0), 0) * (2.0 if t < LAUNCH_IGNITE + 0.6 else 0.6)
		var at := base + Vector2(0, -lift) + shake
		# Дым: клубы у стола (растут с зажигания) и шлейф по пути — каждые 0,07 с новый клуб.
		var puffs := int(t / 0.07)
		for k in puffs:
			var te := k * 0.07
			var age := t - te
			var h := 0.0 if te < LAUNCH_IGNITE else 0.5 * 30.0 * TILE * pow(te - LAUNCH_IGNITE, 2.0)
			var side := WorldGen.hash01(k, 3, 11) * 2.0 - 1.0
			var spread := (1.0 + age * 1.6) * (TILE * 0.5 if te < LAUNCH_IGNITE + 0.4 else TILE * 0.35)
			var c := base + Vector2(side * spread * (2.2 if te < LAUNCH_IGNITE + 0.4 else 0.8), -h + age * TILE * 0.3)
			var a := clampf(0.55 - age * 0.09, 0.0, 0.55)
			if a > 0.0:
				_c.draw_circle(c, spread, Color(0.86, 0.86, 0.88, a))
		if lift > TILE * 60.0:
			continue
		# Пламя: длиннее после отрыва, мерцает.
		var flick := 0.85 + 0.15 * sin(t * 50.0)
		var len := (TILE * (0.8 + t * 1.4) if t < LAUNCH_IGNITE else TILE * 4.0) * flick
		var w := TILE * 0.9
		var blue := String(l[1]).ends_with("nuclear")
		_glow(at + Vector2(0, len * 0.4), len * 0.9, Color(0.4, 0.7, 1.0, 0.35) if blue else Color(1.0, 0.6, 0.2, 0.35))
		var ft := furniture("cosmodrome", "flame_blue" if blue else "flame_orange")
		if ft != null:
			# Пламя-картинка (широкое у сопла, узкое к низу): ширина дрожит, длина — по ходу старта.
			var fw := TILE * 2.2 * (0.92 + 0.08 * sin(t * 37.0))
			_c.draw_texture_rect(ft, Rect2(at.x - fw * 0.5, at.y - 6.0, fw, len * 1.35), false)
		else:
			_c.draw_colored_polygon(PackedVector2Array([at + Vector2(-w, -4), at + Vector2(w, -4), at + Vector2(0, len)]), Color(1.0, 0.55, 0.15, 0.95))
			_c.draw_colored_polygon(PackedVector2Array([at + Vector2(-w * 0.55, -4), at + Vector2(w * 0.55, -4), at + Vector2(0, len * 0.65)]), Color(1.0, 0.92, 0.5))
		if not _sprite(l[1], at, 1.0):
			_rbox(Rect2(at.x - TILE * 1.2, at.y - TILE * 12, TILE * 2.4, TILE * 12), 6, HULL, HULL_DARK, 2)


## Постройка, у которой что-то движется, — рисуется живым слоем каждый кадр.
static func animated(p: Project) -> bool:
	match p.kind:
		Project.Kind.LIFT, Project.Kind.DRILL, Project.Kind.PROBE:
			return p.phase == Project.Phase.DONE
		Project.Kind.ROOM:
			if p.phase != Project.Phase.DONE:
				return false
			return p.purpose in [RoomType.PUMP, RoomType.VENT, RoomType.HEARTH, RoomType.SHIP, RoomType.NONE, RoomType.OIL_PUMP,
				RoomType.KILN, RoomType.FORGE, RoomType.GENERATOR, RoomType.GAS_GEN, RoomType.DIESEL_GEN,
				RoomType.OIL_TANK, RoomType.REFINERY, RoomType.ENRICHMENT, RoomType.TELEPORT, RoomType.LAUNCHPAD]
	return false


func _draw_signs() -> void:
	if colony == null:
		return
	_vis = _vis_rect()
	for p in colony.projects:
		if not p.rect.intersects(_vis):
			continue
		if p.wear >= Colony.WEAR_WARN[0] and not p.repairing:
			_draw_wear_sign(p)
		if colony.is_workplace(p) and p.kind != Project.Kind.BRIDGE and not p.paused and colony.assigned_to(p).is_empty():
			_draw_no_worker_sign(p)
		if colony.home_freezing(p):
			_draw_frost_sign(p)


## Что видно на экране (в клетках, с запасом на подписи и леса): рисуем только это — раньше
## каждый кадр рисовались все постройки и все кучи на карте (десятки тысяч команд).
const VIS_MARGIN := 8
var _vis := Rect2i()


func _vis_rect() -> Rect2i:
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var a := view.local_to_cell(view.camera.position - half)
	var b := view.local_to_cell(view.camera.position + half)
	return Rect2i(a, b - a + Vector2i.ONE).grow(VIS_MARGIN)


func _rect_px(r: Rect2i) -> Rect2:
	return Rect2(view.cell_to_local(r.position), Vector2(r.size) * TILE)


func _draw() -> void:
	if colony == null:
		return
	var font := ThemeDB.fallback_font
	_vis = _vis_rect()
	if not live:
		_drawn_vis = _vis
	var shown: Array[Project] = []
	for p in colony.projects:
		if p.rect.intersects(_vis) and animated(p) == live:
			shown.append(p)
	if live:
		_c = self
		_draw_live(shown)
		return
	_batch.clear()
	_batch.strict = true
	_c = _batch
	_draw_static(shown, font)
	_c = self
	_meshes = _batch.build()
	_batch.render(self, _meshes)


func _draw_static(shown: Array[Project], font: Font) -> void:
	_draw_stockpile(font)
	for p in shown:
		if not p.foundation.is_empty():
			_draw_foundation(p)
	for p in shown:
		if p.phase == Project.Phase.DONE or p.phase == Project.Phase.EQUIP:
			_draw_done(p)
	for p in shown:
		if p.phase == Project.Phase.DIG or p.phase == Project.Phase.BUILD:
			_draw_site(p, font)
	_draw_drops(font)
	_draw_gas()
	for p in colony.projects:
		if p.rect.intersects(_vis):
			_draw_supply(p, font)
	_draw_zone(colony.project_by_id(selected_project) if selected_project != 0 else null)
	_draw_extend(colony.project_by_id(selected_project) if selected_project != 0 else null, font)
	_draw_drill_plan(colony.project_by_id(selected_project) if selected_project != 0 else null, font)
	_draw_landing(font)
	if preview.size != Vector2i.ZERO:
		var r := _rect_px(preview)
		var col := Color(0.4, 1.0, 0.45) if preview_ok else Color(1.0, 0.35, 0.3)
		_c.draw_rect(r, Color(col, 0.18))
		_c.draw_rect(r, col, false, 3.0)
		_label(font, r.position + Vector2(4, -8), preview_text, col)


## Живой слой: движущиеся постройки, трещины копки, падающая порода, лампы на стройках.
func _draw_live(shown: Array[Project]) -> void:
	_draw_launches()
	for p in shown:
		if p.kind == Project.Kind.DRILL:
			_draw_drill(p, _rect_px(p.rect), 1.0)
		elif p.kind == Project.Kind.PROBE:
			_draw_probe(p, _rect_px(p.rect), 1.0)
		else:
			_draw_done(p)
	_draw_dig_progress()
	# Падающая порода.
	for f in colony.physics.fx:
		var t := clampf(f[3] / Physics.FX_TIME, 0.0, 1.0)
		var pos: Vector2 = (f[0] as Vector2).lerp(f[1], t * t)
		var px := view.cell_to_local(Vector2i.ZERO) + pos * TILE
		var col := ChunkView.rock_color(f[2], 0.5)
		_c.draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col)
		_c.draw_rect(Rect2(px + Vector2(2, 2), Vector2(TILE - 4, TILE - 4)), col.darkened(0.3), false, 2.0)
	# Лампы там, где сейчас идёт работа на стройке или в шахте.
	for c in colony.work_lamps:
		if not _vis.has_point(c):
			continue
		var at := view.cell_to_local(c) + Vector2(TILE * 0.5, 2)
		_glow(at + Vector2(0, 8), TILE * 2.2, Color(1.0, 0.86, 0.45, 0.3))
		_c.draw_line(at + Vector2(-6, -2), at + Vector2(6, -2), Color(0.3, 0.3, 0.32), 2.0)
		_c.draw_circle(at + Vector2(0, 3), 4, LAMP)


## Цвета по материалу стен: [задняя стена, рама, линии кладки].
const WALLS := {
	"wood": [Color(0.8, 0.56, 0.35), Color(0.48, 0.31, 0.19), Color(0.74, 0.51, 0.31)],
	"stone": [Color(0.7, 0.73, 0.8), Color(0.42, 0.45, 0.55), Color(0.6, 0.63, 0.71)],
	"brick": [Color(0.84, 0.43, 0.32), Color(0.5, 0.24, 0.18), Color(0.95, 0.84, 0.74)],
	"iron": [Color(0.64, 0.7, 0.78), Color(0.34, 0.39, 0.47), Color(0.52, 0.58, 0.66)],
	"silver": [Color(0.82, 0.85, 0.9), Color(0.5, 0.53, 0.6), Color(0.95, 0.97, 1.0)],
	"gold": [Color(0.95, 0.76, 0.28), Color(0.6, 0.42, 0.1), Color(1.0, 0.9, 0.55)],
	"diamond": [Color(0.66, 0.9, 0.98), Color(0.28, 0.55, 0.7), Color(0.92, 1.0, 1.0)],
}
const BED_FRAME := Color(0.56, 0.36, 0.22)
const BLANKETS := [Color(0.31, 0.6, 0.95), Color(0.94, 0.4, 0.55), Color(0.38, 0.78, 0.45), Color(0.98, 0.72, 0.25)]
const SOIL := Color(0.38, 0.25, 0.17)
const MUSHROOM := Color(0.98, 0.95, 0.88)
const MUSHROOM_CAPS := [Color(1.0, 0.47, 0.35), Color(1.0, 0.78, 0.3), Color(0.6, 0.45, 1.0)]
const CRATE := Color(0.8, 0.58, 0.34)


## Фундамент под комнатой (космодром на неровной земле) — кладка из материала комнаты.
func _draw_foundation(p: Project) -> void:
	var c: Array = WALLS.get(p.material, WALLS["stone"])
	var tex := structure_texture("foundation_" + p.material)
	for cell in p.foundation:
		if not Mat.is_solid(colony.world.get_mat(cell.x, cell.y)):
			continue
		var r := _rect_px(Rect2i(cell, Vector2i.ONE))
		if tex != null:
			_c.draw_texture_rect(tex, r, false)
			continue
		_c.draw_rect(r, c[0])
		_c.draw_rect(r, c[1], false, 2.0)
		var mid := r.position.y + r.size.y * 0.5
		_c.draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), c[1], 1.5)
		var off := r.size.x * (0.25 if (cell.y % 2) == 0 else 0.75)
		_c.draw_line(Vector2(r.position.x + off, r.position.y), Vector2(r.position.x + off, mid), c[1], 1.5)


func _draw_done(p: Project) -> void:
	var r := _rect_px(p.rect)
	if p.is_water_structure():
		_draw_deck(p, r, 1.0)
	elif p.kind == Project.Kind.ROOM:
		if p.purpose == RoomType.SHIP:
			# Корпус снаружи — под отсеком: нос, стабилизаторы и обшивка видны вокруг комнаты.
			_sprite("ship_hull", r.position + Vector2(0, r.size.y), 1.0)
		# Космодром — открытая площадка, не здание: без стен (стол и пульты — в _draw_launchpad).
		if not (p.purpose == RoomType.LAUNCHPAD and p.phase == Project.Phase.DONE and furniture("cosmodrome", "table") != null):
			_draw_room_shell(p, r)
		_ceil.clear()
		_rails.clear()
		_wall_items.clear()
		_room_top = r.position.y
		if p.phase == Project.Phase.EQUIP:
			var w := RoomType.job_work(p)
			var t := clampf(p.equip_done / w, 0.0, 1.0) if p.equip_paid else 0.0
			if p.equip_ladder:
				_draw_furniture(p, r, p.purpose, 1.0)
				_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 0.25 + 0.6 * t, RoomType.furnish_material(p))
			else:
				_draw_furniture(p, r, RoomType.base_type(p.equip_target), 0.25 + 0.6 * t)
			var bar := Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 16, 6)
			_c.draw_rect(bar, BAR_BG)
			_c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
			_dashed_rect(r, PAUSED if p.paused else BUILD_EDGE, 2.5)
		else:
			_draw_furniture(p, r, p.purpose, 1.0)
			if p.purpose == RoomType.NONE and p.phase == Project.Phase.DONE:
				_draw_question(r)
		_room_top = -INF
		if not (p.purpose == RoomType.LAUNCHPAD and p.phase == Project.Phase.DONE and furniture("cosmodrome", "table") != null):
			_draw_room_lamps(p, r)
	elif p.kind == Project.Kind.LIFT:
		_draw_lift(p, r)
	elif p.kind != Project.Kind.DRILL and p.kind != Project.Kind.PROBE:
		_draw_supports(p, r, 1.0 - p.wear * 0.5)
	if p.wear > 0.4:
		_draw_cracks(p, r)
	# Завал: проход перекрыт — выработка красная, обломки ярче (нажмите — разобрать).
	if colony.has_blockage(p):
		_c.draw_rect(r, Color(0.9, 0.15, 0.1, 0.22))
		for c in colony.remaining_dig(p):
			var cr := _rect_px(Rect2i(c, Vector2i.ONE))
			_c.draw_rect(cr, Color(0.95, 0.15, 0.1, 0.55))
		_dashed_rect(r, Color(1.0, 0.25, 0.2, 0.95), 3.0)
	if p.repairing:
		var t := clampf(p.repair_done / maxf(1.0, p.repair_work), 0.0, 1.0) if p.repair_paid else 0.0
		var bar := Rect2(r.position.x + 8, r.position.y + 10, r.size.x - 16, 6)
		_c.draw_rect(bar, BAR_BG)
		_c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Color(0.4, 0.7, 1.0))
		_dashed_rect(r, Color(0.4, 0.7, 1.0), 2.5)
	# Бур-лифт выделяется целиком: и бур, и его лифт.
	if p.id == selected_project or (p.link_id != 0 and p.link_id == selected_project):
		_c.draw_rect(r.grow(2), Color.WHITE, false, 2.0)


## Корабль: койки в два яруса, пульт, иллюминаторы; снаружи — нос, стабилизаторы, опоры.
const HULL := Color(0.78, 0.8, 0.84)
const HULL_DARK := Color(0.45, 0.48, 0.55)


func _draw_ship(p: Project, r: Rect2, alpha: float) -> void:
	if structure_texture("ship_hull") == null:
		_draw_ship_hull(r, alpha)
	if furniture("ship", "bunk") != null:
		_draw_ship_cabin(r, alpha)
	else:
		_draw_ship_inside(r, alpha)


## Каюта корабля (прототип art_src/rooms/prototypes/ship_9.png): по 3 м — двухъярусная койка;
## тумбочка с лампой и койка, над ними полка; пульт с планетой на экране. Под потолком — светильники.
func _draw_ship_cabin(r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var k := TILE / FURN_PX_PER_M
	var b := r.size.x / 3.0
	var x0 := r.position.x
	var light := furniture("ship", "light")
	for i in 3:
		var lx := x0 + b * (i + 0.5)
		_c.draw_texture_rect(light, Rect2(lx - light.get_width() * k * 0.5, fy - TILE * (CEILING - 0.02), light.get_width() * k, light.get_height() * k), false, Color(1, 1, 1, alpha))
		if alpha >= 1.0:
			_glow(Vector2(lx, fy - TILE * (CEILING - 0.25)), TILE * 1.3, Color(1.0, 0.95, 0.8, 0.1))
	_furn_at(furniture("ship", "bunk"), x0 + b * 0.5, fy, alpha, 1)
	var stand := furniture("ship", "nightstand")
	var bed := furniture("ship", "bed")
	var sw := stand.get_width() * k
	var bw := bed.get_width() * k
	var mx := x0 + b * 1.5 - (sw + bw + TILE * 0.08) * 0.5
	_furn_at(stand, mx + sw * 0.5, fy, alpha, 1)
	var lamp := furniture("ship", "lamp")
	_furn_at(lamp, mx + sw * 0.5, fy - stand.get_height() * k + 2.0, alpha)
	_furn_at(bed, mx + sw + TILE * 0.08 + bw * 0.5, fy, alpha, 1)
	# Полка — между спинкой кровати и иллюминатором (цветок и ракета не заходят на стекло).
	var shelf := furniture("ship", "shelf")
	_furn_at(shelf, x0 + b * 1.5, fy - TILE * 0.98, alpha, 2, 0.85)
	var con := furniture("ship", "console")
	_furn_at(con, x0 + b * 2.5, fy, alpha, 1)
	if alpha >= 1.0:
		var ch := con.get_height() * k
		var t := _anim_t()
		_glow(Vector2(x0 + b * 2.5, fy - ch * 0.68), TILE * 0.7, Color(0.3, 0.75, 1.0, 0.2 + 0.08 * sin(t * 2.0)))
		# Огоньки пульта мигают по очереди.
		var lit := int(t * 2.0) % 3
		var cols := [Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.25)]
		var lx := x0 + b * 2.5 - con.get_width() * k * 0.075
		_glow(Vector2(lx + lit * con.get_width() * k * 0.075, fy - ch * 0.42), TILE * 0.18, Color(cols[lit], 0.6))


## Нос, стабилизаторы, опоры и иллюминаторы — кодом (если нет рендера корпуса).
func _draw_ship_hull(r: Rect2, alpha: float) -> void:
	# Нос справа, стабилизаторы слева, опоры снизу — вокруг комнаты.
	var mid := r.get_center().y
	_c.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y + 4), Vector2(r.end.x + TILE * 2.2, mid),
		Vector2(r.end.x, r.end.y - 4)]), Color(HULL, alpha))
	_c.draw_polyline(PackedVector2Array([Vector2(r.end.x, r.position.y + 4), Vector2(r.end.x + TILE * 2.2, mid),
		Vector2(r.end.x, r.end.y - 4)]), Color(HULL_DARK, alpha), 3.0)
	for sgn in [-1.0, 1.0]:
		var base: Vector2 = Vector2(r.position.x, mid + sgn * r.size.y * 0.35)
		_c.draw_colored_polygon(PackedVector2Array([base, base + Vector2(-TILE * 1.4, sgn * TILE * 1.2),
			base + Vector2(TILE * 0.8, 0)]), Color(0.85, 0.35, 0.3, alpha))
	for k in 3:
		var lx := r.position.x + r.size.x * (0.2 + 0.3 * k)
		_c.draw_line(Vector2(lx, r.end.y), Vector2(lx - 6, r.end.y + 10), Color(HULL_DARK, alpha), 3.0)
	# Иллюминаторы под потолком.
	for k in 4:
		var wc := Vector2(r.position.x + r.size.x * (0.15 + 0.23 * k), r.position.y + 14)
		_c.draw_circle(wc, 7, Color(HULL_DARK, alpha))
		_c.draw_circle(wc, 5, Color(0.55, 0.8, 1.0, alpha))


## Внутри корабля: койки в два яруса и пульт.
func _draw_ship_inside(r: Rect2, alpha: float) -> void:
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
		_c.draw_circle(Vector2(cx + 9 + k * 13, r.end.y - 25), 3.5,
			Color(0.4, 1.0, 0.5, alpha) if k == blink else Color(0.25, 0.45, 0.3, alpha))


## Космодром: бетонный стол, башня обслуживания; ракета на столе (во время сборки — в лесах).
## Стартовый стол космодрома (картинка cosmodrome/table): во всю ширину площадки, ракета — в
## гнезде посередине (TABLE_STAND — его верх, пиксели картинки), башня и пульты — на настиле
## (TABLE_DECK). -> {"deck": y настила, "stand": точка, где стоит ракета} (пиксели слоя).
const TABLE_DECK := 52.0
const TABLE_STAND := 18.0
func _pad_layout(r: Rect2) -> Dictionary:
	var table := furniture("cosmodrome", "table")
	if table == null:
		return {"deck": r.end.y - 16, "stand": Vector2(r.get_center().x - TILE * 0.6, r.end.y - 16), "k": 0.0}
	var k := r.size.x * 0.99 / table.get_width()
	var bottom := r.end.y - 2.0
	var top := bottom - table.get_height() * k
	return {"deck": top + TABLE_DECK * k, "stand": Vector2(r.get_center().x, top + TABLE_STAND * k), "k": k, "top": top}


func _draw_launchpad(p: Project, r: Rect2, alpha: float) -> void:
	var lay := _pad_layout(r)
	var tx := r.end.x - TILE * 0.8
	var stand: float = lay["deck"]
	var table := furniture("cosmodrome", "table")
	if table == null:
		_rbox(Rect2(r.position.x + 4, r.end.y - 16, r.size.x - 8, 12), 3, Color(0.62, 0.62, 0.6, alpha), Color(0.4, 0.4, 0.4, alpha), 2)
	else:
		# Пульт и ящики слева, баллоны справа — на настиле, вне ракеты и башни.
		var dk: float = lay["deck"]
		var kk := TILE / FURN_PX_PER_M
		var x0 := r.position.x
		_furn_at(furniture("cosmodrome", "console"), x0 + TILE * 0.85, dk, alpha, 1)
		_furn_at(furniture("cosmodrome", "crate"), x0 + TILE * 1.9, dk, alpha, 1)
		_furn_at(furniture("cosmodrome", "lever"), x0 + TILE * 1.75, dk - furniture("cosmodrome", "crate").get_height() * kk + 2.0, alpha)
		for cx in [r.end.x - TILE * 1.95, r.end.x - TILE * 1.5]:
			_furn_at(furniture("cosmodrome", "cylinder"), cx, dk, alpha, 1)
		_c.draw_texture_rect(table, Rect2(r.position.x + r.size.x * 0.005, lay["top"], table.get_width() * lay["k"], table.get_height() * lay["k"]), false, Color(1, 1, 1, alpha))
		if alpha >= 1.0:
			var lit := int(_anim_t() * 2.0) % 2 == 0
			_glow(Vector2(x0 + TILE * 0.85, dk - TILE * 0.62), TILE * 0.35, Color(0.3, 0.8, 1.0, 0.25 if lit else 0.12))
	if not _sprite("launch_tower", Vector2(tx, stand), alpha):
		_draw_tower_code(r, tx, alpha)
	var t := 0.0
	if not p.rocket.is_empty():
		t = 1.0
	elif not p.equip_rocket.is_empty():
		t = clampf(p.equip_done / RoomType.ROCKET_WORK, 0.0, 1.0) if p.equip_paid else 0.0
	else:
		return
	var nuclear := p.rocket == "nuclear" or p.equip_rocket == "nuclear"
	var at: Vector2 = lay["stand"]
	var name := "rocket_nuclear" if nuclear else "rocket_chem"
	if structure_texture(name) != null:
		# Во время сборки — силуэт ракеты и собранная снизу часть.
		if t < 1.0:
			_sprite(name, at, alpha * 0.18)
		_sprite(name, at, alpha * (0.35 + 0.65 * t), maxf(t, 0.05))
		return
	_draw_rocket_code(r, t, nuclear, alpha)


func _draw_tower_code(r: Rect2, tx: float, alpha: float) -> void:
	for y in range(int(r.position.y - TILE * 12), int(r.end.y - 16), 18):
		_c.draw_line(Vector2(tx - 8, y), Vector2(tx + 8, y + 18), Color(0.75, 0.3, 0.25, alpha), 2.0)
		_c.draw_line(Vector2(tx + 8, y), Vector2(tx - 8, y + 18), Color(0.75, 0.3, 0.25, alpha), 2.0)
	_c.draw_line(Vector2(tx - 8, r.position.y - TILE * 12), Vector2(tx - 8, r.end.y - 16), Color(0.6, 0.25, 0.2, alpha), 3.0)
	_c.draw_line(Vector2(tx + 8, r.position.y - TILE * 12), Vector2(tx + 8, r.end.y - 16), Color(0.6, 0.25, 0.2, alpha), 3.0)


func _draw_rocket_code(r: Rect2, t: float, nuclear: bool, alpha: float) -> void:
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
		_c.draw_colored_polygon(PackedVector2Array([Vector2(body.position.x, body.position.y), Vector2(cx, top),
			Vector2(body.end.x, body.position.y)]), Color(0.85, 0.3, 0.28, alpha) if not nuclear else Color(0.3, 0.75, 0.4, alpha))
		for sgn in [-1.0, 1.0]:
			var fx: float = cx + sgn * w * 0.5
			_c.draw_colored_polygon(PackedVector2Array([Vector2(fx, body.end.y - TILE * 2.5), Vector2(fx + sgn * TILE, body.end.y),
				Vector2(fx, body.end.y)]), Color(0.85, 0.3, 0.28, alpha))
		_c.draw_circle(Vector2(cx, body.position.y + TILE * 2), 9, Color(HULL_DARK, alpha))
		_c.draw_circle(Vector2(cx, body.position.y + TILE * 2), 6.5, Color(0.55, 0.8, 1.0, alpha))
		if nuclear:
			_c.draw_circle(Vector2(cx, body.end.y - TILE * 3), 8, Color(1.0, 0.85, 0.2, alpha))


## Бур — машина 3×3: корпус с мотором сзади, сверло спереди (куда едет; стоит — вниз).
## Сверло крутится, пока бур сверлит.
func _draw_drill(p: Project, r: Rect2, alpha: float) -> void:
	var dir := p.drill_dir if p.drill_dir != Vector2i.ZERO else Vector2i.DOWN
	var body := r.grow(-3)
	var face := r
	if dir == Vector2i.DOWN:
		body.size.y = TILE * 2 - 4
		face = Rect2(r.position.x, r.position.y + TILE * 2, r.size.x, TILE)
	elif dir == Vector2i.UP:
		# Вверх: корпус снизу, коронка — верхний ряд (раньше рисовался как бур влево).
		body.position.y += TILE + 2
		body.size.y = TILE * 2 - 4
		face = Rect2(r.position.x, r.position.y, r.size.x, TILE)
	elif dir == Vector2i.RIGHT:
		body.size.x = TILE * 2 - 4
		face = Rect2(r.position.x + TILE * 2, r.position.y, TILE, r.size.y)
	else:
		body.position.x += TILE + 2
		body.size.x = TILE * 2 - 4
		face = Rect2(r.position.x, r.position.y, TILE, r.size.y)
	var bodyc: Color = Color(0.88, 0.62, 0.16) if p.bonus() <= 1.0 else (MAT_BEAM[p.material] as Array)[0]
	var tex := structure_texture("drill_diamond" if p.bonus() > 1.0 and p.material == "diamond" else "drill")
	if tex != null:
		# Рендер смотрит вправо: поворачиваем углы (влево — зеркально, свет остаётся сверху).
		var c := r.get_center()
		var hx := Vector2(r.size.x * 0.5, 0)
		var hy := Vector2(0, r.size.y * 0.5)
		var q: PackedVector2Array
		match dir:
			Vector2i.RIGHT:
				q = [c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy]
			Vector2i.LEFT:
				q = [c + hx - hy, c - hx - hy, c - hx + hy, c + hx + hy]
			Vector2i.DOWN:
				q = [c + hx - hy, c + hx + hy, c - hx + hy, c - hx - hy]
			_:
				q = [c - hx + hy, c - hx - hy, c + hx - hy, c + hx + hy]
		_sprite_quad(tex, q, alpha)
		var on := colony.powered() or p.fuel > 0.0
		_c.draw_circle(body.position + Vector2(9, 9), 4, Color(LAMP, alpha) if on else Color(0.35, 0.35, 0.38, alpha))
		var spin0 := Time.get_ticks_msec() * 0.01 if colony._drill_active(p) and on else 0.0
		var d0 := Vector2(dir)
		var base0 := face.get_center() - d0 * TILE * 0.5
		var tip0 := face.get_center() + d0 * TILE * 0.45
		var half0 := Vector2(-d0.y, d0.x) * TILE * 1.3
		for k in 3:
			var tt := fmod(spin0 + k / 3.0, 1.0)
			var m := base0.lerp(tip0, tt)
			_c.draw_line(m - half0 * (1.0 - tt), m + half0 * (1.0 - tt), Color(0.25, 0.26, 0.3, alpha * 0.8), 2.0)
		return
	_rbox(body, 6, Color(bodyc, alpha), Color(bodyc.darkened(0.5), alpha), 2)
	# Решётка мотора и лампа: горит, когда есть энергия.
	var mc := body.get_center()
	for k in 3:
		var off := (k - 1) * 7.0
		if dir == Vector2i.DOWN or dir == Vector2i.UP:
			_c.draw_line(mc + Vector2(-12, off), mc + Vector2(12, off), Color(0.45, 0.3, 0.1, alpha), 2.0)
		else:
			_c.draw_line(mc + Vector2(off, -12), mc + Vector2(off, 12), Color(0.45, 0.3, 0.1, alpha), 2.0)
	var lamp_on := colony.powered() or p.fuel > 0.0
	_c.draw_circle(body.position + Vector2(9, 9), 4, Color(LAMP, alpha) if lamp_on else Color(0.35, 0.35, 0.38, alpha))
	var d := Vector2(dir)
	var side := Vector2(-d.y, d.x)
	var base_c := face.get_center() - d * TILE * 0.5
	var tip := face.get_center() + d * TILE * 0.45
	var half := side * TILE * 1.3
	_c.draw_colored_polygon(PackedVector2Array([base_c - half, base_c + half, tip]), Color(0.6, 0.62, 0.68, alpha))
	var spin := Time.get_ticks_msec() * 0.01 if colony._drill_active(p) and lamp_on else 0.0
	for k in 3:
		var t := fmod(spin + k / 3.0, 1.0)
		var m := base_c.lerp(tip, t)
		var w := half * (1.0 - t)
		_c.draw_line(m - w, m + w, Color(0.3, 0.31, 0.35, alpha), 2.0)


## Геоскважина 2×2: вышка-тренога с мотором, из середины — штанга зонда (пока идёт,
## тянется на пройденные метры; кончик крутится).
func _draw_probe(p: Project, r: Rect2, alpha: float) -> void:
	var steel := Color(0.58, 0.6, 0.66, alpha)
	var dark := Color(0.32, 0.34, 0.4, alpha)
	var c := r.get_center()
	var top := Vector2(c.x, r.position.y + 4)
	if _sprite("probe", Vector2(c.x, r.end.y), alpha):
		_draw_probe_rod(p, r, alpha)
		return
	# Ноги вышки и перекладины.
	for sx in [-1.0, 1.0]:
		_c.draw_line(Vector2(c.x + sx * (r.size.x * 0.5 - 4), r.end.y - 2), top, dark, 5.0)
		_c.draw_line(Vector2(c.x + sx * (r.size.x * 0.5 - 4), r.end.y - 2), top, steel, 3.0)
	for k in [0.4, 0.7]:
		var y: float = lerpf(top.y, r.end.y - 2, k)
		var half: float = (r.size.x * 0.5 - 4) * k
		_c.draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), steel, 2.5)
	# Мотор и лампа (горит, когда есть энергия).
	_rbox(Rect2(c.x - 9, r.end.y - 16, 18, 13), 4, Color(0.88, 0.62, 0.16, alpha), Color(0.45, 0.3, 0.1, alpha), 2)
	_c.draw_circle(top + Vector2(0, 2), 3.5, Color(LAMP, alpha) if colony.powered() else Color(0.35, 0.35, 0.38, alpha))
	_draw_probe_rod(p, r, alpha)


## Штанга зонда: тянется на пройденные метры, кончик крутится.
func _draw_probe_rod(p: Project, r: Rect2, alpha: float) -> void:
	var c := r.get_center()
	if not colony.probing(p) or alpha < 1.0:
		return
	var d := Vector2(p.drill_dir)
	var start := c + d * r.size.x * 0.5
	var tip := start + d * TILE * p.probe_done
	_c.draw_line(start, tip, Color(0.2, 0.2, 0.24, 0.9), 5.0)
	_c.draw_line(start, tip, Color(0.75, 0.78, 0.84), 2.5)
	var a := Time.get_ticks_msec() * 0.012 if not p.paused and colony.powered() else 0.0
	var side := Vector2(-d.y, d.x) * 5.0
	_c.draw_line(tip - side.rotated(a), tip + side.rotated(a), Color(0.9, 0.9, 0.95), 2.5)


## Лифт: железные направляющие вдоль шахты, трос и кабина (у грузового — с ящиками).
const LIFT_STEEL := Color(0.55, 0.58, 0.64)
const LIFT_CAB := Color(0.86, 0.62, 0.22)


func _draw_lift(p: Project, r: Rect2) -> void:
	var dark := Color(0.2, 0.21, 0.24)
	var cab_col := Color(0.5, 0.56, 0.62) if p.cargo else LIFT_CAB
	var rail: Color = LIFT_STEEL if p.bonus() <= 1.0 else (MAT_BEAM[p.material] as Array)[0]
	if p.lift_vertical():
		var look := p.material if p.bonus() > 1.0 else "iron"
		for x in [r.position.x + 3, r.end.x - 3]:
			if _sprite_column("rail_" + look, x, r.position.y, r.end.y, 1.0):
				continue
			_c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), dark, 5.0)
			_c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), rail, 3.0)
		var y := r.end.y - TILE
		if p.lift_pos != Project.LIFT_UNSET:
			y = view.cell_to_local(Vector2i(0, 0)).y + p.lift_pos * TILE
		# Кабина — на высоту человека (2 м) над полом клетки, где стоит.
		var cab := Rect2(r.position.x + 5, y - TILE + 2, r.size.x - 10, TILE * 2 - 2)
		_c.draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, cab.position.y), Color(0.15, 0.15, 0.17), 2.0)
		_draw_cabin(cab, cab_col, p)
	else:
		_c.draw_line(Vector2(r.position.x, r.end.y - 3), Vector2(r.end.x, r.end.y - 3), rail, 4.0)
		_c.draw_line(Vector2(r.position.x, r.position.y + 4), Vector2(r.end.x, r.position.y + 4), rail, 3.0)
		var x0 := r.position.x
		if p.lift_pos != Project.LIFT_UNSET:
			x0 = view.cell_to_local(Vector2i(0, 0)).x + p.lift_pos * TILE
		var cab := Rect2(x0 - TILE * 0.5 + 2, r.end.y - TILE * 2 - 2, TILE * 2 - 4, TILE * 2)
		_draw_cabin(cab, cab_col, p)


func _draw_cabin(cab: Rect2, col: Color, p: Project) -> void:
	var tex := structure_texture("cab_cargo" if p.cargo else "cab_passenger")
	if tex != null:
		# Клетка-рендер на всю кабину (её рамка чуть выше — крюк троса).
		_c.draw_texture_rect(tex, Rect2(cab.position.x, cab.end.y - cab.size.y * 2.15 / 2.0, cab.size.x, cab.size.y * 2.15 / 2.0), false)
	else:
		_rbox(cab, 5, Color(col, 0.35), col.darkened(0.3), 3)
	if p.cargo and not p.lift_load.is_empty():
		var n := mini(4, 1 + int(colony._load_total(p.lift_load)) / 10)
		for i in n:
			var bx := cab.position.x + 4 + (i % 2) * (cab.size.x * 0.5 - 4)
			var by := cab.end.y - 12 - (i / 2) * 11
			_rbox(Rect2(bx, by, cab.size.x * 0.5 - 8, 10), 2, Color(0.65, 0.45, 0.25), Color(0.4, 0.27, 0.15), 1)
	# Лампочка: горит, когда лифт под током.
	_c.draw_circle(Vector2(cab.get_center().x, cab.position.y + 5), 3.0,
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
		_c.draw_rect(zr, Color(col, 0.13))
		_dashed_rect(zr, Color(col, 0.85), 3.0)
		return
	if p.purpose == RoomType.HEARTH or p.purpose in RoomType.GENERATORS:
		var zone := RoomType.heat_zone(p, colony.research.has("insulation"))
		var reach := _rect_px(p.rect.grow(zone.y))
		var full := _rect_px(p.rect.grow(zone.x))
		_c.draw_rect(reach, Color(1.0, 0.6, 0.2, 0.09))
		_dashed_rect(reach, Color(1.0, 0.6, 0.2, 0.6), 2.5)
		_c.draw_rect(full, Color(1.0, 0.45, 0.15, 0.12))
		_dashed_rect(full, Color(1.0, 0.5, 0.2, 0.9), 3.0)


func _draw_room_shell(p: Project, r: Rect2) -> void:
	var tex := room_texture("ship" if p.purpose == RoomType.SHIP else p.material, p.rect.size.x)
	if tex != null:
		_c.draw_texture_rect(tex, r, false)
	else:
		_draw_room_walls(p, r)
	# Лестница у стены, за которой снаружи порода или уступ: по ней выбираются наверх.
	if colony.edge_ladder(p, -1):
		_ladder(r.position.x + TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0, RoomType.furnish_material(p))
	if colony.edge_ladder(p, 1):
		_ladder(r.end.x - TILE * 0.5, r.position.y + 5, r.end.y - 6, 1.0, RoomType.furnish_material(p))


## Что мебель комнаты тянет к потолку (дымоходы, трубы, короба, арка телепорта) — отрезки по x
## (пиксели); и брусья под потолком (воздуховод, таль) — Rect2: x, ширина, низ (y). Собирается,
## пока рисуется мебель комнаты, — по нему лампы ищут свободное место.
var _ceil: Array[Vector2] = []
var _rails: Array[Rect2] = []
## Настенные предметы комнаты: x0, x1, верх (y) — лампа под брусом на них не садится.
var _wall_items: Array[Vector3] = []
var _room_top := -INF


## Лампочки — по одной на каждые 3 м; горят, когда в комнате включён свет. Рисуются после мебели:
## не на дымоходе или трубе в потолок, не на лестнице у стены; под воздуховодом или талью — висят
## под ними. У корабля свои светильники под потолком.
func _draw_room_lamps(p: Project, r: Rect2) -> void:
	if not colony.research.has("electricity") or not colony.is_underground(p) or p.purpose == RoomType.SHIP:
		return
	var n := RoomType.blocks(p)
	var ladders: Array[Vector2] = []
	if p.ladder or colony.edge_ladder(p, -1):
		ladders.append(Vector2(r.position.x, r.position.x + TILE * 0.8))
	if colony.edge_ladder(p, 1):
		ladders.append(Vector2(r.end.x - TILE * 0.8, r.end.x))
	var busy: Array[Vector2] = _ceil.duplicate()
	busy.append_array(ladders)
	# Места ламп зависят только от раскладки мебели — считаем раз на раскладку.
	var key := hash([r, n, busy, _rails, _wall_items])
	var spots: Array = _lamp_cache.get(p.id, [0, []])
	if spots[0] != key:
		spots = [key, _lamp_spots(r, n, busy)]
		_lamp_cache[p.id] = spots
	for spot in spots[1]:
		var lamp := Vector2(spot.x, spot.y + 5)
		_c.draw_line(lamp + Vector2(0, -5), lamp, Color(0.25, 0.25, 0.3), 2.0)
		if p.lit:
			_glow(lamp + Vector2(0, 6), r.size.y * 0.9, Color(1.0, 0.86, 0.45, 0.28))
			_c.draw_circle(lamp + Vector2(0, 4), 5, LAMP)
			_c.draw_circle(lamp + Vector2(-1.5, 2.5), 1.6, Color.WHITE)
		else:
			_c.draw_circle(lamp + Vector2(0, 4), 5, Color(0.35, 0.35, 0.38))


## Лампы: точки подвеса (x, верх шнура) — по одной на блок.
var _lamp_cache := {}
func _lamp_spots(r: Rect2, n: int, busy: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var blk := r.size.x / n
	var placed: Array[float] = []
	for i in n:
		# Лучше — посередине блока (лампы ровно через 3 м); занято — ближайшее свободное место в
		# комнате, не ближе 0,8 м к соседней лампе. Сначала — где ничего нет, потом — хоть перед
		# настенным предметом; совсем негде (тесный склад с талью) — без лампы.
		var mid := r.position.x + blk * (i + 0.5)
		var lx := NAN
		var hang := r.position.y + 5
		for strict in [true, false]:
			var best := INF
			var x := r.position.x + 8.0
			while x <= r.end.x - 8.0:
				var near := false
				for q in placed:
					if absf(q - x) < TILE * 0.8:
						near = true
				var d := absf(x - mid)
				if not near and d < best:
					var y := _lamp_hang(r, x)
					if _lamp_free(x, y, busy, strict):
						best = d
						lx = x
						hang = y
				x += 3.0
			if not is_nan(lx):
				break
		if is_nan(lx):
			continue
		placed.append(lx)
		out.append(Vector2(lx, hang))
	return out


## Откуда свисает лампа в точке x: с потолка или из-под бруса (воздуховод, таль).
func _lamp_hang(r: Rect2, x: float) -> float:
	var hang := r.position.y + 5
	for rail in _rails:
		if x >= rail.position.x and x <= rail.position.x + rail.size.x:
			hang = maxf(hang, rail.size.y)
	return hang


## Лампа (шнур от hang, шар радиусом 5 под ним) в x не задевает занятое и настенные предметы.
func _lamp_free(x: float, hang: float, busy: Array[Vector2], walls := true) -> bool:
	for b in busy:
		if x + 7 > b.x and x - 7 < b.y:
			return false
	if not walls:
		return true
	for w in _wall_items:
		if x + 7 > w.x and x - 7 < w.y and hang + 16 > w.z:
			return false
	return true


## Готовая картинка комнаты (рендер из Blender, assets/rooms/) или null — тогда рисуем сами.
static var _room_tex := {}
static func room_texture(material: String, w: int) -> Texture2D:
	var key := "%s_%d" % [material, w]
	if not _room_tex.has(key):
		var path := "res://assets/rooms/%s.png" % key
		_room_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _room_tex[key]


## Постройки-рендеры из Blender (art_src/structures/build_structures.py → assets/structures/):
## имя → рамка спрайта (x0, x1, z0, z1) в метрах вокруг опорной точки (x — вправо, z — вверх).
const STRUCT_FRAMES := {
	"rocket_chem": [-2.5, 2.5, -0.1, 14.3], "rocket_nuclear": [-2.6, 2.6, -0.1, 14.6],
	"launch_tower": [-2.0, 0.8, -0.1, 15.1], "ship_hull": [-2.6, 11.7, -0.3, 4.4],
	"teleport": [-1.5, 1.5, -0.05, 2.95], "drill": [0.0, 3.0, 0.0, 3.0], "drill_diamond": [0.0, 3.0, 0.0, 3.0],
	"probe": [-1.0, 1.0, 0.0, 2.0], "cab_passenger": [-1.0, 1.0, 0.0, 2.15], "cab_cargo": [-1.5, 1.5, 0.0, 2.15],
}
## Рамы, лестницы и направляющие — по материалу (support_wood, ladder_gold…): рамка по виду.
const PART_FRAMES := {"support": [-0.5, 0.5, 0.0, 1.0], "slice": [-0.5, 0.5, 0.0, 3.0], "ladder": [-0.5, 0.5, 0.0, 1.0],
	"rail": [-0.15, 0.15, 0.0, 1.0], "foundation": [-0.5, 0.5, 0.0, 1.0]}
static var _struct_tex := {}
static func structure_texture(name: String) -> Texture2D:
	if not _struct_tex.has(name):
		var path := "res://assets/structures/%s.png" % name
		_struct_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _struct_tex[name]


## Нарисовать постройку-рендер с опорной точкой at (пиксели слоя). built — какая доля снизу
## видна (сборка ракеты); false — картинки нет, рисуйте кодом.
func _sprite(name: String, at: Vector2, alpha: float, built := 1.0, scale := 1.0) -> bool:
	var tex := structure_texture(name)
	if tex == null:
		return false
	var f: Array = STRUCT_FRAMES[name] if STRUCT_FRAMES.has(name) else PART_FRAMES[name.get_slice("_", 0)]
	var size := Vector2(float(f[1]) - float(f[0]), float(f[3]) - float(f[2])) * TILE * scale
	var rect := Rect2(at + Vector2(float(f[0]), -float(f[3])) * TILE * scale, size)
	if built >= 1.0:
		_c.draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))
		return true
	var ts := tex.get_size()
	var k := clampf(built, 0.0, 1.0)
	_c.draw_texture_rect_region(tex, Rect2(rect.position + Vector2(0, size.y * (1.0 - k)), Vector2(size.x, size.y * k)),
		Rect2(0, ts.y * (1.0 - k), ts.x, ts.y * k), Color(1, 1, 1, alpha))
	return true


## Звенья (лестница, направляющая) картинки name по вертикали от top до bottom с центром cx.
func _sprite_column(name: String, cx: float, top: float, bottom: float, alpha: float) -> bool:
	var tex := structure_texture(name)
	if tex == null:
		return false
	var f: Array = PART_FRAMES[name.get_slice("_", 0)]
	var w := (float(f[1]) - float(f[0])) * TILE
	var ts := tex.get_size()
	var y := top
	while y < bottom - 0.5:
		var h := minf(TILE, bottom - y)
		_c.draw_texture_rect_region(tex, Rect2(cx - w * 0.5, y, w, h), Rect2(0, ts.y * (1.0 - h / TILE), ts.x, ts.y * h / TILE),
			Color(1, 1, 1, alpha))
		y += TILE
	return true


## Картинка в повёрнутом прямоугольнике: углы по часовой с левого верхнего картинки.
func _sprite_quad(tex: Texture2D, corners: PackedVector2Array, alpha: float) -> void:
	_c.draw_colored_polygon(corners, Color(1, 1, 1, alpha),
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), tex)


## Стены, пол и рама, нарисованные кодом (для материалов без готовой картинки).
func _draw_room_walls(p: Project, r: Rect2) -> void:
	var c: Array = WALLS.get(p.material, WALLS["wood"])
	var wall: Color = c[0]
	_c.draw_rect(r, wall)
	match p.material:
		"wood":
			# Доски — полосы чуть разного тона.
			var y := r.position.y
			var i := 0
			while y < r.end.y:
				var h := minf(12.0, r.end.y - y)
				_c.draw_rect(Rect2(r.position.x, y, r.size.x, h), wall if i % 2 == 0 else c[2])
				_c.draw_line(Vector2(r.position.x, y + h - 1), Vector2(r.end.x, y + h - 1), Color(c[1], 0.35), 1.0)
				y += 12
				i += 1
		"silver", "gold":
			# Полированные листы: панели с бликом наискосок и заклёпками.
			var x := r.position.x + 5
			while x < r.end.x - 5:
				_c.draw_line(Vector2(x, r.position.y + 5), Vector2(x, r.end.y - 6), c[1], 2.0)
				var w := minf(24.0, r.end.x - 5 - x)
				_c.draw_colored_polygon(PackedVector2Array([Vector2(x + w * 0.35, r.position.y + 6), Vector2(x + w * 0.6, r.position.y + 6),
					Vector2(x + w * 0.3, r.end.y - 7), Vector2(x + w * 0.05, r.end.y - 7)]), Color(c[2], 0.5))
				_c.draw_circle(Vector2(x + 5, r.position.y + 12), 1.8, c[1])
				_c.draw_circle(Vector2(x + 5, r.end.y - 14), 1.8, c[1])
				x += 24
		"diamond":
			# Грани кристалла: ромбы с бликом.
			var dy := r.position.y + 6
			var row := 0
			while dy < r.end.y - 14:
				var dx := r.position.x + 6 + (10.0 if row % 2 else 0.0)
				while dx < r.end.x - 20:
					var m := Vector2(dx + 10, dy + 8)
					_c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -8), m + Vector2(10, 0), m + Vector2(0, 8), m + Vector2(-10, 0)]), c[2] if (row + int(dx)) % 3 == 0 else c[0].lightened(0.1))
					_c.draw_line(m + Vector2(0, -8), m + Vector2(10, 0), Color(c[1], 0.6), 1.0)
					dx += 20
				dy += 16
				row += 1
		"iron":
			# Железные панели с заклёпками.
			var x := r.position.x + 5
			while x < r.end.x - 5:
				_c.draw_line(Vector2(x, r.position.y + 5), Vector2(x, r.end.y - 6), c[2], 2.0)
				_c.draw_circle(Vector2(x + 5, r.position.y + 12), 1.8, c[1])
				_c.draw_circle(Vector2(x + 5, r.end.y - 14), 1.8, c[1])
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
						_c.draw_rect(Rect2(bx + 1, y + 1, bwid - 2, h - 2), wall.lightened(tone) if p.material == "stone" else wall.darkened(tone))
						_c.draw_line(Vector2(bx + 2, y + 2), Vector2(bx + bwid - 3, y + 2), Color(1, 1, 1, 0.22), 1.5)
					x += bw
				y += bh
				row += 1
			# Швы.
			y = r.position.y + 5
			while y < r.end.y - 6:
				_c.draw_line(Vector2(r.position.x + 5, y), Vector2(r.end.x - 5, y), Color(c[2], 0.8), 1.5)
				y += bh
	# Тень под потолком.
	_c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 16), Vector2(r.position.x, r.position.y + 16)]),
		PackedColorArray([Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	# Пол — доски с бликом.
	_c.draw_rect(Rect2(r.position.x, r.end.y - 7, r.size.x, 7), ROOM_FLOOR)
	_c.draw_line(Vector2(r.position.x, r.end.y - 6), Vector2(r.end.x, r.end.y - 6), ROOM_FLOOR.lightened(0.25), 1.5)
	# Рама тоном стены, со скруглёнными углами.
	_rbox(r, 6, Color(0, 0, 0, 0), c[1], 5)



## Полка у задней стены: доска с бликом сверху, тенью снизу и кронштейнами.
func _shelf(x0: float, x1: float, y: float, alpha: float) -> void:
	var wood := Color(BED_FRAME.lightened(0.1), alpha)
	_c.draw_rect(Rect2(x0, y + 3, x1 - x0, 4), Color(0, 0, 0, 0.18 * alpha))
	_rbox(Rect2(x0, y - 1, x1 - x0, 4), 1, wood, Color(BED_FRAME.darkened(0.35), alpha), 1)
	_c.draw_line(Vector2(x0 + 2, y - 0.5), Vector2(x1 - 2, y - 0.5), Color(1, 1, 1, 0.25 * alpha), 1.0)
	var n := maxi(2, int((x1 - x0) / (TILE * 2.0)) + 1)
	for i in n:
		var bx := lerpf(x0 + 6, x1 - 6, float(i) / (n - 1))
		_c.draw_colored_polygon(PackedVector2Array([Vector2(bx - 1.5, y + 3), Vector2(bx + 1.5, y + 3), Vector2(bx + 1.5, y + 9), Vector2(bx - 1.5, y + 5)]),
			Color(BED_FRAME.darkened(0.25), alpha))


## Мягкое световое пятно: веер треугольников от яркого центра к прозрачному краю.
func _glow(c: Vector2, rad: float, col: Color) -> void:
	var edge := Color(col, 0.0)
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_c.draw_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad]),
			PackedColorArray([col, edge, edge]))


## Прямоугольник со скруглением (мебель, плашки).
func _rbox(r: Rect2, rad: int, col: Color, border := Color(0, 0, 0, 0), bw := 0) -> void:
	# Многоугольником, а не StyleBoxFlat: без нового объекта на каждую плашку, и собирается в
	# общую сетку слоя.
	if col.a > 0.0:
		_c.draw_colored_polygon(_round_poly(r, rad), col)
	if bw > 0 and border.a > 0.0:
		var pts := _round_poly(r.grow(-bw * 0.5), maxf(0.0, rad - bw * 0.5))
		pts.append(pts[0])
		_c.draw_polyline(pts, border, bw)


## Скруглённый прямоугольник: по четыре отрезка на угол.
static func _round_poly(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	if rad <= 0.5:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cs := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for k in 4:
		var a0 := -PI * 0.5 + k * PI * 0.5
		for j in 5:
			var a := a0 + PI * 0.5 * j / 4.0
			pts.append(cs[k] + Vector2(cos(a), sin(a)) * rad)
	return pts


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
	_c.draw_circle(c, fs * 0.55, Color(0.98, 0.72, 0.25, 0.35 * pulse))
	var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := c + Vector2(-w * 0.5, fs * 0.36)
	_c.draw_string_outline(font, p, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.25, 0.15, 0.05, 0.9))
	_c.draw_string(font, p, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.3))


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
	# Ресурсу без своей картинки ящика (нефть, уран…) — не рисуем (раньше рисование падало).
	if t == null:
		return
	var sz := t.get_size() / FURN_PX_PER_M * TILE * scale
	var rect := Rect2(cx - sz.x * 0.5, bottom - sz.y, sz.x, sz.y)
	if shadow == 1:
		_soft_ellipse(Vector2(cx, bottom - 1.0), sz.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	elif shadow == 2:
		_c.draw_texture_rect(t, Rect2(rect.position + Vector2(1.5, 2.5), rect.size), false, Color(0, 0, 0, 0.22 * alpha))
	_c.draw_texture_rect(t, rect, false, Color(1, 1, 1, alpha))


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
		_c.draw_polygon(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), PackedColorArray([cols[0], cols[i + 1], cols[i + 2]]))


## Стойки на задней стене комнаты-картинки (art_src/rooms/build_rooms.py: через 3 м и в углах),
## в метрах от левого края комнаты, с учётом сужения к задней стене. Полки на них не вешаем.
static func wall_posts(w: int) -> Array[float]:
	var out: Array[float] = [0.6, w - 0.6]
	for x in range(3, w, 3):
		out.append(0.5 + (x - 0.2) * (w - 1.0) / (w - 0.4))
	return out


## Что мешает вешать на стену этой комнаты: стойки и лестницы у стен (лестница ~0.5 м у края —
## три «стойки» подряд закрывают её целиком). По возрастанию.
func _wall_posts(p: Project) -> Array[float]:
	var w := p.rect.size.x
	var out := wall_posts(w)
	if colony != null and (p.ladder or colony.edge_ladder(p, -1)):
		out.append_array([0.3, 0.5, 0.7])
	if colony != null and colony.edge_ladder(p, 1):
		out.append_array([w - 0.7, w - 0.5, w - 0.3])
	out.sort()
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
	var posts := _wall_posts(p)
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
## Машины и столы (блоки по 3 м) стоят от стены до стены одинаково, есть у левой стены лестница
## или нет (её полметра у стены они и так перекрывают) — иначе в малой комнате с лестницей им
## оставалось полтора метра и всё мельчало.
func _inside(p: Project, r: Rect2, units: float, machines := false) -> Dictionary:
	var lo := r.position.x + TILE * (1.1 if p.ladder and not machines else RACK_INSET)
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
	var hw := t.get_width() / FURN_PX_PER_M * TILE * scale * 0.5
	_wall_items.append(Vector3(cx - hw, cx + hw, top))
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
	var sorted := posts.duplicate()
	sorted.sort()
	for pst in sorted:
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


## Настенный предмет шириной w (px) около x (px): ближайшее место, где он не на стойке и не на
## лестнице (не дальше метра); нет такого — где был.
## extra — ещё занятые места (м от левого края), strict — нет места: NAN, а не «где был».
func _wall_x(p: Project, r: Rect2, x: float, w: float, extra: Array[float] = [], strict := false) -> float:
	var m := (x - r.position.x) / TILE
	var posts := _wall_posts(p)
	posts.append_array(extra)
	var dx := _decor_x(maxf(0.1, m - 1.0), minf(p.rect.size.x - 0.1, m + 1.0), w / TILE, posts)
	if is_nan(dx):
		return NAN if strict else x
	return r.position.x + dx * TILE


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
		_c.draw_texture_rect(t, Rect2(cx - hs.x * 0.5, top + 47 * k, hs.x, hs.y), false, Color(1, 1, 1, alpha))


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
		_c.draw_texture_rect_region(m, Rect2(x, top, seg, m.get_height() * k), Rect2(0, 0, seg / k, m.get_height()), mod)
		x += seg
	_c.draw_texture_rect(l, Rect2(left, top, l.get_width() * k, l.get_height() * k), false, mod)
	_c.draw_texture_rect(rt, Rect2(end, top, rt.get_width() * k, rt.get_height() * k), false, mod)


## Ферма: грядка на каждые 2 м, на ней грибы трёх стадий роста (в холоде — блёклые); с
## электричеством над грибами лампы роста на стене — горят, когда есть энергия. Выше на стене — по предмету
## над грядкой, без повторов и не на стойках.
const FARM_DECOR := ["tools", "can", "gauge", "hose"]
func _draw_farm_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.farm_slots(p)
	var lay := _inside(p, r, n * 2.0)
	var posts := _wall_posts(p)
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
			_c.draw_texture_rect(lamp, Rect2(cx - lsz.x * 0.5, fy - TILE * 0.9 * sc - lsz.y, lsz.x, lsz.y), false, Color(1, 1, 1, alpha))
		var sz := shoots.get_size() * k
		_c.draw_texture_rect(shoots, Rect2(cx - sz.x * 0.5, fy - (bed.get_height() - 7) * k - sz.y, sz.x, sz.y), false, tint)
		_furn_at(bed, cx, fy, alpha, 1, sc)


## Очаг: печь на каждые 3 м (каменная, кирпичная; с газом — отопительный котёл вместо печи),
## горит, когда топится; от печи труба в потолок, рядом её топливо (дрова, у кирпичной — уголь).
## Котлы соединены трубами отопления с вентилями. На стене между печами — кочерга и совок.
## Движущиеся детали комнат (art_src/rooms/cut_anim.py → assets/furniture/anim/): ось (pivot),
## верх под трубу (top, x) и топка (mouth) — в пикселях картинки (128 px на метр). Печи и топки
## пустые и прозрачные внутри: за ними — тёмная глубина и живое пламя; колёса, лопасти и стрелки
## крутятся вокруг своей оси.
const ANIM := {
	"pump_body": {"pivot": Vector2(112.0, 95.1), "top": 87.5},
	"pump_wheel": {"pivot": Vector2(37.0, 37.5), "top": 37.5},
	"flame_orange": {"pivot": Vector2(130.0, 138.5), "top": 116.8},
	"flame_blue": {"pivot": Vector2(130.0, 136.0), "top": 113.5},
	"gas_body": {"pivot": Vector2(119.6, 46.1), "top": 55.0, "mouth": Rect2(38.7, 38.7, 32.9, 29.3)},
	"gas_dynamo": {"pivot": Vector2(40.5, 43.5), "top": 40.6},
	"gas_flywheel": {"pivot": Vector2(52.0, 53.5), "top": 52.2},
	"gas_pulley": {"pivot": Vector2(21.5, 21.5), "top": 21.1},
	"gas_belt": {"pivot": Vector2(65.0, 6.0), "top": 64.6},
	"gauge_dial": {"pivot": Vector2(22.7, 23.3), "top": 22.2},
	"gauge_needle": {"pivot": Vector2(2.3, 10.5), "top": 8.3},
	"vent_housing": {"pivot": Vector2(79.6, 77.0), "top": 79.9},
	"vent_blades": {"pivot": Vector2(65.0, 66.0), "top": 65.2},
	"coal_body": {"pivot": Vector2(92.9, 107.1), "top": 42.6, "mouth": Rect2(25.0, 81.5, 36.3, 32.8)},
	"coal_dynamo": {"pivot": Vector2(46.0, 43.5), "top": 53.2},
	"coal_flywheel": {"pivot": Vector2(52.0, 53.5), "top": 52.0},
	"coal_pulley": {"pivot": Vector2(21.5, 21.5), "top": 21.0},
	"coal_belt": {"pivot": Vector2(65.0, 6.0), "top": 64.5},
	"stove_stone": {"pivot": Vector2(65.5, 64.5), "top": 65.3, "mouth": Rect2(31.9, 39.1, 66.7, 54.1)},
	"stove_brick": {"pivot": Vector2(65.5, 64.0), "top": 65.1, "mouth": Rect2(33.0, 39.4, 65.2, 52.1)},
	"stove_kiln": {"pivot": Vector2(78.5, 90.0), "top": 78.4, "mouth": Rect2(51.9, 124.5, 52.7, 35.7)},
	"stove_forge": {"pivot": Vector2(91.0, 71.0), "top": 119.2, "mouth": Rect2(93.8, 69.0, 50.9, 36.0)},
	"stove_boiler": {"pivot": Vector2(62.5, 95.0), "top": 60.8, "mouth": Rect2(34.7, 109.4, 54.3, 47.8)},
}


func _anim(name: String) -> Texture2D:
	return furniture("anim", name)


## Время для анимации мебели, с.
static func _anim_t() -> float:
	return Time.get_ticks_msec() / 1000.0


## Деталь name, повёрнутая на angle вокруг своей оси; ось — в точке at, масштаб sc (1 — 128 px/м).
func _spin(name: String, at: Vector2, angle: float, sc: float, alpha: float) -> void:
	var t := _anim(name)
	var k := TILE / FURN_PX_PER_M * sc
	_xform(at, angle, Vector2(k, k))
	_c.draw_texture(t, -(ANIM[name]["pivot"] as Vector2), Color(1, 1, 1, alpha))
	_xform(Vector2.ZERO, 0.0, Vector2.ONE)


## Прямоугольник детали name, стоящей низом на bottom по центру cx (как _furn_at).
func _anim_rect(name: String, cx: float, bottom: float, sc: float) -> Rect2:
	var sz := _anim(name).get_size() / FURN_PX_PER_M * TILE * sc
	return Rect2(cx - sz.x * 0.5, bottom - sz.y, sz.x, sz.y)


## Точка картинки детали (пиксели картинки) на экране, если деталь в прямоугольнике rect.
func _anim_at(name: String, rect: Rect2, px: Vector2) -> Vector2:
	return rect.position + px * rect.size.x / _anim(name).get_width()


## Живое пламя: картинка огня на сетке, которую каждый кадр колышет (языки качаются волной снизу
## вверх, пламя то вытягивается, то приседает) — плавно, без кадров. base — середина низа, w —
## ширина (пиксели), seed — чтобы соседние огни горели вразнобой.
const FLAME_COLS := 4
const FLAME_ROWS := 6
func _flame(gas: bool, base: Vector2, w: float, seed: float, alpha: float) -> void:
	var t := _anim("flame_blue" if gas else "flame_orange")
	if t == null:
		return
	var tt := _anim_t() + seed * 3.7
	var stretch := 1.0 + 0.14 * sin(tt * 8.3) + 0.08 * sin(tt * 21.0 + 1.3)
	var h := w * t.get_height() / t.get_width() * stretch
	var pts := []
	for j in FLAME_ROWS + 1:
		var v := float(j) / FLAME_ROWS     # 0 — верх, 1 — низ
		var up := 1.0 - v
		var row := []
		for i in FLAME_COLS + 1:
			var u := float(i) / FLAME_COLS
			var sway := w * (0.11 * sin(tt * 6.0 - v * 4.0) + 0.05 * sin(tt * 13.0 + u * 3.0 - v * 6.0)) * up * up
			var pinch := 1.0 + 0.06 * sin(tt * 9.0 + v * 5.0) * up
			row.append(Vector2(base.x + (u - 0.5) * w * pinch + sway, base.y - h * up))
		pts.append(row)
	var col := Color(1, 1, 1, alpha)
	for j in FLAME_ROWS:
		for i in FLAME_COLS:
			var u0 := float(i) / FLAME_COLS
			var u1 := float(i + 1) / FLAME_COLS
			var v0 := float(j) / FLAME_ROWS
			var v1 := float(j + 1) / FLAME_ROWS
			_c.draw_colored_polygon(PackedVector2Array([pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]), col,
				PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]), t)


## Печь или топка name (пустая внутри): низом на bottom по центру cx, масштаб sc. Горит — за
## прозрачной топкой тёмная глубина, пламя и отсвет. Возвращает прямоугольник печи.
func _stove(name: String, cx: float, bottom: float, sc: float, burning: bool, gas: bool, alpha: float, seed := 0.0) -> Rect2:
	var rect := _anim_rect(name, cx, bottom, sc)
	var m: Rect2 = ANIM[name]["mouth"]
	var kk := rect.size.x / _anim(name).get_width()
	var mouth := Rect2(rect.position + m.position * kk, m.size * kk)
	_c.draw_rect(mouth.grow(-1.0), Color(0.09, 0.05, 0.04, alpha))
	if burning:
		var flick := 0.85 + 0.15 * sin(_anim_t() * 7.0 + seed * 5.0)
		_glow(mouth.get_center() + Vector2(0, mouth.size.y * 0.2), mouth.size.x * 1.3,
			Color(0.3, 0.55, 1.0, 0.35 * flick * alpha) if gas else Color(1.0, 0.55, 0.2, 0.4 * flick * alpha))
		_flame(gas, Vector2(mouth.get_center().x, mouth.end.y - mouth.size.y * 0.04), mouth.size.x * 0.85, seed, alpha)
	_soft_ellipse(Vector2(cx, bottom - 1.0), rect.size.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	_c.draw_texture_rect(_anim(name), rect, false, Color(1, 1, 1, alpha))
	return rect


## Патрубки газового котла (stove_boiler): высота верхнего и нижнего — доля высоты спрайта сверху.
const BOILER_PORTS := [0.39, 0.59]
func _draw_hearth_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.stoves(p)
	var lay := _inside(p, r, n * 3.0, true)
	var done := p.phase == Project.Phase.DONE
	var gas := p.gas_boiler and done
	var kind := "gas" if gas else ("brick" if p.brick_stoves and done else "stone")
	var stove := furniture("hearth", kind + ("_on" if p.burning else "_off"))
	# Новые печи — пустые внутри, огонь живой (см. _stove).
	var live_name: String = "stove_" + {"gas": "boiler", "brick": "brick", "stone": "stone"}[kind]
	var live := _anim(live_name) != null
	if live:
		stove = _anim(live_name)
	var fuel := null if gas else furniture("hearth", "coal" if kind == "brick" else "logs")
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var xs: Array[float] = []
	for i in n:
		xs.append(lay.x + (i * 3 + 1.5) * lay.unit - (TILE * 0.35 if fuel != null else 0.0))
	var sh := stove.get_height() * k
	if gas:
		# Трубы отопления — за котлами, от первого котла в правую стену, на уровне патрубков
		# котла (доли его высоты сверху: верхний и нижний патрубок).
		var right: float = r.end.x - TILE * 0.15
		for pipe in [["pipe_red", BOILER_PORTS[0]], ["pipe_blue", BOILER_PORTS[1]]]:
			var t := furniture("hearth", pipe[0])
			_tile_h(t, xs[0], right, fy - sh * (1.0 - pipe[1]) - t.get_height() * k * 0.5, alpha)
		var valve := furniture("hearth", "valve")
		for i in n:
			var vx: float = (xs[i] + xs[i + 1]) * 0.5 if i + 1 < n else (xs[i] + right) * 0.5 + TILE * 0.2
			var vs := valve.get_size() * k
			_c.draw_texture_rect(valve, Rect2(vx - vs.x * 0.5, fy - sh * (1.0 - BOILER_PORTS[0]) - vs.y * 0.5, vs.x, vs.y), false, mod)
	var chimney := furniture("hearth", "chimney")
	if not gas:
		_tools_between(p, r, lay, xs, furniture("hearth", "tools"), fy, alpha)
	for i in n:
		var cw := chimney.get_width() * k
		_tile_v(chimney, xs[i] - cw * 0.5, fy - TILE * 2.62, fy - sh + 4 * k, alpha)
		if p.burning and alpha >= 1.0:
			_glow(Vector2(xs[i], fy - sh * 0.4), TILE * 2.2, Color(0.3, 0.55, 1.0, 0.18) if gas else Color(1.0, 0.6, 0.25, 0.22))
		if live:
			_stove(live_name, xs[i], fy, 1.0, p.burning and alpha >= 1.0, p.on_gas, alpha, i + p.id * 0.37)
		else:
			_furn_at(stove, xs[i], fy, alpha, 1)
		if fuel != null:
			_furn_at(fuel, xs[i] + stove.get_width() * k * 0.5 + fuel.get_width() * k * 0.5 + TILE * 0.05, fy, alpha, 1)



## Инструменты на стене между печами (по одним на промежуток); у единственной печи — где есть
## место, мимо стоек и трубы.
func _tools_between(p: Project, r: Rect2, lay: Dictionary, xs: Array[float], tools: Texture2D, fy: float, alpha: float) -> void:
	var posts := _wall_posts(p)
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


## Ширина блока обычной комнаты (6 м, м): по ней — размер машин во всех комнатах.
const BLOCK_REF := 2.65
## Ряд предметов блока одного размера в комнате любой ширины: масштаб — как в блоке обычной
## комнаты; в узком блоке (малая комната) сначала убираем необязательные (opt — их номера по
## порядку), и только если и так не влезает — мельче. Возвращает [масштаб, оставленные (null —
## убран)].
func _row_fit(items: Array, opt: Array, width: float) -> Array:
	var sc := _group_fit(items, TILE * BLOCK_REF)
	var kept := items.duplicate()
	for i in opt:
		if _row_w(kept) * sc <= width:
			break
		kept[i] = null
	sc = minf(sc, width / _row_w(kept))
	return [sc, kept]


## Ширина ряда (px при обычном размере): предметы и зазоры по 0,1 м; null — пропуск.
func _row_w(items: Array) -> float:
	var w := 0.0
	for t in items:
		if t != null:
			w += t.get_width() / FURN_PX_PER_M * TILE + TILE * 0.1
	return w


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
	var lay := _inside(p, r, n * 3.0, true)
	var on := _crafting(p)
	var kiln := furniture("kiln", "kiln_on" if on else "kiln_off")
	var live := _anim("stove_kiln") != null
	if live:
		kiln = _anim("stove_kiln")
	var chimney := furniture("hearth", "chimney")
	var clay := furniture("kiln", "clay")
	var bricks := furniture("kiln", "bricks")
	# Глина, печь и кирпичи в ряд — печь одного размера в любой обжиговой; в малой нет глины.
	var fit := _row_fit([clay, kiln, bricks], [0], lay.unit * 3)
	var sc: float = fit[0]
	if fit[1][0] == null:
		clay = null
	var k := TILE / FURN_PX_PER_M * sc
	var xs := _block_centers(lay, n, 0.0)
	var kw := kiln.get_width() * k
	var cw := clay.get_width() * k + TILE * 0.03 if clay != null else 0.0
	var shift := (cw - bricks.get_width() * k - TILE * 0.03) * 0.5
	for j in xs.size():
		xs[j] += shift
	_tools_between(p, r, lay, xs, furniture("kiln", "tools"), fy, alpha)
	for x in xs:
		_tile_v(chimney, x - chimney.get_width() * k * 0.5, fy - TILE * CEILING, fy - kiln.get_height() * k + 4 * k, alpha)
		if on and alpha >= 1.0:
			_glow(Vector2(x, fy - TILE * 0.3), TILE * 2.0, Color(1.0, 0.6, 0.25, 0.22))
		if live:
			_stove("stove_kiln", x, fy, sc, on and alpha >= 1.0, false, alpha, x * 0.013)
		else:
			_furn_at(kiln, x, fy, alpha, 1, sc)
		if clay != null:
			_furn_at(clay, x - kw * 0.5 - clay.get_width() * k * 0.5 - TILE * 0.03, fy, alpha, 1, sc)
		_furn_at(bricks, x + kw * 0.5 + bricks.get_width() * k * 0.5 + TILE * 0.03, fy, alpha, 1, sc)


## Генераторная: генератор на каждые 3 м — на угле и дровах (топка, маховик, динамо, рядом уголь,
## труба в потолок) или на метане (синий двигатель, газовая труба с вентилем с потолка). Что
## комната даёт ток, видно сразу: от динамо провода к гирлянде лампочек под потолком и щитку —
## всё горит, когда генератор работает.
func _draw_generator_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	# Дизельный — пока как газовый (двигатель с топливной трубой, без угля), своей картинки нет.
	var gas := p.purpose == RoomType.GAS_GEN or p.purpose == RoomType.DIESEL_GEN
	var on := p.burning
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var machine := furniture("generator", ("gas" if gas else "coal") + ("_on" if on else "_off"))
	var coal := furniture("hearth", "coal")
	# Генератор одного размера в любой генераторной; в малой — без кучи угля рядом.
	var fit := _row_fit([machine] if gas else [coal, machine], [] if gas else [0], lay.unit * 3)
	var sc: float = fit[0]
	if gas or fit[1][0] == null:
		coal = null
	var mw := machine.get_width() * k * sc
	var mh := machine.get_height() * k * sc
	var xs := _block_centers(lay, n, 0.0 if coal == null else coal.get_width() / FURN_PX_PER_M * sc * 0.5)
	# Гирлянда под потолком от левого края до щитка справа.
	var panel := furniture("generator", "panel_on" if on else "panel_off")
	var ps := panel.get_size() * k
	var line_y := fy - TILE * 2.25
	var right: float = lay.x + n * 3 * lay.unit
	_tile_h(furniture("generator", "bulbs_on" if on else "bulbs_off"), lay.x + TILE * 0.1, right - ps.x, line_y, alpha)
	_c.draw_texture_rect(panel, Rect2(right - ps.x, line_y - ps.y * 0.3, ps.x, ps.y), false, mod)
	_ceil.append(Vector2(right - ps.x, right))
	var cable := Color(0.12, 0.12, 0.14, alpha)
	var chimney := furniture("hearth", "chimney")
	var pipe := furniture("generator", "gas_pipe")
	var valve := furniture("generator", "valve")
	var live := _anim("coal_body") != null
	var diesel := p.purpose == RoomType.DIESEL_GEN and furniture("diesel", "engine") != null
	for x in xs:
		var top := fy - mh
		# Провод от динамо (справа) вверх к гирлянде.
		var dx := x + mw * 0.36
		var gx := x + (0.17 - 0.5) * mw
		var cx := x + (0.145 - 0.5) * mw
		var unit := {}
		if diesel:
			unit = _diesel_unit(x, fy, lay.unit * 3, on and alpha >= 1.0, alpha, x * 0.017)
			dx = unit["dynamo"].x
			top = unit["top"]
			gx = unit["inlet"]
			# Выхлоп — к потолку от фланца коллектора, толщиной с фланец (0.13 м).
			var es: float = 0.13 / (chimney.get_width() / FURN_PX_PER_M) * unit["scale"]
			_tile_v(chimney, gx - chimney.get_width() * k * es * 0.5, fy - TILE * CEILING, unit["inlet_y"], alpha, es)
			_c.draw_line(unit["dynamo"], Vector2(dx, line_y + 4 * k), cable, maxf(2.0, 4 * k))
			_diesel_unit(x, fy, lay.unit * 3, on and alpha >= 1.0, alpha, x * 0.017, true)
			continue
		if live:
			unit = _gen_unit(gas, x, fy, mw, on and alpha >= 1.0, alpha, x * 0.017)
			dx = unit["dynamo"].x
			top = unit["top"]
			gx = unit["inlet"]
			cx = unit["inlet"]
		_c.draw_line(Vector2(dx, (unit["dynamo"].y if live else top + 6 * k)), Vector2(dx, line_y + 4 * k), cable, maxf(2.0, 4 * k))
		# Труба — толщиной по патрубку двигателя (в узкой комнате двигатель меньше — и она тоньше).
		var us: float = unit.get("scale", 1.0)
		if gas:
			_tile_v(pipe, gx - pipe.get_width() * k * us * 0.5, fy - TILE * CEILING, top + 8 * k * us, alpha, us)
			var vs := valve.get_size() * k * us
			_c.draw_texture_rect(valve, Rect2(gx - vs.x * 0.5, (fy - TILE * CEILING + top) * 0.5 - vs.y * 0.5, vs.x, vs.y), false, mod)
		else:
			var cs := us * (0.13 / (chimney.get_width() / FURN_PX_PER_M) if live else 1.0)
			_tile_v(chimney, cx - chimney.get_width() * k * cs * 0.5, fy - TILE * CEILING, top + 4 * k * us, alpha, cs)
			if coal != null:
				_furn_at(coal, x - mw * 0.5 - coal.get_width() * k * sc * 0.5, fy, alpha, 1, sc)
		if on and alpha >= 1.0:
			_glow(Vector2(x, fy - mh * 0.5), TILE * 2.0, Color(0.3, 0.55, 1.0, 0.16) if gas else Color(1.0, 0.75, 0.3, 0.18))
		if live:
			_gen_unit(gas, x, fy, mw, on and alpha >= 1.0, alpha, x * 0.017, true)
		else:
			_furn_at(machine, x, fy, alpha, 1, sc)


## Дизельный генератор шириной width по центру x: канистра, зелёный дизель (дрожит, пока
## работает), маховик на его конце (крутится), вал к синему генератору. draw = false — только
## места: верх (top), выхлоп (inlet, inlet_y) и верх генератора (dynamo).
func _diesel_unit(x: float, fy: float, width: float, on: bool, alpha: float, seed: float, draw := false) -> Dictionary:
	var k := TILE / FURN_PX_PER_M
	var can := furniture("diesel", "canister")
	var eng := furniture("diesel", "engine")
	var gen := furniture("diesel", "generator")
	var fly := furniture("diesel", "flywheel")
	var shaft := furniture("diesel", "shaft")
	var fly_m := 0.6                       # маховик, м (на листе 0.82 — велик для конца дизеля)
	var gap := 0.08
	var can_m := can.get_width() / FURN_PX_PER_M + gap
	var total_m := can_m + eng.get_width() / FURN_PX_PER_M + fly_m * 0.35 + 0.18 + gen.get_width() / FURN_PX_PER_M
	# Размер — как в блоке обычной комнаты; в малой — без канистры, и только потом мельче.
	var sc := minf(1.0, BLOCK_REF * 0.92 / total_m)
	var with_can := total_m * sc * TILE <= width * 0.96
	if not with_can:
		total_m -= can_m
		sc = minf(sc, width * 0.96 / (total_m * TILE))
	var m := TILE * sc                     # пикселей на метр
	var x0 := x - total_m * m * 0.5
	var cw := (can.get_width() / FURN_PX_PER_M * m) if with_can else -gap * m
	var ew := eng.get_width() / FURN_PX_PER_M * m
	var eh := eng.get_height() / FURN_PX_PER_M * m
	var ex := x0 + cw + gap * m
	var shake := Vector2(sin(_anim_t() * 47.0 + seed), sin(_anim_t() * 39.0 + seed * 2.0) * 0.6) * (0.7 if on else 0.0)
	var hub := Vector2(ex + ew * 188.0 / 198.0 + 0.05 * m, fy - maxf(eh * 33.0 / 116.0, fly_m * 0.5 * m + 0.02 * m))
	var gw := gen.get_width() / FURN_PX_PER_M * m
	var gh := gen.get_height() / FURN_PX_PER_M * m
	var gx := hub.x + fly_m * 0.35 * m + 0.18 * m
	var out := {"top": fy - eh, "inlet": ex + ew * 180.0 / 200.0, "inlet_y": fy - eh + 3.0 * sc, "scale": sc,
		"dynamo": Vector2(gx + gw * 0.55, fy - gh + 3.0)}
	if not draw:
		return out
	if with_can:
		_furn_at(can, x0 + cw * 0.5, fy, alpha, 1, sc)
	# Вал — от маховика к порту генератора (на высоте оси).
	var sh := shaft.get_size()
	var from := hub
	var to := Vector2(gx + gw * 0.05, hub.y)
	_xform(from, 0.0, Vector2((to.x - from.x) / sh.x, m * 0.12 / sh.y))
	_c.draw_texture(shaft, Vector2(0, -sh.y * 0.5), Color(1, 1, 1, alpha))
	_xform(Vector2.ZERO, 0.0, Vector2.ONE)
	_furn_at(gen, gx + gw * 0.5, fy, alpha, 1, sc)
	_soft_ellipse(Vector2(ex + ew * 0.5, fy - 1.0), ew * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	_c.draw_texture_rect(eng, Rect2(Vector2(ex, fy - eh) + shake, Vector2(ew, eh)), false, Color(1, 1, 1, alpha))
	var ang := fmod(_anim_t() * 4.5 + seed, TAU) if on else 0.3
	_spin_t(fly, fly.get_size() * 0.5, hub + shake, ang, sc * fly_m / (fly.get_width() / FURN_PX_PER_M), alpha)
	return out


## Генератор из деталей шириной width (пиксели) по центру x: двигатель (на угле — топка с живым
## огнём, на газе — синий мотор с голубым пламенем в окошке), маховик (у угольного — за правым
## краем двигателя, у газового — на его валу), ремень к шкиву динамо-машины; маховик и шкив
## крутятся, пока генератор работает. draw = false — только посчитать места: верх двигателя,
## куда подходит труба (inlet), и верх динамо (dynamo — туда идёт провод).
const GEN_FLY := {"coal": 1.0, "gas": 0.85}
func _gen_unit(gas: bool, x: float, fy: float, width: float, on: bool, alpha: float, seed: float, draw := false) -> Dictionary:
	var pre := "gas" if gas else "coal"
	var body := _anim(pre + "_body")
	var dyn := _anim(pre + "_dynamo")
	var fly := _anim(pre + "_flywheel")
	var pul := _anim(pre + "_pulley")
	# Раскладка в пикселях картинок (128 px/м), потом — масштаб под ширину width.
	var bw := float(body.get_width())
	var bh := float(body.get_height())
	var fr: float = fly.get_width() * 0.5 * float(GEN_FLY[pre])
	var axle: Vector2      # ось маховика — от левого низа двигателя (y вверх)
	if gas:
		var pv: Vector2 = ANIM["gas_body"]["pivot"]
		axle = Vector2(pv.x, bh - pv.y)
	else:
		axle = Vector2(bw, fr + 4.0)
	var dx0 := maxf(bw, axle.x + fr) + 14.0
	var total := dx0 + dyn.get_width()
	var s := width / total            # пикселей экрана на пиксель картинки
	var left := x - total * s * 0.5
	var fly_c := Vector2(left + axle.x * s, fy - axle.y * s)
	var drect := Rect2(left + dx0 * s, fy - dyn.get_height() * s, dyn.get_width() * s, dyn.get_height() * s)
	var pul_c := drect.get_center()
	var brect := Rect2(left, fy - bh * s, bw * s, bh * s)
	var out := {"top": brect.position.y, "inlet": left + float(ANIM[pre + "_body"]["top"]) * s,
		"dynamo": Vector2(drect.get_center().x, drect.position.y + drect.size.y * 0.1),
		"scale": s * FURN_PX_PER_M / TILE}
	if not draw:
		return out
	var sc := s * FURN_PX_PER_M / TILE
	var ang := fmod(_anim_t() * 2.6 + seed, TAU) if on else 0.4
	var pr := pul.get_width() * 0.5
	if not gas:
		_spin(pre + "_flywheel", fly_c, ang, sc * GEN_FLY[pre], alpha)
	_stove(pre + "_body", brect.get_center().x, fy, sc, on, gas, alpha, seed)
	if gas:
		_spin(pre + "_flywheel", fly_c, ang, sc * GEN_FLY[pre], alpha)
	_soft_ellipse(Vector2(drect.get_center().x, fy - 1.0), drect.size.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	_c.draw_texture_rect(dyn, drect, false, Color(1, 1, 1, alpha))
	# Ремень: верхняя и нижняя ветви от обода маховика к шкиву.
	var belt := _anim(pre + "_belt")
	for side in [-1.0, 1.0]:
		var a := fly_c + Vector2(0, side * fr * s * 0.97)
		var b := pul_c + Vector2(0, side * pr * s * 0.9)
		var d := b - a
		_xform(a, d.angle(), Vector2(d.length() / belt.get_width(), s * 0.8))
		_c.draw_texture(belt, Vector2(0, -belt.get_height() * 0.5), Color(1, 1, 1, alpha))
		_xform(Vector2.ZERO, 0.0, Vector2.ONE)
	_spin(pre + "_pulley", pul_c, ang * fr / pr, sc, alpha)
	return out


## Насосная: насос на каждые 3 м, справа бак с водой; от насоса труба в потолок; под потолком —
## водопровод с вентилями и манометрами. Насос «крутится», когда комната работает.
## Нефтекачалка — работает по-настоящему: кривошип на редукторе крутится, шатун тянет хвост
## балансира, балансир кивает «головой», шток с подвеской ходит вверх-вниз в устье скважины.
## Детали — art_src/rooms/cut_oil_pump.py; оси — в пикселях вырезанных картинок. Сборка — в
## координатах картинки станины (frame), потом масштаб под 3 м комнаты.
const PJ_A := Vector2(232.0, 331.1)        # ось кривошипа на станине
const PJ_O := Vector2(463.1, 35.0)         # шарнир балансира на станине
const PJ_FLOOR := 491.0                    # низ станины
const PJ_BEAM_O := Vector2(407.3, 182.0)   # ось на картинке балансира
const PJ_REAR := Vector2(-354.2, -19.3)    # палец шатуна на балансире — от оси
const PJ_HEAD := 367.7                     # радиус «головы лошади» (дуга вокруг оси)
const PJ_CRANK_O := Vector2(222.3, 135.1)  # ось на картинке кривошипа
const PJ_CRANK_PIN := Vector2(382.3, 130.5)
const PJ_CRANK_SCALE := 0.6                # кривошип меньше, чем на листе: балансир кивает на ±18°
const PJ_ROD_A := Vector2(46.5, 46.8)      # проушины шатуна
const PJ_ROD_LEN := 363.7
const PJ_POLISH_TOP := Vector2(60.0, 29.0) # подвес штока
const PJ_WELL := Vector2(147.0, 11.0)      # верх устья (центр)
const PJ_WIDTH := 990.0                    # вся качалка от хвоста балансира до устья
const PJ_HEIGHT := 690.0                   # от пола до верха «головы» в верхней точке
const PJ_PERIOD := 3.2                     # секунд на ход
## Длина шатуна в сборке: при горизонтальном балансире кривошип смотрит вниз.
static var _pj_rod := -1.0
## id -> [угол кривошипа, угол балансира, когда считали (мс)].
static var _pj_state := {}


func _draw_oil_pump_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var on := p.phase == Project.Phase.DONE and not p.paused and p.blocked.is_empty() and colony.powered()
	# Рядом с качалкой — смотровой бачок и бочка нефти (если есть картинки), качалка — левее.
	var extras := furniture("oil_pump", "barrel") != null
	# Качалка одного размера в любой комнате (как в блоке обычной); бочка и бачок — рядом, если
	# помещаются в полный размер.
	var s := minf(TILE * BLOCK_REF * (0.7 if extras else 0.96) / PJ_WIDTH, TILE * (CEILING - 0.15) / PJ_HEIGHT)
	if _pj_rod < 0.0:
		_pj_rod = (PJ_O + PJ_REAR).distance_to(PJ_A + Vector2(0, PJ_CRANK_PIN.distance_to(PJ_CRANK_O) * PJ_CRANK_SCALE))
	# Угол кривошипа и балансира (балансир — из длины шатуна, Ньютоном от прошлого угла).
	var now := Time.get_ticks_msec()
	var st: Array = _pj_state.get(p.id, [PI * 0.5, 0.0, now])
	if on and alpha >= 1.0:
		st[0] = fmod(st[0] + TAU * minf(0.1, (now - int(st[2])) / 1000.0) / PJ_PERIOD, TAU)
	st[2] = now
	var cr := PJ_CRANK_PIN.distance_to(PJ_CRANK_O) * PJ_CRANK_SCALE
	var pin := PJ_A + Vector2(cos(st[0]), sin(st[0])) * cr
	var phi: float = st[1]
	for it in 8:
		var b := PJ_O + PJ_REAR.rotated(phi)
		var d := b.distance_to(pin) - _pj_rod
		var b2 := PJ_O + PJ_REAR.rotated(phi + 0.001)
		var g := (b2.distance_to(pin) - _pj_rod - d) / 0.001
		if absf(g) < 1e-6:
			break
		phi -= d / g
	phi = clampf(phi, -0.6, 0.6)
	st[1] = phi
	_pj_state[p.id] = st
	var frame := furniture("oil_pump", "frame")
	var beam := furniture("oil_pump", "beam")
	var crank := furniture("oil_pump", "crank")
	var rod := furniture("oil_pump", "rod")
	var polished := furniture("oil_pump", "polished")
	var well := furniture("oil_pump", "wellhead")
	var mod := Color(1, 1, 1, alpha)
	var rear := PJ_O + PJ_REAR.rotated(phi)
	var head_x := PJ_O.x + PJ_HEAD
	for cx in _block_centers(lay, n):
		# Начало координат сборки (левый верх станины) — так, чтобы вся качалка была по центру
		# блока, а станина стояла на полу.
		var org := Vector2(cx - PJ_WIDTH * 0.5 * s, fy - PJ_FLOOR * s)
		var kk := TILE / FURN_PX_PER_M
		var barrel := furniture("oil_pump", "barrel")
		var sight := furniture("oil_pump", "sight")
		var bw: float = barrel.get_width() * kk if extras else 0.0
		var sw: float = sight.get_width() * kk if extras else 0.0
		var free: float = lay.unit * 3 - TILE * 0.13 - PJ_WIDTH * s
		var with_sight := extras and free >= bw + sw + TILE * 0.06
		if extras and free >= bw:
			# Бочка (и бачок, если влезает) — правее качалки, не заходя под её голову.
			org.x = cx - lay.unit * 1.5 + TILE * 0.05
			var es := 1.0
			var room_x: float = cx + lay.unit * 1.5 - TILE * 0.05
			var bx: float = room_x - bw * es * 0.5
			var sx: float = bx - bw * es * 0.5 - sw * es * 0.5 - TILE * 0.06 * es
			# Труба от устья к бачку (или к бочке) у пола.
			var pipe := furniture("oil_pump", "pipe_h")
			var wx: float = org.x + (PJ_O.x + PJ_HEAD) * s
			_tile_h(pipe, wx, sx if with_sight else bx, fy - TILE * 0.2 * es - pipe.get_height() * kk * es * 0.5, alpha, es)
			if with_sight:
				_furn_at(sight, sx, fy, alpha, 1, es)
			_furn_at(barrel, bx, fy, alpha, 1, es)
			if on and with_sight:
				# В бачке нефть колышется: тёмный блик ходит вверх-вниз.
				var sh := sight.get_height() * kk * es
				var yy := fy - sh * (0.45 + 0.08 * sin(_anim_t() * 2.2 + cx))
				_c.draw_rect(Rect2(sx - sw * es * 0.18, yy, sw * es * 0.36, 2.0), Color(0, 0, 0, 0.35 * alpha))
		var at := func(v: Vector2) -> Vector2: return org + v * s
		# Шток: висит под «головой» на канате; ход — длина дуги головы (радиус × угол).
		var well_top := PJ_FLOOR - (well.get_height() - PJ_WELL.y)
		var rod_top := PJ_O.y + 45.0 + PJ_HEAD * phi
		var vis := maxf(10.0, well_top + 30.0 - rod_top)
		var src := Rect2(0, PJ_POLISH_TOP.y - 12.0, polished.get_width(), minf(vis + 12.0, polished.get_height() - PJ_POLISH_TOP.y + 12.0))
		_c.draw_texture_rect_region(polished, Rect2(at.call(Vector2(head_x - PJ_POLISH_TOP.x, rod_top - 12.0)), src.size * s), src, mod)
		var head_y := PJ_O.y + Vector2(PJ_HEAD, -9.0).rotated(phi).y
		for dx in [-3.0, 3.0]:
			_c.draw_line(at.call(Vector2(head_x + dx, head_y)), at.call(Vector2(head_x + dx, rod_top - 6.0)), Color(0.15, 0.15, 0.17, alpha), maxf(1.0, 5.0 * s))
		_c.draw_texture_rect(well, Rect2(at.call(Vector2(head_x - PJ_WELL.x, well_top - PJ_WELL.y)), well.get_size() * s), false, mod)
		_c.draw_texture_rect(frame, Rect2(org, frame.get_size() * s), false, mod)
		# Балансир — вокруг шарнира на раме.
		_xform(at.call(PJ_O), phi, Vector2(s, s))
		_c.draw_texture(beam, -PJ_BEAM_O, mod)
		# Кривошип — вокруг оси редуктора (палец — по углу кривошипа).
		var pin0 := (PJ_CRANK_PIN - PJ_CRANK_O).angle()
		_xform(at.call(PJ_A), st[0] - pin0, Vector2(s, s) * PJ_CRANK_SCALE)
		_c.draw_texture(crank, -PJ_CRANK_O, mod)
		# Шатун — от пальца кривошипа к хвосту балансира (тянется по длине, толщина та же).
		var dv := rear - pin
		_xform(at.call(pin), dv.angle(), Vector2(s * dv.length() / PJ_ROD_LEN, s))
		_c.draw_texture(rod, -PJ_ROD_A, mod)
		_xform(Vector2.ZERO, 0.0, Vector2.ONE)


## Перенос-поворот-масштаб для следующих картинок: масштаб — вдоль осей самой картинки (до
## поворота). У CanvasItem.draw_set_transform неравный масштаб ложится после поворота — наклонные
## ремни и шатун сплющивались и не доставали до шкивов.
func _xform(pos: Vector2, rot := 0.0, scale := Vector2.ONE) -> void:
	_c.draw_set_transform_matrix(Transform2D(rot, scale, 0.0, pos))


## Деталь t, повёрнутая на angle вокруг своей точки pivot (пиксели картинки); pivot — в точке at,
## sc — масштаб к обычному (128 px на метр).
func _spin_t(t: Texture2D, pivot: Vector2, at: Vector2, angle: float, sc: float, alpha: float) -> void:
	var k := TILE / FURN_PX_PER_M * sc
	_xform(at, angle, Vector2(k, k))
	_c.draw_texture(t, -pivot, Color(1, 1, 1, alpha))
	_xform(Vector2.ZERO, 0.0, Vector2.ONE)


## Стрелка прибора: картинка стрелки смотрит вверх, втулка внизу; value 0..1 — от −120° до +120°,
## дрожит, пока прибор работает. dial — центр циферблата (пиксели слоя), len — длина стрелки.
func _needle(t: Texture2D, dial: Vector2, len: float, value: float, live: bool, alpha: float, seed := 0.0) -> void:
	var a := lerpf(-2.1, 2.1, clampf(value, 0.0, 1.0))
	if live:
		a += 0.06 * sin(_anim_t() * 9.0 + seed) + 0.03 * sin(_anim_t() * 23.0 + seed * 2.0)
	var piv := Vector2(t.get_width() * 0.5, t.get_height() - t.get_width() * 0.5)
	var s := len / (t.get_height() - t.get_width() * 0.5) * FURN_PX_PER_M / TILE
	_spin_t(t, piv, dial, a, s, alpha)


## Ремень между двумя шкивами (центры a, b; радиусы ra, rb): две прямые ветви картинкой ремня.
func _belt(t: Texture2D, a: Vector2, ra: float, b: Vector2, rb: float, thick: float, alpha: float) -> void:
	for side in [-1.0, 1.0]:
		var p0 := a + Vector2(0, side * ra)
		var p1 := b + Vector2(0, side * rb)
		var d := p1 - p0
		_xform(p0, d.angle(), Vector2(d.length() / t.get_width(), thick / t.get_height()))
		_c.draw_texture(t, Vector2(0, -t.get_height() * 0.5), Color(1, 1, 1, alpha))
		_xform(Vector2.ZERO, 0.0, Vector2.ONE)


## Нефтехранилище: чёрный бак на каждые 3 м, в окошке бака — уровень нефти (сколько её в
## хранилище); у пола баки соединены трубой с вентилями (крутятся, пока качалка гонит нефть);
## на стене — манометр (стрелка — заполнение) и фонарь.
func _draw_oil_storage(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var k := TILE / FURN_PX_PER_M
	var tank := furniture("oil_storage", "tank")
	var sc := minf(1.0, TILE * BLOCK_REF * 0.62 / (tank.get_width() * k))
	var xs := _block_centers(lay, n, 0.0)
	var limit := float(colony.room_limit(p, "oil"))
	var fill := clampf(colony.held_in(p, "oil") / maxf(1.0, limit), 0.0, 1.0)
	var flowing := p.phase == Project.Phase.DONE and alpha >= 1.0 and fill < 1.0
	if flowing:
		flowing = false
		for q in colony.rooms_of(RoomType.OIL_PUMP):
			if not q.paused and q.blocked.is_empty() and colony.powered():
				flowing = true
	# Труба у пола — через все баки, за ними.
	var py := fy - TILE * 0.2 * sc
	var right: float = lay.x + n * 3 * lay.unit
	var pipe := furniture("oil_storage", "pipe_h")
	_tile_h(pipe, lay.x + TILE * 0.15, right - TILE * 0.15, py - pipe.get_height() * k * 0.5, alpha)
	var tw := tank.get_width() * k * sc
	var th := tank.get_height() * k * sc
	var posts := _wall_posts(p)
	for i in n:
		var x: float = xs[i]
		_furn_at(tank, x, fy, alpha, 1, sc)
		# Окошко: стекло, нефть снизу по заполнению, блик.
		var win := Rect2(x - tw * 0.5 + tw * 85.0 / 188.0, fy - th + th * 120.0 / 272.0, tw * 28.0 / 188.0, th * 74.0 / 272.0)
		_rbox(win, win.size.x * 0.5, Color(0.86, 0.88, 0.9, alpha))
		var oh := win.size.y * fill
		if oh > 1.0:
			var wave := sin(_anim_t() * 2.0 + i) * 0.6 if flowing else 0.0
			_rbox(Rect2(win.position.x, win.end.y - oh + wave, win.size.x, oh - wave), minf(win.size.x * 0.5, oh * 0.5), Color(0.08, 0.07, 0.07, alpha))
		_c.draw_rect(Rect2(win.position.x + win.size.x * 0.2, win.position.y + win.size.y * 0.12, win.size.x * 0.18, win.size.y * 0.5), Color(1, 1, 1, 0.35 * alpha))
		# Вентиль между баками (и справа от последнего).
		var vx: float = (x + xs[i + 1]) * 0.5 if i + 1 < n else minf(x + tw * 0.62, right - TILE * 0.2)
		var valve := furniture("oil_storage", "valve_small")
		_spin_t(valve, valve.get_size() * 0.5, Vector2(vx, py), fmod(_anim_t() * 1.6 + i, TAU) if flowing else 0.0, sc, alpha)
	# На стене: манометр со стрелкой (заполнение) и фонарь — между баками или сбоку.
	var gauge := furniture("oil_storage", "gauge")
	var gs := gauge.get_size() * k
	var grect: Rect2
	var tank_side: Array[float] = []    # бок бака занят (м от левого края) — для фонаря
	var tm := (xs[0] - tw * 0.5 - r.position.x) / TILE
	while tm <= (xs[0] + tw * 0.5 - r.position.x) / TILE:
		tank_side.append(tm)
		tm += 0.2
	var gx: float = (xs[0] + xs[1]) * 0.5 if n > 1 else NAN
	if n > 1:
		gx = _wall_x(p, r, minf(gx, right - TILE * 0.3), gs.x)
		grect = Rect2(gx - gs.x * 0.5, fy - TILE * HANG_TOP, gs.x, gs.y)
	else:
		# Один бак: на стене рядом места нет (лестницы) — манометр на самом баке, на его
		# правом плече, поменьше.
		var gsz := gs * 0.75
		grect = Rect2(Vector2(xs[0] + tw * 0.5 - gsz.x * 0.85, fy - th * 0.72 - gsz.y * 0.5), gsz)
		gs = gsz
	_wall_items.append(Vector3(grect.position.x, grect.end.x, grect.position.y))
	_c.draw_texture_rect(gauge, grect, false, Color(1, 1, 1, alpha))
	_needle(furniture("oil_storage", "needle"), grect.position + Vector2(gs.x * 0.5, gs.x * 0.5), gs.x * 0.36, fill, flowing, alpha)
	var lamp := furniture("oil_storage", "lamp")
	# При двух баках между ними манометр — фонарь слева от первого.
	var lx: float = (xs[n - 2] + xs[n - 1]) * 0.5 if n > 2 else xs[0] - tw * 0.5 - TILE * 0.3
	# Места нет (малая комната с лестницами) — без фонаря.
	if n > 1:
		tank_side.clear()
	lx = _wall_x(p, r, maxf(lx, lay.x + TILE * 0.2), lamp.get_width() * k, tank_side, n == 1)
	if is_nan(lx):
		return
	_furn_hang(lamp, lx, fy, alpha)
	if alpha >= 1.0:
		_glow(Vector2(lx, fy - TILE * HANG_TOP + lamp.get_height() * k * 0.6), TILE * 1.4, Color(1.0, 0.8, 0.45, 0.16))


## Нефтезавод: на каждые 3 м — медная перегонная колонна (в окошках булькает, пока идёт
## перегонка), холодильник-змеевик (светится), канистра дизеля. Трубы между
## ними на высоте метра с вентилями (крутятся при работе); на стене — манометры со стрелками.
const REFINERY_PIPE := 0.7
func _draw_refinery(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var on := _crafting(p) and alpha >= 1.0
	var k := TILE / FURN_PX_PER_M
	var col := furniture("refinery", "column")
	var cond := furniture("refinery", "condenser")
	var can := furniture("refinery", "canister")
	var pipe := furniture("refinery", "pipe_h")
	var valve := furniture("refinery", "valve_gold")
	var gauge := furniture("refinery", "gauge")
	var t := _anim_t()
	for i in n:
		# Колонна и змеевик — одного размера в любом заводе; канистра — если помещается.
		var fit := _row_fit([col, cond, can], [2], lay.unit * 3)
		var sc: float = fit[0]
		var items: Array = fit[1].filter(func(it) -> bool: return it != null)
		var gap := TILE * 0.1 * sc
		var x: float = lay.x + i * 3 * lay.unit
		var w := 0.0
		for it in items:
			w += it.get_width() * k * sc + gap
		x += (lay.unit * 3 - w + gap) * 0.5
		var cx := []
		for it in items:
			var iw: float = it.get_width() * k * sc
			cx.append(x + iw * 0.5)
			x += iw + gap
		# Труба за машинами — от колонны через патрубки змеевика к горловине канистры, на высоте
		# патрубков (REFINERY_PIPE м над полом при полном размере).
		var py := fy - TILE * REFINERY_PIPE * sc
		_tile_h(pipe, cx[0], cx[-1], py - pipe.get_height() * k * sc * 0.5, alpha, sc)
		for j in items.size():
			_furn_at(items[j], cx[j], fy, alpha, 1, sc)
		# Колонна: огоньки в окошках «кипят»; змеевик светится.
		var ch: float = col.get_height() * k * sc
		if on:
			for j in 4:
				var wy: float = fy - ch + ch * (0.31 + j * 0.19)
				var pulse := 0.5 + 0.5 * sin(t * 5.0 + j * 1.7 + i)
				_glow(Vector2(cx[0], wy), TILE * 0.32 * sc, Color(1.0, 0.75, 0.25, 0.35 * pulse))
			var cc := Vector2(cx[1], fy - cond.get_height() * k * sc * 0.48)
			_glow(cc, TILE * 0.75 * sc, Color(0.35, 1.0, 0.85, 0.22 + 0.1 * sin(t * 3.0 + i)))
		# Вентили на трубе — между колонной и змеевиком и между змеевиком и канистрой.
		var vxs := [0.5 * (cx[0] + cx[1])]
		if cx.size() > 2:
			vxs.append(0.5 * (cx[1] + cx[2]))
		for v in vxs:
			_spin_t(valve, valve.get_size() * 0.5, Vector2(v, py), fmod(t * 1.2 + i, TAU) if on else 0.4, sc, alpha)
		# Манометр на стене над змеевиком.
		var gs := gauge.get_size() * k
		var grect := Rect2(_wall_x(p, r, cx[1], gs.x) - gs.x * 0.5, fy - TILE * HANG_TOP, gs.x, gs.y)
		_c.draw_texture_rect(gauge, grect, false, Color(1, 1, 1, alpha))


## Обогатительная: на каждые 3 м — центрифуга (сверху шкивы с ремнём крутятся, в окне вращается
## барабан — по стеклу бегут блики), рядом шкаф для урана или пульт и контейнер с ураном; на стене —
## знак радиации.
func _draw_enrichment(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var on := _crafting(p) and alpha >= 1.0
	var k := TILE / FURN_PX_PER_M
	var cen := furniture("enrichment", "centrifuge")
	var can := furniture("enrichment", "canister")
	var wheel := furniture("enrichment", "wheel")
	var small := furniture("enrichment", "wheel_small")
	var belt := furniture("enrichment", "belt")
	var sign := furniture("enrichment", "sign")
	var t := _anim_t()
	for i in n:
		var mid := furniture("enrichment", "panel" if i % 2 == 0 else "cabinet")
		# Центрифуга одного размера в любой обогатительной; канистра и пульт — если помещаются.
		var fit := _row_fit([cen, mid, can], [2, 1], lay.unit * 3)
		var sc: float = fit[0]
		var items: Array = fit[1].filter(func(it) -> bool: return it != null)
		var gap := TILE * 0.12 * sc
		var x: float = lay.x + i * 3 * lay.unit
		var w := 0.0
		for it in items:
			w += it.get_width() * k * sc + gap
		x += (lay.unit * 3 - w + gap) * 0.5
		var cx := []
		for it in items:
			var iw: float = it.get_width() * k * sc
			cx.append(x + iw * 0.5)
			x += iw + gap
		var cw: float = cen.get_width() * k * sc
		var chh: float = cen.get_height() * k * sc
		var left: float = cx[0] - cw * 0.5
		var top := fy - chh
		# Шкивы над центрифугой: большой над левой опорой, малый над правой, ремень между ними.
		var wa := Vector2(left + cw * 37.0 / 147.0, top - TILE * 0.05)
		var wb := Vector2(left + cw * 112.0 / 147.0, top + TILE * 0.02)
		var ra := wheel.get_width() * 0.5 * k * sc * 0.92
		var rb := small.get_width() * 0.5 * k * sc * 0.92
		var ang := fmod(t * 3.0 + i, TAU) if on else 0.2
		_belt(belt, wa, ra, wb, rb, TILE * 0.05 * sc, alpha)
		_spin_t(wheel, wheel.get_size() * 0.5, wa, ang, sc, alpha)
		_spin_t(small, small.get_size() * 0.5, wb, ang * ra / rb, sc, alpha)
		_furn_at(cen, cx[0], fy, alpha, 1, sc)
		# Барабан крутится: по зелёному окну бегут светлые полосы.
		var win := Rect2(left + cw * 50.0 / 147.0, top + chh * 64.0 / 174.0, cw * 48.0 / 147.0, chh * 62.0 / 174.0)
		if on:
			for j in 3:
				var u := fmod(t * 0.9 + j / 3.0 + i * 0.13, 1.0)
				var bw := win.size.x * 0.16 * sin(u * PI)
				var bx := win.position.x + u * win.size.x
				_c.draw_rect(Rect2(bx - bw * 0.5, win.position.y + 2, bw, win.size.y - 4), Color(0.85, 1.0, 0.6, 0.28 * sin(u * PI)))
			_glow(win.get_center(), win.size.x * 1.2, Color(0.45, 1.0, 0.35, 0.18 + 0.08 * sin(t * 4.0 + i)))
		for j in range(1, items.size()):
			_furn_at(items[j], cx[j], fy, alpha, 1, sc)
		if on and i % 2 == 0 and items.size() > 1 and items[1] == mid:
			# Пульт: экран-радар мигает.
			var mh: float = mid.get_height() * k * sc
			_glow(Vector2(cx[1] - mid.get_width() * k * sc * 0.12, fy - mh * 0.6), TILE * 0.3 * sc, Color(0.4, 1.0, 0.4, 0.3 + 0.2 * sin(t * 6.0)))
		_furn_hang(sign, _wall_x(p, r, cx[mini(1, cx.size() - 1)] if cx.size() > 1 else cx[0] + cw * 0.7, sign.get_width() * k), fy, alpha)


func _draw_pump_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
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
		var ptop := fy - pump.get_height() * k * sc + 4 * k
		if _anim("pump_body") != null:
			# Новый насос: труба — в его верхний патрубок (сверху картинки).
			var nb := _anim_rect("pump_body", x, fy, sc * pump.get_width() / _anim("pump_body").get_width())
			px = nb.position.x + float(ANIM["pump_body"]["top"]) * nb.size.x / _anim("pump_body").get_width()
			ptop = nb.position.y + 3.0
		_tile_v(pipe_v, px - pipe_v.get_width() * k * 0.5, fy - TILE * CEILING, ptop, alpha)
		# На водопроводе — вентиль левее трубы насоса и манометр правее, если помещаются в блок.
		for it in [["valve", -1], ["gauge", 1]]:
			var t := furniture("pump", it[0])
			var ts := t.get_size() * k * sc
			var tx: float = px + it[1] * (ts.x * 0.5 + TILE * 0.15)
			if tx - ts.x * 0.5 >= b0 and tx + ts.x * 0.5 <= b0 + lay.unit * 3:
				_c.draw_texture_rect(t, Rect2(tx - ts.x * 0.5, line_y - ts.y * 0.5, ts.x, ts.y), false, mod)
		if _anim("pump_body") != null:
			var pr := _anim_rect("pump_body", x, fy, sc * pump.get_width() / _anim("pump_body").get_width())
			var pk := pr.size.x / _anim("pump_body").get_width()
			_soft_ellipse(Vector2(x, fy - 1.0), pr.size.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
			_c.draw_texture_rect(_anim("pump_body"), pr, false, Color(1, 1, 1, alpha))
			var ang := fmod(_anim_t() * 4.0 + x, TAU) if on else 0.0
			_spin("pump_wheel", _anim_at("pump_body", pr, ANIM["pump_body"]["pivot"]), ang, pk * FURN_PX_PER_M / TILE, alpha)
		else:
			_furn_at(pump, x, fy, alpha, 1, sc)
		_furn_at(tank, x + pw * 0.5 + tw * 0.5 + TILE * 0.05, fy, alpha, 1, sc)


## Дегазация: один синий бак метана — чем больше комната, тем больше бак (3 / 6 / 9 м), рядом
## компрессор; под потолком — газовая труба с раструбами-заборниками на концах и манометрами,
## от неё труба вниз к баку.
func _draw_degas_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var k := TILE / FURN_PX_PER_M
	var mod := Color(1, 1, 1, alpha)
	var tank := furniture("degas", "tank_%d" % clampi(n, 1, 3))
	var comp := furniture("degas", "compressor")
	var span: float = n * 3 * lay.unit
	# Компрессор и трубы одного размера в любой комнате; бак (он и так свой на каждую ширину) —
	# по оставшемуся месту.
	var cw := comp.get_width() * k
	var tw := minf(tank.get_width() * k, span - TILE * 0.2 - cw)
	var sc := tw / (tank.get_width() * k)
	var total := tw + TILE * 0.1 + cw
	var x0: float = lay.x + (span - total) * 0.5
	var tank_x := x0 + tw * 0.5
	# Газовая труба под потолком, на концах раструбы (правый — зеркально).
	var line_y := fy - TILE * 2.15
	var pipe := furniture("degas", "pipe")
	var intake := furniture("degas", "intake")
	var is_ := intake.get_size() * k * 0.8
	var left: float = lay.x + TILE * 0.05
	var right: float = lay.x + span - TILE * 0.05
	_tile_h(pipe, left + is_.x * 0.6, right - is_.x * 0.6, line_y - pipe.get_height() * k * 0.5, alpha)
	_c.draw_texture_rect(intake, Rect2(left, line_y - is_.y * 0.5, is_.x, is_.y), false, mod)
	_c.draw_texture_rect(intake, Rect2(right, line_y - is_.y * 0.5, -is_.x, is_.y), false, mod)
	# Отвод вниз к баку — та же труба, стоймя и потоньше.
	_tile_v_rot(pipe, tank_x, line_y, fy - tank.get_height() * k * sc + 4, alpha, 0.6)
	var gauge := furniture("degas", "gauge")
	var gs := gauge.get_size() * k
	for i in n:
		var gx: float = lay.x + (i * 3 + 0.9) * lay.unit
		if absf(gx - tank_x) > TILE * 0.4:
			_c.draw_texture_rect(gauge, Rect2(gx - gs.x * 0.5, line_y - gs.y * 0.3, gs.x, gs.y), false, mod)
	_furn_at(tank, tank_x, fy, alpha, 1, sc)
	_furn_at(comp, x0 + tw + TILE * 0.1 + cw * 0.5, fy, alpha, 1)


## Вентиляция: установка на каждые 3 м; под потолком — воздуховод во всю комнату, над каждой
## установкой — решётка и короб в потолок. Что комната охлаждает и работает от тока, видно сразу:
## при энергии лопасти крутятся, из решёток вниз идёт холодный воздух со снежинками.
func _draw_vent_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
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
	_rails.append(Rect2(lay.x, 0.0, right - lay.x, top + dh))
	var grille := furniture("vent", "grille")
	var gw := grille.get_width() * k
	var box := furniture("vent", "duct_v")
	var air := furniture("vent", "air")
	var thermo := furniture("vent", "thermo")
	for i in n:
		var x: float = xs[i]
		_tile_v(box, x - box.get_width() * k * 0.5, fy - TILE * CEILING, top + 2, alpha)
		_c.draw_texture_rect(grille, Rect2(x - gw * 0.5, top, gw, dh), false, mod)
		if on:
			var asz := air.get_size() * k
			_c.draw_texture_rect(air, Rect2(x - asz.x * 0.5, top + dh * 0.8, asz.x, asz.y), false, Color(1, 1, 1, 0.85 * alpha))
		if _anim("vent_housing") != null:
			# Корпус с прозрачным нутром: за решёткой — тёмная глубина и крутящаяся крыльчатка.
			var hr := _anim_rect("vent_housing", x, fy, sc * fan.get_width() / _anim("vent_housing").get_width())
			var hk := hr.size.x / _anim("vent_housing").get_width()
			var hub := _anim_at("vent_housing", hr, ANIM["vent_housing"]["pivot"])
			_c.draw_circle(hub, hk * 66.0, Color(0.06, 0.06, 0.07, alpha))
			var ang := fmod(_anim_t() * 9.0 + x, TAU) if on else 0.3
			_spin("vent_blades", hub, ang, hk * FURN_PX_PER_M / TILE, alpha)
			_soft_ellipse(Vector2(x, fy - 1.0), hr.size.x * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
			_c.draw_texture_rect(_anim("vent_housing"), hr, false, Color(1, 1, 1, alpha))
		else:
			_furn_at(fan, x, fy, alpha, 1, sc)
	# Термометр — на стене возле первой установки (между установками или справа от неё).
	var a := (xs[0] - r.position.x) / TILE + 0.85 * sc
	var b: float = minf(a + 0.9, (lay.x + n * 3 * lay.unit - r.position.x) / TILE)
	if b - a < 0.3:     # справа места нет — слева от установки
		b = (xs[0] - r.position.x) / TILE - 0.85 * sc
		a = maxf(b - 0.9, (lay.x - r.position.x) / TILE)
	_hang_fit(thermo, r, a, b, _wall_posts(p), fy, alpha)


## Кузница: на каждые 3 м — горн с мехами (угли горят, пока кузнец работает), наковальня на пне,
## бочка с водой; перед горном — ящик руды и стопка слитков; от колпака горна — труба в потолок;
## на стене между горнами — клещи и молот.
func _draw_forge_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := RoomType.blocks(p)
	var lay := _inside(p, r, n * 3.0, true)
	var on := _crafting(p)
	var forge := furniture("forge", "forge_on" if on else "forge_off")
	var live := _anim("stove_forge") != null
	if live:
		forge = _anim("stove_forge")
	var anvil := furniture("forge", "anvil")
	var barrel := furniture("forge", "barrel")
	var ore := furniture("forge", "ore")
	var ingots := furniture("forge", "ingots")
	var chimney := furniture("hearth", "chimney")
	# Горн и наковальня — всегда; бочка — если помещается (в малой кузнице её нет).
	var fit := _row_fit([forge, anvil, barrel], [2], lay.unit * 3)
	var sc: float = fit[0]
	if fit[1][2] == null:
		barrel = null
	var k := TILE / FURN_PX_PER_M * sc
	var gap := TILE * 0.08 * sc
	var row := (forge.get_width() + anvil.get_width()) * k + gap
	if barrel != null:
		row += barrel.get_width() * k + gap
	var fxs: Array[float] = []
	var hoods: Array[float] = []
	for i in n:
		var x0: float = lay.x + i * 3 * lay.unit + (lay.unit * 3 - row) * 0.5
		var fx := x0 + forge.get_width() * k * 0.5
		fxs.append(fx)
		var hood := x0 + (float(ANIM["stove_forge"]["top"]) if live else forge.get_width() * 0.657) * k
		hoods.append(hood)
		_tile_v(chimney, hood - chimney.get_width() * k * 0.5, fy - TILE * CEILING, fy - forge.get_height() * k + 3 * k, alpha)
		if on and alpha >= 1.0:
			_glow(Vector2(hood, fy - TILE * 0.5 * sc), TILE * 2.0, Color(1.0, 0.55, 0.2, 0.22))
		if live:
			_stove("stove_forge", fx, fy, sc, on and alpha >= 1.0, false, alpha, fx * 0.011)
		else:
			_furn_at(forge, fx, fy, alpha, 1, sc)
		var ax := x0 + forge.get_width() * k + gap + anvil.get_width() * k * 0.5
		_furn_at(anvil, ax, fy, alpha, 1, sc)
		if barrel != null:
			_furn_at(barrel, ax + anvil.get_width() * k * 0.5 + gap + barrel.get_width() * k * 0.5, fy, alpha, 1, sc)
		_furn_at(ore, x0 + ore.get_width() * k * 0.45, fy + TILE * 0.04, alpha, 1, sc)
		_furn_at(ingots, x0 + forge.get_width() * k * 0.8, fy + TILE * 0.04, alpha, 1, sc)
	# Инструменты — мимо труб (они над колпаками горнов, а не над серединой горна).
	_tools_between(p, r, lay, hoods, furniture("forge", "tools"), fy, alpha)


## Столовая: стол с лавкой на каждые 3 м, на столе — свой набор посуды; на стене — полки и меню.
const DINING_WALL := ["shelf_vine", "menu", "shelf_plates"]
const DINING_TABLEWARE := ["bowl", "jug_blue", "mug_red", "fruit", "mug_blue", "jug_red", "bowl", "mug_green"]
func _draw_dining_furniture(p: Project, r: Rect2, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var n := maxi(1, p.rect.size.x / 3)
	var lay := _inside(p, r, n * 3.0, true)
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
	var lay := _inside(p, r, n * 3.0, true)
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
	_hang_fit(t, r, a, a + width / TILE, _wall_posts(p), fy, alpha)


## Предметы в ряд на поверхности (стол): поровну по ширине width с центром cx, низом на bottom.
func _place_row(items: Array[Texture2D], cx: float, width: float, bottom: float, alpha: float) -> void:
	for j in items.size():
		_furn_at(items[j], cx - width * 0.5 + (j + 0.5) * width / items.size(), bottom, alpha)


## Повторяющийся по горизонтали предмет (трубы) от left до right, верхом на top.
func _tile_h(t: Texture2D, left: float, right: float, top: float, alpha: float, scale := 1.0) -> void:
	var k := TILE / FURN_PX_PER_M * scale
	var x := left
	while x < right - 0.5:
		var seg := minf(t.get_width() * k, right - x)
		_c.draw_texture_rect_region(t, Rect2(x, top, seg, t.get_height() * k), Rect2(0, 0, seg / k, t.get_height()), Color(1, 1, 1, alpha))
		x += seg


## Повторяющийся по вертикали предмет (труба дымохода) с левым краем x от top до bottom.
func _tile_v(t: Texture2D, x: float, top: float, bottom: float, alpha: float, scale := 1.0) -> void:
	var k := TILE / FURN_PX_PER_M * scale
	if top < _room_top + TILE * 0.6:
		_ceil.append(Vector2(x, x + t.get_width() * k))
	var y := top
	while y < bottom - 0.5:
		var seg := minf(t.get_height() * k, bottom - y)
		_c.draw_texture_rect_region(t, Rect2(x, y, t.get_width() * k, seg), Rect2(0, 0, t.get_width(), seg / k), Color(1, 1, 1, alpha))
		y += seg


## Горизонтальная труба t, поставленная стоймя (повёрнута на 90°) по центру cx от top до bottom.
func _tile_v_rot(t: Texture2D, cx: float, top: float, bottom: float, alpha: float, scale := 1.0) -> void:
	var k := TILE / FURN_PX_PER_M * scale
	var hw := t.get_height() * k
	var y := top
	while y < bottom - 0.5:
		var seg := minf(t.get_width() * k, bottom - y)
		_xform(Vector2(cx + hw * 0.5, y), PI * 0.5, Vector2(k, k))
		_c.draw_texture_rect_region(t, Rect2(0, 0, seg / k, t.get_height()), Rect2(0, 0, seg / k, t.get_height()), Color(1, 1, 1, alpha))
		y += seg
	_xform(Vector2.ZERO)


## Стеллаж шириной width: стойки как на спрайте, середина (полки) сжата.
func _draw_rack(t: Texture2D, cx: float, bottom: float, width: float, post_px: float, alpha: float) -> void:
	var k := TILE / FURN_PX_PER_M
	var sz := t.get_size()
	var h := sz.y * k
	var post := post_px * k
	var x := cx - width * 0.5
	var mod := Color(1, 1, 1, alpha)
	_soft_ellipse(Vector2(cx, bottom - 1.0), width * 0.5, 3.0, Color(0, 0, 0, 0.3 * alpha))
	_c.draw_texture_rect_region(t, Rect2(x, bottom - h, post, h), Rect2(0, 0, post_px, sz.y), mod)
	_c.draw_texture_rect_region(t, Rect2(x + post, bottom - h, width - 2 * post, h), Rect2(post_px, 0, sz.x - 2 * post_px, sz.y), mod)
	_c.draw_texture_rect_region(t, Rect2(x + width - post, bottom - h, post, h), Rect2(sz.x - post_px, 0, post_px, sz.y), mod)


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
		_c.draw_texture_rect_region(beam, Rect2(x, top, seg, beam.get_height() * k), Rect2(0, 0, seg / k, beam.get_height()), mod)
		x += seg
	_c.draw_texture_rect(cap, Rect2(left, top, cap.get_width() * k, cap.get_height() * k), false, mod)
	# Лампы — под брусом, мимо лебёдки и блока с крюком.
	_rails.append(Rect2(left, 0.0, right - left, top + beam.get_height() * k))
	_ceil.append(Vector2(winch_x, right))
	if not is_nan(block_x):
		_ceil.append(Vector2(block_x - block.get_width() * k * 0.5, block_x + block.get_width() * k * 0.5))
	if is_nan(block_x):
		_c.draw_texture_rect(winch, Rect2(winch_x, top, winch.get_width() * k, winch.get_height() * k), false, mod)
		return
	# Трос: от шкива каретки (правый край) к барабану лебёдки (координаты в пикселях спрайтов).
	_c.draw_line(Vector2(block_x + 25 * k, top + 38 * k), Vector2(winch_x + 12 * k, top + 46 * k), Color(0.55, 0.5, 0.45, alpha), maxf(1.0, 3 * k))
	_c.draw_texture_rect(winch, Rect2(winch_x, top, winch.get_width() * k, winch.get_height() * k), false, mod)
	_c.draw_texture_rect(block, Rect2(block_x - block.get_width() * k * 0.5, top, block.get_width() * k, block.get_height() * k), false, mod)


## Телепорт: арка из рубинов и аметистов над светящейся площадкой посередине пола
## (связан с другим — сияет ярче).
func _draw_teleport(p: Project, r: Rect2, alpha: float) -> void:
	var c := view.cell_to_local(Colony.portal_cell(p)) + Vector2(TILE * 0.5, TILE)
	var linked := colony.teleports().size() >= 2 and p.phase == Project.Phase.DONE
	if furniture("teleport", "pedestal") != null and structure_texture("teleport") != null:
		_draw_teleport_pedestal(p, r, c, linked, alpha)
		return
	var h := minf(r.size.y - 14.0, TILE * 2.6)
	var w := TILE * 1.15
	var glow := Color(1.0, 0.2, 0.45, (0.55 if linked else 0.2) * alpha)
	_c.draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.85, -4), c + Vector2(w * 0.85, -4),
		c + Vector2(w * 0.55, -h * 0.9), c + Vector2(0, -h), c + Vector2(-w * 0.55, -h * 0.9)]), glow)
	if linked:
		_c.draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.4, -4), c + Vector2(w * 0.4, -4),
			c + Vector2(w * 0.25, -h * 0.75), c + Vector2(-w * 0.25, -h * 0.75)]), Color(1.0, 0.85, 0.95, 0.45 * alpha))
	# Арка с камнями — рендер (свечение портала — под ней, кодом).
	if _sprite("teleport", c, alpha):
		return
	_c.draw_rect(Rect2(c + Vector2(-w, -7), Vector2(w * 2, 7)), Color(0.3, 0.26, 0.34, alpha))
	_c.draw_rect(Rect2(c + Vector2(-w * 0.7, -10), Vector2(w * 1.4, 3)), Color(1.0, 0.3, 0.5, alpha))
	var prev := Vector2.ZERO
	for i in 9:
		var a := PI + PI * i / 8.0
		var at := c + Vector2(cos(a) * w, sin(a) * h - 6)
		if i > 0:
			_c.draw_line(prev, at, Color(0.35, 0.3, 0.4, alpha), 4.0)
		prev = at
	for i in 9:
		var a := PI + PI * i / 8.0
		var at := c + Vector2(cos(a) * w, sin(a) * h - 6)
		var gem := Color(0.92, 0.08, 0.22, alpha) if i % 2 == 0 else Color(0.66, 0.3, 1.0, alpha)
		_c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -9), at + Vector2(7, 0), at + Vector2(0, 9), at + Vector2(-7, 0)]), gem)
		_c.draw_circle(at + Vector2(-2, -3), 2.0, Color(1, 1, 1, 0.7 * alpha))


## Телепорт (прототип teleport_3.png): пьедестал на полу, на нём арка с самоцветами (поменьше —
## вместе с пьедесталом в комнату 3 м), на пьедестале — светящееся кольцо (пульсирует; когда
## телепорты связаны — ярко, и в арке переливается портал); на стене — пульт.
const TP_PEDESTAL := 1.95
const TP_ARCH := 0.68
func _draw_teleport_pedestal(p: Project, r: Rect2, c: Vector2, linked: bool, alpha: float) -> void:
	var fy := r.end.y - FURN_FLOOR * TILE
	var k := TILE / FURN_PX_PER_M
	var ped := furniture("teleport", "pedestal")
	var sc := TP_PEDESTAL / (ped.get_width() / FURN_PX_PER_M)
	var pw := ped.get_width() * k * sc
	var ph := ped.get_height() * k * sc
	var top := fy - ph + ph * 15.0 / 87.0         # середина верхней площадки
	var t := _anim_t()
	var pulse := 0.5 + 0.5 * sin(t * 2.4)
	# Портал в арке.
	var ah := 2.95 * TP_ARCH * TILE
	var aw := 1.15 * TP_ARCH * TILE
	var glow := Color(0.85, 0.3, 1.0, (0.45 + 0.2 * pulse if linked else 0.14) * alpha)
	_c.draw_colored_polygon(PackedVector2Array([Vector2(c.x - aw * 0.85, top), Vector2(c.x + aw * 0.85, top),
		Vector2(c.x + aw * 0.55, top - ah * 0.82), Vector2(c.x, top - ah * 0.9), Vector2(c.x - aw * 0.55, top - ah * 0.82)]), glow)
	if linked and alpha >= 1.0:
		for j in 3:
			var u := fmod(t * 0.35 + j / 3.0, 1.0)
			_c.draw_arc(Vector2(c.x, top - ah * 0.42), aw * 0.75 * u, 0, TAU, 28, Color(1.0, 0.85, 1.0, 0.35 * (1.0 - u) * alpha), 2.0)
	_sprite("teleport", Vector2(c.x, top + ph * 0.05), alpha, 1.0, TP_ARCH)
	_ceil.append(Vector2(c.x - aw * 0.75, c.x + aw * 0.75))
	_furn_at(ped, c.x, fy, alpha, 1, sc)
	# Кольцо на площадке — лёжа (сплюснуто), пульсирует.
	var ring := furniture("teleport", "ring")
	var rw := pw * 0.62
	var ring_a := (0.55 + 0.45 * pulse if linked else 0.3) * alpha
	_c.draw_texture_rect(ring, Rect2(c.x - rw * 0.5, top - rw * 0.11, rw, rw * 0.22), false, Color(1, 1, 1, ring_a))
	if linked and alpha >= 1.0:
		_glow(Vector2(c.x, top), rw * 0.7, Color(0.8, 0.35, 1.0, 0.18 * pulse))
	# Пульт на стене слева от арки.
	var panel := furniture("teleport", "panel")
	var px := maxf(r.position.x + TILE * 0.35, c.x - pw * 0.5 - panel.get_width() * k * 0.2)
	# Арка занята от ноги до ноги; места нет (3 м между лестницами) — без пульта.
	var arch: Array[float] = []
	var a0 := (c.x - aw * 0.75 - r.position.x) / TILE
	var a1 := (c.x + aw * 0.75 - r.position.x) / TILE
	var am := a0
	while am <= a1:
		arch.append(am)
		am += 0.2
	px = _wall_x(p, r, px, panel.get_width() * k, arch, true)
	if not is_nan(px):
		_furn_hang(panel, px, fy, alpha)


func _draw_furniture(p: Project, r: Rect2, purpose: int, alpha: float) -> void:
	var floor_y := r.end.y - 6
	var x0 := view.cell_to_local(Vector2i(RoomType.floor_start(p), 0)).x
	if purpose == RoomType.SHIP:
		_draw_ship(p, r, alpha)
		return
	if purpose == RoomType.LAUNCHPAD:
		_draw_launchpad(p, r, alpha)
		return
	if purpose == RoomType.TELEPORT:
		_draw_teleport(p, r, alpha)
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
	if purpose == RoomType.OIL_TANK and furniture("oil_storage", "tank") != null:
		_draw_oil_storage(p, r, alpha)
		return
	if purpose == RoomType.REFINERY and furniture("refinery", "column") != null:
		_draw_refinery(p, r, alpha)
		return
	if purpose == RoomType.ENRICHMENT and furniture("enrichment", "centrifuge") != null:
		_draw_enrichment(p, r, alpha)
		return
	if purpose == RoomType.OIL_PUMP and furniture("oil_pump", "frame") != null:
		_draw_oil_pump_furniture(p, r, alpha)
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
				_c.draw_line(Vector2(bx + 23, floor_y - 18), Vector2(bx + bw - 5, floor_y - 18), Color(1, 1, 1, 0.35 * alpha), 2.0)
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
					_c.draw_line(Vector2(bx + 2, by + 2), Vector2(bx + 12, by + 14), Color(CRATE.darkened(0.2), alpha), 1.5)
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
				_c.draw_line(Vector2(mx, floor_y - 9), top, Color(MUSHROOM, alpha), 3.0)
				var rad := 4.0 + h * 0.18
				if warm:
					_c.draw_circle(top, rad * 1.9, Color(cap, 0.12 * alpha))
				var dome := PackedVector2Array()
				for j in 9:
					var a := PI + PI * j / 8.0
					dome.append(top + Vector2(cos(a) * rad, sin(a) * rad * 0.85 + 1.5))
				_c.draw_colored_polygon(dome, Color(cap, alpha))
				_c.draw_circle(top + Vector2(-rad * 0.35, -rad * 0.3), rad * 0.22, Color(1, 1, 1, 0.75 * alpha))
		RoomType.PUMP:
			# Насос и труба вверх через потолок.
			var px := x0 + TILE * 1.2
			_c.draw_rect(Rect2(px - 14, floor_y - 26, 28, 26), Color(0.35, 0.45, 0.55, alpha))
			_c.draw_rect(Rect2(px - 4, r.position.y, 8, floor_y - 26 - r.position.y), Color(0.45, 0.5, 0.55, alpha))
			var a := Time.get_ticks_msec() / 300.0
			_c.draw_arc(Vector2(px + 26, floor_y - 18), 10, 0, TAU, 16, Color(0.55, 0.38, 0.2, alpha), 3.0)
			_c.draw_line(Vector2(px + 26, floor_y - 18), Vector2(px + 26, floor_y - 18) + Vector2(cos(a), sin(a)) * 10, Color(0.55, 0.38, 0.2, alpha), 3.0)
			_c.draw_line(Vector2(px + 14, floor_y - 18), Vector2(px + 26, floor_y - 18), Color(0.45, 0.5, 0.55, alpha), 3.0)
		RoomType.VENT:
			# Вентилятор в стене и короб воздуховода.
			var cx := x0 + RoomType.usable_width(p) * TILE * 0.5
			var cy := (r.position.y + floor_y) * 0.5
			_c.draw_rect(Rect2(x0 + 4, r.position.y + 6, RoomType.usable_width(p) * TILE - 8, 10), Color(0.55, 0.58, 0.62, alpha))
			_c.draw_circle(Vector2(cx, cy), 20, Color(0.3, 0.33, 0.38, alpha))
			var a := Time.get_ticks_msec() / 120.0
			for k in 3:
				var dir := Vector2(cos(a + k * TAU / 3.0), sin(a + k * TAU / 3.0))
				_c.draw_line(Vector2(cx, cy), Vector2(cx, cy) + dir * 17, Color(0.85, 0.88, 0.92, alpha), 5.0)
			_c.draw_circle(Vector2(cx, cy), 4, Color(0.2, 0.2, 0.22, alpha))
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
					_c.draw_line(Vector2(cx - 22, floor_y - 10 - row * 9), Vector2(cx + 22, floor_y - 10 - row * 9), Color(1, 1, 1, 0.25 * alpha), 1.0)
				_rbox(Rect2(cx - 14, floor_y - 22, 28, 22), 8, Color(0.16, 0.1, 0.1, alpha))
				_rbox(Rect2(cx - 28, floor_y - 40, 56, 8), 3, top, Color(0, 0, 0, 0), 0)
				# Труба в потолок.
				_c.draw_rect(Rect2(cx - 6, r.position.y + 4, 12, floor_y - 40 - r.position.y - 4), top.lightened(0.08))
				if p.gas_boiler and p.phase == Project.Phase.DONE:
					# Железный газовый котёл на печи: бак с заклёпками, манометр и газовая труба.
					var steel := Color(0.46, 0.5, 0.56, alpha)
					var b := Rect2(cx - 17, floor_y - 68, 34, 27)
					_rbox(b, 7, steel, Color(0.26, 0.29, 0.33, alpha), 2)
					_c.draw_rect(Rect2(b.position.x + 2, b.position.y + 6, b.size.x - 4, 3), Color(1, 1, 1, 0.18 * alpha))
					for k in 4:
						_c.draw_circle(Vector2(b.position.x + 6 + k * 7.3, b.end.y - 5), 1.6, Color(0.3, 0.32, 0.36, alpha))
					_c.draw_circle(Vector2(cx + 9, b.position.y + 12), 4.5, Color(0.92, 0.9, 0.84, alpha))
					_c.draw_line(Vector2(cx + 9, b.position.y + 12), Vector2(cx + 11, b.position.y + 9), Color(0.7, 0.15, 0.1, alpha), 1.2)
					_c.draw_rect(Rect2(b.position.x - 8, b.position.y + 14, 9, 4), Color(0.75, 0.62, 0.2, alpha))
				if p.burning and alpha >= 1.0:
					var tt := Time.get_ticks_msec() / 1000.0 + i * 1.3
					_glow(Vector2(cx, floor_y - 12), r.size.y * 1.2, Color(1.0, 0.6, 0.25, 0.22))
					for k in 3:
						var fx := cx + (k - 1) * 7.0
						var fh := 11.0 + 5.0 * sin(tt * 7.0 + k * 2.0)
						_c.draw_colored_polygon(PackedVector2Array([Vector2(fx - 5, floor_y - 2), Vector2(fx + 5, floor_y - 2), Vector2(fx + sin(tt * 5.0 + k) * 2.0, floor_y - 2 - fh)]),
							Color(0.3, 0.55, 1.0) if p.on_gas else Color(1.0, 0.5, 0.15))
						_c.draw_colored_polygon(PackedVector2Array([Vector2(fx - 3, floor_y - 2), Vector2(fx + 3, floor_y - 2), Vector2(fx, floor_y - 2 - fh * 0.6)]),
							Color(0.7, 0.88, 1.0) if p.on_gas else Color(1.0, 0.85, 0.35))
			# Поленница у последней печи.
			var wx := x0 + span * (n - 0.5) / n + 32
			for k in 3:
				_c.draw_circle(Vector2(wx + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 4.5, Color(0.66, 0.44, 0.25, alpha))
				_c.draw_circle(Vector2(wx + (k % 2) * 8, floor_y - 5 - (k / 2) * 8), 2.0, Color(0.9, 0.75, 0.5, alpha))
		RoomType.DINING:
			var w := RoomType.usable_width(p)
			var tx := x0 + 8
			while tx + 40 < x0 + w * TILE:
				_c.draw_rect(Rect2(tx, floor_y - 18, 40, 4), Color(BED_FRAME, alpha))
				_c.draw_line(Vector2(tx + 6, floor_y - 14), Vector2(tx + 6, floor_y), Color(BED_FRAME, alpha), 3.0)
				_c.draw_line(Vector2(tx + 34, floor_y - 14), Vector2(tx + 34, floor_y), Color(BED_FRAME, alpha), 3.0)
				_c.draw_circle(Vector2(tx + 20, floor_y - 21), 4, Color(0.9, 0.9, 0.85, alpha))
				_c.draw_rect(Rect2(tx - 8, floor_y - 9, 8, 3), Color(BED_FRAME.lightened(0.2), alpha))
				_c.draw_rect(Rect2(tx + 40, floor_y - 9, 8, 3), Color(BED_FRAME.lightened(0.2), alpha))
				tx += 64


## Крепь тоннеля: рамы поперёк, в шахте — лестница.
func _draw_supports(p: Project, r: Rect2, alpha: float) -> void:
	var bc: Array = MAT_BEAM.get(p.material, MAT_BEAM["wood"])
	var col := Color(bc[0], alpha)
	# Готовая шахта — крепь на каждом метре, как ставили при проходке, и рельсы.
	if p.kind == Project.Kind.MINE:
		for i in p.slice_count():
			_draw_slice_support(p, i, alpha)
		_draw_rails(r, alpha)
		return
	if p.rect.size.y > p.rect.size.x:
		_shaft_lining(r.position.x, r.end.x, r.position.y, r.end.y, alpha, p.material)
		_ladder(r.get_center().x, r.position.y, r.end.y, alpha, p.material)
	else:
		var dark := Color(bc[1], alpha)
		var x := r.position.x + TILE * 0.5
		var tex := structure_texture("support_" + p.material)
		while x < r.end.x:
			if tex != null:
				_c.draw_texture_rect(tex, Rect2(x - TILE * 0.5, r.position.y, TILE, r.size.y), false, Color(1, 1, 1, alpha))
				x += TILE * 3.0
				continue
			for sx in [-8.0, 8.0]:
				_c.draw_line(Vector2(x + sx + 1.5, r.end.y), Vector2(x + sx + 1.5, r.position.y + 3), dark, 4.5)
				_c.draw_line(Vector2(x + sx, r.end.y), Vector2(x + sx, r.position.y + 3), col, 4.5)
			_c.draw_line(Vector2(x - 13, r.position.y + 5), Vector2(x + 13, r.position.y + 5), dark, 6.0)
			_c.draw_line(Vector2(x - 13, r.position.y + 3), Vector2(x + 13, r.position.y + 3), col, 6.0)
			x += TILE * 3.0



## Рельсы для вагонеток по полу шахты: шпалы и рельс.
func _draw_rails(r: Rect2, alpha: float) -> void:
	var rail := Color(0.42, 0.42, 0.46, alpha)
	var y := r.end.y - 4
	var sx := r.position.x + 4
	while sx < r.end.x - 4:
		_c.draw_line(Vector2(sx, y + 1), Vector2(minf(sx + 6, r.end.x - 4), y + 1), Color(BEAM_DARK, alpha), 3.0)
		sx += 10
	_c.draw_line(Vector2(r.position.x + 2, y - 2), Vector2(r.end.x - 2, y - 2), rail, 2.0)


## Сверлящие буры сдвинулись — пунктир их пути перерисовать.
func _drills_sig() -> int:
	var h := 0
	if colony == null:
		return h
	for p in colony.projects:
		if p.kind == Project.Kind.DRILL:
			h = hash([h, p.rect.position, p.drill_left, p.drill_dir])
	return h


## Места посадки: корабль (отсек 9×3) пунктиром над ровной землёй; первое — ярче, «сядет сюда».
func _draw_landing(font: Font) -> void:
	for i in landing.size():
		var r := _rect_px(landing[i])
		var col := Color(0.45, 1.0, 0.5) if i == 0 else Color(0.6, 0.85, 1.0, 0.8)
		_c.draw_rect(r, Color(col, 0.12 if i == 0 else 0.06))
		_dashed_rect(r, Color(col, 0.95), 3.5 if i == 0 else 2.5)
		# Ровная земля под кораблём — 9 клеток.
		_c.draw_line(Vector2(r.position.x, r.end.y + 2), Vector2(r.end.x, r.end.y + 2), Color(col, 0.9), 3.0)
		# Подпись — читаемая и при отдалённой камере.
		var fs := int(22.0 / clampf(view.camera.zoom.x, 0.3, 1.0))
		var at := r.position + Vector2(4, -10)
		var text := "сядет сюда" if i == 0 else "место %d" % (i + 1)
		_c.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(6, fs / 4), Color(0, 0, 0, 0.85))
		_c.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Бур: выбран и стоит — пунктиром, докуда пройдёт на выбранные метры в каждую сторону
## (зелёным — можно, красным — нельзя); сверлит — жёлтым пунктиром, сколько ещё осталось.
const DRILL_PLAN := Color(1.0, 0.85, 0.2)


func _draw_drill_plan(sel: Project, font: Font) -> void:
	for p in colony.projects:
		if p.kind != Project.Kind.DRILL or p.phase != Project.Phase.DONE:
			continue
		if colony.drilling(p):
			var r := _rect_px(Colony.drill_path(p, p.drill_dir, p.drill_left))
			_c.draw_rect(r, Color(DRILL_PLAN, 0.08))
			_dashed_rect(r, Color(DRILL_PLAN, 0.95), 3.0)
			var at := r.position + Vector2(4, -8) if p.drill_dir != Vector2i.DOWN else Vector2(r.position.x + 4, r.end.y + 22)
			_label(font, at, "ещё %d м" % p.drill_left, DRILL_PLAN)
		elif p == sel and p.order_len > 0:
			var dirs: Array = [p.drill_lift_dir()] if p.link_id != 0 else [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT]
			for d: Vector2i in dirs:
				var ok := colony.drill_error(p, d, p.order_len).is_empty()
				var col := Color(0.45, 1.0, 0.5) if ok else Color(1.0, 0.4, 0.35)
				var r := _rect_px(Colony.drill_path(p, d, p.order_len))
				_c.draw_rect(r, Color(col, 0.1))
				_dashed_rect(r, Color(col, 0.95), 3.0)
				var at := r.position + Vector2(4, -8) if d != Vector2i.DOWN else Vector2(r.position.x + 4, r.end.y + 22)
				_label(font, at, "%d м" % p.order_len, col)


## Выбранная готовая шахта, тоннель или лифт: пунктиром — докуда дойдёт продление на выбранные
## метры в каждую сторону (зелёным — можно, красным — нельзя).
func _draw_extend(p: Project, font: Font) -> void:
	if p == null or p.phase != Project.Phase.DONE or p.repairing or p.order_len <= 0:
		return
	var dirs := Colony.extend_dirs(p)
	if dirs.is_empty() or colony.extension_of(p) != null:
		return
	for d: Vector2i in dirs:
		var er := Colony.extend_rect(p, d, p.order_len)
		var ok := colony.extend_error(p, d, p.order_len).is_empty()
		var col := Color(0.45, 1.0, 0.5) if ok else Color(1.0, 0.4, 0.35)
		var r := _rect_px(er)
		_c.draw_rect(r, Color(col, 0.1))
		_dashed_rect(r, Color(col, 0.95), 3.0)
		var at := r.position + Vector2(4, -8) if d != Vector2i.DOWN else Vector2(r.position.x + 4, r.end.y + 22)
		_label(font, at, "+%d м" % p.order_len, col)


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
		_c.draw_circle(at, 10, Color(1.0, 0.72, 0.2))
		_c.draw_string(font, at + Vector2(-3, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.25, 0.15, 0.05))
	if p.phase == Project.Phase.DIG:
		for c in colony.remaining_dig(p):
			_c.draw_rect(Rect2(view.cell_to_local(c), Vector2(TILE, TILE)), DIG_FILL)
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
			_c.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * t, r.size.x, r.size.y * t), Color(wall, 0.55))
		elif p.kind == Project.Kind.DRILL:
			_draw_drill(p, r, 0.3 + 0.7 * t)
		elif p.kind == Project.Kind.PROBE:
			_draw_probe(p, r, 0.3 + 0.7 * t)
		else:
			_draw_supports(p, r, 0.3 + 0.7 * t)
		var bar := Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, 6)
		_c.draw_rect(bar, BAR_BG)
		_c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)
	_dashed_rect(r, edge, 2.5 if p.id != selected_project else 4.0)
	if p.paused:
		var c := r.get_center()
		_c.draw_rect(Rect2(c + Vector2(-10, -12), Vector2(7, 24)), PAUSED)
		_c.draw_rect(Rect2(c + Vector2(3, -12), Vector2(7, 24)), PAUSED)


func _draw_dig_progress() -> void:
	for u in colony.units:
		if u.task != Unit.Task.DIG or u.state != Unit.State.WORK:
			continue
		var c := u.target
		if not _vis.has_point(c):
			continue
		var need := colony.dig_time(c)
		if need <= 0.0:
			continue
		var t := clampf(colony.dig_progress.get(c, 0.0) / need, 0.0, 1.0)
		var r := Rect2(view.cell_to_local(c), Vector2(TILE, TILE))
		# Трещины по мере копки.
		var crack := Color(0, 0, 0, 0.25 + 0.4 * t)
		_c.draw_line(r.get_center(), r.get_center() + Vector2(-9, -8) * t * 1.4, crack, 2.0)
		_c.draw_line(r.get_center(), r.get_center() + Vector2(10, 4) * t * 1.4, crack, 2.0)
		_c.draw_line(r.get_center(), r.get_center() + Vector2(-2, 11) * t * 1.4, crack, 2.0)
		var bar := Rect2(r.position.x + 3, r.end.y - 7, r.size.x - 6, 5)
		_c.draw_rect(bar, BAR_BG)
		_c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), BAR)


func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		_c.draw_dashed_line(pts[i], pts[i + 1], col, width, 10.0)


func _label(font: Font, p: Vector2, text: String, col: Color) -> void:
	if text.is_empty():
		return
	_c.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.85))
	_c.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)


## Кирпичный (каменный) ствол: стенки выложены кирпичом, в них — железные скобы лестницы.
func _shaft_lining(x0: float, x1: float, top: float, bottom: float, alpha: float, mat: String) -> void:
	if mat != "brick" and mat != "stone":
		return
	var bc: Array = MAT_BEAM[mat]
	for x in [x0 + 3.0, x1 - 3.0]:
		_c.draw_line(Vector2(x, top), Vector2(x, bottom), Color(bc[1], alpha), 6.0)
		_c.draw_line(Vector2(x, top), Vector2(x, bottom), Color(bc[0], alpha), 4.0)


func _ladder(cx: float, top: float, bottom: float, alpha: float, mat := "wood") -> void:
	if _sprite_column("ladder_" + RoomType.ladder_material(mat), cx, top, bottom, alpha):
		return
	var bc: Array = MAT_BEAM.get(RoomType.ladder_material(mat), MAT_BEAM["wood"])
	var col := Color(bc[0], alpha)
	var dark := Color(bc[1], alpha)
	var y := top + 8
	while y < bottom:
		_c.draw_line(Vector2(cx - 7, y + 1.5), Vector2(cx + 7, y + 1.5), dark, 3.0)
		_c.draw_line(Vector2(cx - 7, y), Vector2(cx + 7, y), col, 3.0)
		y += 10
	for sx in [-8.0, 8.0]:
		_c.draw_line(Vector2(cx + sx + 1, top), Vector2(cx + sx + 1, bottom), dark, 3.5)
		_c.draw_line(Vector2(cx + sx, top), Vector2(cx + sx, bottom), col, 3.5)


const RES_COLORS := {
	"wood": Color(0.55, 0.38, 0.2), "stone": Color(0.6, 0.6, 0.62), "clay": Color(0.66, 0.42, 0.3),
	"food": Color(0.9, 0.8, 0.62), "fish": Color(0.55, 0.72, 0.85), "berries": Color(0.85, 0.25, 0.3), "coal": Color(0.15, 0.14, 0.13), "iron": Color(0.69, 0.33, 0.18),
	"copper": Color(0.25, 0.68, 0.57), "silver": Color(0.84, 0.87, 0.9), "gold": Color(0.95, 0.79, 0.23),
	"uranium": Color(0.53, 0.88, 0.31), "diamond": Color(0.75, 0.95, 1.0), "salt": Color(0.91, 0.87, 0.9),
	"oil": Color(0.1, 0.08, 0.06), "limestone": Color(0.81, 0.78, 0.69), "ruby": Color(0.88, 0.08, 0.2),
	"soil": Color(0.36, 0.25, 0.16), "sand": Color(0.85, 0.75, 0.52), "gravel": Color(0.55, 0.52, 0.47),
	"iron_ore": Color(0.52, 0.28, 0.18), "copper_ore": Color(0.2, 0.52, 0.44), "silver_ore": Color(0.63, 0.65, 0.69),
	"gold_ore": Color(0.72, 0.6, 0.21), "uranium_ore": Color(0.4, 0.65, 0.24), "amethyst": Color(0.6, 0.28, 0.95),
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
		ResIcon.draw(_c, e[0], Vector2(x + 16, y + 14), 10)
		var tp := Vector2(x + 30, y + 21)
		_c.draw_string(Fonts.black(), tp, "%d/%d" % [e[1], e[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		x += widths[i] + 6.0


## Добытое, лежащее на земле: кучка значков и число.
func _draw_drops(font: Font) -> void:
	for c: Vector2i in colony.drops:
		if not _vis.has_point(c):
			continue
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
				ResIcon.draw(_c, k, p + Vector2((j - (piles - 1) * 0.5) * 9.0 + i * 6.0, -7.0 - (j % 2) * 5.0 - i * 9.0), 8.0)
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
		_c.draw_line(Vector2(box.position.x + 3, box.get_center().y), Vector2(box.end.x - 3, box.get_center().y), CRATE.darkened(0.3), 1.5)
	var top := bottom - Vector2(0, 3 + h * n + 9)
	ResIcon.draw(_c, key, top, 8.0)
	_label(font, top + Vector2(10, 4), str(total), Color(1.0, 0.45, 0.4) if full else Color(1, 1, 1, 0.9))


## Метан: зеленоватая дымка, гуще — опаснее.
func _draw_gas() -> void:
	for c: Vector2i in colony.elements.gas:
		if not _vis.has_point(c):
			continue
		var g: float = colony.elements.gas[c]
		var col := Color(0.55, 0.8, 0.25, clampf(g * 0.8, 0.05, 0.55))
		if g >= Elements.GAS_EXPLOSIVE:
			col = Color(0.75, 0.85, 0.2, clampf(g * 0.8, 0.2, 0.65))
		_c.draw_rect(Rect2(view.cell_to_local(c), Vector2(TILE, TILE)), col)


## Трещины на ветхой постройке — тем больше, чем сильнее износ.
func _draw_cracks(p: Project, r: Rect2) -> void:
	var n := int((p.wear - 0.4) * 12.0) + 1
	var col := Color(0.15, 0.1, 0.08, 0.35 + p.wear * 0.4)
	for k in n:
		var a := r.position + Vector2(10 + WorldGen.hash01(p.id, k, 81) * (r.size.x - 20), 8 + WorldGen.hash01(p.id, k, 82) * (r.size.y - 20))
		var b := a + Vector2(WorldGen.hash01(p.id, k, 83) * 14 - 7, 9)
		var c := b + Vector2(WorldGen.hash01(p.id, k, 84) * 14 - 7, 9)
		_c.draw_polyline(PackedVector2Array([a, b, c]), col, 2.0)


## Знак «нужен ремонт» над ветхой постройкой (мигает, если вот-вот рухнет).
func _draw_wear_sign(p: Project) -> void:
	var r := _rect_px(p.rect)
	# Гаечный ключ: износ 70% — оранжевый, 90% — красный и мигает. Всегда внутри постройки:
	# в высокой (комната, шахта) — вверху посередине, в узкой (тоннель, мост, пристань) — по центру.
	var col := Color(1.0, 0.7, 0.2) if p.wear < Colony.WEAR_WARN[1] else Color(1.0, 0.3, 0.25)
	if p.wear >= Colony.WEAR_WARN[1] and int(Time.get_ticks_msec() / 400) % 2 == 0:
		col = col.lightened(0.4)
	var c := Vector2(r.get_center().x, r.position.y + 22) if p.rect.size.y >= 3 else r.get_center()
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
					_c.draw_circle(c, 4.5, col)
					_c.draw_circle(c, 2.0, col.lightened(0.35))
				left -= in_row
				row += 1
		else:
			var rad := clampf(sqrt(ground) * 2.2, 5.0, TILE * 0.9)
			var pts := PackedVector2Array()
			for j in 11:
				var a := PI + j * PI / 10.0
				pts.append(base + Vector2(cos(a) * rad, sin(a) * rad * 0.8))
			_c.draw_colored_polygon(pts, col)
			_c.draw_circle(base + Vector2(-rad * 0.3, -rad * 0.5), rad * 0.2, col.lightened(0.25))
		_label(font, base + Vector2(-8, -30), str(ground), Color(1, 1, 1, 0.9))



## Мостик: настил над водой, сваи и перила. Пристань: широкий настил и навес на берегу.
func _draw_deck(p: Project, r: Rect2, alpha: float) -> void:
	var plank := Color(0.6, 0.43, 0.25, alpha)
	var dark := Color(0.42, 0.29, 0.16, alpha)
	var deck_y := r.end.y - (8 if p.kind == Project.Kind.PIER else 6)
	_c.draw_rect(Rect2(r.position.x, deck_y, r.size.x, r.end.y - deck_y), plank)
	var x := r.position.x
	while x < r.end.x:
		_c.draw_line(Vector2(x, deck_y), Vector2(x, r.end.y), dark, 1.0)
		x += 8
	# Сваи уходят в воду.
	x = r.position.x + 4
	while x < r.end.x:
		_c.draw_rect(Rect2(x, r.end.y, 5, TILE * 1.5), dark)
		x += TILE * (1.5 if p.kind == Project.Kind.PIER else 2.0)
	if p.kind == Project.Kind.BRIDGE:
		_c.draw_line(Vector2(r.position.x, deck_y - 16), Vector2(r.end.x, deck_y - 16), plank, 3.0)
		x = r.position.x + 2
		while x < r.end.x:
			_c.draw_line(Vector2(x, deck_y - 16), Vector2(x, deck_y), plank, 2.0)
			x += TILE
	else:
		# Навес рыбаков на береговом конце.
		var land_left := Mat.is_solid(colony.world.get_mat(p.rect.position.x, p.rect.position.y + 1))
		var hx := r.position.x if land_left else r.end.x - TILE * 1.6
		var hw := TILE * 1.6
		_c.draw_rect(Rect2(hx + 4, deck_y - TILE * 1.3, hw - 8, TILE * 1.3), Color(0.72, 0.56, 0.36, alpha))
		_c.draw_colored_polygon(PackedVector2Array([
			Vector2(hx - 4, deck_y - TILE * 1.3), Vector2(hx + hw * 0.5, deck_y - TILE * 2.1),
			Vector2(hx + hw + 4, deck_y - TILE * 1.3)]), Color(0.55, 0.25, 0.2, alpha))
		# Сети на шестах.
		_c.draw_line(Vector2(hx + hw + 10, deck_y), Vector2(hx + hw + 10, deck_y - 30), dark, 2.0)



## Из чего выглядит крепь: у тоннеля и шахты — их материал, у комнаты — каркас.
static func _support_look(p: Project) -> String:
	return Colony.room_support(p) if p.kind == Project.Kind.ROOM else p.material


## Крепь одного среза: стойки по краям и верхняя балка (в шахте — пролёт лестницы).
func _draw_slice_support(p: Project, i: int, alpha: float) -> void:
	var cells := p.slice_cells(i)
	if cells.is_empty():
		return
	var col := Color((MAT_BEAM.get(_support_look(p), MAT_BEAM["wood"]) as Array)[0], alpha)
	var a := view.cell_to_local(cells[0])
	var b := view.cell_to_local(cells[cells.size() - 1]) + Vector2(TILE, TILE)
	if p.vertical():
		_shaft_lining(a.x, b.x, a.y, b.y, alpha, _support_look(p))
		_ladder((a.x + b.x) * 0.5, a.y, b.y, alpha, _support_look(p))
		return
	var tex := structure_texture("slice_" + _support_look(p))
	if tex != null:
		_c.draw_texture_rect(tex, Rect2(a, b - a), false, Color(1, 1, 1, alpha))
		return
	_c.draw_line(Vector2(a.x + 4, a.y + 3), Vector2(a.x + 4, b.y), col, 4.0)
	_c.draw_line(Vector2(b.x - 4, a.y + 3), Vector2(b.x - 4, b.y), col, 4.0)
	_c.draw_line(Vector2(a.x, a.y + 3), Vector2(b.x, a.y + 3), col, 5.0)
