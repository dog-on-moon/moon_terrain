@tool
extends Resource
class_name TreeCurve3D
## A recursive tree resource, describing a nested path in 3D space.

signal curve_updated
signal detach_requested(leaf: TreeCurve3D)
signal delete_requested

@export var leaves: Array[TreeCurve3D] = []:
	set(x):
		for l in leaves:
			if l:
				if l.curve_updated.is_connected(curve_updated.emit):
					l.curve_updated.disconnect(curve_updated.emit)
				if l.detach_requested.is_connected(_handle_detach):
					l.detach_requested.disconnect(_handle_detach)
				l.root = true
		leaves = x
		_update_leaf_signals()
		curve_updated.emit()

@export var position := Vector3.ZERO:
	set(x):
		position = x
		position2 = Vector2(x.x, x.z)
		curve_updated.emit()

var position2 := Vector2.ZERO

@export_storage var root := true

## Attaches a new leaf to the tree, parenting it to the leaf nearest to it.
func attach_leaf(leaf: TreeCurve3D):
	var parent := get_nearest_leaf(leaf.position)
	parent.force_attach_leaf(leaf)

## Attaches a new position to the tree, parented to the leaf nearest to it.
func attach_pos(pos: Vector3):
	var new_leaf := TreeCurve3D.new()
	new_leaf.position = pos
	var parent := get_nearest_leaf(pos)
	parent.force_attach_leaf(new_leaf)

## Force attaches a leaf to the tree, not sorting it by position.
func force_attach_leaf(leaf: TreeCurve3D):
	leaves.append(leaf)
	_update_leaf_signals()
	curve_updated.emit()

## Call this to detach this node from the rest of the tree.
func detach():
	if not root:
		# Let our parent detach us.
		detach_requested.emit(self)
	else:
		# As the parent, we special handle detaching ourselves.
		# We do this by merging with our 0th leaf.
		if leaves:
			var new_leaf: TreeCurve3D = leaves.pop_at(0)
			leaves.append_array(new_leaf.leaves)
			_update_leaf_signals()
			position = new_leaf.position
		else:
			# We have no leaves. We request for God to kill us.
			delete_requested.emit()

# Handles detaching a child leaf.
func _handle_detach(l: TreeCurve3D):
	assert(l in leaves)
	var new_leaves := leaves.duplicate()
	new_leaves.append_array(l.leaves)
	new_leaves.erase(l)
	leaves = new_leaves

# Updates leaf signals.
func _update_leaf_signals():
	for l in leaves:
		if l:
			if not l.curve_updated.is_connected(curve_updated.emit):
				l.curve_updated.connect(curve_updated.emit)
			if not l.detach_requested.is_connected(_handle_detach):
				l.detach_requested.connect(_handle_detach)
			l.root = false

## Returns the node in the tree closest to this position.
func get_nearest_leaf(pos: Vector3) -> TreeCurve3D:
	var best_dist := INF
	var best_leaf: TreeCurve3D = null
	for node in get_all_nodes():
		var dist := node.position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_leaf = node
	return best_leaf

## Returns all nodes in the tree curve.
func get_all_nodes() -> Array[TreeCurve3D]:
	var a: Array[TreeCurve3D] = [self]
	for l in leaves:
		a.append_array(l.get_all_nodes())
	return a

## Returns nodes in clockwise order.
func get_clockwise_nodes(parent: TreeCurve3D = null) -> Array[TreeCurve3D]:
	var l := leaves.duplicate()
	if parent:
		# Sort leaves by clockwise-angle relative to parent.
		var parent_angle := position2.angle_to_point(parent.position2)
		l.sort_custom(
			func (a: TreeCurve3D, b: TreeCurve3D):
				return (
					cw_angle_difference(  parent_angle, position2.angle_to_point(a.position2))
					> cw_angle_difference(parent_angle, position2.angle_to_point(b.position2))
				)
		)
		l.append(parent)
	else:
		# Doesnt matter which one we start on, as long as they are clockwise.
		l.sort_custom(
			func (a: TreeCurve3D, b: TreeCurve3D):
				return (
					cw_angle_difference  (0.0, position2.angle_to_point(a.position2))
					> cw_angle_difference(0.0, position2.angle_to_point(b.position2))
				)
		)
	return l

