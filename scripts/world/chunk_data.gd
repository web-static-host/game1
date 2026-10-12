class_name ChunkData
extends RefCounted
## Квадрат мира SIZE×SIZE клеток. 1 клетка = 1 метр.

const SIZE := 32
const SHIFT := 5 # log2(SIZE)
const MASK := SIZE - 1

const F_REVEALED := 1 # игрок знает, что в клетке
const F_DUG := 2 # клетка выкопана игроком
const F_CAVE := 4 # природная полость под землёй (воздух/вода)

var cx: int
var cy: int
## Природный материал клетки (Mat.*).
var mat := PackedByteArray()
var flags := PackedByteArray()
## Чанк отличается от сгенерированного — его нужно сохранять.
var modified := false
## Изменились сами материалы (осыпь, обломки) — сохраняем и их.
var mat_modified := false


func _init(p_cx: int, p_cy: int) -> void:
	cx = p_cx
	cy = p_cy
	mat.resize(SIZE * SIZE)
	flags.resize(SIZE * SIZE)


static func idx(lx: int, ly: int) -> int:
	return (ly << SHIFT) | lx


## Материал с учётом раскопок.
func effective(i: int) -> int:
	return Mat.AIR if flags[i] & F_DUG else mat[i]
