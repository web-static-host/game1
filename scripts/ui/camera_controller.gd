class_name CameraController
extends Camera2D
## Управление камерой: палец — прокрутка, два пальца — масштаб,
## колесо мыши — масштаб на ПК. В режиме копания одним пальцем «рисуем» заказы.

signal tapped(screen_pos: Vector2)
signal painted(screen_pos: Vector2, first: bool)
signal paint_ended(screen_pos: Vector2)
signal paint_cancelled

const MIN_ZOOM := 0.3
const MAX_ZOOM := 3.0
const TAP_DISTANCE := 14.0
const TAP_TIME_MS := 450

## Если true, одиночный палец рисует (рамку стройки), а камера двигается двумя пальцами.
var paint_mode := false

var _touches := {}
var _press_pos := Vector2.ZERO
var _press_time := 0
var _moved := false
var _multi := false
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(event.position, 1.0 / 1.12)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		position += event.delta * 8.0 / zoom.x


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_press_time = Time.get_ticks_msec()
			_moved = false
			_multi = false
			if paint_mode:
				painted.emit(e.position, true)
		else:
			if paint_mode and not _multi:
				paint_cancelled.emit()
			_multi = true
			_start_pinch()
	else:
		_touches.erase(e.index)
		if _touches.is_empty():
			var quick := Time.get_ticks_msec() - _press_time < TAP_TIME_MS
			if paint_mode and not _multi:
				paint_ended.emit(e.position)
			elif not _moved and not _multi and quick and not paint_mode:
				tapped.emit(e.position)
		elif _touches.size() >= 2:
			_start_pinch()
	get_viewport().set_input_as_handled()


func _on_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if e.position.distance_to(_press_pos) > TAP_DISTANCE:
		_moved = true
	if _touches.size() >= 2:
		var pts: Array = _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var mid := (a + b) * 0.5
		var dist := a.distance_to(b)
		if _pinch_dist > 1.0:
			zoom_at(mid, dist / _pinch_dist)
		position -= (mid - _pinch_mid) / zoom.x
		_pinch_dist = dist
		_pinch_mid = mid
	elif not _multi:
		if paint_mode:
			painted.emit(e.position, false)
		else:
			position -= e.relative / zoom.x
	get_viewport().set_input_as_handled()


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size * 0.5) / zoom.x


## Масштабирование так, чтобы точка под пальцем осталась на месте.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position += before - screen_to_world(screen_pos)