## Returns the curve as a tree string.
func get_tree_string(tab_count := 0):
	var tab_chars := "\t".repeat(tab_count)
	if tab_chars:
		tab_chars += " -> "
	var s := "%s%s" % [tab_chars, position]
	for child in leaves:
		s += "\n%s" % [child.get_tree_string(tab_count + 1)]
	return s

## Generates a perimeter around the TreeCurve3D.
func generate_perimeter_curve(distance := 1.0, end_distance := 1.0, t := Transform3D.IDENTITY, closed := false) -> Curve3D:
	var c := Curve3D.new()
	for point in _recursive_get_perimeter_points(distance, end_distance, null, closed):
		c.add_point(t * point)
	return c

const DEBUG_PRINT_PERIMETER := false

func _recursive_get_perimeter_points(distance: float, end_distance: float, parent: TreeCurve3D = null, closed := false) -> PackedVector3Array:
	var points := PackedVector3Array()
	
	# Get our clockwise nodes.
	var cw_nodes := get_clockwise_nodes(parent)
	var is_leaf := cw_nodes.size() <= 1
	if not is_leaf:
		for idx in cw_nodes.size():
			# Get our adjacent nodes.
			var this := cw_nodes[idx]
			var prev := cw_nodes[(idx - 1) if idx != 0 else -1]
			
			# Create tangent lines for each curve.
			var angle_a := cw_angle_difference(0.0, position2.angle_to_point(prev.position2))
			var angle_b := cw_angle_difference(0.0, position2.angle_to_point(this.position2))
			
			var vec_a := Vector2.from_angle(angle_a) * Vector2(1, -1)
			var vec_b := Vector2.from_angle(angle_b) * Vector2(1, -1)
			
			var start_angle_a := angle_a - (PI * 0.5)
			var start_angle_b := angle_b + (PI * 0.5)
			
			var start_dir_a := (Vector2.from_angle(start_angle_a) * distance) * Vector2(1, -1)
			var start_dir_b := (Vector2.from_angle(start_angle_b) * distance) * Vector2(1, -1)
			
			var start_a := position2 + start_dir_a
			var start_b := position2 + start_dir_b
			
			var intersection := Geometry2D.line_intersects_line(start_a, vec_a, start_b, vec_b)
			
			#Log.dict(self, {
				#curve = curve.position2,
				#prev = prev.position2,
				#this = this.position2,
				#angle_a = angle_a,
				#angle_b = angle_b,
				#vec_a = vec_a,
				#vec_b = vec_b,
				#start_angle_a = start_angle_a,
				#start_angle_b = start_angle_b,
				#start_dir_a = start_dir_a,
				#start_dir_b = start_dir_b,
				#start_a = start_a,
				#start_b = start_b,
				#intersection = intersection,
			#})
			
			if intersection != null:
				# Math!
				var ivec: Vector2 = intersection
				var isec_point := Vector3(ivec.x, position.y, ivec.y)
				
				var has_counter_points := cw_angle_difference(angle_a, angle_b) > PI
				if not has_counter_points:
					#if DEBUG_PRINT_PERIMETER:
						#Log.dict(self, {
							#case = "Acute intersection",
							#angle_a = roundi(rad_to_deg(angle_a)),
							#angle_b = roundi(rad_to_deg(angle_b)),
							#angle_diff = roundi(rad_to_deg(DogUtils.cw_angle_difference(angle_a, angle_b))),
							#isec_point = isec_point
						#})
					points.append(isec_point)
				else:
					var core_to_intersection_angle := position2.angle_to_point(ivec)
					var angle_offset := PI - absf(angle_difference(angle_b, angle_a))
					var ccw_angle := core_to_intersection_angle + angle_offset
					var cw_angle  := core_to_intersection_angle - angle_offset
					var offset_distance := distance
					var flat_ccw_point := Geometry2D.line_intersects_line(start_b, vec_b, position2, Vector2.from_angle(ccw_angle))
					var flat_cw_point  := Geometry2D.line_intersects_line(position2, Vector2.from_angle(cw_angle), start_a, vec_a)
					
					#if DEBUG_PRINT_PERIMETER:
						#Log.dict(self, {
							#case = "Obtuse intersection",
							#position2 = position2,
							#core_to_intersection_angle = roundi(rad_to_deg(core_to_intersection_angle)),
							#angle_a = roundi(rad_to_deg(angle_a)),
							#angle_b = roundi(rad_to_deg(angle_b)),
							#angle_offset_pre = roundi(rad_to_deg(angle_difference(angle_b, angle_a))),
							#angle_offset = roundi(rad_to_deg(angle_offset)),
							#ccw_angle = roundi(rad_to_deg(ccw_angle)),
							#cw_angle = roundi(rad_to_deg(cw_angle)),
							#offset_distance = offset_distance,
							#flat_cw_point = flat_cw_point,
							#ivec = ivec,
							#flat_ccw_point = flat_ccw_point,
						#})
					
					# Add all points.
					if flat_cw_point != null:
						var cw_point := Vector3(flat_cw_point.x,  position.y, flat_cw_point.y)
						if not cw_point.is_equal_approx(isec_point):
							points.append(cw_point)
					
					points.append(isec_point)
					
					if flat_ccw_point != null:
						var ccw_point := Vector3(flat_ccw_point.x, position.y, flat_ccw_point.y)
						if not ccw_point.is_equal_approx(isec_point):
							points.append(ccw_point)
			else:
				#if DEBUG_PRINT_PERIMETER:
					#Log.dict(self, {
						#case = "Invalid intersection",
						#invalid_point = Vector3(start_a.x, position.y, start_a.y)
					#})
				points.append(Vector3(start_a.x, position.y, start_a.y))
			
			if this != parent:
				points.append_array(this._recursive_get_perimeter_points(distance, end_distance, self))
	else:
		# We are a leaf, so create an endcap.
		var build := false
		var angle := 0.0
		if not parent:
			if cw_nodes:
				# As the root, we build leaf points relative to our next node.
				angle = cw_nodes[0].position2.angle_to_point(position2)
				build = true
		else:
			# As a child, we build leaf points relative to our parent.
			angle = parent.position2.angle_to_point(position2)
			build = true
		if build:
			var root_point := position2 + Vector2.from_angle(angle) * end_distance
			var tangent_a := angle - (PI * 0.5)
			var tangent_b := angle + (PI * 0.5)
			var point_a := root_point + Vector2.from_angle(tangent_a) * distance
			var point_b := root_point + Vector2.from_angle(tangent_b) * distance
			if not parent:
				var temp := point_a
				point_a = point_b
				point_b = temp
			#if DEBUG_PRINT_PERIMETER:
				#Log.dict(self, {
					#case = "Leaf points",
					#point_a = Vector3(point_a.x, position.y, point_a.y),
					#point_b = Vector3(point_b.x, position.y, point_b.y)
				#})
			points.append(Vector3(point_a.x, position.y, point_a.y))
			if not parent:
				points.append_array(cw_nodes[0]._recursive_get_perimeter_points(distance, end_distance, self))
			points.append(Vector3(point_b.x, position.y, point_b.y))
	
	if not parent and points and closed:
		points.append(points[0])
	
	return points

func duplicate_deep() -> TreeCurve3D:
	var d: TreeCurve3D = duplicate()
	d.leaves = []
	for l in leaves:
		d.leaves.append(l.duplicate_deep())
		d._update_leaf_signals()
	return d

func serialize() -> Array:
	var d := [position]
	for l in leaves:
		d.append(l.serialize())
	return d

static func deserialize(d: Array) -> TreeCurve3D:
	var c := TreeCurve3D.new()
	c.position = d[0]
	for l: Array in d.slice(1):
		c.leaves.append(deserialize(l))
	c._update_leaf_signals()
	return c 

## Calculates the angle difference between A and B, going clockwise from A.
static func cw_angle_difference(a: float, b: float) -> float:
	return fmod((fmod(a, TAU) - fmod(b, TAU)) + (2.0 * TAU), TAU)
