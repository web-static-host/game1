class_name UnitLayer
extends Node2D
## Рисует гавриков — мультяшных существ (CreatureArt) по их генам.
## Каждого гаврика в каждой позе собираем один раз и кэшируем (DrawRecorder), а дальше
## только двигаем узел: так дёшево даже для десятков гавриков на телефоне.
## Поверх — значки нужд, имя выбранного, инструмент в руке, груз, «z» у спящих.

const TILE := ChunkView.TILE
## Ширина туловища взрослого гаврика в пикселях.
const BODY_W := 34.0
const TOOL := Color(0.45, 0.45, 0.5)
const HANDLE := Color(0.5, 0.35, 0.2)

## Позы: сдвиг кистей [левая, правая] в долях ширины, шаг ноги, закрыты ли глаза.
const POSES := {
	"idle": {},
	"blink": {"closed": true},
	"walk0": {"arms": [Vector2(0.0, -0.06), Vector2(0.0, 0.05)], "leg": 1.0},
	"walk1": {"arms": [Vector2.ZERO, Vector2.ZERO], "leg": 0.0},
	"walk2": {"arms": [Vector2(0.0, 0.05), Vector2(0.0, -0.06)], "leg": -1.0},
	"walk3": {"arms": [Vector2.ZERO, Vector2.ZERO], "leg": 0.0},
	"work0": {"arms": [Vector2.ZERO, Vector2(-0.2, -0.75)]},
	"work1": {"arms": [Vector2.ZERO, Vector2(0.05, -0.4)]},
	"work2": {"arms": [Vector2.ZERO, Vector2(0.15, 0.0)]},
	"work3": {"arms": [Vector2.ZERO, Vector2(0.05, -0.4)]},
	"climb0": {"arms": [Vector2(-0.25, -0.95), Vector2(-0.25, -0.7)], "leg": 1.0},
	"climb1": {"arms": [Vector2(-0.25, -0.7), Vector2(-0.25, -0.95)], "leg": -1.0},
	"carry0": {"arms": [Vector2(-0.35, -0.95), Vector2(-0.35, -0.95)], "leg": 1.0},
	"carry1": {"arms": [Vector2(-0.35, -0.95), Vector2(-0.35, -0.95)], "leg": 0.0},
	"carry2": {"arms": [Vector2(-0.35, -0.95), Vector2(-0.35, -0.95)], "leg": -1.0},
	"carry3": {"arms": [Vector2(-0.35, -0.95), Vector2(-0.35, -0.95)], "leg": 0.0},
	"eat": {"arms": [Vector2.ZERO, Vector2(-0.4, -0.45)]},
	"fish": {"arms": [Vector2.ZERO, Vector2(0.25, -0.35)]},
	"swim": {"arms": [Vector2(0.2, -0.45), Vector2(0.2, -0.45)]},
	"fall": {"arms": [Vector2(0.1, -0.9), Vector2(0.1, -0.9)]},
	"sleep": {"closed": true},
	"water0": {"arms": [Vector2.ZERO, Vector2(0.3, 0.02)]},
	"water1": {"arms": [Vector2.ZERO, Vector2(0.32, 0.08)]},
	"study0": {"arms": [Vector2.ZERO, Vector2(-0.3, -0.55)]},
	"study1": {"arms": [Vector2.ZERO, Vector2(-0.27, -0.6)]},
	"shovel0": {"arms": [Vector2.ZERO, Vector2(0.3, 0.05)]},
	"shovel1": {"arms": [Vector2.ZERO, Vector2(0.25, -0.55)]},
	"turn0": {"arms": [Vector2.ZERO, Vector2(0.3, -0.3)]},
	"turn1": {"arms": [Vector2.ZERO, Vector2(0.3, -0.18)]},
	"scan0": {"arms": [Vector2.ZERO, Vector2(0.3, -0.15)]},
	"scan1": {"arms": [Vector2.ZERO, Vector2(0.32, -0.05)]},
}
## Мастерская -> [инструмент, позы]: у каждой своё движение (кузница — молот, как у строителя).
const CRAFT_LOOK := {
	RoomType.KILN: ["shovel", "shovel"], RoomType.REFINERY: ["wrench", "turn"], RoomType.ENRICHMENT: ["geiger", "scan"],
}
## Инструмент в руке по делу: кирка, молоток, топор, лейка, колба, удочка.
const TOOLS := {
	Unit.Task.DIG: "pickaxe", Unit.Task.BUILD: "hammer", Unit.Task.EQUIP: "hammer", Unit.Task.REPAIR: "hammer",
	Unit.Task.SUPPORT: "hammer", Unit.Task.CRAFT: "hammer", Unit.Task.HARVEST: "axe", Unit.Task.FARM: "can",
	Unit.Task.RESEARCH: "flask", Unit.Task.FISH: "rod",
}

