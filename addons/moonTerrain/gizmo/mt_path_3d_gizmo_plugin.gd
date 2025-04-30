@tool
extends EditorNode3DGizmoPlugin
class_name MTPath3DGizmoPlugin
## An editor gizmo for a MTPath3D.

const DEPTH_MATERIALS := 8

var plugin: EditorPlugin = null

func _init():
	for i in DEPTH_MATERIALS:
		create_material("depth%s" % i, Color.from_hsv(float(i) / float(DEPTH_MATERIALS), 1.0, 1.0))
	create_material("white", Color.WHITE)
	create_handle_material("handles")

var idx := 0
var idx_to_curve: Dictionary[int, TreeCurve3D] = {}
var start_pos := Vector3.ZERO

var creating_new_point := false
var new_point: TreeCurve3D = null

func _redraw(gizmo):
	if gizmo.get_node_3d():
		var old_mtp3d: MTPath3D = gizmo.get_node_3d()
		if old_mtp3d.curve_updated.is_connected(_redraw.bind(gizmo)):
			old_mtp3d.curve_updated.disconnect(_redraw.bind(gizmo))
	gizmo.clear()
	idx = 0
	idx_to_curve.clear()

	var mt_path_3d: MTPath3D = gizmo.get_node_3d()
	if not mt_path_3d.curve_updated.is_connected(_redraw.bind(gizmo)):
		mt_path_3d.curve_updated.connect(_redraw.bind(gizmo))
	if mt_path_3d.tree_curve_3d:
		_recursive_build_gizmo(mt_path_3d.tree_curve_3d, gizmo)

func _recursive_build_gizmo(curve: TreeCurve3D, gizmo: EditorNode3DGizmo, depth := 0):
	# Build lines and handles with our local leaves.
	const OFFSET := Vector3.UP * 0.01
	var main_mat := get_depth_material(depth, gizmo)
	var handle_mat := get_material("handles", gizmo)
	var white_mat := get_material("white", gizmo)
	for leaf in curve.leaves:
		gizmo.add_lines(PackedVector3Array([curve.position + OFFSET, leaf.position + OFFSET]), white_mat)
		gizmo.add_lines(PackedVector3Array([curve.position + OFFSET * 2, leaf.position + OFFSET * 2]), main_mat)
		gizmo.add_lines(PackedVector3Array([curve.position + OFFSET * 3, leaf.position + OFFSET * 3]), main_mat)
		gizmo.add_lines(PackedVector3Array([curve.position + OFFSET * 4, leaf.position + OFFSET * 4]), main_mat)
		gizmo.add_lines(PackedVector3Array([curve.position + OFFSET * 5, leaf.position + OFFSET * 5]), main_mat)
	
	gizmo.add_handles(PackedVector3Array([curve.position + OFFSET]), handle_mat, PackedInt32Array([idx]))
	idx_to_curve[idx] = curve
	idx += 1
	
	# Progress gizmo development.
	for leaf in curve.leaves:
		_recursive_build_gizmo(leaf, gizmo, depth + 1)

func _has_gizmo(node):
	return node is MTPath3D

func _get_gizmo_name() -> String:
	return "MTPath3D"

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Leaf"

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	if handle_id in idx_to_curve:
		return idx_to_curve[handle_id].position
	return null

