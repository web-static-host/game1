class_name NameGen
extends RefCounted
## Имена гавриков: свои, из двух-трёх слогов — Бубо, Тикаша, Зумаро, Милена, Пакос…
## Слоги в основном простые (согласная + гласная); редкие сочетания согласных
## («бр», «кл», «шм», «зв»…) — изредка, для разнообразия.
## Женские — на гласную, мужские — на согласную или «о».

const CONSONANTS := ["б", "в", "г", "д", "ж", "з", "к", "л", "м", "н", "п", "р", "с", "т", "ф", "х", "ч", "ш"]
const CLUSTERS := ["бр", "гр", "кр", "пр", "тр", "др", "вр", "фр", "бл", "гл", "кл", "пл", "фл", "сл", "ст", "ск",
	"сп", "шм", "шп", "зв", "тв", "кв", "хр", "зл", "мр", "дз"]
const VOWELS := ["а", "о", "у", "и", "е", "ю", "я", "а", "о", "у", "и", "е"]
const MALE_ENDS := ["к", "н", "м", "с", "р", "п", "ф", "ш", "б", "т", "л", "х", "кс", "нт", "о", "о"]
const FEMALE_ENDS := ["", "", "", "ла", "на", "ка", "ша", "ля", "ра", "ма", "я", "та"]
## Как часто слог начинается с сочетания согласных.
const CLUSTER_CHANCE := 0.1


static func make(rng: RandomNumberGenerator, female: bool) -> String:
	var s := ""
	var syllables := 2 if rng.randf() < 0.65 else 3
	for i in syllables:
		var onset: String = CONSONANTS[rng.randi() % CONSONANTS.size()]
		if rng.randf() < CLUSTER_CHANCE:
			onset = CLUSTERS[rng.randi() % CLUSTERS.size()]
		s += onset + VOWELS[rng.randi() % VOWELS.size()]
	if female:
		# Окончание-слог — только у двусложных, чтобы не выходило длиннее трёх слогов.
		var end: String = FEMALE_ENDS[rng.randi() % FEMALE_ENDS.size()] if syllables == 2 else ""
		s += end
	else:
		var end: String = MALE_ENDS[rng.randi() % MALE_ENDS.size()]
		if end == "о":
			# «о» заменяет последнюю гласную: Бубо, а не Бубао.
			s = s.substr(0, s.length() - 1) + "о"
		else:
			s += end
	# Русская орфография: после ж, ш, ч — «у» и «а», а не «ю» и «я».
	for c in ["ж", "ш", "ч"]:
		s = s.replace(c + "ю", c + "у").replace(c + "я", c + "а")
	for pair in ["аа", "оо", "уу", "ии", "ее", "яя", "юю", "ая", "ея", "ия"]:
		s = s.replace(pair, pair.substr(0, 1))
	return s.substr(0, 1).to_upper() + s.substr(1)