var view: WorldView
var colony: Colony
var selected_unit := 0
var _nodes := {}
var _overlay: Node2D
var _models: ModelSprites
## Стоящие в одной комнате не стоят в одной точке: каждому — своё место по ширине комнаты
## (только на рисунке, игра о нём не знает). id -> сдвиг по x (пиксели), куда сдвиг стремится,
## и id -> куда смотрит, пока идёт к месту (0 — уже стоит).
var _spread := {}
var _spread_to := {}
var _spread_face := {}
const SPREAD_SPEED := TILE * 1.6
## Ждущие лифт — очередью от шахты (а не толпой в одной точке), едущие — рядом в кабине:
## id -> сдвиг (пиксели) и куда смотрит.
var _lift_off := {}
var _lift_face := {}
## Остановки, где ждут кабину: [клетка шахты, сторона (-1 — шахта слева от ждущих), вверх?].
var _lift_calls: Array = []
const QUEUE_STEP := 0.45


## Узел одного гаврика. Модель рисуется куском атласа (дёшево). Рисованный гаврик — много
## фигур: каждую позу рисуем один раз в свой дочерний узел, а при смене позы только
## переключаем, какой узел виден, — без перерисовки.
class CreatureSprite:
	extends Node2D
	var looks := {}
	var pose := ""
	var cache := {}
	var _drawn := {}
	var _shown: Node2D

	func set_pose(p: String) -> void:
		if p == pose:
			return
		pose = p
		if _is_model():
			queue_redraw()
			return
		var n: Node2D = _drawn.get(p)
		if n == null:
			n = Node2D.new()
			add_child(n)
			n.draw.connect(_draw_pose.bind(n, p))
			_drawn[p] = n
		# Видимость — прямо на сервере отрисовки: смена .visible заставила бы узел перерисоваться.
		if _shown != null and _shown != n:
			RenderingServer.canvas_item_set_visible(_shown.get_canvas_item(), false)
		RenderingServer.canvas_item_set_visible(n.get_canvas_item(), true)
		_shown = n

	func _is_model() -> bool:
		return ModelSprites.shared != null and ModelSprites.shared.is_baked and ModelSprites.enabled \
			and ModelSprites.fits(looks)

	## Модель запеклась или её включили/выключили — рисуем заново.
	func reset() -> void:
		for k in _drawn:
			(_drawn[k] as Node2D).queue_free()
		_drawn.clear()
		_shown = null
		var p := pose
		pose = ""
		queue_redraw()
		set_pose(p)

	func _draw() -> void:
		if pose.is_empty() or not _is_model():
			return
		ModelSprites.draw_creature(self, pose, Vector2.ZERO, BODY_W, looks)

	func _draw_pose(n: Node2D, p: String) -> void:
		if not cache.has(p):
			var g := looks.duplicate()
			var key := ModelSprites.base_pose(p)
			g["pose"] = POSES.get(key, {})
			g["mood"] = -0.6 if p.ends_with("|sad") else 1.0
			cache[p] = CreatureArt.record(BODY_W, g)
		(cache[p] as DrawRecorder).replay(n)


