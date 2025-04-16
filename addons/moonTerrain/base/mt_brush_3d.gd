@tool
extends MTBase3D
class_name MTBrush3D
## Creates a large, flat mesh.

@export var curve_3d: Curve3D:
	set(x):
		if not x:
			x = Curve3D.new()
		if curve_3d:
			curve_3d.changed.disconnect(update)
		curve_3d = x
		if curve_3d:
			curve_3d.changed.connect(update)
		if not curve_3d.point_count:
			curve_3d.add_point(Vector3.ZERO)
		else:
			update()

func _generate_mesh() -> Mesh:
	if material:
		return material.generate_curve_mesh(self, curve_3d)
	return null

func _generate_collision_mesh() -> Mesh:
	if material:
		return material.generate_collision_mesh(self, curve_3d)
	return null

func _get_duplicate_check() -> Variant:
	return curve_3d

func _handle_duplicate():
	curve_3d = curve_3d.duplicate()
