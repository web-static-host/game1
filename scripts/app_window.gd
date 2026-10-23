class_name AppWindow
## Окно приложения: «Назад» на Android сворачивает игру (как кнопка «Домой»), а не закрывает её.


static func minimize() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
		var activity = Engine.get_singleton("AndroidRuntime").getActivity()
		if activity != null:
			activity.moveTaskToBack(true)
			return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