func _ready() -> void:
	_models = ModelSprites.new()
	_models.baked.connect(refresh)
	add_child(_models)
	_overlay = Node2D.new()
	_overlay.z_index = 1
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	if colony == null:
		return
	_update_spread(delta)
	_update_lift_queue()
	var alive := {}
	for u in colony.units:
		alive[u.id] = true
		var node: CreatureSprite = _nodes.get(u.id)
		if node == null or not is_same(node.looks.get("_gen", null), u.genome):
			if node != null:
				node.queue_free()
			node = CreatureSprite.new()
			node.looks = Genetics.looks(u.genome) if not u.genome.is_empty() else {}
			node.looks["_gen"] = u.genome
			add_child(node)
			move_child(_overlay, -1)
			_nodes[u.id] = node
		_place(u, node)
	for id in _nodes.keys():
		if not alive.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	_overlay.queue_redraw()


## Кто стоит на месте (работает, ест, греется, ждёт) — его можно отодвинуть от соседа.
func _stationary(u: Unit) -> bool:
	return u.state in [Unit.State.WORK, Unit.State.IDLE] and u.task != Unit.Task.SLEEP and u.task != Unit.Task.FISH \
		and u.lift_id == 0


## Стоящие на полу одной комнаты не стоят друг в друге: наложившихся раздвигаем на SPREAD_GAP
## (кто стоит отдельно — на месте; на лестнице у стены — не трогаем). Сдвиг дорастает шагом.
const SPREAD_GAP := 0.85


func _update_spread(delta: float) -> void:
	var rooms := {}
	for u in colony.units:
		if not _stationary(u):
			continue
		var c := u.cell()
		var room := colony.project_at(c)
		if room == null or room.kind != Project.Kind.ROOM or room.phase != Project.Phase.DONE:
			continue
		# Только на полу комнаты (не на лестнице посреди стены).
		if c.y != room.rect.end.y - 1 or absf(u.pos.y - c.y) > 0.05:
			continue
		if not rooms.has(room.id):
			rooms[room.id] = [room]
		rooms[room.id].append(u)
	_spread_to.clear()
	for id in rooms:
		var room: Project = rooms[id][0]
		var us: Array = rooms[id].slice(1)
		if us.size() < 2:
			continue
		us.sort_custom(func(a: Unit, b: Unit) -> bool: return a.pos.x < b.pos.x or (a.pos.x == b.pos.x and a.id < b.id))
		var lo := float(RoomType.floor_start(room)) + 0.1
		var hi := float(room.rect.end.x) - 1.1
		# Раздвигаем слева направо, потом прижимаем к стенам обратно справа налево.
		var xs: Array[float] = []
		for u in us:
			xs.append(clampf(u.pos.x, lo, hi))
		for i in range(1, xs.size()):
			xs[i] = maxf(xs[i], xs[i - 1] + SPREAD_GAP)
		if xs[xs.size() - 1] > hi:
			xs[xs.size() - 1] = hi
			for i in range(xs.size() - 2, -1, -1):
				xs[i] = minf(xs[i], xs[i + 1] - SPREAD_GAP)
		for i in us.size():
			var u: Unit = us[i]
			var off := (xs[i] - u.pos.x) * TILE
			if absf(off) > 0.5:
				_spread_to[u.id] = off
	for u in colony.units:
		var cur: float = _spread.get(u.id, 0.0)
		var to: float = _spread_to.get(u.id, 0.0)
		cur = move_toward(cur, to, SPREAD_SPEED * delta * (1.0 if _stationary(u) else 3.0))
		_spread_face[u.id] = signf(to - cur) if absf(to - cur) > 2.0 and _stationary(u) else 0.0
		if absf(cur) < 0.01 and to == 0.0:
			_spread.erase(u.id)
		else:
			_spread[u.id] = cur


