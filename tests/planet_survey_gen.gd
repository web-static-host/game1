extends SceneTree
## Пересобрать обследование недр планет (scripts/game/planet_survey.gd) после смены генерации:
##   godot --headless --path . -s res://tests/planet_survey_gen.gd -- earth venus mercury mars jupiter saturn uranus neptune
## и строки после «SURVEY» вставить в SURVEY.

const KEYS := {
	Mat.COAL: "coal", Mat.OIL: "oil", Mat.CLAY: "clay", Mat.IRON_ORE: "iron_ore", Mat.COPPER_ORE: "copper_ore",
	Mat.SILVER_ORE: "silver_ore", Mat.GOLD_ORE: "gold_ore", Mat.URANIUM_ORE: "uranium_ore", Mat.DIAMOND: "diamond",
	Mat.AMETHYST: "amethyst", Mat.GAS_POCKET: "gas", Mat.SANDSTONE: "sandstone", Mat.SHALE: "shale", Mat.LIMESTONE: "limestone",
	Mat.GRANITE: "granite", Mat.GNEISS: "gneiss", Mat.BASALT: "basalt", Mat.GRAPHITE: "graphite", Mat.SULFUR: "sulfur",
	Mat.GYPSUM: "gypsum", Mat.ICE: "ice", Mat.RUBY: "ruby", Mat.MAGMA: "magma", Mat.KIMBERLITE: "kimberlite",
}

func _initialize() -> void:
	var planets: Array = OS.get_cmdline_user_args()
	for pl in planets:
		var depths := {}
		var total := 0
		for sd in [3, 17, 41]:
			var g := WorldGen.new(sd, WorldGen.LATEST, pl)
			for x in range(-1500, 1500, 7):
				var surf := g.surface_y(x)
				for d in range(0, 1000, 3):
					var m := g.material_at(x, surf + d)
					total += 1
					if KEYS.has(m):
						if not depths.has(m):
							depths[m] = []
						depths[m].append(d)
		var out := []
		for m in depths:
			var a: Array = depths[m]
			a.sort()
			var n := a.size()
			if n < 20:
				continue
			out.append("\"%s\": [%.3f, %d, %d, %d]" % [KEYS[m], 100.0 * n / total, a[0], a[n / 10], a[n * 9 / 10]])
		out.sort()
		print("SURVEY\t\"%s\": {%s}," % [pl, ", ".join(out)])
	quit()
