class_name Fmt
extends RefCounted
## Форматирование чисел и времени для интерфейса.


## 1234567 -> "1 234 567"
static func int_spaced(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return "-" + out if neg else out


static func duration(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%d сек" % s
	if s < 3600:
		return "%d мин" % (s / 60)
	return "%d ч %d мин" % [s / 3600, (s % 3600) / 60]