## Очереди у лифтов и места в кабине.
func _update_lift_queue() -> void:
	_lift_off.clear()
	_lift_face.clear()
	_lift_calls.clear()
	var queues := {}
	var cabins := {}
	for u in colony.units:
		if u.lift_id == 0 or u.lift_board >= u.path.size():
			continue
		if u.riding:
			if not cabins.has(u.lift_id):
				cabins[u.lift_id] = []
			cabins[u.lift_id].append(u)
			continue
		var board: Vector2i = u.path[u.lift_board]
		var key := "%d:%d,%d" % [u.lift_id, board.x, board.y]
		if not queues.has(key):
			queues[key] = []
		queues[key].append(u)
	for key in queues:
		var q: Array = queues[key]
		q.sort_custom(func(a: Unit, b: Unit) -> bool: return a.lift_wait > b.lift_wait or (a.lift_wait == b.lift_wait and a.id < b.id))
		var first: Unit = q[0]
		var board: Vector2i = first.path[first.lift_board]
		var exit: Vector2i = first.path[mini(first.lift_exit, first.path.size() - 1)]
		var lift := colony.project_by_id(first.lift_id)
		# Шахта — с той стороны, где клетка посадки; очередь тянется от неё назад.
		var side := signf(float(board.x) - first.pos.x)
		if side == 0.0:
			side = 1.0
		var up := (exit.y < board.y) if lift != null and lift.lift_vertical() else (exit.x > board.x)
		_lift_calls.append([board, side, up, lift != null and lift.lift_vertical()])
		for i in q.size():
			var u: Unit = q[i]
			# Первый — у самой шахты, остальные — по шагу назад; стоят лицом к лифту.
			var want := float(board.x) - side * (0.62 + QUEUE_STEP * i)
			_lift_off[u.id] = Vector2((want - u.pos.x) * TILE, 0.0)
			_lift_face[u.id] = side
	for id in cabins:
		var cab: Array = cabins[id]
		var lift := colony.project_by_id(id)
		if lift == null or not lift.lift_vertical():
			continue
		cab.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
		var w := float(lift.rect.size.x) - 0.5
		for i in cab.size():
			var u: Unit = cab[i]
			var want := float(lift.rect.position.x) + 0.25 + w * (i + 0.5) / cab.size() - 0.5
			_lift_off[u.id] = Vector2((want - u.pos.x) * TILE, 0.0)
			_lift_face[u.id] = 1.0 if i % 2 == 0 else -1.0


## Перерисовать всех (модель готова или переключили 3D / рисованных).
func refresh() -> void:
	for id in _nodes:
		(_nodes[id] as CreatureSprite).reset()


## Гаврик нарисован 3D-моделью.
func _is_model(node: CreatureSprite) -> bool:
	return _models.is_baked and ModelSprites.enabled and ModelSprites.fits(node.looks)


## Точка ступней гаврика в координатах слоя.
func foot_of(u: Unit) -> Vector2:
	var foot := view.cell_to_local(Vector2i.ZERO) + (u.pos + Vector2(0.5, 1.0)) * TILE
	# На естественном рельефе ноги ставим на сглаженную линию поверхности.
	var gen := colony.world.gen
	var cx := roundi(u.pos.x)
	var below := roundi(u.pos.y) + 1
	if u.state != Unit.State.FALL and below == gen.surface_y(cx) and not colony.world.is_dug(cx, below) \
			and not colony.interior.has(Vector2i(cx, below - 1)):
		foot.y = view.cell_to_local(Vector2i.ZERO).y + gen.surface_smooth(u.pos.x + 0.5) * TILE
	foot.x += _spread.get(u.id, 0.0)
	foot += _lift_off.get(u.id, Vector2.ZERO)
	return foot


## Кровать, в которой спит гаврик (как её рисует StructureLayer), или пустой прямоугольник.
func bed_rect(u: Unit) -> Rect2:
	if u.task != Unit.Task.SLEEP or u.state != Unit.State.WORK or u.project_id == 0 or u.bed_index < 1:
		return Rect2()
	var room := colony.project_by_id(u.project_id)
	if room == null or room.purpose != RoomType.HOME:
		return Rect2()
	var x0 := view.cell_to_local(Vector2i(RoomType.floor_start(room), 0)).x
	var floor_y := view.cell_to_local(Vector2i(0, room.rect.end.y)).y - 6
	var bx := x0 + (u.bed_index - 1) * TILE * 2 + 4
	return Rect2(bx, floor_y - 26, TILE * 2 - 8, 26)


