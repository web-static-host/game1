class_name SeasonFx
extends Node2D
## Анимация времён года поверх мира: осенью с лиственных деревьев падают листья,
## зимой над землёй идёт снег. Только для красоты, на игру не влияет.

const TILE := ChunkView.TILE
const LEAVES_PER_TREE := 2
const SNOWFLAKES := 90

var view: WorldView
var colony: Colony


## Высота земли по столбцам (рельеф не меняется) — снежинке каждый кадр нужно знать, над
## землёй ли она, а расчёт высоты — шум.
var _surf := {}
var _drawn := false


func _surface(x: int) -> int:
	var s = _surf.get(x)
	if s == null:
		s = colony.world.gen.surface_y(x)
		if _surf.size() > 20000:
			_surf.clear()
		_surf[x] = s
	return s


## Ядовитый газ над поверхностью (Венера, газовые гиганты): дымка цвета газа, у земли гуще.
## Где дегазация очистила воздух — дымка плавно рассеивается (и возвращается, если её выключить).
const HAZE_H := 14
const HAZE_FADE := 0.6
const GAS_COLORS := {"venus": Color(0.95, 0.78, 0.25), "jupiter": Color(0.9, 0.58, 0.32),
	"saturn": Color(0.92, 0.8, 0.42), "uranus": Color(0.55, 0.95, 0.55), "neptune": Color(0.45, 0.85, 0.75)}
## Густота у земли.
const HAZE_ALPHA := 0.62
## Густота дымки по столбцам 0..1 (плавно идёт к 0 над очищенным, к 1 — над ядовитым).
var _haze := {}


func _gas_sky() -> bool:
	return str(colony.world.gen.planet.get("atm", "air")) == "gas"


func _process(delta: float) -> void:
	if colony == null:
		return
	if _gas_sky():
		for x in _haze.keys():
			var target := 0.0 if colony.sky_clear(x) else 1.0
			_haze[x] = move_toward(_haze[x], target, delta * HAZE_FADE)
		queue_redraw()
		return
	# Ни снега, ни листопада — рисовать нечего (раньше слой перерисовывался каждый кадр).
	var m := ChunkView.season_m
	var active := ChunkView.snow or (m >= 8.6 and m < 11.2)
	if active or _drawn:
		queue_redraw()
	_drawn = active


func _draw() -> void:
	var world := colony.world
	var t := Time.get_ticks_msec() / 1000.0
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var a := view.local_to_cell(view.camera.position - half)
	var b := view.local_to_cell(view.camera.position + half)
	if _gas_sky():
		_draw_haze(a, b, t)
	var m := ChunkView.season_m
	if m >= 8.6 and m < 11.2:
		# Листопад.
		for x in range(a.x - 2, b.x + 3):
			if world.feature_at(x) != WorldGen.FEATURE_TREE or ChunkView.is_spruce(x):
				continue
			var fol := ChunkView.foliage(x)
			if fol[0] <= 0.02:
				continue
			var surf := _surface(x)
			if surf < a.y - 8 or surf > b.y + 2:
				continue
			var h := world.gen.tree_height(x) * TILE
			var top := view.cell_to_local(Vector2i(x, surf)) + Vector2(TILE * 0.5, -h * 0.75)
			for k in LEAVES_PER_TREE:
				var ph := WorldGen.hash01(x, k, 990)
				var fall := h * 0.8
				var p := fmod(t * (14.0 + ph * 10.0) + ph * fall, fall)
				var sway := sin(t * 2.0 + ph * TAU) * 10.0
				var c := top + Vector2((ph - 0.5) * TILE * 1.4 + sway, p)
				var col: Color = fol[1]
				var ang := sin(t * 3.0 + ph * 5.0) * 0.8
				var leaf := PackedVector2Array()
				for j in 6:
					var aa := ang + TAU * j / 6.0
					leaf.append(c + Vector2(cos(aa) * 4.5, sin(aa) * 2.2).rotated(ang))
				draw_colored_polygon(leaf, Color(col, 0.95))
	if ChunkView.snow:
		# Снегопад над землёй (под землю не залетает).
		var w := half.x * 2.0
		var hgt := half.y * 2.0
		var origin := view.camera.position - half
		for i in SNOWFLAKES:
			var hx := WorldGen.hash01(i, 1, 991)
			var hy := WorldGen.hash01(i, 2, 991)
			var sp := 30.0 + WorldGen.hash01(i, 3, 991) * 40.0
			var p := origin + Vector2(fmod(hx * w + sin(t * 0.8 + i) * 12.0 + w * 10.0, w), fmod(hy * hgt + t * sp, hgt))
			var cell := view.local_to_cell(p)
			if cell.y >= _surface(cell.x):
				continue
			draw_circle(p, 1.6 + WorldGen.hash01(i, 4, 991) * 2.0, Color(1, 1, 1, 0.85))


