# Исходники графики

Godot эту папку не импортирует (`.gdignore`) — в игру попадает только то, что из неё
подготовлено (спрайты, модели в `assets/`).

- `characters/BlueBuddy.blend` — 3D-модель жителя (синий, треугольный, один глаз), со скелетом.
- `characters/BlueBuddy.glb` — она же в glTF для экспорта и рендера.
- `characters/export_buddy.py` — экспорт в игру (`assets/models/blue_buddy.glb`): только сцена
  Buddy_Studio, риг в начале координат, тело упрощено до 30%, починены веса крайних пальцев.
  Запуск: `blender -b -P art_src/characters/export_buddy.py` (или Python с модулем `bpy`).

В игре модель не крутится в 3D постоянно: при запуске `ModelSprites` один раз рисует её
во всех позах в атлас и красит тело в цвет генов жителя.

Картинки ChatGPT и сборка их в игру (у каждой папки свой скрипт, запуск из корня проекта):
- `backgrounds/` — слои фона → `prepare.py` → `assets/background/`;
- `ground/` — пласты породы, кромки травы и снега → `prepare.py` → `assets/ground/`;
- `icons/` — листы иконок ресурсов и погоды → `cut_icons.py` → `assets/icons/`;
- `rooms/build_rooms.py` — комнаты из Blender (дерево, камень, кирпич, металл) → `assets/rooms/`.
Новые картинки можно класть прямо в `art_src/` — Claude разложит по папкам.