func _scale(u: Unit) -> float:
	return lerpf(0.5, 0.9, u.growth()) if u.child else 1.0


func _place(u: Unit, node: CreatureSprite) -> void:
	var foot := foot_of(u)
	var sc := _scale(u)
	var pose := _pose(u)
	var face := _facing(u)
	var to_spot := float(_spread_face.get(u.id, 0.0)) != 0.0
	if to_spot:
		# Идёт к своему месту в комнате.
		pose = "walk%d" % (int(u.anim * 8.0) % 4)
	if u.lift_id != 0:
		# Ждёт кабину или едет — стоит, а не шагает на месте.
		pose = "blink" if fmod(u.anim + u.id * 0.37, 4.0) < 0.15 else "idle"
	var sad := u.satiety < 25.0 or u.energy < 15.0 or u.health < 40.0
	var tool: String = TOOLS.get(u.task, "") if u.state == Unit.State.WORK and not to_spot else ""
	var craft := _craft_look(u)
	if not craft.is_empty() and not tool.is_empty():
		tool = craft[0]
	node.set_pose(pose + ("@" + tool if not tool.is_empty() else "") + ("|sad" if sad else ""))
	node.rotation = 0.0
	node.position = foot
	var bob := 0.0
	if pose.begins_with("walk") or pose.begins_with("carry"):
		bob = -absf(sin(u.anim * 9.0)) * 2.0
	if to_spot:
		bob = -absf(sin(Time.get_ticks_msec() * 0.009)) * 2.0
	if pose == "sleep":
		var bed := bed_rect(u)
		if bed.size.x > 0.0:
			# В кровати: у подушки, укрыт одеялом по пояс (одеяло — в оверлее).
			node.position = Vector2(bed.position.x + 22, bed.end.y - 7)
			node.scale = Vector2(sc * 0.9, sc * 0.9)
			return
		# На полу — лежит на боку, серединой тела там, где стоял.
		var h := CreatureArt.height_of(BODY_W, node.looks) * sc
		node.rotation = -PI * 0.5 * u.facing
		node.position = foot + Vector2(u.facing * h * 0.5, -BODY_W * 0.3 * sc)
	node.position.y += bob
	node.scale = Vector2(sc * face, sc)


## Инструмент и движение мастера по его мастерской ([] — как у строителя).
func _craft_look(u: Unit) -> Array:
	if u.task != Unit.Task.CRAFT:
		return []
	var room := colony.project_by_id(u.project_id)
	if room == null:
		room = colony.project_by_id(u.workplace)
	return CRAFT_LOOK.get(room.purpose, []) if room != null else []


## Куда смотрит на рисунке: идёт к своему месту в комнате — туда, иначе как в игре.
func _facing(u: Unit) -> float:
	if _lift_face.has(u.id):
		return _lift_face[u.id]
	var f: float = _spread_face.get(u.id, 0.0)
	return f if f != 0.0 else float(u.facing)


