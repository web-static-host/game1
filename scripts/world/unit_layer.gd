class_name UnitLayer
extends Node2D
## Рисует жителей: плоские векторные фигурки с анимацией ходьбы и работы.

const TILE := ChunkView.TILE
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.87, 0.68, 0.5), Color(0.72, 0.53, 0.38)]
const HAIR := [Color(0.25, 0.17, 0.1), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.4), Color(0.12, 0.1, 0.1)]
const SHIRT_M := [Color(0.25, 0.45, 0.75), Color(0.3, 0.55, 0.4), Color(0.6, 0.35, 0.25)]
const SHIRT_F := [Color(0.75, 0.3, 0.45), Color(0.55, 0.35, 0.7), Color(0.85, 0.55, 0.2)]
const PANTS := Color(0.22, 0.24, 0.3)
const TOOL := Color(0.45, 0.45, 0.5)
const HANDLE := Color(0.5, 0.35, 0.2)

var view: WorldView
var colony: Colony
var selected_unit := 0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if colony == null:
		return
	var font := ThemeDB.fallback_font
	for u in colony.units:
		var foot := view.cell_to_local(Vector2i.ZERO) + (u.pos + Vector2(0.5, 1.0)) * TILE
		# На естественном рельефе ноги ставим на сглаженную линию поверхности.
		var gen := colony.world.gen
		var cx := roundi(u.pos.x)
		var below := roundi(u.pos.y) + 1
		if u.state != Unit.State.FALL and below == gen.surface_y(cx) and not colony.world.is_dug(cx, below) \
				and not colony.interior.has(Vector2i(cx, below - 1)):
			foot.y = view.cell_to_local(Vector2i.ZERO).y + gen.surface_smooth(u.pos.x + 0.5) * TILE
		if u.task == Unit.Task.SLEEP and u.state == Unit.State.WORK:
			_draw_sleeping(u, foot)
		else:
			var sc := lerpf(0.5, 0.9, u.growth()) if u.child else 1.0
			draw_set_transform(foot, 0.0, Vector2(sc, sc))
			_draw_unit(u, Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
			if u.task == Unit.Task.HAUL and u.haul_stage == 1 and u.carry_amount > 0:
				# Груз на плече.
				ResIcon.draw(self, u.carry_key, foot + Vector2(-u.facing * 6, -50 * sc), 9)
			_draw_needs(u, foot + Vector2(0, -70 * sc))
		if u.id == selected_unit:
			draw_arc(foot + Vector2(0, -26), 34, 0, TAU, 32, Color.WHITE, 2.0)
			var w := font.get_string_size(u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var p := foot + Vector2(-w * 0.5, -62)
			draw_string_outline(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.85))
			draw_string(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## Спящий: лежит, над ним «z».
func _draw_sleeping(u: Unit, foot: Vector2) -> void:
	var k := int(u.look * 1000.0)
	var shirts: Array = SHIRT_M if u.sex == Unit.Sex.MALE else SHIRT_F
	var sc := lerpf(0.5, 0.9, u.growth()) if u.child else 1.0
	var y := foot.y - 22 * sc
	draw_rect(Rect2(foot.x - 22 * sc, y, 36 * sc, 10 * sc), shirts[(k / 7) % shirts.size()])
	draw_circle(Vector2(foot.x + 20 * sc, y + 4 * sc), 7 * sc, SKIN[k % SKIN.size()])
	var font := ThemeDB.fallback_font
	var bob := sin(u.anim * 2.0) * 3.0
	draw_string(font, Vector2(foot.x + 18, y - 10 + bob), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
	draw_string(font, Vector2(foot.x + 26, y - 20 + bob), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.6))


## Значки нужд над головой: голод (красный кружок) и усталость (синий).
func _draw_needs(u: Unit, p: Vector2) -> void:
	var icons: Array[Color] = []
	if u.satiety < 25.0:
		icons.append(Color(0.95, 0.35, 0.3))
	if u.energy < 20.0:
		icons.append(Color(0.4, 0.55, 0.95))
	if u.pregnancy >= 0.0:
		icons.append(Color(1.0, 0.6, 0.75))
	if u.health < 50.0:
		icons.append(Color(1.0, 1.0, 1.0))
	for i in icons.size():
		var c := p + Vector2((i - (icons.size() - 1) * 0.5) * 14, 0)
		draw_circle(c, 6, Color(0, 0, 0, 0.5))
		draw_circle(c, 4.5, icons[i])


func _draw_unit(u: Unit, foot: Vector2) -> void:
	var k := int(u.look * 1000.0)
	var skin: Color = SKIN[k % SKIN.size()]
	var hair: Color = HAIR[(k / 3) % HAIR.size()]
	var shirts: Array = SHIRT_M if u.sex == Unit.Sex.MALE else SHIRT_F
	var shirt: Color = shirts[(k / 7) % shirts.size()]
	var f := float(u.facing)
	var walking := u.state == Unit.State.MOVE
	var working := u.state == Unit.State.WORK
	var swing := sin(u.anim * 9.0) if walking else 0.0
	var climbing := walking and u.path_i < u.path.size() and u.path[u.path_i].x == roundi(u.pos.x) \
		and absf(u.path[u.path_i].y - u.pos.y) > 0.01

	# Ноги
	var hip := foot + Vector2(0, -22)
	draw_line(hip, foot + Vector2(-4 + swing * 6, 0), PANTS, 5.0)
	draw_line(hip, foot + Vector2(4 - swing * 6, 0), PANTS, 5.0)
	# Корпус
	var body := PackedVector2Array([
		hip + Vector2(-7, 2), hip + Vector2(7, 2), hip + Vector2(6, -22), hip + Vector2(-6, -22)])
	if u.sex == Unit.Sex.FEMALE:
		body = PackedVector2Array([
			hip + Vector2(-9, 4), hip + Vector2(9, 4), hip + Vector2(6, -22), hip + Vector2(-6, -22)])
	draw_colored_polygon(body, shirt)
	var neck := hip + Vector2(0, -22)
	var head := neck + Vector2(0, -9)
	# Руки и инструмент
	var shoulder := neck + Vector2(f * 3, 3)
	var hand: Vector2
	if working and u.task == Unit.Task.EAT:
		# Подносит еду ко рту.
		var a := sin(u.anim * 5.0) * 0.5
		hand = head + Vector2(f * (6 + a * 4), 6)
		draw_circle(hand + Vector2(f * 3, -2), 3.5, Color(0.85, 0.2, 0.25))
	elif working:
		var a := -0.6 + sin(u.anim * (7.0 if u.task != Unit.Task.BUILD else 10.0)) * (0.15 if u.task == Unit.Task.FISH else 0.9)
		hand = shoulder + Vector2(f * cos(a), sin(a)) * 14.0
		_draw_tool(u.task, hand, f, a)
	elif climbing:
		hand = shoulder + Vector2(f * 4, -12 + swing * 4)
	else:
		hand = shoulder + Vector2(-swing * 6 * f, 14)
	draw_line(shoulder, hand, skin, 4.0)
	# Голова
	draw_circle(head, 8.0, skin)
	if u.sex == Unit.Sex.FEMALE:
		draw_circle(head + Vector2(-f * 3, -3), 8.0, hair)
		draw_rect(Rect2(head + Vector2(-f * 8 - 3, -2), Vector2(6, 12)), hair)
	else:
		draw_circle(head + Vector2(-f * 2, -4), 6.5, hair)
	draw_circle(head + Vector2(f * 4, -1), 1.4, Color(0.1, 0.1, 0.1))
	# Каска у работающих под землёй
	if working and u.task == Unit.Task.DIG:
		draw_arc(head + Vector2(0, -2), 9.0, PI, TAU, 10, Color(1.0, 0.78, 0.15), 5.0)


func _draw_tool(task: int, hand: Vector2, f: float, a: float) -> void:
	var dir := Vector2(f * cos(a - 1.2), sin(a - 1.2))
	var tip := hand + dir * 14.0
	draw_line(hand, tip, HANDLE, 3.0)
	var across := Vector2(-dir.y, dir.x)
	match task:
		Unit.Task.DIG:
			draw_line(tip - across * 7, tip + across * 7 + dir * 2, TOOL, 3.0)
		Unit.Task.BUILD, Unit.Task.EQUIP:
			draw_rect(Rect2(tip - Vector2(4, 4), Vector2(8, 8)), TOOL)
		Unit.Task.FARM:
			draw_circle(tip, 4, Color(0.4, 0.7, 0.9))
		Unit.Task.FISH:
			# Удочка: длинное удилище и леска в воду.
			var end := hand + Vector2(f * 30, -18)
			draw_line(hand, end, HANDLE, 2.0)
			draw_line(end, end + Vector2(f * 4, 40 + sin(hand.x) * 2), Color(0.9, 0.9, 0.9, 0.7), 1.0)
		Unit.Task.HARVEST:
			draw_colored_polygon(PackedVector2Array([tip, tip + across * 8, tip + across * 6 - dir * 7]), TOOL)
