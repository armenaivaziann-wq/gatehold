extends RefCounted
## Руки игрока от первого лица: перчатки и наручи из models/hands/gloves.glb
## (исходник art_src/hands/build_gloves.py). У перчатки и наруча одной руки общее начало
## координат — центр хвата; оси руки: +X — ось того, что рука держит (большой палец правой
## руки смотрит в -X, левой — в +X), +Y — тыльная сторона кисти, +Z — к локтю.
## Правая рука сжата под рукоять, левая — поддерживает ложе снизу.

const MODEL := preload("res://hero/models/gloves.glb")
# Из вывода скрипта сборки: радиус хвата и направление предплечья в осях руки
const POSES := {
	true: {"radius": 0.0167, "forearm": Vector3(0.042, 0.03, 0.999)},
	false: {"radius": 0.0247, "forearm": Vector3(-0.382, 0.025, 0.924)},
}

static var _meshes := {}


## Новая рука (перчатка с наручем). Добавить дочерним узлом оружия и поставить place().
static func make(right: bool) -> Node3D:
	if _meshes.is_empty():
		var scene := MODEL.instantiate()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D"):
			_meshes[mi.name] = mi.mesh
		scene.free()
	var hand := Node3D.new()
	var prefix := "Right_" if right else "Left_"
	for part in ["Glove", "Forearm"]:
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[prefix + part]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(mi)
	hand.set_meta("right", right)
	return hand


## Поставить руку в осях родителя.
## at — точка на оси того, что рука держит; axis — направление этой оси; radius — радиус ложа или
## рукояти в этом месте; elbow — куда уходит локоть.
static func place(hand: Node3D, at: Vector3, axis: Vector3, radius: float, elbow: Vector3, size := 1.0) -> void:
	var pose: Dictionary = POSES[hand.get_meta("right")]
	var f: Vector3 = pose["forearm"]
	var x := axis.normalized()
	var f_perp := Vector3(0.0, f.y, f.z).normalized()
	var local := Basis(Vector3.RIGHT, f_perp, Vector3.RIGHT.cross(f_perp))
	var e_perp := (elbow - x * x.dot(elbow)).normalized()
	var basis := Basis(x, e_perp, x.cross(e_perp)) * local.inverse()
	# Ложе толще кулака — ладонь ложится на его поверхность: сдвигаем руку наружу
	var back := (basis * Vector3.UP).normalized()
	var center := at + back * (radius - float(pose["radius"]) * size)
	hand.transform = Transform3D(basis.scaled_local(Vector3.ONE * size), center)