func _pose(u: Unit) -> String:
	var frame := int(u.anim * 8.0) % 4
	match u.state:
		Unit.State.FALL:
			return "fall"
		Unit.State.SWIM:
			return "swim"
		Unit.State.MOVE:
			# Лезет — только если участок пути строго вертикальный (лестница, шахта),
			# а не шаг по склону.
			var climbing := false
			if u.path_i < u.path.size():
				var next: Vector2i = u.path[u.path_i]
				var prev: Vector2i = u.path[u.path_i - 1] if u.path_i > 0 else Vector2i(roundi(u.pos.x), roundi(u.pos.y))
				climbing = next.x == prev.x and next.y != prev.y and absf(u.pos.x - next.x) < 0.05
			if climbing:
				return "climb%d" % (frame % 2)
			if u.task == Unit.Task.HAUL and u.haul_stage == 1 and u.carry_amount > 0:
				return "carry%d" % frame
			return "walk%d" % frame
		Unit.State.WORK:
			match u.task:
				Unit.Task.SLEEP:
					return "sleep"
				Unit.Task.EAT:
					return "eat"
				Unit.Task.FISH:
					return "fish"
				Unit.Task.GOTO, Unit.Task.NONE, Unit.Task.STROLL, Unit.Task.WARM:
					return "idle"
				Unit.Task.FARM:
					return "water%d" % (int(u.anim * 2.0) % 2)
				Unit.Task.RESEARCH:
					return "study%d" % (int(u.anim * 1.5) % 2)
				Unit.Task.CRAFT:
					var look := _craft_look(u)
					if not look.is_empty():
						return "%s%d" % [look[1], int(u.anim * 2.0) % 2]
			return "work%d" % frame
	return "blink" if fmod(u.anim + u.id * 0.37, 4.0) < 0.15 else "idle"


