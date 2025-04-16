@tool
extends RefCounted
class_name MTMesher
## A utility class for creating meshes for moonTerrain.

var st := SurfaceTool.new()
var mesh := ArrayMesh.new()
var current_height := 0.0
var current_expand := 0.0
var current_shadow := 0.0

func _start(layer: MTLayer) -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_material(layer.material)
	
func _end():
	st.generate_normals()
	st.generate_tangents()
	st.optimize_indices_for_cache()
	st.commit(mesh)
	st.clear()

## Builds a floor layer onto the internal SurfaceTool.
func build_floor(mt3d: MTBase3D, curve: Curve3D, material: MTMaterial, layer: MTLayer, flipped := false):
	current_height += layer.height
	current_expand += layer.expand
	if not layer.override_start_shadow:
		current_shadow += layer.shadow
	else:
		current_shadow = layer.start_shadow
	
	var flatten_height := mt3d.get_flatten_height()
	
	var curve_points := _get_curve_3d_points(curve)
	var point_count := curve_points.size()
	var flat_points := _get_flat_points(curve_points)
	var point_heights: Array[float] = []
	for idx in point_count:
		point_heights.append(curve_points[idx].y)
	
	_start(layer)
	st.set_normal(Vector3.UP if not flipped else Vector3.DOWN)
	
	for idx in point_count:
		var to_point := flat_points[idx] + (_get_curve_2d_normal(flat_points, idx) * current_expand)
		st.set_uv(Vector2(current_shadow, current_shadow))
		st.add_vertex(Vector3(to_point.x, (curve_points[idx].y + current_height) if not layer.flatten else flatten_height, to_point.y))
	
	# Prepare tringle adjacency.
	var point_adjacency: Dictionary[int, Array] = {}
	for idx in point_count:
		point_adjacency[idx] = [posmod(idx - 1, point_count), posmod(idx + 1, point_count)]
	
	# Begin tringulation.
	var tringles: Array[Array] = []
	
	# Loop over adjacency while it exists.
	var tests := 0
	var invalid_points := {}
	while tests < point_adjacency.size():
		tests += 1
	
		# Only one tringle remains -- add it.
		if point_adjacency.size() == 3:
			var point: int = point_adjacency.keys()[0]
			var adjacency := point_adjacency[point]
			var tringle := [point, adjacency[0], adjacency[1]]
			tringle.sort()
			tringles.append(tringle)
			break
		elif point_adjacency.size() <= 2:
			# Not enough adjacencies to build a triangle
			break
		
		# Calculate the most favorable point.
		var point := -1
		var best_height_offset := INF
		for check_point in point_adjacency:
			if check_point in invalid_points:
				continue
			var adjacency := point_adjacency[check_point]
			var height_a := point_heights[check_point]
			var height_b := point_heights[adjacency[0]]
			var height_c := point_heights[adjacency[1]]
			var height_offset := absf(height_b - height_c) # + absf(height_a - height_b) + absf(height_c - height_a)
			if best_height_offset > height_offset:
				best_height_offset = height_offset
				point = check_point
				if is_zero_approx(height_offset):
					break
		if point == -1:
			break
		
		# Begin forming a tringle quad with this point
		var adjacency := point_adjacency[point]
		var adjacency_a: int = adjacency[0]
		var adjacency_b: int = adjacency[1]
		
		# Behold, our Alpha Tringle:
		var test_tringle := [point, adjacency_a, adjacency_b]
		if _validate_tringle(flat_points, test_tringle):
			# Update adjacency.
			point_adjacency.erase(test_tringle[0])
			point_adjacency[test_tringle[1]][1] = test_tringle[2]
			point_adjacency[test_tringle[2]][0] = test_tringle[1]
			invalid_points.erase(test_tringle[1])
			invalid_points.erase(test_tringle[2])
			
			# Insert tringle or select credit type
			test_tringle.sort()
			tringles.append(test_tringle)
			tests = 0
		else:
			invalid_points[point] = null
	
	# Index the tringles.
	for tringle in tringles:
		if flipped:
			tringle.reverse()
		for v in tringle:
			st.add_index(v)
	_end()

