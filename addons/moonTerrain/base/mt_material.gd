@tool
extends Resource
class_name MTMaterial

const DEFAULT_SHADOW_GRADIENT = preload("uid://jjg2mbs3kl5x")

signal render_changed

## The name of the material.
@export var name := ""

## Layers determines how the material geometry is constructed.
@export var layers: Array[MTLayer] = []:
	set(x):
		for l in layers:
			if l:
				if l.render_changed.is_connected(_update_shader_parameters):
					l.render_changed.disconnect(_update_shader_parameters)
		layers = x
		for l in layers:
			if l:
				if not l.render_changed.is_connected(_update_shader_parameters):
					l.render_changed.connect(_update_shader_parameters)
		_update_shader_parameters()

@export_group("Visual")
## The texture of the backface.
@export var backface_texture: Texture2D:
	set(x):
		if backface_texture:
			if backface_texture.changed.is_connected(render_changed.emit):
				backface_texture.changed.disconnect(render_changed.emit)
		backface_texture = x
		if backface_texture:
			if not backface_texture.changed.is_connected(render_changed.emit):
				backface_texture.changed.connect(render_changed.emit)
		_update_shader_parameters()

@export_range(0.01, 4.0, 0.001, "or_greater") var backface_uv_scale := 1.0:
	set(x):
		backface_uv_scale = x
		_update_shader_parameters()

## Defines a shadow gradient. Used for color blending on walls.
@export var shadow_gradient: Gradient = DEFAULT_SHADOW_GRADIENT:
	set(x):
		if shadow_gradient:
			if shadow_gradient.changed.is_connected(_update_shader_parameters):
				shadow_gradient.changed.disconnect(_update_shader_parameters)
		shadow_gradient = x if x else DEFAULT_SHADOW_GRADIENT
		shadow_gradient_texture.gradient = shadow_gradient
		if shadow_gradient:
			if not shadow_gradient.changed.is_connected(_update_shader_parameters):
				shadow_gradient.changed.connect(_update_shader_parameters)
		_update_shader_parameters()

@export_storage var shadow_gradient_texture: GradientTexture1D:
	get:
		if not shadow_gradient_texture:
			shadow_gradient_texture = GradientTexture1D.new()
			shadow_gradient_texture.width = 32
			shadow_gradient_texture.gradient = shadow_gradient
		return shadow_gradient_texture

@export_tool_button("Force Update", "Reload") var _force_update = func ():
	render_changed.emit()

@export_group("Collision", "collision")
## The script associated with this material's StaticBody3D.
@export var collision_script: GDScript = null:
	set(x):
		collision_script = x
		render_changed.emit()

## How far to expand the collision floor.
@export var collision_expand := 0.0:
	set(x):
		collision_expand = x
		render_changed.emit()

@export_group("Paths", "path")
## The width of a generated path mesh.
@export var path_width := 1.25:
	set(x):
		path_width = x
		render_changed.emit()

## The endcap length of a generated path mesh.
@export var path_endcap_distance := 1.25:
	set(x):
		path_endcap_distance = x
		render_changed.emit()

@export_group("Smoothing", "smooth")
## Number of smoothness vertices made per vertex.
@export_range(1, 8) var smooth_steps := 1:
	set(x):
		smooth_steps = x
		render_changed.emit()

## The distance between each smoothness vertex.
@export_range(0.0, 8.0, 0.01, "or_greater") var smooth_distance := 1.0:
	set(x):
		smooth_distance = x
		render_changed.emit()

## Generates a mesh using the MTMaterial.
## [flatten_height] specifies where the flatten layers should generate at.
func generate_curve_mesh(mt3d: MTBase3D, curve: Curve3D) -> ArrayMesh:
	var mesher := MTMesher.new()
	curve = smooth_curve(curve)
	for layer in layers:
		if not layer:
			continue
		layer.create_layer(mt3d, curve, self, mesher)
	return mesher.mesh

## Generates a simplified mesh for the brush collision.
func generate_collision_mesh(mt3d: MTBase3D, curve: Curve3D) -> ArrayMesh:
	# Calculate the collision mesh heights.
	var start_height := -INF
	var end_height := INF
	
	for layer in layers:
		if layer:
			start_height = maxf(start_height, layer.height)
			end_height = minf(end_height, layer.height)
	
	if is_inf(end_height):
		start_height = 0.0
		end_height = 0.0
	
	# Define all the layers.
	var floor_layer := MTLayer.new()
	floor_layer.generation_mode = MTLayer.Mode.FLOOR
	floor_layer.expand = collision_expand
	floor_layer.height = start_height
	
	var wall_layer := MTLayer.new()
	wall_layer.generation_mode = MTLayer.Mode.WALL
	wall_layer.height = end_height - start_height
	wall_layer.flatten = true
	
	var roof_layer := MTLayer.new()
	roof_layer.generation_mode = MTLayer.Mode.ROOF
	
	# Build the mesh.
	curve = smooth_curve(curve)
	var mesher := MTMesher.new()
	floor_layer.create_layer(mt3d, curve, self, mesher)
	wall_layer.create_layer(mt3d, curve, self, mesher)
	roof_layer.create_layer(mt3d, curve, self, mesher)
	return mesher.mesh

## Creates an updated Curve3D with smoother points.
func smooth_curve(curve: Curve3D) -> Curve3D:
	if curve.point_count == 1 or smooth_steps == 1 or is_zero_approx(smooth_distance):
		return curve
	var smooth_curve := Curve3D.new()
	for idx in curve.point_count:
		# Calculate many things...
		var v_this := curve.get_point_position(idx)
		var v_next := curve.get_point_position(posmod(idx + 1, curve.point_count))
		var v_last := curve.get_point_position(posmod(idx - 1, curve.point_count))
		var dist_next := v_this.distance_to(v_next)
		var dist_last := v_this.distance_to(v_last)
		
		# Calculate our tangent point adjacencies.
		var t_next := v_this.move_toward(v_next, minf(dist_next * 0.49, smooth_distance))
		var t_last := v_this.move_toward(v_last, minf(dist_last * 0.49, smooth_distance))
		
		# Start adding points.
		smooth_curve.add_point(t_last)
		
		if smooth_steps > 2:
			var between_count := smooth_steps - 2
			var gravity := (v_this - t_next.lerp(t_last, 0.5)) * 0.5
			for betwidx in between_count:  # this pun sucks lmao
				var t := float(betwidx + 1) / float(between_count + 1)
				smooth_curve.add_point(t_last.lerp(t_next, t) + gravity * (-4 * (t * t - t)))  # awesome parabola
				#var mp := t_next.lerp(t_last, t) + gravity * (-4 * (t * t - t))  # awesome parabola
			
		smooth_curve.add_point(t_next)
		
	return smooth_curve

func _update_shader_parameters():
	for l in layers:
		if l:
			l.update_shader_parameters(self)
	render_changed.emit()