func _draw_overlay() -> void:
	if colony == null:
		return
	var font := ThemeDB.fallback_font
	_draw_lift_calls()
	for u in colony.units:
		var node: CreatureSprite = _nodes.get(u.id)
		if node == null:
			continue
		var foot := foot_of(u)
		var sc := _scale(u)
		var h := CreatureArt.height_of(BODY_W, node.looks) * sc
		var pose := ModelSprites.base_pose(node.pose)
		if pose == "sleep":
			var bob := sin(u.anim * 2.0) * 3.0
			var bed := bed_rect(u)
			var zp := foot
			if bed.size.x > 0.0:
				# Одеяло поверх: видно голову и плечи.
				var room := colony.project_by_id(u.project_id)
				var col: Color = StructureLayer.BLANKETS[(room.id + u.bed_index - 1) % StructureLayer.BLANKETS.size()]
				var sb := StyleBoxFlat.new()
				sb.bg_color = col
				sb.set_corner_radius_all(7)
				sb.border_color = col.darkened(0.25)
				sb.set_border_width_all(1)
				_overlay.draw_style_box(sb, Rect2(bed.position.x + 8, bed.position.y + 9, bed.size.x - 8, 15))
				_overlay.draw_line(Vector2(bed.position.x + 13, bed.position.y + 13), Vector2(bed.end.x - 5, bed.position.y + 13), Color(1, 1, 1, 0.35), 2.0)
				zp = Vector2(bed.position.x + 30, bed.position.y + 6)
			_overlay.draw_string(font, Vector2(zp.x + 14, zp.y - 26 + bob), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
			_overlay.draw_string(font, Vector2(zp.x + 22, zp.y - 36 + bob), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.6))
		elif node.pose.begins_with("carry") and u.carry_amount > 0:
			# Груз над головой в поднятых руках.
			var top := -h - 8 * sc
			if _is_model(node):
				top = _models.hand_pos(pose, h / sc, node.looks).y * sc - 4 * sc
			ResIcon.draw(_overlay, u.carry_key, foot + Vector2(0, top), 10)
		elif u.state == Unit.State.WORK and _is_model(node) and _models.tool_ready(node.looks, ModelSprites.tool_of(node.pose), pose):
			# Инструмент модели — в её листе; у удочки здесь только леска от кончика.
			var tip = _models.tool_tip(pose, h / sc, node.looks, "rod") if u.task == Unit.Task.FISH else null
			if tip != null:
				var t: Vector2 = tip * sc
				t.x *= u.facing
				_overlay.draw_line(foot + t, foot + t + Vector2(u.facing * 6, 40 + sin(u.anim * 2.0) * 2), Color(0.9, 0.9, 0.9, 0.7), 1.0)
		elif u.state == Unit.State.WORK and u.task != Unit.Task.EAT:
			var g := node.looks.duplicate()
			g["pose"] = POSES.get(pose, {})
			var hand := CreatureArt.hand_pos(BODY_W, g, 1.0) * sc
			if _is_model(node):
				hand = _models.hand_pos(pose, h / sc, node.looks) * sc
			hand.x *= _facing(u)
			_draw_tool(u, foot + hand, _facing(u))
		_draw_needs(u, foot + Vector2(0, -h - 14 * sc))
		if u.id == selected_unit:
			_overlay.draw_arc(foot + Vector2(0, -h * 0.5), maxf(26.0, h * 0.75), 0, TAU, 32, Color.WHITE, 2.0)
			var w := font.get_string_size(u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var p := foot + Vector2(-w * 0.5, -h - 26)
			_overlay.draw_string_outline(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.85))
			_overlay.draw_string(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## Кнопка вызова у шахты, где ждут кабину: стрелка куда ехать, мигает.
func _draw_lift_calls() -> void:
	var lit := int(Time.get_ticks_msec() / 500) % 2 == 0
	for c in _lift_calls:
		var board: Vector2i = c[0]
		var side: float = c[1]
		var up: bool = c[2]
		var cell := view.cell_to_local(board)
		# Панель — на стене у шахты, на уровне груди (вертикальный лифт), иначе — над проходом.
		var at := Vector2(cell.x + (TILE * 0.5 - side * TILE * 0.62), cell.y + TILE * 0.05) if c[3] \
			else Vector2(cell.x + TILE * 0.5, cell.y - TILE * 0.15)
		_overlay.draw_rect(Rect2(at - Vector2(5, 8), Vector2(10, 16)), Color(0.2, 0.21, 0.25))
		_overlay.draw_rect(Rect2(at - Vector2(5, 8), Vector2(10, 16)), Color(0.08, 0.08, 0.1), false, 1.0)
		var col := Color(1.0, 0.78, 0.25) if lit else Color(0.85, 0.55, 0.15)
		var d := -1.0 if up else 1.0
		_overlay.draw_colored_polygon(PackedVector2Array([at + Vector2(0, d * 5), at + Vector2(-4, -d * 2), at + Vector2(4, -d * 2)]), col)
		if lit:
			_overlay.draw_circle(at, 9, Color(1.0, 0.8, 0.3, 0.18))


func draw_string_on(font: Font, p: Vector2, text: String, size: int, col: Color) -> void:
	_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Значки нужд над головой: голод (красный), усталость (синий), беременность, ранен.
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
		_overlay.draw_circle(c, 6, Color(0, 0, 0, 0.5))
		_overlay.draw_circle(c, 4.5, icons[i])


## Инструмент в правой руке: кирка, молоток, лейка, удочка, топор.
func _draw_tool(u: Unit, hand: Vector2, f: float) -> void:
	var a := -0.6 + sin(u.anim * 7.0) * 0.9
	var dir := Vector2(f * cos(a - 1.2), sin(a - 1.2))
	var tip := hand + dir * 12.0
	var across := Vector2(-dir.y, dir.x)
	match u.task:
		Unit.Task.DIG:
			_overlay.draw_line(hand, tip, HANDLE, 3.0)
			_overlay.draw_line(tip - across * 6, tip + across * 6 + dir * 2, TOOL, 3.0)
		Unit.Task.BUILD, Unit.Task.EQUIP, Unit.Task.REPAIR, Unit.Task.SUPPORT:
			_overlay.draw_line(hand, tip, HANDLE, 3.0)
			_overlay.draw_rect(Rect2(tip - Vector2(4, 4), Vector2(8, 8)), TOOL)
		Unit.Task.HARVEST:
			_overlay.draw_line(hand, tip, HANDLE, 3.0)
			_overlay.draw_colored_polygon(PackedVector2Array([tip, tip + across * 7, tip + across * 5 - dir * 6]), TOOL)
		Unit.Task.FISH:
			var end := hand + Vector2(f * 26, -16)
			_overlay.draw_line(hand, end, HANDLE, 2.0)
			_overlay.draw_line(end, end + Vector2(f * 4, 36 + sin(hand.x) * 2), Color(0.9, 0.9, 0.9, 0.7), 1.0)