## Builds a wall layer onto the internal SurfaceTool.
func build_wall(mt3d: MTBase3D, curve: Curve3D, material: MTMaterial, layer: MTLayer):
	if layer.override_start_shadow:
		current_shadow = layer.start_shadow
	
	var flatten_height := mt3d.get_flatten_height()
	
	var curve_points := _get_curve_3d_points(curve)
	var flat_points := _get_flat_points(curve_points)
	var point_count := curve_points.size()
	if point_count <= 1:
		return
	
	# Build every vertex.
	_start(layer)
	for idx in point_count:
		var x_ratio := float(idx) / float(point_count)
		var point := curve_points[idx]
		var flat_point := flat_points[idx]
		var normal := _get_curve_2d_normal(flat_points, idx)
		
		var in_point  := flat_point + (normal * current_expand)
		var in_point_t := Vector3(in_point.x, point.y + current_height, in_point.y)
		var out_point := flat_point + (normal * (layer.expand + current_expand))
		var out_point_t := Vector3(out_point.x, (point.y + current_height + layer.height) if not layer.flatten else flatten_height, out_point.y)
		
		st.set_uv(Vector2(current_shadow, current_shadow))
		st.add_vertex(in_point_t)
		
		st.set_uv(Vector2(current_shadow + layer.shadow, current_shadow + layer.shadow))
		st.add_vertex(out_point_t)
	
	# Set every index.
	for idx in point_count - 1:
		st.add_index(idx * 2)
		st.add_index(idx * 2 + 1)
		st.add_index(idx * 2 + 2)
		
		st.add_index(idx * 2 + 1)
		st.add_index(idx * 2 + 3)
		st.add_index(idx * 2 + 2)
	
	st.add_index((point_count * 2) - 2)
	st.add_index((point_count * 2) - 1)
	st.add_index(0)
	
	st.add_index((point_count * 2) - 1)
	st.add_index(1)
	st.add_index(0)
	
	current_height += layer.height
	current_expand += layer.expand
	current_shadow += layer.shadow
	
	_end()

#region Internal

static func _validate_tringle(big_polygon: PackedVector2Array, tringle: Array) -> bool:
	var small_polygon: Array = []
	for idx: int in tringle:
		small_polygon.append(big_polygon[idx])
	return Geometry2D.clip_polygons(small_polygon, big_polygon).size() == 0

## Returns the points of a Curve3D.
static func _get_curve_3d_points(curve: Curve3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var flat_points := PackedVector2Array()
	for idx in curve.point_count:
		points.append(curve.get_point_position(idx))
	if Geometry2D.is_polygon_clockwise(_get_flat_points(points)):
		points.reverse()
	return points

static func _get_flat_points(curve_points: PackedVector3Array) -> PackedVector2Array:
	var flat_points := PackedVector2Array()
	for p in curve_points:
		flat_points.append(Vector2(p.x, p.z))
	return flat_points

## Returns the normal of a point along a Curve3D.
static func _get_curve_2d_normal(flat_points: PackedVector2Array, idx: int) -> Vector2:
	var point_count := flat_points.size()
	while idx >= point_count:
		idx -= point_count
	while idx < 0:
		idx += point_count
	var point := flat_points[idx]
	var last_point := flat_points[(idx - 1) if idx >= 1 else point_count - 1]
	var next_point := flat_points[(idx + 1) if idx < (point_count - 1) else (idx - point_count + 1)]
	
	var angle_a := point.angle_to_point(last_point)
	var angle_b := point.angle_to_point(next_point)
	
	var normal := Vector2.from_angle((angle_a + angle_b) * 0.5)
	if Geometry2D.is_point_in_polygon(point + normal, flat_points):
		return normal.rotated(PI)
	return normal

#endregion