## Дымка: в каждом столбце — от земли вверх на HAZE_H клеток, прозрачнее кверху; постройки
## (корабль, комнаты) не закрывает — внутри воздух свой. Сверху медленно плывут клубы.
func _draw_haze(a: Vector2i, b: Vector2i, t: float) -> void:
	var gas: Color = GAS_COLORS.get(colony.world.gen.planet_id, Color(0.7, 0.85, 0.5))
	var seen := {}
	for x in range(a.x - 8, b.x + 9):
		seen[x] = true
		if not _haze.has(x):
			_haze[x] = 0.0 if colony.sky_clear(x) else 1.0
	# Густота и высота земли — по границам столбцов (среднее соседей), а не по столбцу целиком:
	# соседние столбцы сходятся без ступенек и полос. Густота сглажена по 11 столбцам.
	var k_at := {}
	for x in range(a.x - 2, b.x + 4):
		var k := 0.0
		for d in range(-5, 6):
			k += _haze[x + d]
		k /= 11.0
		k_at[x] = k * k * (3.0 - 2.0 * k)
	var edge_k := func(x: int) -> float: return (k_at[x - 1] + k_at[x]) * 0.5
	var edge_s := func(x: int) -> float: return (_surface(x - 1) + _surface(x)) * 0.5
	var alpha := func(k: float, surf: float, y: float) -> float:
		return HAZE_ALPHA * k * clampf(1.0 - (surf - y) / HAZE_H, 0.0, 1.0)
	for x in range(a.x - 1, b.x + 2):
		var kl: float = edge_k.call(x)
		var kr: float = edge_k.call(x + 1)
		if kl <= 0.005 and kr <= 0.005:
			continue
		var sl: float = edge_s.call(x)
		var sr: float = edge_s.call(x + 1)
		var surf := _surface(x)
		var top := surf - HAZE_H - 1
		if surf < a.y or top > b.y + 1:
			continue
		# Отрезки столбца вне построек — по градиенту каждый.
		var y := top
		while y < surf:
			while y < surf and colony.interior.has(Vector2i(x, y)):
				y += 1
			var y0 := y
			while y < surf and not colony.interior.has(Vector2i(x, y)):
				y += 1
			if y > y0:
				var p0 := view.cell_to_local(Vector2i(x, y0))
				var p1 := view.cell_to_local(Vector2i(x + 1, y))
				draw_polygon(PackedVector2Array([p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)]),
					PackedColorArray([Color(gas, alpha.call(kl, sl, y0)), Color(gas, alpha.call(kr, sr, y0)),
						Color(gas, alpha.call(kr, sr, y)), Color(gas, alpha.call(kl, sl, y))]))
		# Клубы: по одному на пару столбцов, плывут по ветру.
		if (x & 1) == 0:
			var ph := WorldGen.hash01(x, 7, 993)
			var drift := fmod(t * (6.0 + ph * 6.0) + ph * 60.0, 60.0)
			var c := view.cell_to_local(Vector2i(x, surf)) + Vector2(drift - 30.0, -TILE * (2.0 + ph * 6.0))
			var cell := view.local_to_cell(c)
			if not colony.interior.has(cell) and cell.y < _surface(cell.x):
				var r := TILE * (1.2 + ph * 1.4)
				draw_circle(c, r, Color(gas.lightened(0.2), 0.2 * (k_at.get(cell.x, kl) as float)))
	# Ушедшие с экрана столбцы забываем (появятся снова — сразу в нужном виде).
	if _haze.size() > 600:
		for x in _haze.keys():
			if not seen.has(x):
				_haze.erase(x)
