class_name NameGen
extends RefCounted
## Имена жителей: свои, из слогов — Бубо, Тиньк, Крупп, Зульма, Фляна…
## Женские чаще кончаются на гласную, мужские — на согласную или «о».

const ONSETS := ["б", "в", "г", "д", "ж", "з", "к", "л", "м", "н", "п", "р", "с", "т", "ф", "х", "ц", "ч", "ш", "щ",
	"бр", "вр", "гр", "др", "кр", "пр", "тр", "фр", "бл", "гл", "кл", "пл", "фл", "шл", "сл", "зв", "шм", "шп", "ст",
	"ск", "сп", "тв", "дз", "кв", "хр", "чп", "гв", "зл", "мр", "пш", "тш", "", ""]
const VOWELS := ["а", "о", "у", "и", "е", "ы", "ю", "я", "э", "а", "о", "у", "и"]
const CODAS := ["", "", "", "н", "р", "к", "м", "с", "ш", "ль", "ф", "п", "ст", "нк", "рк", "нт", "мп", "ш", "ц", "х",
	"ньк", "рп", "лк", "т", "б", "г", "з", "в"]
const MALE_ENDS := ["", "", "", "о", "ик", "ун", "ош", "ам", "ур", "ек", "ус", "ак", "ох", "иф", "ет", "ыр"]
const FEMALE_ENDS := ["а", "я", "и", "ла", "на", "ша", "ка", "ля", "ри", "ма", "та", "ня", "са", "ва", "ли", "за"]


static func make(rng: RandomNumberGenerator, female: bool) -> String:
	var s := ""
	var syllables := 1 + int(rng.randf() < 0.75) + int(rng.randf() < 0.2)
	for i in syllables:
		s += ONSETS[rng.randi() % ONSETS.size()] + VOWELS[rng.randi() % VOWELS.size()]
		if i < syllables - 1 and rng.randf() < 0.3:
			s += CODAS[rng.randi() % CODAS.size()]
	if female:
		s += FEMALE_ENDS[rng.randi() % FEMALE_ENDS.size()]
	else:
		s += CODAS[rng.randi() % CODAS.size()] if rng.randf() < 0.6 else MALE_ENDS[rng.randi() % MALE_ENDS.size()]
	# Убираем неудобные стыки: две гласные подряд из одного слога сливаем.
	for pair in ["аа", "оо", "уу", "ии", "ыы", "ее", "яя", "юю", "ээ", "ыи", "йй"]:
		s = s.replace(pair, pair.substr(0, 1))
	if s.length() < 3:
		s += "ко" if not female else "ма"
	return s.substr(0, 1).to_upper() + s.substr(1)
