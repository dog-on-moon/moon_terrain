@tool
extends EditorNode3DGizmoPlugin
class_name MTBrush3DGizmoPlugin
## An editor gizmo for a Brush3D.

const DEPTH_MATERIALS := 9

var plugin: EditorPlugin = null

func _init():
	for i in DEPTH_MATERIALS:
		create_material("depth%s" % i, Color.from_hsv(float(i) / float(DEPTH_MATERIALS), 1.0, 1.0))
	create_material("white", Color.WHITE)
	create_handle_material("handles")

var idx := 0
var current_brush: MTBrush3D = null
var start_pos := Vector3.ZERO
var creating_new_point := false

func _redraw(gizmo):
	gizmo.clear()

	current_brush = gizmo.get_node_3d()
	if not current_brush or not current_brush.curve_3d:
		return
	
	const OFFSET := Vector3.UP * 0.01
	var handle_mat := get_material("handles", gizmo)
	var white_mat := get_material("white", gizmo)
	
	var c: Curve3D = current_brush.curve_3d
	for idx in c.point_count:
		var depth_mat := get_depth_material(idx, gizmo)
		var last := idx == (c.point_count - 1)
		var point_a := c.get_point_position(idx)
		var point_b := c.get_point_position((idx + 1) if not last else 0)
		gizmo.add_lines(PackedVector3Array([point_a + (OFFSET * 1), point_b + (OFFSET * 1)]), depth_mat)
		gizmo.add_lines(PackedVector3Array([point_a + (OFFSET * 2), point_b + (OFFSET * 2)]), depth_mat)
		gizmo.add_lines(PackedVector3Array([point_a + (OFFSET * 3), point_b + (OFFSET * 3)]), depth_mat)
		gizmo.add_lines(PackedVector3Array([point_a + (OFFSET * 4), point_b + (OFFSET * 4)]), depth_mat)
		gizmo.add_handles(PackedVector3Array([point_a + OFFSET]), handle_mat, PackedInt32Array([idx]))

func get_depth_material(depth: int, gizmo) -> Material:
	return get_material("depth%s" % posmod(-depth, DEPTH_MATERIALS), gizmo)

func _has_gizmo(node):
	return node is MTBrush3D

func _get_gizmo_name() -> String:
	return "MTBrush3D"

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Point"

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	if current_brush:
		return current_brush.curve_3d.get_point_position(handle_id)
	return null

func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> void:
	idx = handle_id
	creating_new_point = Input.is_key_pressed(KEY_SHIFT)
	start_pos = current_brush.global_position + current_brush.curve_3d.get_point_position(handle_id)
	if creating_new_point:
		current_brush.curve_3d.add_point(current_brush.curve_3d.get_point_position(handle_id), Vector3.ZERO, Vector3.ZERO, idx)

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var raycast := _raycast(camera, screen_pos, gizmo.get_node_3d().get_viewport())
	raycast.position = gizmo.get_node_3d().transform.affine_inverse() * raycast.position
	if not Input.is_key_pressed(KEY_CTRL):
		var snap := get_snap()
		if not Input.is_key_pressed(KEY_ALT):
			raycast.position.x = roundf(raycast.position.x * snap) / snap
			raycast.position.z = roundf(raycast.position.z * snap) / snap
		else:
			raycast.position.y = roundf(raycast.position.y * snap) / snap
	current_brush.curve_3d.set_point_position(handle_id, raycast.position)
	_redraw(gizmo)

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var value: Vector3 = _get_handle_value(gizmo, handle_id, secondary)
	if not creating_new_point:
		if cancel:
			if current_brush.curve_3d.point_count > 1:
				current_brush.curve_3d.remove_point(handle_id)
		else:
			var undo_redo: EditorUndoRedoManager = plugin.get_undo_redo()
			undo_redo.create_action("Update Brush3D handle")
			undo_redo.add_undo_method(current_brush.curve_3d, &"set_point_position", handle_id, restore)
			undo_redo.commit_action()
	else:
		if cancel:
			current_brush.curve_3d.remove_point(handle_id)
		else:
			var undo_redo: EditorUndoRedoManager = plugin.get_undo_redo()
			undo_redo.create_action("New Brush3D point")
			undo_redo.add_undo_method(current_brush.curve_3d, &"remove_point", handle_id)
			undo_redo.commit_action()
		creating_new_point = false
	
	_redraw(gizmo)

func _raycast(camera: Camera3D, position: Vector2, viewport: Viewport) -> Dictionary:
	# Project the mouse position onto the XZ plane, call relevant events.
	var from := camera.global_position
	var to := camera.project_position(position, 10000.0)
	
	# Project onto the XZ plane using the reference pos.
	if not Input.is_key_pressed(KEY_ALT):
		var t := inverse_lerp(from.y, to.y, start_pos.y)
		var pos := from.lerp(to, t)
		return {'position': from.lerp(to, t)}
	else:
		# When we are holding alt, we lock movement to Y axis only
		var alting_pos: Vector3 = current_brush.global_transform * current_brush.curve_3d.get_point_position(idx)
		var plane_normal := (alting_pos - from)
		plane_normal.y = 0.0
		plane_normal.normalized()
		var plane := Plane(plane_normal, alting_pos)
		var intersection: Vector3 = plane.intersects_ray(from, to)
		start_pos.y = intersection.y
		return {'position': Vector3(alting_pos.x, intersection.y, alting_pos.z)}

func get_snap() -> float:
	return 1.0 / maxf(0.001, EditorInterface.get_editor_settings().get_project_metadata("3d_editor", "snap_translate_value", 1.0))