func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> void:
	if handle_id not in idx_to_curve:
		return
	creating_new_point = Input.is_key_pressed(KEY_SHIFT)
	start_pos = idx_to_curve[handle_id].position + gizmo.get_node_3d().global_position
	if creating_new_point:
		new_point = TreeCurve3D.new()
		var curve := idx_to_curve[handle_id]
		new_point.position = curve.position
		curve.force_attach_leaf(new_point)

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	if handle_id not in idx_to_curve:
		return
	var curve := idx_to_curve[handle_id]
	var point_pos: Vector3
	if not creating_new_point:
		point_pos = gizmo.get_node_3d().transform * curve.position
	else:
		point_pos = gizmo.get_node_3d().transform * new_point.position
	var raycast := _raycast(gizmo, camera, screen_pos, gizmo.get_node_3d().get_viewport(), curve, point_pos)
	raycast.position = gizmo.get_node_3d().transform.affine_inverse() * raycast.position
	if not Input.is_key_pressed(KEY_CTRL):
		var snap := get_snap()
		if not Input.is_key_pressed(KEY_ALT):
			raycast.position.x = roundf(raycast.position.x * snap) / snap
			raycast.position.z = roundf(raycast.position.z * snap) / snap
		else:
			raycast.position.y = roundf(raycast.position.y * snap) / snap
	if not creating_new_point:
		curve.position = raycast.position
	else:
		new_point.position = raycast.position
	_redraw(gizmo)

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	if handle_id not in idx_to_curve:
		return
	var curve := idx_to_curve[handle_id]
	var value: Vector3 = _get_handle_value(gizmo, handle_id, secondary)
	if not creating_new_point:
		if cancel:
			curve.detach()
		else:
			var undo_redo: EditorUndoRedoManager = plugin.get_undo_redo()
			undo_redo.create_action("Update MTPath3D handle")
			undo_redo.add_undo_property(curve, &"position", restore)
			undo_redo.commit_action()
			_redraw(gizmo)
	else:
		if cancel:
			new_point.detach()
		else:
			var undo_redo: EditorUndoRedoManager = plugin.get_undo_redo()
			undo_redo.create_action("New MTPath3D leaf")
			undo_redo.add_undo_method(new_point, &"detach")
			undo_redo.commit_action()
			_redraw(gizmo)
		creating_new_point = false
		new_point = null

func get_depth_material(depth: int, gizmo) -> Material:
	return get_material("depth%s" % (depth % DEPTH_MATERIALS), gizmo)

func _raycast(gizmo, camera: Camera3D, position: Vector2, viewport: Viewport, curve: TreeCurve3D, point_pos) -> Dictionary:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Mouse position is locked onto whatever plane we're looking at.
		var from := camera.project_position(position, 0.0)
		var to := camera.project_position(position, 0.01)
		
		var plane := Plane(camera.basis.z, point_pos)
		var intersection := plane.intersects_ray(from, to - from)
		if intersection:
			return {'position': intersection}
		else:
			return {'position': point_pos}
	
	# Project the mouse position onto the XZ plane, call relevant events.
	var from := camera.global_position
	var to := camera.project_position(position, 10000.0)
	
	# Also perform a raycast.
	var ray_from := camera.project_ray_origin(position)
	var ray_to := ray_from + camera.project_ray_normal(position) * 10000.0
	var space := viewport.find_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = from
	ray_query.to = to
	ray_query.collide_with_areas = true
	ray_query.collision_mask = (2 ** 32) - 1
	#ray_query.collision_mask |= 1 << (32 - 1)  # terrain mask
	#ray_query.collision_mask |= 1 << (31 - 1)  # editor scenes
	#ray_query.collision_mask |= 1 << (30 - 1)  # editor doors
	var raycast := space.intersect_ray(ray_query)
	if raycast and Input.is_key_pressed(KEY_SPACE):
		return raycast
	
	# Raycast failed, so now we will re-project onto the XZ plane using the reference pos.
	if not Input.is_key_pressed(KEY_ALT):
		var t := inverse_lerp(from.y, to.y, start_pos.y)
		var pos := from.lerp(to, t)
		return {'position': from.lerp(to, t)}
	else:
		# When we are holding alt, we lock movement to Y axis only
		var alting_pos := Vector3.ZERO
		if not creating_new_point:
			alting_pos = gizmo.get_node_3d().global_transform * curve.position
		else:
			alting_pos = gizmo.get_node_3d().global_transform * new_point.position
		var plane_normal := (alting_pos - from)
		plane_normal.y = 0.0
		plane_normal.normalized()
		var plane := Plane(plane_normal, alting_pos)
		var intersection: Vector3 = plane.intersects_ray(from, to)
		start_pos.y = intersection.y
		return {'position': Vector3(alting_pos.x, intersection.y, alting_pos.z)}

func get_snap() -> float:
	return 1.0 / maxf(0.001, EditorInterface.get_editor_settings().get_project_metadata("3d_editor", "snap_translate_value", 1.0))
