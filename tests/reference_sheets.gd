extends SceneTree
## Листы-образцы гавриков для художника (ChatGPT): как они выглядят в игре сейчас (3D).
## 1 — формы тела и цвета, 2 — размеры (метровая линейка: 1 клетка = 1 м, комната 3 м),
## 3 — мутации. Нужен дисплей, напр. xvfb-run:
##   xvfb-run godot --path . --resolution 1600x1000 -s res://tests/reference_sheets.gd -- <папка>

var _out := "user://"
var _models: ModelSprites
var _sheets := []        # [имя, заголовок, [[подпись, гены, поза?], …], раскладка]
var _cur := -1
var _layer: CanvasLayer
var _frame := 0
var _shot_at := -1
var _wait := 0

## Размер листа — видимая область окна (у проекта своё растяжение экрана).
var W := 1600.0
var H := 1000.0
const INK := Color(0.12, 0.1, 0.18)
const BLUE := Color(0.2, 0.45, 1.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var base := {"color": BLUE, "shape": CreatureArt.Shape.TRIANGLE, "eyes": 1, "fingers": 4, "size": 0, "pattern": 0,
		"hair_color": Genetics.HAIR_COLORS[2]}
	var mk := func(over: Dictionary) -> Dictionary:
		var g := base.duplicate()
		g.merge(over, true)
		return g
	var S := CreatureArt.Shape
	# 1. Формы и цвета.
	var shapes := []
	for sh in [[S.TRIANGLE, "треугольник"], [S.SQUARE, "квадрат"], [S.ROUND, "круглый"]]:
		shapes.append([sh[1], mk.call({"shape": sh[0]})])
		shapes.append([sh[1] + ", самка", mk.call({"shape": sh[0], "female": true})])
	var cols := []
	for c in [["красный", Genetics.RED], ["оранжевый", Genetics.ORANGE], ["жёлтый", Genetics.YELLOW], ["зелёный", Genetics.GREEN],
			["синий", Genetics.BLUE], ["фиолетовый", Genetics.PURPLE], ["розовый", Genetics.PINK]]:
		cols.append([c[0], mk.call({"color": c[1]})])
	cols.append(["Супер-Гаврик", mk.call({"super": true})])
	_sheets.append(["gavriki_1_formy_cveta", "ГАВРИКИ · формы тела и цвета (вид в игре)", [shapes, cols]])
	# 2. Размеры — в одном масштабе, на одной земле.
	var sizes := []
	for s in [[-3, "кроха −3"], [-1, "кроха −1"], [0, "обычный"], [1, "гигант +1"], [2, "гигант +2"],
			[3, "гигант +3"], [5, "гигант +5"]]:
		sizes.append([s[1], mk.call({"size": s[0]})])
	sizes.append(["ребёнок", mk.call({"child": 0.55})])
	_sheets.append(["gavriki_2_razmery", "ГАВРИКИ · размеры в одном масштабе (1 клетка = 1 м, комната — 3 м)", [sizes]])
	# 3. Мутации.
	var muts := []
	for m in [["2 глаза", {"eyes": 2}], ["3 глаза", {"eyes": 3}], ["5 глаз", {"eyes": 5}], ["без глаз", {"eyes": 0}],
			["полосы", {"pattern": 1}], ["пятна", {"pattern": 2}], ["3 пальца", {"fingers": 3}], ["6 пальцев", {"fingers": 6}],
			["волосы", {"hair": true}], ["шерсть", {"fur": true}], ["длинные руки", {"long_arms": true}], ["усики", {"antennae": true}],
			["рог", {"horn": true}], ["жабры", {"gills": true}], ["панцирь", {"shell": true}], ["светится", {"glow": true}],
			["альбинос", {"albino": true}], ["меланист", {"melanist": true}], ["грустный", {"sad": true}],
			["всё сразу", {"eyes": 2, "pattern": 2, "hair": true, "horn": true, "fur": true, "gills": true}]]:
		muts.append([m[0], mk.call(m[1])])
	_sheets.append(["gavriki_3_mutacii", "ГАВРИКИ · мутации (обычный синий треугольник + одна мутация)", [muts]])
	_models = ModelSprites.new()
	root.add_child(_models)


func _all(sheet: Array) -> Array:
	var out := []
	for row in sheet[2]:
		out.append_array(row)
	return out


func _process(_delta: float) -> bool:
	_frame += 1
	if not _models.is_baked:
		return false
	if _shot_at < 0:
		var nxt := _cur + 1
		if nxt >= _sheets.size():
			return true
		var ready := true
		for it in _all(_sheets[nxt]):
			var g: Dictionary = it[1]
			ready = ModelSprites.fits(g) and ready
			for l in ModelSprites.layers_of(g, g.get("sad", false)):
				if not _models.sheets.has(l[0]):
					_models._want(l[0])
					ready = false
		_wait += 1
		if ready or _wait > 3000:
			_cur = nxt
			_wait = 0
			_build(_sheets[_cur])
			_shot_at = _frame + 4
		return false
	if _frame == _shot_at:
		var path := _out.path_join(_sheets[_cur][0] + ".png")
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		_shot_at = -1
	return false


func _build(sheet: Array) -> void:
	W = root.get_visible_rect().size.x
	H = root.get_visible_rect().size.y
	if _layer != null:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	root.add_child(_layer)
	_add(func(ci: CanvasItem) -> void:
		ci.draw_rect(Rect2(0, 0, W, H), Color(0.78, 0.88, 0.96))
		ci.draw_string(ThemeDB.fallback_font, Vector2(0, 52), sheet[1], HORIZONTAL_ALIGNMENT_CENTER, W, 34, INK))
	if sheet[0] == "gavriki_2_razmery":
		_build_sizes(sheet[2][0])
		return
	var rows: Array = sheet[2]
	var lines := []
	for row in rows:
		var per: int = 10 if row.size() > 10 else row.size()
		for i in range(0, row.size(), per):
			lines.append(row.slice(i, i + per))
	var row_h := (H - 110.0) / lines.size()
	var w := minf((W - 140.0) / 10.0 * 0.6, row_h * 0.42)
	for li in lines.size():
		var line: Array = lines[li]
		var y := 100.0 + row_h * (li + 0.5) + w * 0.6
		for i in line.size():
			var x := 70.0 + (W - 140.0) * (i + 0.5) / line.size()
			_creature(line[i], Vector2(x, y), w)


## Размеры: все на одной земле, слева — метровая линейка и высота комнаты.
func _build_sizes(items: Array) -> void:
	var ground := H - 120.0
	# Каждому — место по его ширине (с руками и зазором, м); масштаб — чтобы все влезли в ряд.
	var ks := []
	var sum_m := 0.0
	for it in items:
		var g: Dictionary = it[1]
		var k := CreatureArt.size_scale(int(g.get("size", 0))) * float(g.get("child", 1.0))
		ks.append(k)
		sum_m += k * 1.75 * UnitLayer.BODY_W / ChunkView.TILE + 0.15
	var span := W - 200.0
	var px := minf((ground - 140.0) / 4.0, span / sum_m)     # пикселей на метр
	var w := UnitLayer.BODY_W / ChunkView.TILE * px   # ширина тела в игре (BODY_W на клетку 1 м)
	_add(func(ci: CanvasItem) -> void:
		var font := ThemeDB.fallback_font
		ci.draw_rect(Rect2(0, ground, W, H - ground), Color(0.55, 0.42, 0.3))
		ci.draw_line(Vector2(0, ground), Vector2(W, ground), INK, 2.0)
		# Линейка: метры до 4.
		for m in 5:
			var y := ground - m * px
			ci.draw_line(Vector2(40, y), Vector2(60, y), INK, 2.0)
			ci.draw_string(font, Vector2(70, y + 6), "%d м" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
			# Сетка клеток (1 м) — тонко.
			ci.draw_line(Vector2(110, y), Vector2(W - 20, y), Color(1, 1, 1, 0.35), 1.0)
		ci.draw_line(Vector2(40, ground), Vector2(40, ground - 4 * px), INK, 2.0)
		# Высота комнаты (3 м) — пунктир.
		var ry := ground - 3.0 * px
		ci.draw_dashed_line(Vector2(110, ry), Vector2(W - 20, ry), Color(0.85, 0.2, 0.2), 2.5, 10.0)
		ci.draw_string(font, Vector2(118, ry - 8), "потолок комнаты — 3 м", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.1, 0.1)))
	var x := 170.0 + (span - sum_m * px) * 0.5
	for i in items.size():
		var cw: float = (float(ks[i]) * 1.75 * UnitLayer.BODY_W / ChunkView.TILE + 0.15) * px
		_creature(items[i], Vector2(x + cw * 0.5, ground), w, true, 34.0 if i % 2 == 0 else 62.0)
		x += cw


func _creature(it: Array, at: Vector2, w: float, under := false, label_y := 30.0) -> void:
	var g: Dictionary = it[1]
	var sc := 1.0
	if g.has("child"):
		sc = float(g["child"])
	var pose := "idle" + ("|sad" if g.get("sad", false) else "")
	var name: String = it[0]
	# Модель и подпись — разными узлами: модель ставит узлу свой шейдер, текст с ним не рисуется.
	_add(func(ci: CanvasItem) -> void: ModelSprites.draw_creature(ci, pose, at, w * sc, g))
	_add(func(ci: CanvasItem) -> void:
		ci.draw_string(ThemeDB.fallback_font, Vector2(at.x - 90, at.y + label_y), name,
			HORIZONTAL_ALIGNMENT_CENTER, 180, 18, INK))


func _add(f: Callable) -> void:
	var n := Node2D.new()
	n.draw.connect(f.bind(n))
	_layer.add_child(n)
