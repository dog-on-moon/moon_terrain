@tool
extends MTBase3D
class_name MTPath3D
## Creates a branching path.

@export var tree_curve_3d: TreeCurve3D:
	set(x):
		if not x:
			x = TreeCurve3D.new()
		if tree_curve_3d:
			tree_curve_3d.curve_updated.disconnect(update)
		tree_curve_3d = x
		if tree_curve_3d:
			tree_curve_3d.curve_updated.connect(update)
		update()

func _generate_mesh() -> Mesh:
	if material:
		return material.generate_curve_mesh(self, tree_curve_3d.generate_perimeter_curve(material.path_width, material.path_endcap_distance))
	return null

func _generate_collision_mesh() -> Mesh:
	if material:
		return material.generate_collision_mesh(self, tree_curve_3d.generate_perimeter_curve(material.path_width, material.path_endcap_distance))
	return null

func _get_duplicate_check() -> Variant:
	return tree_curve_3d

func _handle_duplicate():
	tree_curve_3d = tree_curve_3d.duplicate_deep()
