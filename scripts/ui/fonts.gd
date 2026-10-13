class_name Fonts
extends RefCounted
## Шрифты игры: Inter (лицензия OFL, см. assets/fonts/LICENSE-Inter.txt).
## Bold — основной текст, Black — заголовки и числа.

static var _bold: Font
static var _black: Font


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Inter-Bold.otf")
	return _bold


static func black() -> Font:
	if _black == null:
		_black = load("res://assets/fonts/Inter-Black.otf")
	return _black
