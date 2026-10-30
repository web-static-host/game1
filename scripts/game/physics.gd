class_name Physics
extends RefCounted
## Горная механика:
## - сыпучие породы (песок, гравий, обломки) осыпаются в пустоту под собой;
## - у каждой породы свой наибольший пролёт без крепи — шире потолок обрушивается.
## Готовые постройки (крепь тоннелей, стены комнат) защищают свои клетки.
## Идущая стройка держится на временных стойках, пока не простоит без дела
## дольше GRACE секунд (пауза, ожидание материалов) — потом может обвалиться.

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const MAX_FALL := 200
const MAX_RUN := 64
## Сколько выработка может стоять на временных стойках без работ.
const GRACE := 180.0
const FX_TIME := 0.6

var colony: Colony
var world: WorldData
## Падающие куски для анимации: [откуда Vector2, куда Vector2, материал, время].
var fx: Array = []


func _init(p_colony: Colony) -> void:
	colony = p_colony
	world = p_colony.world


## Клетка защищена готовой постройкой.
func is_protected(c: Vector2i) -> bool:
	return colony.interior.has(c) or colony.cell_supported(c)


## Пустота без защиты: туда может осыпаться порода.
func hollow(c: Vector2i) -> bool:
	return world.is_open(c.x, c.y) and not is_protected(c)


## Пока стройка идёт (или недолго простаивает), её держат временные стойки.
func temporarily_supported(c: Vector2i) -> bool:
	var p := colony.project_at(c)
	if p == null:
		return false
	if p.phase != Project.Phase.DIG and p.phase != Project.Phase.BUILD:
		return false
	return p.exposed_t < GRACE


## Клетка только что стала пустой.
func on_opened(c: Vector2i) -> void:
	drop_column(c)
	check_span(c)


## Проверка целой зоны (снос, отмена, долгий простой).
func check_area(cells: Array[Vector2i]) -> void:
	for c in cells:
		if hollow(c):
			drop_column(c)
	for c in cells:
		if hollow(c):
			check_span(c)


## Осыпает сыпучую породу над пустой клеткой c (столбом, пока есть что сыпаться).
func drop_column(c: Vector2i) -> int:
	var moved := 0
	var k := c
	# Под идущей стройкой временные стойки — ничего не осыпается.
	while moved < MAX_FALL and hollow(k) and not temporarily_supported(k):
		var src := k + UP
		var m := world.get_mat(src.x, src.y)
		if not Mat.is_loose(m) or is_protected(src) or not Mat.is_solid(m):
			break
		var land := k
		while hollow(land + DOWN) and land.y - k.y < MAX_FALL:
			land += DOWN
		world.set_dug(src.x, src.y)
		world.set_material(land.x, land.y, m)
		for n in world.reveal_around(src.x, src.y, colony.see_radius()):
			colony.note_discovery(world.get_mat(n.x, n.y), n)
		_landed(src, land, m)
		moved += 1
		k = src
	if moved > 0:
		colony.on_slide(c, moved, world.get_mat(c.x, c.y))
	return moved


## Если пустота под потолком шире, чем держит порода, — потолок рушится обломками.
func check_span(c: Vector2i) -> bool:
	if not hollow(c) or temporarily_supported(c):
		return false
	var top := c
	while hollow(top + UP) and c.y - top.y < 8:
		top += UP
	var ceiling := top + UP
	var m := world.get_mat(ceiling.x, ceiling.y)
	if not Mat.is_solid(m) or Mat.is_loose(m) or is_protected(ceiling):
		return false
	var left := top.x
	var right := top.x
	while right - left < MAX_RUN and hollow(Vector2i(left - 1, top.y)) and Mat.is_solid(world.get_mat(left - 1, top.y - 1)):
		left -= 1
	while right - left < MAX_RUN and hollow(Vector2i(right + 1, top.y)) and Mat.is_solid(world.get_mat(right + 1, top.y - 1)):
		right += 1
	var span := right - left + 1
	var limit := colony.span_limit(m, ceiling)
	if span <= limit:
		return false
	for x in range(left, right + 1):
		if temporarily_supported(Vector2i(x, top.y)):
			return false
	var fell := 0
	for x in range(left, right + 1):
		var cc := Vector2i(x, top.y - 1)
		var cm := world.get_mat(cc.x, cc.y)
		if not Mat.is_solid(cm) or is_protected(cc):
			continue
		var land := Vector2i(x, top.y)
		while hollow(land + DOWN) and land.y - top.y < MAX_FALL:
			land += DOWN
		world.set_dug(cc.x, cc.y)
		world.set_material(land.x, land.y, Mat.RUBBLE)
		for n in world.reveal_around(cc.x, cc.y, colony.see_radius()):
			colony.note_discovery(world.get_mat(n.x, n.y), n)
		_landed(cc, land, Mat.RUBBLE)
		fell += 1
	colony.on_collapse(Vector2i((left + right) / 2, top.y), span, limit, m)
	return true


func _landed(src: Vector2i, land: Vector2i, m: int) -> void:
	if not colony.offline:
		fx.append([Vector2(src), Vector2(land), m, 0.0])
	colony.on_cell_filled(src, land)


func update(dt: float) -> void:
	for f in fx:
		f[3] += dt
	fx = fx.filter(func(f: Array) -> bool: return f[3] < FX_TIME)
