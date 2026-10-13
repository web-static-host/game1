class_name SeasonFx
extends Node2D
## Анимация времён года поверх мира: осенью с лиственных деревьев падают листья,
## зимой над землёй идёт снег. Только для красоты, на игру не влияет.

const TILE := ChunkView.TILE
const LEAVES_PER_TREE := 2
const SNOWFLAKES := 90

var view: WorldView
var colony: Colony


func _process(_delta: float) -> void:
	if colony != null:
		queue_redraw()


func _draw() -> void:
	var world := colony.world
	var t := Time.get_ticks_msec() / 1000.0
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var a := view.local_to_cell(view.camera.position - half)
	var b := view.local_to_cell(view.camera.position + half)
	var m := ChunkView.season_m
	if m >= 8.6 and m < 11.2:
		# Листопад.
		for x in range(a.x - 2, b.x + 3):
			if world.feature_at(x) != WorldGen.FEATURE_TREE or ChunkView.is_spruce(x):
				continue
			var fol := ChunkView.foliage(x)
			if fol[0] <= 0.02:
				continue
			var surf := world.gen.surface_y(x)
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
			if cell.y >= world.gen.surface_y(cell.x):
				continue
			draw_circle(p, 1.6 + WorldGen.hash01(i, 4, 991) * 2.0, Color(1, 1, 1, 0.85))
