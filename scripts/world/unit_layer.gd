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
}

var view: WorldView
var colony: Colony
var selected_unit := 0
var _nodes := {}
var _overlay: Node2D
var _models: ModelSprites


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
			var key := p.split("|")[0]
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


func _process(_delta: float) -> void:
	if colony == null:
		return
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
	var sad := u.satiety < 25.0 or u.energy < 15.0 or u.health < 40.0
	node.set_pose(pose + ("|sad" if sad else ""))
	node.rotation = 0.0
	node.position = foot
	var bob := 0.0
	if pose.begins_with("walk") or pose.begins_with("carry"):
		bob = -absf(sin(u.anim * 9.0)) * 2.0
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
	node.scale = Vector2(sc * u.facing, sc)


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
				Unit.Task.FARM, Unit.Task.RESEARCH:
					return "work%d" % (int(u.anim * 4.0) % 4)
			return "work%d" % frame
	return "blink" if fmod(u.anim + u.id * 0.37, 4.0) < 0.15 else "idle"


func _draw_overlay() -> void:
	if colony == null:
		return
	var font := ThemeDB.fallback_font
	for u in colony.units:
		var node: CreatureSprite = _nodes.get(u.id)
		if node == null:
			continue
		var foot := foot_of(u)
		var sc := _scale(u)
		var h := CreatureArt.height_of(BODY_W, node.looks) * sc
		var pose := node.pose.split("|")[0]
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
		elif u.state == Unit.State.WORK and u.task != Unit.Task.EAT:
			var g := node.looks.duplicate()
			g["pose"] = POSES.get(pose, {})
			var hand := CreatureArt.hand_pos(BODY_W, g, 1.0) * sc
			if _is_model(node):
				hand = _models.hand_pos(pose, h / sc, node.looks) * sc
			hand.x *= u.facing
			_draw_tool(u, foot + hand, float(u.facing))
		_draw_needs(u, foot + Vector2(0, -h - 14 * sc))
		if u.id == selected_unit:
			_overlay.draw_arc(foot + Vector2(0, -h * 0.5), maxf(26.0, h * 0.75), 0, TAU, 32, Color.WHITE, 2.0)
			var w := font.get_string_size(u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var p := foot + Vector2(-w * 0.5, -h - 26)
			_overlay.draw_string_outline(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.85))
			_overlay.draw_string(font, p, u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


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
